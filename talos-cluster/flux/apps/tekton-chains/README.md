# Tekton Chains

[Tekton Chains](https://tekton.dev/docs/chains/) controller — observes completed
TaskRuns/PipelineRuns and produces signed SLSA build provenance.

Vendored from the `tektoncd/chains` GitHub release; refresh with `./update-manifests.sh`
(pin the version inside it). Wired into Flux via `../../tekton-chains.kustomization.yaml`
(`dependsOn: tekton`).

## Configuration

`chains-config` is patched in `kustomization.yaml`:

| Setting | Value |
|---------|-------|
| TaskRun / PipelineRun format | `slsa/v2alpha4` (SLSA v1.0 provenance) |
| TaskRun / PipelineRun storage | `tekton, oci` (Run annotations + Rekor, **and** attestations attached to the built images) |
| Signer | `x509` (cosign key in `signing-secrets`) |
| Pipeline deep inspection | enabled (captures child TaskRun subjects) |
| OCI storage | `oci` — signs images (simplesigning) + attaches SLSA attestations; **needs registry push creds on the run namespace's SA** (below) |
| Transparency | enabled → public Rekor (`https://rekor.sigstore.dev`) |

> **Note:** transparency uploads make the signing public key and run metadata public.

## Required: registry credentials for OCI storage

With `artifacts.oci.storage: oci`, Chains pushes image signatures and SLSA attestations to
the registry. **It authenticates as the TaskRun's ServiceAccount — the `default` SA in the
*run* namespace — NOT the `tekton-chains-controller` SA.** (go-containerregistry's k8schain
reads the run pod's SA, which is the controller's only for the controller's own pod.)

So the credential lives with each run namespace, not here. Link a ghcr token
(`write:packages` on `ghcr.io/pfenerty/*`) to that namespace's `default` SA via its app's
`service-account.yaml`, e.g. `apps/ocidex-ci/service-account.yaml` and
`apps/apko-cicd/service-account.yaml`:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
    name: default
    namespace: ocidex-ci
secrets:            # what Chains reads to authenticate the OCI push
    - name: ghcr-docker-config
imagePullSecrets:
    - name: ghcr-docker-config
```

Until that SA has the creds, signing still works (tekton storage + Rekor) but OCI pushes log
`UNAUTHORIZED`. No controller restart is needed — the credential is read per-run.

## Required: the signing key

Chains needs a `signing-secrets` Secret in the `tekton-chains` namespace, or the controller
logs signing errors. It is **not** committed here — create it with `cosign` (one of):

**A. Directly in the cluster (simplest; key lives only in-cluster):**

```bash
cosign generate-key-pair k8s://tekton-chains/signing-secrets
```

**B. GitOps (SOPS-encrypted in this repo):**

```bash
cosign generate-key-pair                       # → cosign.key, cosign.pub (set a password)
kubectl create secret generic signing-secrets \
  -n tekton-chains \
  --from-file=cosign.key \
  --from-file=cosign.pub \
  --from-literal=cosign.password=<password> \
  --dry-run=client -o yaml > signing-secrets.secret.yaml
sops -e -i signing-secrets.secret.yaml         # age recipient comes from ../../../../.sops.yaml
```

Then add `signing-secrets.secret.yaml` to `resources:` in `kustomization.yaml` and add a
`decryption: { provider: sops, secretRef: { name: sops-age } }` block to
`../../tekton-chains.kustomization.yaml` (as `pac.kustomization.yaml` does).

## Verifying provenance

```bash
# public key for verification
cosign public-key --key k8s://tekton-chains/signing-secrets
# a signed PipelineRun carries chains.tekton.dev/signed=true and a transparency annotation
kubectl get pipelinerun <name> -o jsonpath='{.metadata.annotations}'
```
