#!/usr/bin/env bash
set -euo pipefail
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true \
  --set config.enableGatewayAPI=true
kubectl rollout status deployment/cert-manager -n cert-manager --timeout=5m
kubectl rollout status deployment/cert-manager-webhook -n cert-manager --timeout=5m
kubectl rollout status deployment/cert-manager-cainjector -n cert-manager --timeout=5m
