/**
 * Homelab CI.
 *
 * Validation pipelines for this repository, run by Pipelines as Code on the cluster
 * this repository configures. Synthesize with `npm run synth` from `.tektonic/`; the
 * output lands in `../.tekton/`, which PAC reads from the pushed commit.
 *
 * Every check is a shell script under `.tektonic/scripts/`, invoked from the cloned
 * workspace rather than embedded into the Task YAML. That keeps the synthesized
 * manifests small and — more usefully — means each check runs identically on a
 * laptop: `.tektonic/scripts/<name>.sh` with the tools on $PATH.
 */
import {
    Task,
    GitPipeline,
    TektonicProject,
    TRIGGER_EVENTS,
    withConcurrency,
    sh,
} from "@pfenerty/tektonic";

// ─── Images ──────────────────────────────────────────────────────────────────
// alpine/k8s carries every tool these checks need — kustomize, kubeconform, yq, jq,
// git, curl — for both amd64 and arm64, so a check runs on the Pi control plane as
// happily as on the amd64 worker, and the nodes pull one image instead of five.
// The tag tracks the Kubernetes release: keep it aligned with KUBERNETES_VERSION in
// talos-cluster/Makefile, which is what validate-manifests.sh validates against.
const K8S_TOOLS = "alpine/k8s:1.37.0";

// Scratch image — no shell — so this step runs the binary via command/args.
const GITLEAKS = "ghcr.io/gitleaks/gitleaks:v8.30.1";

// RPi4 nodes have ~3.2Gi allocatable. kustomize building the whole tree and
// kubeconform holding schemas are the only checks that need more than the default.
const BUILD_RESOURCES = {
    requests: { cpu: "200m", memory: "256Mi" },
    limits: { cpu: "1", memory: "1Gi" },
};

// ─── Tasks ───────────────────────────────────────────────────────────────────

/**
 * The check that pays for the whole pipeline: nearly every commit here is a Renovate
 * bump to a chart version or an image tag, and a bad one is only visible as a build
 * failure. Flux reconciles this repo on a 1m interval, so "broken on main" reaches
 * the cluster before anyone reads the merge notification.
 */
const manifests = new Task({
    name: "manifests",
    timeout: "15m",
    steps: [
        {
            name: "kustomize-build",
            image: K8S_TOOLS,
            computeResources: BUILD_RESOURCES,
            script: sh`sh .tektonic/scripts/build-manifests.sh`,
        },
        {
            name: "kubeconform",
            image: K8S_TOOLS,
            computeResources: BUILD_RESOURCES,
            script: sh`sh .tektonic/scripts/validate-manifests.sh`,
        },
    ],
});

/**
 * Catches the failure modes kustomize cannot see: a Kustomization nothing references
 * (so it silently never reconciles), a spec.path pointing at a directory that does not
 * exist, a dependsOn naming a Kustomization that was renamed or removed.
 */
const fluxWiring = new Task({
    name: "flux-wiring",
    timeout: "5m",
    steps: [
        {
            name: "check-wiring",
            image: K8S_TOOLS,
            script: sh`sh .tektonic/scripts/check-flux-wiring.sh`,
        },
    ],
});

/**
 * .sops.yaml decides what gets encrypted when someone runs `sops -e`. Nothing
 * enforces that they ran it, and a secret committed in cleartext is in the history
 * for good — so this gates the pull request rather than the review.
 */
const sopsEncryption = new Task({
    name: "sops-encryption",
    timeout: "5m",
    steps: [
        {
            name: "check-encryption",
            image: K8S_TOOLS,
            script: sh`sh .tektonic/scripts/check-sops-encryption.sh`,
        },
    ],
});

/**
 * Second, independent line on the same risk: SOPS coverage only protects paths that
 * match a creation rule, while gitleaks looks at content wherever it lands.
 * Configuration (including why the encrypted files are allow-listed) is .gitleaks.toml.
 */
const secretScan = new Task({
    name: "secret-scan",
    timeout: "10m",
    steps: [
        {
            name: "gitleaks",
            image: GITLEAKS,
            // No shell in this image, so no `script:` — exec the binary directly.
            command: ["gitleaks"],
            args: [
                "dir", ".",
                "--config", ".gitleaks.toml",
                "--no-banner",
                "--redact",
                "--exit-code", "1",
            ],
        },
    ],
});

/**
 * The Makefile half of the repository, which manifest validation never touches.
 * Generates the node configs from the committed patches against throwaway PKI and
 * validates each one — no age key in CI, because what a pull request changes is the
 * patches, and those validate identically without the real secrets.
 */
const talosPatches = new Task({
    name: "talos-patches",
    // Fetches the talosctl release binary pinned by TALOS_VERSION on first run.
    timeout: "15m",
    steps: [
        {
            name: "validate-patches",
            image: K8S_TOOLS,
            script: sh`sh .tektonic/scripts/validate-talos-patches.sh`,
        },
    ],
});

// Every check is independent, so Tekton would start all five at once. Three of the
// four nodes are Pi 4s and the workspace PVC is local-path (node-pinned), which puts
// all five pods on one node — two at a time finishes no slower and leaves the node
// able to run the workloads it is actually hosting.
const checks = () =>
    withConcurrency(
        [manifests, fluxWiring, sopsEncryption, secretScan, talosPatches],
        2,
    );

// ─── Pipelines ───────────────────────────────────────────────────────────────

const pullRequest = new GitPipeline({
    name: "validate-pull-request",
    trigger: {
        rules: [{ on: TRIGGER_EVENTS.PULL_REQUEST, branch: "main" }],
        // Renovate force-pushes its branches on every rebase; superseding the older
        // run keeps a queue of stale PipelineRuns off the Pis.
        cancelInProgress: true,
    },
    tasks: checks(),
});

// Re-run on main: a pull request validates the merge source, not the merge result,
// and Flux reconciles main regardless of what any pull request said.
const push = new GitPipeline({
    name: "validate-push",
    trigger: { rules: [{ on: TRIGGER_EVENTS.PUSH, branch: "main" }] },
    tasks: checks(),
});

// ─── Synthesize ──────────────────────────────────────────────────────────────

new TektonicProject({
    name: "homelab",
    namespace: "homelab-ci",
    pipelines: [pullRequest, push],
    // PAC only discovers PipelineRun templates in `.tekton/` at the repo root; the
    // definition lives in `.tektonic/`, so synthesis writes up one level and the task
    // annotations still reference the repo-root path.
    outdir: "../.tekton",
    repoRelativePath: ".tekton",
    serviceAccountName: "default",
    workspaceStorageSize: "2Gi",
    workspaceStorageClass: "local-path",
    // The PAC Repository CR is NOT emitted here. Nothing applies `.tekton/`, so a
    // copy in this output would be decoration that drifts; Flux owns the real one
    // at talos-cluster/flux/apps/homelab-ci/pac-repository.yaml.
});
