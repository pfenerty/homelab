# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Personal infrastructure managed as code.

| Directory | What |
|-----------|------|
| `talos-cluster/` | Kubernetes cluster: 3× RPi4 control planes + 1 amd64 worker (Talos Linux + Flux CD) |
| `.tektonic/` | This repo's CI definition (tektonic); `npm run synth` writes `.tekton/` |
| `.tekton/` | Generated PipelineRuns for Pipelines as Code. Never hand-edit |

## Secrets

All secrets are SOPS-encrypted with an age key at `age.key` (repo root, gitignored). Encryption rules are in `.sops.yaml`. Never commit decrypted secrets.

Secret guards run before every commit: `.beads/hooks/pre-commit` calls `prek` (from the flox env), which runs `.pre-commit-config.yaml`:
- **betterleaks** scans staged changes with `.betterleaks.toml`. CI runs the same version and config, so bump them together.
- **sops-encrypted** (`.tektonic/scripts/check-sops-encryption.sh`) fails on any staged `*.secret.yaml`, `*.enc.yaml` or `secrets.yaml` that is not encrypted. betterleaks skips those paths, so this check is the only thing that catches them.

Commit from inside `flox activate`, or the hook fails closed. Full sweep: `prek run --all-files`.

## Talos Cluster

Three RPi4 control-plane nodes (192.168.1.101-103) with a floating VIP at 192.168.1.100, plus the amd64 worker `x86-01` (192.168.1.104, separate factory schematic with the binfmt-misc extension). Stack: Talos Linux, Cilium CNI, Flux CD GitOps, Tailscale, Tekton + Pipelines as Code CI, CloudNativePG, kube-prometheus-stack/Loki/Grafana.

Always pass `--talosconfig talos-cluster/talos/clusterconfig/talosconfig` to `talosctl`. The default `~/.talos/config` context points somewhere else.

All operations run from `talos-cluster/`:

```bash
make generate        # Regenerate node configs from patches + SOPS secrets
make validate        # Validate all generated configs
make apply-all       # Apply configs to all running nodes
make repatch-all     # Re-apply patches without touching secrets
make repatch-rpi-01  # Re-apply patches to single node
make health          # Check cluster health
make validate-patches  # Validate patches against throwaway PKI (same as CI)
make upgrade-all     # Upgrade all nodes (103 → 102 → 101 → x86-01)
make upgrade-101     # Upgrade single node by last IP octet
make upgrade-x86-01  # Worker upgrade; opens a CNPG maintenance window around the drain
make upgrade-k8s     # Kubernetes upgrade to $(KUBERNETES_VERSION)
make bootstrap       # First-time etcd bootstrap
make kubeconfig      # Fetch kubeconfig to ~/.kube/config
```

`TALOS_VERSION` / `KUBERNETES_VERSION` in `talos-cluster/Makefile` are the source of truth. Patches are multi-document (Talos 1.14 split config into per-component documents). After `make repatch-all`, check `talosctl services` for `cri`. A no-reboot apply that restarts cri can leave containerd waiting on sandboxd, and that needs a rolling reboot to clear.

### Flux GitOps Layout

```
talos-cluster/flux/
├── flux-system/            # Flux bootstrap; root Kustomization syncs ./talos-cluster/flux
├── kustomization.yaml      # Lists every *.kustomization.yaml below
├── *.kustomization.yaml    # One Flux Kustomization per component (dependsOn ordering)
├── cilium/, gateway-api/   # Infra outside apps/
└── apps/<name>/            # Workload manifests, one directory per component
```

A new component needs its own `<name>.kustomization.yaml` that is listed in `flux/kustomization.yaml`. CI's `check-flux-wiring.sh` fails on orphans. Kustomizations that hold SOPS files set `spec.decryption` (secret `sops-age`).

Each app directory carries a `network-policy.yaml` (CiliumNetworkPolicy): a `baseline-ingress` that admits only the namespace itself, monitoring, the nodes and the apiserver, plus explicit rules for Tailscale/Cloudflare entry points. Internet-facing namespaces (ocidex-dev, cloudflare-gateway, pipelines-as-code, renovate, trek) and every TaskRun pod (`apps/tekton/network-policy.yaml`) also lock down egress to DNS + internet minus RFC1918. New cross-namespace traffic, or a new HTTPRoute backend namespace, needs a rule on both ends. The ocidex namespaces are the exception: their allow-rules come from the ocidex charts' `networkPolicy` values (set in the HelmReleases), bounded by `apps/ocidex/dev/infra/egress-guardrail.yaml`, an egressDeny that no allow can widen. `policyAuditMode` in the Cilium HelmRelease decides whether policies enforce or only log (`hubble observe --verdict AUDIT`).

### CI

`cd .tektonic && npm run synth` regenerates `.tekton/`. Commit the result. `npm run check` fails if `.tekton/` is stale. The check scripts live in `.tektonic/scripts/` and run locally too.

## Dependency Updates

Automated via [Renovate](https://docs.renovatebot.com/), which runs in-cluster as a CronJob. It covers Helm chart versions, container image tags, vendored Tekton manifests, and the Talos/Kubernetes versions in the Makefile.

## Prerequisites

talosctl, kubectl, sops, helm, flux CLI, Tailscale (the flox env provides talosctl, kubectl, tkn and prek)


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
