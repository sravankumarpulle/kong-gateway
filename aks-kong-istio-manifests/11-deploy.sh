#!/usr/bin/env bash
set -euo pipefail
kubectl apply -f 02-app-namespace.yaml
kubectl apply -f 03-kong-gatewayclass.yaml
kubectl apply -f 04-kong-gateway.yaml
kubectl apply -f 05-clusterissuer.yaml
kubectl apply -f 06-certificate.yaml
kubectl apply -f 07-hello-app.yaml
kubectl apply -f 08-hello-route.yaml
kubectl apply -f 09-istio-security.yaml
