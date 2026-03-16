/**
 * Reference implementation showing how to use @pfenerty/tekton-pipelines.
 *
 * Uses the core API: TektonProject, Pipeline, JOBS, and Job.
 *
 * Run: npx ts-node examples/main.ts   (or: make synth)
 * Output: synth-output/*.yaml
 */
import {
    TektonProject,
    Pipeline,
    JOBS,
    Job,
    TRIGGER_EVENTS,
} from "@pfenerty/tekton-pipelines";

// ─── Configuration ────────────────────────────────────────────────────────────
const NAMESPACE = "ocidex-ci";

// ─── Define jobs ──────────────────────────────────────────────────────────────
const clone = JOBS.clone();
const gitLog = JOBS.gitLog({ needs: clone });

// ─── Compose pipelines ───────────────────────────────────────────────────────
const pushPipeline = new Pipeline({
    name: "push",
    triggers: [TRIGGER_EVENTS.PUSH],
    jobs: [clone, gitLog],
});

const prPipeline = new Pipeline({
    name: "pull-request",
    triggers: [TRIGGER_EVENTS.PULL_REQUEST],
    jobs: [clone, gitLog],
});

// ─── Synthesize everything ───────────────────────────────────────────────────
new TektonProject({
    name: "ocidex",
    namespace: NAMESPACE,
    pipelines: [pushPipeline, prPipeline],
    webhookSecretRef: {
        secretName: "github-webhook-secret",
        secretKey: "secret",
    },
});
