# homelab-ci

Namespace and PAC `Repository` CR for this repository's own CI. The pipelines live
in `.tekton/` at the repo root and are generated from `.tektonic/`.

## What this directory does and does not do

It authorises PAC to run pipelines for `https://github.com/pfenerty/homelab` in the
`homelab-ci` namespace. That is all.

It does **not** deliver GitHub events. PAC is configured here in **GitHub App** mode —
`pipelines-as-code-secret` in the `pipelines-as-code` namespace holds the app ID,
private key and webhook secret — and in that mode events arrive through the app's
webhook. The app must therefore be **installed on this repository**. Creating the
`Repository` CR does not install it, and PAC has no way to ask for it.

So a repository onboarded to CI needs two things, and only one of them is in git:

1. this directory (`Repository` CR + namespace) — Flux applies it
2. the PAC GitHub App granted access to the repository — done once, by hand, at
   `https://github.com/settings/installations`

If pipelines never start and no check run ever appears on a pull request — not a
failed one, none at all — step 2 is the first thing to check. PAC never saw the event.

## Verifying

```bash
# 1. Flux applied the Repository CR
flux get kustomization homelab-ci
kubectl get repository -n homelab-ci homelab

# 2. PAC received the event (nothing here means the app is not installed)
kubectl logs -n pipelines-as-code deploy/pipelines-as-code-controller | grep -i homelab

# 3. Something was created
kubectl get pipelinerun -n homelab-ci
```

The `Repository` CR's `spec.url` must match the repository's canonical URL exactly.
It is `https://github.com/pfenerty/homelab`, lower-case — note that
`flux-system/gotk-sync.yaml` spells it `pfenerty/Homelab`, which GitHub redirects but
PAC would not match.
