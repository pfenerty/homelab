# flux/

Flux CD GitOps manifests for the cluster. The root Kustomization in `flux-system/gotk-sync.yaml` continuously reconciles `./talos-cluster/flux` from `main`.

## Structure

```
flux/
├── flux-system/              # Flux bootstrap components (managed by flux bootstrap)
├── kustomization.yaml        # Root: lists every *.kustomization.yaml below
├── <name>.kustomization.yaml # One Flux Kustomization per component
├── cilium/                   # Cilium CNI HelmRelease
├── gateway-api/              # Gateway API CRDs
└── apps/<name>/              # Manifests for each component
```

Every component has its own Flux `Kustomization` (`<name>.kustomization.yaml`). That file sets the component's `path`, its `dependsOn` ordering, health checks, and SOPS decryption. There is no single "apps" Kustomization, so one broken component doesn't block the others.

### Adding a component

1. Create `apps/<name>/` with a `kustomization.yaml`
2. Create `<name>.kustomization.yaml` pointing `spec.path` at it, with `dependsOn` and (if it contains SOPS files) `spec.decryption`
3. List it in `kustomization.yaml`

CI's `check-flux-wiring.sh` fails if a Kustomization is not referenced from the root, if a `spec.path` doesn't exist, or if a `dependsOn` names something that is gone.

## Reconciliation Order

Arrows point from a dependency to the components that depend on it.

```
cilium ─┬─► tekton ─┬─► pipelines-as-code ─┬─► homelab-ci
        │           │   (also tailscale)   ├─► ocidex-ci
        │           │                      ├─► tektonic-ci
        │           │                      └─► apko-cicd-ci ──► apko-cicd-update
        │           └─► tekton-chains
        ├─► tailscale
        ├─► hubble
        ├─► metrics-server
        ├─► dev-spaces
        └─► cloudflare-gateway (also gateway-api)

cnpg ──► ocidex-dev-infra ──► ocidex-dev-main ──► ocidex-dev-operator ──► ocidex-dev-registries
                              (also cilium,       └─► ocidex-dev-k8s-agent
                               cloudflare-gateway,
                               keda)

tailscale, synology-csi, local-path-provisioner ──► monitoring ──► monitoring-extras
synology-csi ──► trek

no dependencies: gateway-api, cnpg, keda, local-path-provisioner, synology-csi, renovate
```

## Components

### Platform

| Kustomization | Path | What |
|---|---|---|
| `cilium` | `cilium/` | CNI: kube-proxy replacement, WireGuard node-to-node encryption, VXLAN, Hubble |
| `hubble` | `apps/hubble/` | Tailnet Ingress for the Hubble UI |
| `gateway-api` | `gateway-api/` | Gateway API CRDs (`prune: false`) |
| `cloudflare-gateway` | `apps/cloudflare-gateway/` | Cloudflare Gateway API controller + `cloudflare-gateway` Gateway for public HTTPRoutes |
| `tailscale` | `apps/tailscale/` | Tailscale operator. Tailnet services are exposed through `Ingress` with `ingressClassName: tailscale` |
| `metrics-server` | `apps/metrics-server/` | `kubectl top` / HPA metrics |
| `keda` | `apps/keda/` | Event-driven autoscaling (used by ocidex workers) |
| `local-path-provisioner` | `apps/local-path-provisioner/` | Node-local PVs |
| `synology-csi` | `apps/synology-csi/` | Default StorageClass `synology-csi-iscsi`: one iSCSI LUN per PVC on the Synology. Attaches on `x86-01` only, so consumers pin `kubernetes.io/arch: amd64` |
| `cnpg` | `apps/cnpg/` | CloudNativePG operator |

[`../docs/tailscale-cilium.md`](../docs/tailscale-cilium.md) explains why services use `Ingress` instead of the `tailscale.com/expose` Service annotation. The `tailscale-operator` namespace is `privileged` under Pod Security, because proxy pods need privileged containers for nftables/WireGuard.

### CI

| Kustomization | Path | What |
|---|---|---|
| `tekton` | `apps/tekton/` | Vendored Tekton Pipelines, Triggers, Interceptors, Dashboard, plus a PipelineRun pruner CronJob |
| `tekton-chains` | `apps/tekton-chains/` | Signed SLSA provenance for runs ([README](apps/tekton-chains/README.md)) |
| `pipelines-as-code` | `apps/pipelines-as-code/` | Vendored PAC (GitHub App mode) and a second controller for the `tektonic-ci` org. Webhooks arrive over Tailscale funnel |
| `homelab-ci` | `apps/homelab-ci/` | PAC `Repository` for this repo ([README](apps/homelab-ci/README.md)) |
| `ocidex-ci` | `apps/ocidex-ci/` | PAC `Repository`, registry and API credentials, cache PVCs for ocidex |
| `tektonic-ci` | `apps/tektonic-ci/` | PAC `Repository` and cache PVCs for the tektonic packages |
| `apko-cicd-ci` | `apps/apko-cicd/` | PAC `Repository`, ghcr credentials for apko-cicd |
| `apko-cicd-update` | `.tekton/update` in the `apko-cicd` GitRepository | Scheduled package-update pipeline sourced from the apko-cicd repo |
| `renovate` | `apps/renovate/` | Self-hosted Renovate CronJobs |

The vendored manifests (`tekton/`, `tekton-chains/`, `pipelines-as-code/`) are refreshed with each directory's `update-manifests.sh`. Renovate bumps the version pinned in those scripts.

### Workloads

| Kustomization | Path | What |
|---|---|---|
| `ocidex-dev-*` | `apps/ocidex/dev/*` | OCIDex: Postgres, app, operator, registries, k8s agent ([README](apps/ocidex/README.md)) |
| `monitoring` | `apps/monitoring/` | kube-prometheus-stack, Loki, Tempo, Alloy, Grafana, Alertmanager → Discord |
| `monitoring-extras` | `apps/monitoring-extras/` | ServiceMonitors/PodMonitors and dashboards that need the monitoring CRDs first |
| `dev-spaces` | `apps/dev-spaces/` | `devbox` dev-workspace chart from `ghcr.io/pfenerty/charts` |
| `trek` | `apps/trek/` | TREK, exposed on the tailnet |

## Secrets

Flux decrypts SOPS-encrypted files at apply time. Each Kustomization that contains them sets:

```yaml
spec:
  decryption:
    provider: sops
    secretRef:
      name: sops-age
```

The age private key must be in the cluster:

```bash
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=age.key
```

Encrypted files are named `*.secret.yaml` or `*.enc.yaml`. Most have a plaintext `*.template.yaml` beside them that shows the expected keys.

## Making Changes

Push to `main`. Most Kustomizations reconcile every 10 minutes (ocidex every 5). To force one immediately:

```bash
flux reconcile kustomization <name> --with-source
```

To temporarily stop Flux from overwriting a manual change:

```bash
flux suspend kustomization <name>
# ... make manual changes ...
flux resume kustomization <name>
```
