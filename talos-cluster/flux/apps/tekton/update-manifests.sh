#!/bin/bash

# Update Tekton manifests
curl -Lo pipelines.yaml https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
curl -Lo triggers.yaml https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml
curl -Lo dashboard.yaml https://storage.googleapis.com/tekton-releases/dashboard/latest/release.yaml
