#!/bin/bash

# Update Tekton manifests from GitHub Releases (GCS /previous/ paths no longer exist)
# Pin to a specific version by changing the tag variables below.
PIPELINES_VERSION=latest
TRIGGERS_VERSION=v0.36.0
DASHBOARD_VERSION=v0.69.0

gh release download "$PIPELINES_VERSION" -R tektoncd/pipeline  --pattern release.yaml    -O pipelines.yaml     --clobber
gh release download "$TRIGGERS_VERSION"  -R tektoncd/triggers  --pattern release.yaml    -O triggers.yaml      --clobber
gh release download "$TRIGGERS_VERSION"  -R tektoncd/triggers  --pattern interceptors.yaml -O interceptors.yaml --clobber
gh release download "$DASHBOARD_VERSION" -R tektoncd/dashboard --pattern release.yaml    -O dashboard.yaml     --clobber
