#!/bin/sh
# Vendored upstream manifests must agree with the version their update script pins.
#
# A release manifest is one file carrying the CRDs, RBAC, ConfigMaps *and* the image
# tags for a single upstream version. Bumping the images alone — which is what a
# generic image-tag updater does when it is pointed at one — leaves new binaries
# running against old CRDs and RBAC. That drifted silently here for months: PAC ran
# v0.51.0 binaries against v0.48.0 CRDs.
#
# Renovate now tracks the *_VERSION variables in each update-manifests.sh instead of
# the manifests (see renovate.json), so a bump arrives as a one-line change to the
# script. This check is the other half: it fails if the manifest does not match, which
# is what forces the script to actually be re-run.
set -eu

# manifest : version variable : update script
SPECS="
talos-cluster/flux/apps/pipelines-as-code/release.yaml:PAC_VERSION:talos-cluster/flux/apps/pipelines-as-code/update-manifests.sh
talos-cluster/flux/apps/pipelines-as-code/tektonic-ci-controller.yaml:PAC_VERSION:talos-cluster/flux/apps/pipelines-as-code/update-manifests.sh
talos-cluster/flux/apps/tekton/pipelines.yaml:PIPELINES_VERSION:talos-cluster/flux/apps/tekton/update-manifests.sh
talos-cluster/flux/apps/tekton/triggers.yaml:TRIGGERS_VERSION:talos-cluster/flux/apps/tekton/update-manifests.sh
talos-cluster/flux/apps/tekton/interceptors.yaml:TRIGGERS_VERSION:talos-cluster/flux/apps/tekton/update-manifests.sh
talos-cluster/flux/apps/tekton/dashboard.yaml:DASHBOARD_VERSION:talos-cluster/flux/apps/tekton/update-manifests.sh
talos-cluster/flux/apps/tekton-chains/chains.yaml:CHAINS_VERSION:talos-cluster/flux/apps/tekton-chains/update-manifests.sh
"

# Manifests whose committed copy is still behind the images in it, from before Renovate
# was pointed away from these files. Re-running the update script fixes one, but each is
# a real upstream upgrade and wants reviewing as such.
#
# This list is a ratchet: it reports the drift without failing the build. Shrink it,
# never grow it. Anything not listed here is enforced.
#
# chains is what is left: pinned at v0.27.1 with v0.29.5 images. Note that its update
# script would *downgrade* the running images if run as-is — bump CHAINS_VERSION to
# match what is deployed before re-vendoring, the way tekton/ was.
KNOWN_DRIFT="talos-cluster/flux/apps/tekton-chains/chains.yaml"

rc=0

# Every registry-qualified image reference in the file, by tag.
#
# Deliberately not keyed on `image:` — Tekton puts the entrypoint, nop,
# sidecarlogresults and workingdirinit images in Deployment args and ConfigMaps, not
# in an image field, and those are precisely the ones a generic image-tag updater
# misses. They are injected into every TaskRun pod by the controller, so a controller
# newer than its entrypoint is a live incompatibility, not a cosmetic one. Matching
# the reference itself catches both.
tags_in() {
    grep -oE '[a-z0-9.-]+\.[a-z]{2,}/[A-Za-z0-9._/-]+:v?[0-9][A-Za-z0-9.+-]*' "$1" \
        | sed 's/.*://' \
        | sort -u
}

for spec in $SPECS; do
    manifest=${spec%%:*}
    rest=${spec#*:}
    var=${rest%%:*}
    script=${rest#*:}

    [ -f "$manifest" ] || { printf 'FAIL  %s is missing\n' "$manifest"; rc=1; continue; }
    [ -f "$script" ]   || { printf 'FAIL  %s is missing\n' "$script";   rc=1; continue; }

    pinned=$(sed -n "s/^${var}=//p" "$script" | head -1 | tr -d '\r"')
    if [ -z "$pinned" ]; then
        printf 'FAIL  %s: %s not found in %s\n' "$manifest" "$var" "$script"
        rc=1
        continue
    fi

    bad=""
    for tag in $(tags_in "$manifest"); do
        [ "$tag" = "$pinned" ] || bad="$bad $tag"
    done

    if [ -z "$bad" ]; then
        printf 'ok    %-58s %s\n' "$manifest" "$pinned"
        continue
    fi

    case "$KNOWN_DRIFT" in
        *"$manifest"*)
            printf 'DRIFT %-58s %s pinned, images:%s (known — re-run %s)\n' \
                "$manifest" "$pinned" "$bad" "$script"
            ;;
        *)
            printf 'FAIL  %-58s %s pinned, images:%s\n' "$manifest" "$pinned" "$bad"
            printf '        images were changed without re-vendoring. Run %s and commit the result.\n' "$script"
            rc=1
            ;;
    esac
done

printf '\n'
if [ "$rc" -eq 0 ]; then
    printf '✓ vendored manifests match their pinned versions (known drift reported above)\n'
else
    printf '✗ a vendored manifest disagrees with its update script\n'
fi
exit "$rc"
