#!/usr/bin/env bash
# Runs `talosctl upgrade-k8s` under a watchdog.
#
# talosctl can sit at `"<ip>": waiting for kubelet restart` forever when it
# misses the kubelet service restart event (seen 2026-10-11 on 192.168.1.103:
# kubelet had restarted healthy on the new version, talosctl never noticed).
# upgrade-k8s is idempotent — a re-run skips components already at the target —
# so on a stall we kill it and run it again.
#
# Usage: upgrade-k8s.sh <version> [talosctl upgrade-k8s flags...]
set -uo pipefail

TO="$1"; shift
MAX_ATTEMPTS=${MAX_ATTEMPTS:-5}
# Stuck on "waiting for kubelet restart" this long while the node already
# reports the target kubelet and Ready -> treat as missed event.
KUBELET_GRACE_SECS=${KUBELET_GRACE_SECS:-120}
# No output at all for this long -> treat as hung (manifest reconcile waits 5m).
STALL_SECS=${STALL_SECS:-900}
POLL_SECS=${POLL_SECS:-15}

log=$(mktemp -t upgrade-k8s.XXXXXX)
pid="" tailpid=""
trap 'kill $pid $tailpid 2>/dev/null; rm -f "$log"' EXIT

# True when the node with this InternalIP runs kubelet v$TO and is Ready.
kubelet_at_target() {
  kubectl get nodes -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address} {.status.nodeInfo.kubeletVersion} {.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null \
    | awk -v ip="$1" -v v="v$TO" '$1 == ip && $2 == v && $3 == "True" { f = 1 } END { exit !f }'
}

for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
  echo "── talosctl upgrade-k8s --to $TO (attempt $attempt/$MAX_ATTEMPTS)"
  : >"$log"
  talosctl upgrade-k8s --to "$TO" "$@" >"$log" 2>&1 &
  pid=$!
  tail -n +1 -f "$log" &
  tailpid=$!

  stalled="" last_size=0 last_change=$SECONDS
  while kill -0 "$pid" 2>/dev/null; do
    sleep "$POLL_SECS"
    size=$(wc -c <"$log")
    if [ "$size" -ne "$last_size" ]; then last_size=$size; last_change=$SECONDS; fi
    idle=$((SECONDS - last_change))

    last=$(tail -n 1 "$log")
    ip=$(sed -n 's/.*"\([0-9.]*\)": waiting for kubelet restart.*/\1/p' <<<"$last")
    if [ -n "$ip" ] && [ "$idle" -ge "$KUBELET_GRACE_SECS" ] && kubelet_at_target "$ip"; then
      stalled="kubelet on $ip is already v$TO and Ready, talosctl missed the restart"
    elif [ "$idle" -ge "$STALL_SECS" ]; then
      stalled="no output for ${idle}s"
    fi
    if [ -n "$stalled" ]; then
      kill "$pid" 2>/dev/null
      break
    fi
  done

  wait "$pid" 2>/dev/null; rc=$?
  sleep 1; kill "$tailpid" 2>/dev/null; wait "$tailpid" 2>/dev/null
  pid="" tailpid=""

  if [ -z "$stalled" ]; then
    exit "$rc"
  fi
  echo "⚠ $stalled — restarting upgrade-k8s"
done

echo "✗ upgrade-k8s still stalling after $MAX_ATTEMPTS attempts" >&2
exit 1
