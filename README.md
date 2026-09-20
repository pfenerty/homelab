# homelab

Personal infrastructure managed as code.

| Path | What it is |
|------|------------|
| `talos-cluster/` | Four-node Kubernetes cluster — three Raspberry Pi 4 control planes and an amd64 worker (Talos Linux + Flux CD) |
| `.tektonic/` | This repository's own CI: what it checks, and the scripts that do it |
| `.tekton/` | Generated from `.tektonic/`. Pipelines as Code reads it from the pushed commit — do not hand-edit |

## CI

Every push and pull request is validated on the cluster this repository configures,
by Pipelines as Code. The checks build every Flux kustomization and schema-validate
the result, look for Flux wiring that would never reconcile, confirm no secret was
committed unencrypted, scan for leaked credentials, generate and validate the Talos
machine configs, and confirm the vendored upstream manifests match their pinned
versions. See [`.tektonic/README.md`](.tektonic/README.md) — including how to run any
of them locally.

## Secrets

All secrets are encrypted with [SOPS](https://github.com/getsops/sops) using an age key.
The key lives at `age.key` in the repo root (gitignored). Encryption rules are defined
in `.sops.yaml`, and CI fails if anything matching them is committed in the clear.

## Renovate

Dependency updates are automated via [Renovate](https://docs.renovatebot.com/),
configured in `renovate.json`. It covers Helm chart versions, container image tags,
Flux sources and the Talos/Kubernetes versions pinned in `talos-cluster/Makefile`.

Vendored upstream release manifests are deliberately excluded. Each is a single file
carrying CRDs, RBAC and ConfigMaps alongside its image tags, so bumping the tags in
place leaves new binaries running against old CRDs. Renovate tracks the version pinned
in each app's `update-manifests.sh` instead, and CI enforces that the manifest matches.
