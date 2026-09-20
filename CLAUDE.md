# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Personal infrastructure managed as code.

| Path | What |
|------|------|
| `talos-cluster/` | Four-node Kubernetes cluster: three RPi4 control planes + an amd64 worker (Talos Linux + Flux CD) |
| `.tektonic/` | This repository's own CI definition and check scripts |
| `.tekton/` | Generated from `.tektonic/` — PAC reads it from the pushed commit. Never hand-edit; run `npm run synth` |

## Secrets

All secrets are SOPS-encrypted with an age key at `age.key` (repo root, gitignored). Encryption rules are in `.sops.yaml`. Never commit decrypted secrets.

## Talos Cluster

Three RPi4 control-plane nodes (192.168.1.101-103) with a floating VIP at 192.168.1.100. Stack: Talos Linux, Cilium CNI, Flux CD GitOps, Tailscale, Tekton CI.

All operations run from `talos-cluster/`:

```bash
make generate        # Regenerate node configs from patches + SOPS secrets
make validate        # Validate all generated configs
make apply-all       # Apply configs to all running nodes
make repatch-all     # Re-apply patches without touching secrets
make repatch-rpi-01  # Re-apply patches to single node
make health          # Check cluster health
make upgrade-all     # Upgrade all nodes (103 → 102 → 101)
make upgrade-101     # Upgrade single node by last IP octet
make bootstrap       # First-time etcd bootstrap
make kubeconfig      # Fetch kubeconfig to ~/.kube/config
```

### Flux GitOps Layout

```
talos-cluster/flux/
├── kustomization.yaml     # Root: lists every *.kustomization.yaml below
├── flux-system/           # Flux bootstrap components (managed by `flux bootstrap`)
├── <app>.kustomization.yaml   # One Flux Kustomization per app, ~26 of them
├── cilium/                # CNI, reconciled ahead of everything else
├── gateway-api/           # Gateway API CRDs
└── apps/<app>/            # The manifests each Kustomization points at
```

A `*.kustomization.yaml` that the root `kustomization.yaml` does not list will never
reconcile. CI checks for that, for `spec.path` values that do not exist, and for
`dependsOn` naming a Kustomization that is gone.

## CI

Runs on this cluster via Pipelines as Code, defined in `.tektonic/pipeline.ts` and
synthesized to `.tekton/`. Each check is a script under `.tektonic/scripts/` and runs
the same locally as in the cluster:

```bash
.tektonic/scripts/build-manifests.sh          # kustomize build the whole Flux tree
.tektonic/scripts/validate-manifests.sh       # kubeconform against KUBERNETES_VERSION
.tektonic/scripts/check-flux-wiring.sh        # orphaned / dangling Kustomizations
.tektonic/scripts/check-sops-encryption.sh    # nothing committed in the clear
.tektonic/scripts/check-vendored-manifests.sh # vendored manifests match their pins
make -C talos-cluster validate-patches        # Talos configs generate and validate
```

After changing `.tektonic/pipeline.ts`, run `npm run synth` in `.tektonic/` and commit
the regenerated `.tekton/`.

## Dependency Updates

Automated via [Renovate](https://docs.renovatebot.com/) — Helm charts, container image
tags, Flux sources, and the Talos/Kubernetes versions in `talos-cluster/Makefile`.

Vendored upstream release manifests are excluded on purpose: they carry CRDs and RBAC
alongside image tags, so an image-only bump leaves new binaries on old CRDs. Renovate
tracks the version pinned in each app's `update-manifests.sh`; re-run that script to
re-vendor, never edit the manifest.

## Prerequisites

talosctl, kubectl, sops, helm, flux CLI, Tailscale. For CI scripts locally: kustomize, kubeconform, yq (all in `alpine/k8s`), and Node 22+ for `.tektonic/`.


<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:ca08a54f -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd dolt push
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->
