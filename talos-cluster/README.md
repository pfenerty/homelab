# talos-cluster

A four-node Kubernetes cluster managed with [Talos Linux](https://www.talos.dev/) and [Flux CD](https://fluxcd.io/). Three Raspberry Pi 4s form the control plane and an amd64 box runs as a worker.

## Hardware

| Config name | Kubernetes node | IP | Arch | Role |
|------|------|----|------|------|
| rpi-01 | talos-byt-k6n | 192.168.1.101 | arm64 | Control plane |
| rpi-02 | talos-fd9-twg | 192.168.1.102 | arm64 | Control plane |
| rpi-03 | talos-1q6-aue | 192.168.1.103 | arm64 | Control plane |
| x86-01 | talos-jlf-6ro | 192.168.1.104 | amd64 | Worker |
| VIP | | 192.168.1.100 | | Kubernetes API (floating across the RPis) |

Kubernetes names the nodes with Talos's generated hostnames. The Makefile and
patches use the config names. The control planes keep the default
`node-role.kubernetes.io/control-plane:NoSchedule` taint, so most workloads run on
`x86-01`. The RPis carry the control plane, DaemonSets (Cilium, Alloy, …) and the
few pods that tolerate the taint.
Each RPi has about 3.2 Gi allocatable RAM, shared by etcd and the control-plane
components. `x86-01` also hosts the `ocidex-pg` CloudNativePG instance on
`local-path` storage. Its Talos
image comes from a separate factory schematic (`WORKER_SCHEMATIC`) that adds the
`siderolabs/binfmt-misc` extension. Nothing registers qemu handlers yet, so
cross-arch builds are off. The same schematic adds `siderolabs/iscsi-tools`, so
`x86-01` is the only node that can mount `synology-csi-iscsi` volumes (iSCSI LUNs
on the Synology).

## Stack

| Component | Details |
|-----------|---------|
| OS | Talos Linux v1.14.2 (`TALOS_VERSION` in the `Makefile`) |
| Kubernetes | v1.37.1 (`KUBERNETES_VERSION` in the `Makefile`) |
| CNI | Cilium 1.20.2 (kube-proxy replacement, WireGuard encryption, VXLAN routing, Hubble) |
| GitOps | Flux CD, one Kustomization per component |
| Secrets | SOPS + age |
| Ingress | Tailscale operator (tailnet), Cloudflare Gateway API controller (public) |
| CI | Tekton Pipelines, Triggers, Chains, Dashboard + Pipelines as Code |
| Storage | local-path-provisioner, NFS subdir provisioner |
| Database | CloudNativePG |
| Observability | kube-prometheus-stack, Loki, Tempo, Alloy, Grafana |

[`flux/README.md`](flux/README.md) lists every component.

## Repository Layout

```
talos-cluster/
├── Makefile                  # All cluster operations
├── scripts/upgrade-k8s.sh    # Watchdog wrapper behind `make upgrade-k8s`
├── docs/                     # Write-ups on non-obvious decisions
├── talos/                    # Talos machine configs
│   ├── patches/              # Config patches (applied at generate time)
│   ├── clusterconfig/        # Generated node configs + talosconfig (gitignored)
│   └── secrets.yaml          # SOPS-encrypted cluster PKI + bootstrap tokens
└── flux/                     # Flux GitOps manifests
    ├── flux-system/          # Flux bootstrap components
    ├── kustomization.yaml    # Root: lists every *.kustomization.yaml
    ├── *.kustomization.yaml  # One Flux Kustomization per component
    └── apps/                 # Application workloads
```

## Machine config patches

Talos 1.14 split most settings out of the single `v1alpha1` document into dedicated
configuration documents, and **rejects a config that sets the same thing in both
places**. The patches under `talos/patches/` are multi-document as a result: a
`v1alpha1` document for what still lives there, then one document per component.

| Setting | Before 1.14 | Now |
|---|---|---|
| Nameservers | `machine.network.nameservers` | `ResolverConfig` (list of objects, not strings) |
| Kubelet reservations | `machine.kubelet.extraConfig` | `KubeletConfig.config` |
| No bundled CNI | `cluster.network.cni.name: none` | delete the `KubeFlannelCNIConfig` document |
| kube-proxy off | `cluster.proxy.disabled: true` | `KubeProxyConfig.enabled: false` |
| apiserver flags/env | `cluster.apiServer` | `KubeAPIServerConfig` |
| controller-manager flags | `cluster.controllerManager` | `KubeControllerManagerConfig` |
| scheduler flags | `cluster.scheduler` | `KubeSchedulerConfig` |
| containerd CRI fragment | `machine.files` (deprecated) | `CRICustomizationConfig` |

etcd (`cluster.etcd.extraArgs`), `machine.time` and `machine.sysctls` are still read
from `v1alpha1` and stay there.

There is no "disable the bundled CNI" switch in 1.14. `talosctl gen config` always
emits a `KubeFlannelCNIConfig`, so running Cilium instead means removing that document
— `$patch: delete` in `controlplane.yaml` does it. Leave it in and Talos deploys
Flannel alongside Cilium.

Check a patch change without touching secrets or the cluster:

```bash
make validate-patches
```

It generates the node configs against throwaway PKI and validates each one, which is
the same check CI runs.

## Common Operations

All operations are driven by `make`. Run `make <target>` from the `talos-cluster/` directory.

### Generate and apply config changes

```bash
# Regenerate all node configs from patches + secrets (SOPS decrypt is automatic)
make generate

# Apply configs to all running nodes
make apply-all

# Regenerate a node's config from patches + existing PKI and apply it
make repatch-all
make repatch-rpi-01   # single node
```

After any no-reboot apply, run `talosctl services` and check that `cri` is
`Running`. On Talos 1.14.0, an apply that restarted cri left containerd stuck at
"Waiting for service sandboxd to be registered" on every node, because sandboxd
only registers at boot. Every node went NotReady. A rolling reboot, one node at a
time, clears it.

Always pass `--talosconfig talos/clusterconfig/talosconfig` to `talosctl` (the
Makefile does this for you). The default `~/.talos/config` context may point
at a different cluster.

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
make upgrade-all          # upgrade all nodes (103 → 102 → 101 → x86-01)
make upgrade-101          # upgrade single node by last octet
make upgrade-x86-01       # amd64 worker (different schematic)
```

`make upgrade-x86-01` handles the worker's complication on its own. That node
runs `ocidex-pg` as a single CloudNativePG instance on `local-path` storage, so
the PVC is pinned there and the PDB allows zero disruptions — a plain drain can
never evict it. The target opens CNPG's node-maintenance window (which drops the
PDB, with `reusePVC` keeping the volume) and closes it afterwards, on failure
and Ctrl-C too.

The window is opened behind a suspended `ocidex-dev-infra` kustomization,
because the Cluster CR is Flux-managed: an unsuspended reconcile puts the PDB
back mid-drain, which is precisely what deadlocks a drain already in flight.
`make cnpg-maintenance-on` / `off` expose the two halves if you need them by
hand — `off` is safe to run at any time to get back to a clean state.

Escape hatches, both of which leave CNPG alone:

```bash
make upgrade-x86-01 MAINTENANCE=false  # no window, no Flux suspend
make upgrade-x86-01 DRAIN=false        # no cordon/drain; reboot stops the pods
```

Every upgrade target uncordons its node on the way out, so an interrupted run
doesn't leave the cluster short a node.

```bash
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
