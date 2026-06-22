#!/bin/bash
# Update the Tekton Chains manifest from GitHub Releases.
# Pin to a specific version by changing the tag below.
CHAINS_VERSION=v0.27.1

gh release download "$CHAINS_VERSION" -R tektoncd/chains --pattern release.yaml -O chains.yaml --clobber
