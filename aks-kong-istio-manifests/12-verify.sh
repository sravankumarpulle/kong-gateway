#!/usr/bin/env bash
set -euo pipefail
HOST=gateway-rgs.eastus.cloudapp.azure.com

echo '=== DNS ==='
nslookup "$HOST"
echo '=== Istio ==='
kubectl get pods -n aks-istio-system
kubectl get pods -n hello-app -o jsonpath='{range .items[*]}{.metadata.name}{" containers="}{range .spec.containers[*]}{.name}{","}{end}{"\n"}{end}'
echo '=== Gateway API ==='
kubectl get gatewayclass kong-class
kubectl get gateway kong-gateway -n kong -o wide
kubectl get httproute hello-world-1 -n hello-app -o yaml
echo '=== Certificate ==='
kubectl get certificate,certificaterequest,order,challenge -A
echo '=== Application ==='
kubectl get deploy,po,svc -n hello-app
echo '=== HTTPS test ==='
curl -vk "https://${HOST}/"
