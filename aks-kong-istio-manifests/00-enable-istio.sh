#!/usr/bin/env bash
set -euo pipefail

: "${RESOURCE_GROUP:?Set RESOURCE_GROUP}"
: "${AKS_CLUSTER:?Set AKS_CLUSTER}"
: "${LOCATION:=eastus}"

az aks mesh get-revisions --location "$LOCATION" -o table
az aks mesh enable --resource-group "$RESOURCE_GROUP" --name "$AKS_CLUSTER"

REVISION=$(az aks show --resource-group "$RESOURCE_GROUP" --name "$AKS_CLUSTER" --query 'serviceMeshProfile.istio.revisions[0]' -o tsv)
echo "Istio revision: $REVISION"

kubectl get pods -n aks-istio-system
kubectl label namespace kong istio.io/rev="$REVISION" --overwrite
kubectl apply -f 02-app-namespace.yaml
kubectl label namespace hello-app istio.io/rev="$REVISION" --overwrite

echo "Restart Kong after its Helm installation so the Envoy sidecar is injected:"
echo "kubectl rollout restart deployment -n kong"
echo "kubectl rollout status deployment -n kong --timeout=5m"
