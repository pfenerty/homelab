# .tektonic/

CI for this repository, defined with [tektonic](https://github.com/pfenerty/tektonic)
and run by Pipelines as Code on the cluster this repository configures.

```
.tektonic/
├── pipeline.ts     # the definition — what runs, when, on what image
├── scripts/        # the checks themselves, one shell script each
└── package.json    # tektonic.entry points at pipeline.ts
        │
        └── npm run synth ──► ../.tekton/   (committed; PAC reads it from the pushed commit)
```

## Why the output lives in `.tekton/`

PAC only discovers PipelineRun templates in `.tekton/` at the repository root — the
directory is not configurable (the `Repository` CRD exposes `pipelinerun_provenance`,
which chooses the *ref*, not the path). So the definition lives here and synthesis
writes one level up, with `repoRelativePath` keeping the task annotations
repo-root-relative.

`.tekton/` is generated. Do not hand-edit it; change `pipeline.ts` and re-synth.

## Working on it

```bash
cd .tektonic
npm install
npm run synth     # regenerate ../.tekton/ — commit the result
npm run check     # fail if ../.tekton/ is stale, missing or orphaned
npm run graph     # print the task DAG
npm run lint      # shellcheck the scripts/
```

`@pfenerty/tektonic` is installed from git, pinned to a commit: it is not published
to npm yet despite the README there saying so, and the registry 404s for the package.
Switch the dependency to a version range once it is published.

## The checks

Each check is a standalone script, so it runs identically in CI and on a laptop with
the tools on `$PATH` — there is no CI-only behaviour to reproduce.

| Script | What it catches |
|---|---|
| `build-manifests.sh` | a kustomization that no longer builds — the usual shape of a bad Renovate bump |
| `validate-manifests.sh` | manifests that build but are not valid for the cluster's Kubernetes version |
| `check-flux-wiring.sh` | a Kustomization nothing references, a `spec.path` pointing nowhere, a `dependsOn` naming something gone |
| `check-sops-encryption.sh` | a secret committed before anyone ran `sops -e` |
| `validate-talos-patches.sh` | machine-config patches that no longer generate or validate |

`build-manifests.sh` writes to `.ci/` in the workspace, which is gitignored and
allow-listed in `.gitleaks.toml`.

### No age key in CI

`validate-talos-patches.sh` generates throwaway PKI with `talosctl gen secrets` rather
than decrypting `talos/secrets.yaml`. What a pull request changes is the patches, and
those validate identically against any secrets bundle — so CI never needs the age key,
and a compromised CI run cannot decrypt anything.

### The ratchet in `check-flux-wiring.sh`

`ALLOWED_ORPHANS` lists Kustomizations deliberately not wired into the root
kustomization, so the orphan check could be enforced without first clearing the
backlog. Shrink that list; never grow it.
