# talos-cluster

A three-node Kubernetes cluster running on Raspberry Pi 4s, managed with [Talos Linux](https://www.talos.dev/) and [Flux CD](https://fluxcd.io/).

## Hardware

| Node | IP | Role |
|------|----|------|
| rpi-01 | 192.168.1.101 | Control plane |
| rpi-02 | 192.168.1.102 | Control plane |
| rpi-03 | 192.168.1.103 | Control plane |
| VIP | 192.168.1.100 | Kubernetes API (floating) |

All nodes run as control planes with `allowSchedulingOnControlPlanes: true`.

## Stack

| Component | Details |
|-----------|---------|
| OS | Talos Linux v1.13.9 (`TALOS_VERSION` in the `Makefile`) |
| Kubernetes | v1.36.4 (`KUBERNETES_VERSION` in the `Makefile`) |
| CNI | Cilium 1.19.1 (kube-proxy replacement, WireGuard encryption, VXLAN routing) |
| GitOps | Flux CD |
| Secrets | SOPS + age |
| VPN | Tailscale operator |
| CI | Tekton Pipelines + Dashboard |

## Repository Layout

```
talos-cluster/
├── Makefile                  # All cluster operations
├── talos/                    # Talos machine configs
│   ├── patches/              # Config patches (applied at generate time)
│   ├── clusterconfig/        # Generated node configs (gitignored secrets baked in)
│   └── secrets.yaml          # SOPS-encrypted cluster PKI + bootstrap tokens
└── flux/                     # Flux GitOps manifests
    ├── flux-system/          # Flux bootstrap components
    ├── cilium.kustomization.yaml
    ├── apps.kustomization.yaml
    └── apps/                 # Application workloads
```

## Common Operations

All operations are driven by `make`. Run `make <target>` from the `talos-cluster/` directory.

### Generate and apply config changes

```bash
# Regenerate all node configs from patches + secrets (SOPS decrypt is automatic)
make generate

# Apply configs to all running nodes
make apply-all

# Re-apply only the patches to existing configs (no secrets needed)
make repatch-all
make repatch-rpi-01   # single node
```

### Cluster lifecycle

```bash
# First-time node setup (node must be at DHCP IP)
make apply-rpi-01 NODE_DHCP_IP=192.168.1.x

# Bootstrap etcd (first install only)
make bootstrap

# Fetch kubeconfig
make kubeconfig

# Check cluster health
make health
```

### Upgrades

Talos and Kubernetes upgrade independently. `TALOS_VERSION` and
`KUBERNETES_VERSION` in the `Makefile` are the source of truth for both
(Renovate bumps them).

```bash
# Talos (reboots each node — one at a time)
make upgrade-all          # upgrade all nodes (103 → 102 → 101)
make upgrade-101          # upgrade single node by last octet
make upgrade-x86-01       # amd64 worker (different schematic)

# Kubernetes (one run covers every node, control plane and workers)
make k8s-versions         # kubelet + apiserver versions per node
make upgrade-k8s-dry-run  # show the plan, change nothing
make upgrade-k8s          # upgrade to $(KUBERNETES_VERSION)
make upgrade-k8s K8S_TO=1.36.5   # ad-hoc target version
```

`make health` between steps. Note that `make repatch-<node>` carries the
current `KUBERNETES_VERSION` into that node's machine config, so re-patching a
single node can leave the cluster version-skewed until `make upgrade-k8s`
converges it — `make k8s-versions` shows the skew.

## Prerequisites

- `talosctl`
- `kubectl`
- `sops`
- `helm` (for manual Helm operations)
- `flux` CLI
- age key at `../age.key` relative to this directory

## Known Issues / Architecture Notes

See [`docs/`](docs/) for detailed write-ups on non-obvious configuration decisions.
