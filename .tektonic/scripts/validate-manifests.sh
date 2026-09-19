#!/bin/sh
# Schema-validate the manifests produced by build-manifests.sh.
#
# The cluster's Kubernetes version comes from the Makefile that generates the node
# configs, so this validates against the version the cluster will actually run
# rather than whatever kubeconform defaults to.
set -eu

OUT="${BUILD_OUT:-.ci/manifests}"
MAKEFILE="talos-cluster/Makefile"

k8s=$(sed -n 's/^KUBERNETES_VERSION[[:space:]]*:=[[:space:]]*//p' "$MAKEFILE" | head -1 | tr -d ' ')
k8s=${k8s#v}
[ -n "$k8s" ] || { echo "could not read KUBERNETES_VERSION from $MAKEFILE" >&2; exit 1; }

set -- "$OUT"/*.yaml
[ -e "$1" ] || { echo "no manifests in $OUT — did build-manifests.sh run?" >&2; exit 1; }

printf 'validating against Kubernetes v%s\n\n' "$k8s"

# -ignore-missing-schemas keeps CRDs the catalog does not carry (ocidex, trek, zot,
# and friends) from failing the run; the catalog covers the ones that matter here —
# HelmRelease, Kustomization, HelmRepository, Repository, Cluster.
exec kubeconform \
    -strict \
    -ignore-missing-schemas \
    -summary \
    -kubernetes-version "$k8s" \
    -schema-location default \
    -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
    "$@"
