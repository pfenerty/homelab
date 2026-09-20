#!/bin/sh
# Structural checks on the Flux Kustomization tree that `kustomize build` cannot make:
# a manifest nothing references, a spec.path pointing nowhere, a dependsOn naming a
# Kustomization that does not exist. Each of these has shipped to main at least once.
set -eu

FLUX_DIR="talos-cluster/flux"
ROOT_KS="$FLUX_DIR/kustomization.yaml"

# Kustomization files deliberately not wired into the root kustomization.
#
# Empty, and worth keeping that way: the three that used to be here (binfmt, zot,
# podinfo) were deleted rather than carried, so every *.kustomization.yaml in the tree
# is now reachable. An entry here is a manifest that exists but does nothing, which is
# indistinguishable from a mistake — prefer deleting it.
ALLOWED_ORPHANS=""

rc=0
fail() { printf 'FAIL  %s\n' "$*"; rc=1; }
ok()   { printf 'ok    %s\n' "$*"; }

printf '── every *.kustomization.yaml is referenced from the root ──\n'
for f in "$FLUX_DIR"/*.kustomization.yaml; do
    base=$(basename "$f")
    stem=${base%.kustomization.yaml}
    if grep -q -- "- *$base\$" "$ROOT_KS"; then
        ok "$base"
        continue
    fi
    case " $ALLOWED_ORPHANS " in
        *" $stem "*) printf 'skip  %s (allow-listed, see ALLOWED_ORPHANS)\n' "$base"; continue ;;
    esac
    fail "$base is not referenced from $ROOT_KS — it will never reconcile"
done

printf '\n── every spec.path in this repo exists ──\n'
for f in "$FLUX_DIR"/*.kustomization.yaml; do
    base=$(basename "$f")
    src=$(yq -r '.spec.sourceRef.name // ""' "$f")
    # Kustomizations sourced from another repo's GitRepository point at a path in
    # that repo, which this checkout does not have.
    [ "$src" = "flux-system" ] || { printf 'skip  %s (sourceRef: %s)\n' "$base" "$src"; continue; }
    p=$(yq -r '.spec.path // ""' "$f")
    p=${p#./}
    if [ -n "$p" ] && [ -d "$p" ]; then
        ok "$base -> $p"
    else
        fail "$base: spec.path '$p' does not exist"
    fi
done

printf '\n── every dependsOn names a Kustomization that exists ──\n'
known=$(for f in "$FLUX_DIR"/*.kustomization.yaml; do yq -r '.metadata.name' "$f"; done | sort -u)
for f in "$FLUX_DIR"/*.kustomization.yaml; do
    base=$(basename "$f")
    deps=$(yq -r '.spec.dependsOn // [] | .[] | .name' "$f")
    [ -n "$deps" ] || continue
    for d in $deps; do
        if printf '%s\n' "$known" | grep -qx -- "$d"; then
            ok "$base dependsOn $d"
        else
            fail "$base: dependsOn '$d' matches no Kustomization in $FLUX_DIR"
        fi
    done
done

printf '\n'
[ "$rc" -eq 0 ] && printf '✓ flux wiring is consistent\n' || printf '✗ flux wiring problems found\n'
exit "$rc"
