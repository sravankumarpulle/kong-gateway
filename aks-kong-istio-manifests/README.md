# AKS + Kong Gateway + AKS Managed Istio

Traffic path:

`Front Door Premium -> Application Gateway WAF v2 -> Kong Gateway -> Envoy sidecar + application`

Istio is used for east-west service traffic and mTLS. Kong remains the north-south Gateway API implementation. The Kong namespace is added to the mesh so Kong-to-application traffic can satisfy STRICT mTLS.

## Assumptions

- AKS already exists.
- Kong Gateway and Kong Ingress Controller are installed in namespace `kong`.
- Kong proxy Service is `LoadBalancer` as requested.
- `gateway-rgs.eastus.cloudapp.azure.com` resolves publicly to the Kong LoadBalancer public IP before requesting the production certificate.
- Gateway API CRDs are installed before cert-manager starts with Gateway API support.

## Order

1. Run `01-gateway-api-crds.sh`.
2. Install Kong Gateway/KIC in namespace `kong`.
3. Run `00-enable-istio.sh` and restart Kong so its Pods receive Envoy sidecars.
4. Run `10-install-cert-manager.sh`.
5. Replace `REPLACE_WITH_REAL_EMAIL` in `05-clusterissuer.yaml`.
6. Confirm DNS points to the Kong public IP.
7. Run `11-deploy.sh`.
8. Run `12-verify.sh`.

## DNS check

The `nslookup` result must match the Kong proxy Service external IP. If using an Azure Public IP DNS label, ensure that label is assigned to the exact Public IP used by Kong's LoadBalancer Service.

## Production notes

- Pin tested Helm chart, controller, Gateway API, cert-manager and workload image versions.
- Replace `allowedRoutes.namespaces.from: All` with a namespace selector for multi-tenant production clusters.
- Apply NetworkPolicies and Pod Security Admission separately.
- If Front Door and Application Gateway are already the only public entry points, prefer an internal Kong LoadBalancer and private DNS instead of exposing Kong publicly.
- Do not add an Istio ingress gateway to this path unless there is an explicit second ingress use case.
