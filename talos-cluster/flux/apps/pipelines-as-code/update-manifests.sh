#!/bin/sh
# Update the Pipelines as Code manifest from GitHub Releases.
#
# release.yaml is a vendored upstream release, not a hand-maintained file. Re-vendor
# it by bumping PAC_VERSION and re-running this script — never by editing release.yaml,
# and never by bumping the image tags alone. The images are only three lines of a file
# that also carries the CRDs, RBAC and ConfigMap defaults for that same version; moving
# one without the others leaves new binaries running against old CRDs.
#
# That is exactly what happened before this script existed: Renovate's kubernetes
# manager matched release.yaml and bumped the three image tags in place, so the cluster
# ran v0.51.0 binaries against v0.48.0 CRDs and RBAC for months. Renovate now tracks
# PAC_VERSION below instead (see renovate.json), and CI fails if the manifest's image
# tags disagree with it — so a version bump has to come back through this script.
#
# Usage: ./update-manifests.sh
set -eu

PAC_VERSION=v0.51.0

cd "$(dirname "$0")"

url="https://github.com/tektoncd/pipelines-as-code/releases/download/${PAC_VERSION}/release.yaml"
echo "fetching $url"
curl -fsSL -o release.yaml.raw "$url"

# Strip the OpenShift-only pieces: this is a Talos cluster with no route.openshift.io
# API group, so Flux fails to apply the Route, and the RBAC rules granting access to it
# are dead weight. Two edits:
#
#   1. the trailing `Route` document, together with the licence header that precedes it
#      (the header sits at the tail of the previous document, before the `---`)
#   2. the two `route.openshift.io` rules in the controller and watcher ClusterRoles
#
# The two ServiceMonitors that v0.51.0 added are dropped for a different reason: they
# are monitoring.coreos.com/v1, a CRD that kube-prometheus-stack installs, and this
# Kustomization does not (and should not) depend on `monitoring` — CI infrastructure
# waiting on the monitoring stack to be healthy is the wrong way round. They live in
# apps/monitoring-extras/servicemonitor-pac.yaml instead, which already dependsOn
# monitoring. The monitoring Role/RoleBinding stay here: plain RBAC, no CRD needed.
awk '
  # Buffer each ----separated document, then decide whether to emit it.
  function flush() {
    if (buf !~ /\napiVersion: route\.openshift\.io/ && buf !~ /\nkind: ServiceMonitor/) printf "%s", buf
    buf = ""
  }
  /^---$/ { flush(); buf = $0 ORS; next }
  { buf = buf $0 ORS }
  END { flush() }
' release.yaml.raw \
| awk '
  # Drop the 3-line RBAC rule blocks for routes.
  /^  - apiGroups: \["route\.openshift\.io"\]$/ { skip = 3 }
  skip > 0 { skip--; next }
  { print }
' \
| awk '
  # The licence header for the removed Route document is now a trailing comment block
  # with no document under it. Hold any run of trailing comment lines and emit it only
  # if real content follows.
  /^#/ || /^$/ { held = held $0 ORS; next }
  { printf "%s", held; held = ""; print }
' > release.yaml

rm -f release.yaml.raw

echo "wrote release.yaml at ${PAC_VERSION}"
