#!/bin/bash

# uninstall Kubeflow Pipelines
export PIPELINE_VERSION=1.1.0-alpha.1 
kubectl delete -k "github.com/kubeflow/pipelines/manifests/kustomize/env/dev?ref=$PIPELINE_VERSION"
kubectl delete -k "github.com/kubeflow/pipelines/manifests/kustomize/cluster-scoped-resources?ref=$PIPELINE_VERSION"
sleep 10
# Delete GKE Cluster
export CLUSTER=kubeflow-pipelines-cluster
export ZONE=us-central1-c
gcloud container clusters delete "$CLUSTER" --zone "$ZONE"
