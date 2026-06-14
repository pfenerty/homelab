# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Personal infrastructure managed as code. Two sub-projects:

| Directory | What |
|-----------|------|
| `talos-cluster/` | Three-node Kubernetes cluster on Raspberry Pi 4s (Talos Linux + Flux CD) |
| `nix-dev-server/` | NixOS remote development server (GPU workstation) |

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
├── flux-system/     # Flux bootstrap components
├── apps/            # Application workloads
└── *.kustomization.yaml  # Top-level kustomizations (cilium, apps)
```

## NixOS Dev Server

Flake-based NixOS configuration. Modules live in `nix-dev-server/modules/`, host configs in `nix-dev-server/hosts/`.

## Dependency Updates

Automated via [Renovate](https://docs.renovatebot.com/) — covers Nix flake inputs, Helm chart versions, and container image tags.

## Prerequisites

talosctl, kubectl, sops, helm, flux CLI, Tailscale


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
