#!/bin/bash

set -e

#Define Parameter
export CLUSTER=kubeflow-pipelines-cluster
export ZONE=us-central1-c
export MACHINE_TYPE=n1-standard-2
export SCOPES="cloud-platform" # This scope is needed for running some pipeline samples. Read the warning below for its security implications.
export PROJECT=aliz-kubeflow-testing
export PIPELINE_VERSION=1.1.0-alpha.1 

gcloud config set project "$PROJECT"

# Create GKE Cluster
#Warning: Using SCOPES="cloud-platform" grants all GCP permissions to the cluster. For a more secure cluster setup
gcloud container clusters create "$CLUSTER" --zone "$ZONE" --machine-type "$MACHINE_TYPE" \
  --scopes $SCOPES

#Configure kubectl to talk to your cluster
gcloud container clusters get-credentials "$CLUSTER" --zone "$ZONE"

#Prerequisites for using Role-Based Access Control
#You must grant your user the ability to create roles in Kubernetes by running the following command.
kubectl create clusterrolebinding cluster-admin-binding \
  --clusterrole cluster-admin \
  --user $(gcloud config get-value account)

#Deploy the Kubeflow Pipelines
kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/cluster-scoped-resources?ref=$PIPELINE_VERSION"
kubectl wait --for condition=established --timeout=60s crd/applications.app.k8s.io
kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/env/dev?ref=$PIPELINE_VERSION"

#Get the public URL for the Kubeflow Pipelines UI and use it to access the Kubeflow Pipelines UI:
echo "========== Kubeflow Pipelines UI =========="
kubectl describe configmap inverse-proxy-config -n kubeflow | grep googleusercontent.com

echo "========== Installation Done =========="
