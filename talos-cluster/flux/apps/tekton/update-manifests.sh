#!/bin/sh
# Re-vendor the Tekton manifests from GitHub Releases.
#
# These variables are the vendored version of each manifest — what is committed here,
# not what is available upstream. Renovate tracks them (see renovate.json) and CI fails
# if a manifest's image references disagree with its variable, so a version bump means
# re-running this script and committing the result, never editing a manifest in place.
#
# Why that matters here specifically: Renovate's kubernetes manager used to rewrite the
# image tags in these files directly. It only sees `image:` fields, so it moved the
# Deployments and left behind every image passed as a *flag*. That put a v1.16.0
# pipelines controller in charge of a v1.6.0 entrypoint — the binary injected into every
# TaskRun pod — and a v0.37.0 triggers controller with a v0.36.0 eventlistenersink.
# Neither is visible in a Deployment spec, and neither showed up as a failure until a
# pod misbehaved.
#
# curl rather than `gh`: this needs to run anywhere, including CI, without the GitHub
# CLI installed or authenticated. These are public release assets.
#
# Usage: ./update-manifests.sh
set -eu

PIPELINES_VERSION=v1.16.0
TRIGGERS_VERSION=v0.37.0
DASHBOARD_VERSION=v0.72.0

cd "$(dirname "$0")"

fetch() { # <url> <dest>
    echo "fetching $1"
    curl -fsSL -o "$2" "$1"
}

base=https://github.com/tektoncd
fetch "$base/pipeline/releases/download/$PIPELINES_VERSION/release.yaml"      pipelines.yaml
fetch "$base/triggers/releases/download/$TRIGGERS_VERSION/release.yaml"       triggers.yaml
fetch "$base/triggers/releases/download/$TRIGGERS_VERSION/interceptors.yaml"  interceptors.yaml
fetch "$base/dashboard/releases/download/$DASHBOARD_VERSION/release.yaml"     dashboard.yaml

echo "wrote pipelines $PIPELINES_VERSION, triggers $TRIGGERS_VERSION, dashboard $DASHBOARD_VERSION"
