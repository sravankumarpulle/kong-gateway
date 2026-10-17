#!/usr/bin/env bash
set -euo pipefail
# Pin this version after validating compatibility with your installed Kong Ingress Controller.
GATEWAY_API_VERSION="v1.4.0"
kubectl apply --server-side -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"
kubectl get crd gateways.gateway.networking.k8s.io httproutes.gateway.networking.k8s.io gatewayclasses.gateway.networking.k8s.io
