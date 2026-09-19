#!/bin/sh
# Validate the Talos machine-config patches, without the cluster's real secrets.
#
# `make generate` decrypts talos/secrets.yaml so the real PKI is baked into the node
# configs. CI has no age key and should not be given one: what a pull request changes
# is the *patches*, and those validate identically against throwaway PKI. Each run
# generates a fresh secrets bundle with `talosctl gen secrets` and throws it away.
#
# Run it locally the same way: .tektonic/scripts/validate-talos-patches.sh
set -eu

cd "$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)/talos-cluster"

# The Makefile is the source of truth for versions and node names; reading them back
# out keeps this check from drifting away from what `make generate` actually does.
mk() { sed -n "s/^$1[[:space:]]*:=[[:space:]]*//p" Makefile | head -1 | sed 's/[[:space:]]*$//'; }

CLUSTER_NAME=$(mk CLUSTER_NAME)
ENDPOINT=$(mk ENDPOINT)
TALOS_VERSION=$(mk TALOS_VERSION)
KUBERNETES_VERSION=$(mk KUBERNETES_VERSION)
NODES=$(mk NODES)
WORKER_NODES=$(mk WORKER_NODES)

for v in CLUSTER_NAME ENDPOINT TALOS_VERSION KUBERNETES_VERSION NODES WORKER_NODES; do
    eval "val=\$$v"
    [ -n "$val" ] || { printf 'could not read %s from talos-cluster/Makefile\n' "$v" >&2; exit 1; }
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

# Prefer a talosctl already on PATH (local runs); otherwise fetch the one the
# Makefile pins, so CI validates against the version the cluster is going to.
if [ -n "${TALOSCTL:-}" ]; then
    :
elif command -v talosctl >/dev/null 2>&1; then
    TALOSCTL=talosctl
else
    case "$(uname -m)" in
        x86_64)        arch=amd64 ;;
        aarch64|arm64) arch=arm64 ;;
        *) printf 'unsupported architecture: %s\n' "$(uname -m)" >&2; exit 1 ;;
    esac
    TALOSCTL="$tmp/talosctl"
    printf 'fetching talosctl %s (%s)\n' "$TALOS_VERSION" "$arch"
    curl -fsSL -o "$TALOSCTL" \
        "https://github.com/siderolabs/talos/releases/download/$TALOS_VERSION/talosctl-linux-$arch"
    chmod +x "$TALOSCTL"
fi

printf 'cluster=%s endpoint=%s talos=%s k8s=%s\n\n' \
    "$CLUSTER_NAME" "$ENDPOINT" "$TALOS_VERSION" "$KUBERNETES_VERSION"

"$TALOSCTL" gen secrets -o "$tmp/secrets.yaml" >/dev/null

# Mirrors the $(OUTPUT)/controlplane.yaml rule in the Makefile.
"$TALOSCTL" gen config "$CLUSTER_NAME" "$ENDPOINT" \
    --with-secrets "$tmp/secrets.yaml" \
    --talos-version "$TALOS_VERSION" \
    --kubernetes-version "${KUBERNETES_VERSION#v}" \
    --output "$tmp/cc" \
    --config-patch "@talos/patches/all-nodes.yaml" \
    --config-patch-control-plane "@talos/patches/controlplane.yaml" \
    --force >/dev/null

rc=0
validate() { # <node> <base config>
    node=$1
    base=$2
    if ! "$TALOSCTL" machineconfig patch "$base" \
        --patch "@talos/patches/$node-network.yaml" \
        --output "$tmp/cc/$node.yaml" >/dev/null 2>"$tmp/err"; then
        printf 'FAIL  %s (patch)\n' "$node"; sed 's/^/        /' "$tmp/err"; rc=1; return
    fi
    if "$TALOSCTL" validate --config "$tmp/cc/$node.yaml" --mode metal >/dev/null 2>"$tmp/err"; then
        printf 'ok    %s\n' "$node"
    else
        printf 'FAIL  %s (validate)\n' "$node"; sed 's/^/        /' "$tmp/err"; rc=1
    fi
}

for n in $NODES;        do validate "$n" "$tmp/cc/controlplane.yaml"; done
for n in $WORKER_NODES; do validate "$n" "$tmp/cc/worker.yaml";       done

printf '\n'
if [ "$rc" -eq 0 ]; then
    printf '✓ all node configs generate and validate\n'
else
    printf '✗ Talos patch validation failed\n'
fi
exit "$rc"
