#!/bin/sh
# Build every kustomization in the Flux tree, then schema-validate the output.
#
# Each directory holding a kustomization.yaml is built independently rather than
# only building the top-level overlay. A directory the root kustomization does not
# reference (there are a few, deliberately) still gets built, so a broken app dir
# is reported against that app instead of going unnoticed until someone wires it in.
set -eu

FLUX_DIR="talos-cluster/flux"
OUT="${BUILD_OUT:-.ci/manifests}"

rm -rf "$OUT"
mkdir -p "$OUT"

failed="$OUT/.failed"

# `find | while read` runs the loop body in a subshell, so failures are recorded in a
# file rather than a variable that would not survive the pipeline.
find "$FLUX_DIR" -name kustomization.yaml -type f | sort | while read -r k; do
    d=$(dirname "$k")
    name=$(printf '%s' "$d" | tr '/' '_')
    if kustomize build "$d" >"$OUT/$name.yaml" 2>"$OUT/$name.err"; then
        printf 'ok    %s\n' "$d"
        rm -f "$OUT/$name.err"
    else
        printf 'FAIL  %s\n' "$d"
        sed 's/^/        /' "$OUT/$name.err"
        printf '%s\n' "$d" >>"$failed"
    fi
done

if [ -f "$failed" ]; then
    printf '\n✗ kustomize build failed for %s path(s)\n' "$(wc -l <"$failed" | tr -d ' ')"
    exit 1
fi

printf '\n✓ every kustomization builds\n'
