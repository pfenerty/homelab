#!/bin/bash
# Update the Tekton Chains manifest from GitHub Releases.
# Pin to a specific version by changing the tag below.
CHAINS_VERSION=v0.27.1

gh release download "$CHAINS_VERSION" -R tektoncd/chains --pattern release.yaml -O chains.yaml.raw --clobber

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
