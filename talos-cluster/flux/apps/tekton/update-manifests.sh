#!/bin/bash

# Update Tekton manifests from GitHub Releases (GCS /previous/ paths no longer exist)
#
# These variables are the vendored version of each manifest: what is actually committed
# here, not what is available upstream. Renovate tracks them (see renovate.json) and CI
# fails if a manifest's image tags disagree with its variable, so a bump means re-running
# this script and committing the result — never editing the manifests in place.
#
# PIPELINES_VERSION was `latest`, which made this script non-reproducible: two runs on
# different days vendored different releases, and the variable told you nothing about
# what was in the file.
PIPELINES_VERSION=v1.6.0
TRIGGERS_VERSION=v0.36.0
DASHBOARD_VERSION=v0.69.0

gh release download "$PIPELINES_VERSION" -R tektoncd/pipeline  --pattern release.yaml    -O pipelines.yaml     --clobber
gh release download "$TRIGGERS_VERSION"  -R tektoncd/triggers  --pattern release.yaml    -O triggers.yaml      --clobber
gh release download "$TRIGGERS_VERSION"  -R tektoncd/triggers  --pattern interceptors.yaml -O interceptors.yaml --clobber
gh release download "$DASHBOARD_VERSION" -R tektoncd/dashboard --pattern release.yaml    -O dashboard.yaml     --clobber
