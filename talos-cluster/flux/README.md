# flux/

Flux CD reconciles this directory from `main` continuously. The `flux-system`
GitRepository polls on a **1 minute** interval, so a change on `main` reaches the
cluster about as fast as you can push it — which is why everything here is validated
in CI before merge.

## Layout

```
flux/
├── kustomization.yaml          # Root: lists every *.kustomization.yaml below
├── flux-system/                # Flux itself (managed by `flux bootstrap` — do not hand-edit)
├── <name>.kustomization.yaml   # One Flux Kustomization per app
├── cilium/                     # CNI — its own Kustomization, reconciled first
├── gateway-api/                # Gateway API CRDs
└── apps/<name>/                # The manifests each Kustomization points at
```

Each app is two pieces: a `<name>.kustomization.yaml` at this level (the Flux
`Kustomization` — interval, dependsOn, decryption, health checks) and an
`apps/<name>/` directory (the manifests it applies).

**A `*.kustomization.yaml` the root `kustomization.yaml` does not list will never
reconcile.** Nothing in Kubernetes complains; the app simply is not there. CI checks
for exactly this, along with `spec.path` values that do not exist and `dependsOn`
naming a Kustomization that has been removed.

## Ordering

Ordering is expressed with `dependsOn`, not directory layout. Cilium is the deepest
root — the CNI has to be up before anything is schedulable — and `tekton` gates
everything CI.

| Kustomization | Waits for |
|---|---|
| `apko-cicd-ci` | `tekton`, `pipelines-as-code` |
| `apko-cicd-update` | `apko-cicd-ci`, `tekton` |
| `cilium` | — (root) |
| `cloudflare-gateway` | `cilium`, `gateway-api` |
| `cnpg` | — (root) |
| `dev-spaces` | `cilium` |
| `gateway-api` | — (root) |
| `homelab-ci` | `tekton`, `pipelines-as-code` |
| `hubble` | `cilium` |
| `keda` | — (root) |
| `local-path-provisioner` | — (root) |
| `metrics-server` | `cilium` |
| `monitoring` | `tailscale`, `nfs-subdir-provisioner` |
| `monitoring-extras` | `monitoring` |
| `nfs-subdir-provisioner` | — (root) |
| `ocidex-ci` | `tekton`, `pipelines-as-code` |
| `ocidex-dev-infra` | `cnpg` |
| `ocidex-dev-k8s-agent` | `ocidex-dev-main` |
| `ocidex-dev-main` | `ocidex-dev-infra`, `cilium`, `cloudflare-gateway`, `keda` |
| `ocidex-dev-operator` | `ocidex-dev-main` |
| `ocidex-dev-registries` | `ocidex-dev-operator` |
| `pipelines-as-code` | `tekton`, `tailscale` |
| `renovate` | — (root) |
| `tailscale` | `cilium` |
| `tekton` | `cilium` |
| `tekton-chains` | `tekton` |
| `trek` | — (root) |

`apko-cicd-update` is the one Kustomization whose `spec.path` is not in this
repository: it points at `./.tekton/update` in the `apko-cicd` GitRepository.

## Not currently reconciled

Three Kustomizations exist but are deliberately absent from the root
`kustomization.yaml`, so they do nothing:

| | Why |
|---|---|
| `binfmt` | `tonistiigi/binfmt` registers qemu in its own container mount namespace, which does not persist host-globally on Talos, so cross-arch melange builds still fail. Needs a host-init-namespace registrar first. |
| `zot` | Parked — never enabled. |
| `podinfo` | Parked — never enabled. |

They are listed in `ALLOWED_ORPHANS` in `.tektonic/scripts/check-flux-wiring.sh` so the
orphan check can be enforced for everything else. That list is a ratchet: shrink it,
never grow it.

## Secrets

SOPS-encrypted files are decrypted by Flux at reconcile time. Each Kustomization that
needs it carries `spec.decryption.provider: sops` with `secretRef: sops-age`, and the
age key must exist in the cluster:

```bash
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=age.key
```

CI fails if anything matching the patterns in `.sops.yaml` is committed unencrypted.

## Vendored upstream manifests

`apps/pipelines-as-code/release.yaml`, `apps/tekton/*.yaml` and
`apps/tekton-chains/chains.yaml` are vendored upstream releases. Re-vendor them by
bumping the version in that app's `update-manifests.sh` and re-running it — never by
editing the manifest, and never by bumping image tags alone, which leaves new binaries
running against old CRDs. Renovate tracks the script pins; CI enforces that the
manifest agrees.

`apps/cloudflare-gateway/` does it the better way where upstream allows: a
`GitRepository` pinned to a tag plus a Kustomization that builds upstream's own config
at reconcile time, so there is nothing vendored to drift.

## Making changes

Push to `main`. To force a reconcile rather than wait:

```bash
flux reconcile kustomization <name> --with-source
```

To stop Flux overwriting a manual change while you debug:

```bash
flux suspend kustomization <name>
# ...
flux resume kustomization <name>
```

`make upgrade-x86-01` suspends `ocidex-dev-infra` for exactly this reason.
