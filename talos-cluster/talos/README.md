# talos/

Talos Linux machine configuration for the cluster. Configs are generated from patches + a SOPS-encrypted secrets bundle, then applied to nodes with `talosctl`.

## Structure

```
talos/
├── secrets.yaml          # SOPS-encrypted: cluster CA, etcd certs, bootstrap tokens
├── patches/
│   ├── all-nodes.yaml        # Applied to every node
│   ├── controlplane.yaml     # Applied to control plane nodes only
│   ├── rpi-01-network.yaml   # Per-node static IP (+ VIP on rpi-01)
│   ├── rpi-02-network.yaml
│   ├── rpi-03-network.yaml
│   └── x86-01-network.yaml   # amd64 worker: static IP + binfmt_misc module
└── clusterconfig/            # Generated, gitignored
    ├── controlplane.yaml     # Base control plane config (secrets baked in)
    ├── worker.yaml           # Base worker config (secrets baked in)
    ├── rpi-01.yaml           # controlplane.yaml + rpi-01-network.yaml
    ├── rpi-02.yaml
    ├── rpi-03.yaml
    ├── x86-01.yaml           # worker.yaml + x86-01-network.yaml
    └── talosconfig           # Client config for talosctl (endpoints = the three RPis)
```

## Config Generation

Configs in `clusterconfig/` are generated, so do not edit them directly. Change the patches and regenerate.

```
secrets.yaml ──────┐
all-nodes.yaml ────┼──► talosctl gen config ──► controlplane.yaml ──┐
controlplane.yaml ─┘     (--with-secrets)        worker.yaml ───────┤
                                                                    ▼
rpi-XX-network.yaml / x86-01-network.yaml ──► talosctl machineconfig patch ──► <node>.yaml
```

`make generate` runs this pipeline. It decrypts `secrets.yaml` on the fly with `sops exec-file`, using the age key at `../../age.key`. The existing secrets bundle is passed with `--with-secrets`, so regenerating **reuses** the cluster's PKI and does not rotate it. The `Makefile` is a prerequisite of the generated files, so a `TALOS_VERSION` / `KUBERNETES_VERSION` bump forces a regenerate.

## Patches

Talos 1.14 moved most settings out of the `v1alpha1` document into dedicated per-component documents, and it rejects a config that sets the same thing in both places. Each patch file is therefore multi-document. [`../README.md`](../README.md#machine-config-patches) has the full old → new mapping.

### `all-nodes.yaml`
- NTP servers (Cloudflare + Google by IP, to avoid a bootstrap DNS dependency) and a 5 m boot timeout, because the RPi has no RTC
- `vm.dirty_writeback_centisecs` tuning for SD card / flash longevity; `user.max_user_namespaces`
- `ResolverConfig`: nameservers 1.1.1.1, 8.8.8.8
- `CRICustomizationConfig`: containerd runc `NoNewPrivileges = false`

### `controlplane.yaml`
- etcd: `heartbeat-interval: 500` / `election-timeout: 5000` (RPi4 fsync latency), metrics exposed on `:2381`
- `KubeletConfig`: system/kube reservations and eviction thresholds sized for ~3.2 Gi allocatable RAM
- `KubeProxyConfig.enabled: false`, because Cilium's eBPF replaces kube-proxy
- deletes the `KubeFlannelCNIConfig` document, because Cilium is installed via Flux instead
- `KubeAPIServerConfig`: smaller watch cache, shorter event TTL, lower inflight limits, `GOGC`/`GOMEMLIMIT` to leave page cache for etcd
- `KubeControllerManagerConfig` / `KubeSchedulerConfig`: longer leader-election timings so one slow etcd read doesn't cost leadership

### `rpi-XX-network.yaml`
- Static IP via `deviceSelector: driver: bcmgenet` (RPi built-in NIC)
- Default route
- VIP (`192.168.1.100`) on rpi-01 only. It floats between control-plane nodes for API HA

### `x86-01-network.yaml`
- Static IP `192.168.1.104` on `enp0s31f6`
- Loads `binfmt_misc` (provided by the `siderolabs/binfmt-misc` extension in `WORKER_SCHEMATIC`). Nothing registers qemu handlers yet, so cross-arch builds stay off. The patch comment explains why

## Applying Changes

```bash
make validate-patches   # check patch changes against throwaway PKI (what CI runs)
make repatch-all        # regenerate from patches + existing PKI, apply to every node
make repatch-rpi-01     # ...or one node
```

`repatch-%` is idempotent and safe to re-run. Use `generate` + `apply-all` when adding a node.

## Adding a New Node

1. Add it to `NODES`/`NODE_IPS` (control plane) or `WORKER_NODES` (worker) in the Makefile, with a `NODE_IP_<name>` variable
2. Create `patches/<name>-network.yaml` with its static IP
3. Add a `$(OUTPUT)/<name>.yaml` rule if it doesn't match `rpi-%`, and add it to `generate` and `repatch-all`
4. Run `make generate` to produce `clusterconfig/<name>.yaml`
5. Boot the node from the matching factory image (`IMAGE_URL` for RPi, `WORKER_IMAGE_URL` for amd64) and run `make apply-<name> NODE_DHCP_IP=<dhcp-ip>`
6. Run `make bootstrap` if this is the first node. Otherwise the node joins automatically
