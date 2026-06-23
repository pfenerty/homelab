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
| OCI storage | `oci` — signs images (simplesigning) + attaches SLSA attestations; **needs registry push creds** (below) |
| Transparency | enabled → public Rekor (`https://rekor.sigstore.dev`) |

> **Note:** transparency uploads make the signing public key and run metadata public.

## Required: registry credentials for OCI storage

With `artifacts.oci.storage: oci`, the controller pushes image signatures and SLSA
attestations to the registry, so the `tekton-chains-controller` ServiceAccount needs a ghcr
token with `write:packages` on `ghcr.io/pfenerty/*`. Until it has one, signing still works
(tekton storage + Rekor) but OCI pushes log auth errors.

```bash
kubectl create secret docker-registry chains-registry -n tekton-chains \
  --docker-server=ghcr.io --docker-username=pfenerty --docker-password=<GHCR_WRITE_TOKEN> \
  --dry-run=client -o yaml > chains-registry.secret.yaml
sops -e -i chains-registry.secret.yaml
# add chains-registry.secret.yaml to kustomization.yaml resources, then attach it to the
# controller SA (go-containerregistry's k8schain reads the SA's imagePullSecrets):
#   kubectl patch sa tekton-chains-controller -n tekton-chains \
#     -p '{"imagePullSecrets":[{"name":"chains-registry"}]}'
# then: kubectl -n tekton-chains rollout restart deploy/tekton-chains-controller
```

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
