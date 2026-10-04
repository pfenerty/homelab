#!/bin/sh
# Update the Tekton Chains manifest from GitHub Releases.
#
# CHAINS_VERSION is the vendored version — Renovate tracks it (see renovate.json) and CI
# fails if chains.yaml's images disagree with it, so bump it and re-run this script; never
# edit chains.yaml in place. curl rather than `gh`, like the other update scripts, so it
# runs without an authenticated GitHub CLI.
#
# Usage: ./update-manifests.sh
set -eu

CHAINS_VERSION=v0.29.7

cd "$(dirname "$0")"

url="https://github.com/tektoncd/chains/releases/download/${CHAINS_VERSION}/release.yaml"
echo "fetching $url"
curl -fsSL -o chains.yaml.raw "$url"

# Strip the empty `signing-secrets` Secret placeholder from the release — we manage
# that secret via the SOPS-encrypted signing-secrets.secret.yaml, and two resources
# with the same id make Flux fail with "in Replace: id matched 2 resources".
awk '
  function flush() {
    if (!(buf ~ /\nkind: Secret\n/ && buf ~ /\n  name: signing-secrets\n/)) printf "%s", buf
    buf = ""
  }
  /^---$/ { flush(); buf = $0 ORS; next }
  { buf = buf $0 ORS }
  END { flush() }
' chains.yaml.raw > chains.yaml
rm -f chains.yaml.raw

echo "wrote chains.yaml at ${CHAINS_VERSION}"
