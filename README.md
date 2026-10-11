# homelab

Personal infrastructure managed as code: a four-node Kubernetes cluster (three
Raspberry Pi 4 control planes plus an amd64 worker) running Talos Linux, with every
workload delivered by Flux CD from this repository.

| Directory | What it is |
|-----------|-----------|
| [`talos-cluster/`](talos-cluster/) | Talos machine configs, the cluster `Makefile`, and the Flux GitOps tree |
| [`.tektonic/`](.tektonic/) | This repo's CI, defined with tektonic and synthesized into `.tekton/` |
| `.tekton/` | Generated PipelineRuns that Pipelines as Code runs on the cluster. Do not hand-edit |

## Secrets

All secrets are encrypted with [SOPS](https://github.com/getsops/sops) using an age key. The key lives at `age.key` in the repo root (gitignored). Encryption rules are defined in `.sops.yaml`.

Two pre-commit guards (run by `prek` via `.pre-commit-config.yaml`) stop plaintext secrets from being committed:

- **betterleaks** scans staged changes using `.betterleaks.toml`. CI runs the same version and config.
- **sops-encrypted** fails on any staged `*.secret.yaml`, `*.enc.yaml` or `secrets.yaml` that is not encrypted.

Commit from inside `flox activate` so the hook can find `prek`. To check the whole tree, run `prek run --all-files`.

## CI

Pull requests and pushes to `main` run the checks in [`.tektonic/`](.tektonic/README.md): manifest builds, schema validation, Flux wiring, SOPS encryption, and Talos patch validation. They run on the cluster itself, through Pipelines as Code.

## Renovate

[Renovate](https://docs.renovatebot.com/) automates dependency updates. It runs in-cluster as a CronJob (`talos-cluster/flux/apps/renovate/`) and reads its config from `renovate.json`. It covers Helm chart versions, container image tags, vendored Tekton manifests, and the Talos/Kubernetes versions in the `Makefile`.
