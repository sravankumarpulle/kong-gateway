This is the recommended production approach.
### note: this is not tested
With Gateway API + Kong + cert-manager, you do not manually renew certificates. Cert-manager automatically:

Requests certificate from Let's Encrypt
Creates Kubernetes TLS Secret
Renews before expiry
Updates the Secret
Kong automatically serves the renewed certificate
Architecture
Internet
    |
Let's Encrypt
    |
cert-manager
    |
Certificate CR
    |
TLS Secret
    |
Gateway
    |
HTTPRoute
    |
Application

Install cert-manager
helm repo add jetstack https://charts.jetstack.io

helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true


Verify:

kubectl get pods -n cert-manager

Create ClusterIssuer
letsencrypt-prod.yaml

Replace email.

apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: sravan@example.com

    server: https://acme-v02.api.letsencrypt.org/directory

    privateKeySecretRef:
      name: letsencrypt-prod

    solvers:
    - http01:
        gatewayHTTPRoute:
          parentRefs:
          - name: kong-gateway
            namespace: kong


Apply:

kubectl apply -f letsencrypt-prod.yaml

Create Certificate Object
certificate.yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: gateway-rgs-cert
  namespace: kong
spec:
  secretName: gateway-rgs-tls

  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer

  dnsNames:
  - gateway-rgs.eastus.cloudapp.azure.com


Apply:

kubectl apply -f certificate.yaml


Check:

kubectl get certificate -n kong


Check Secret:

kubectl get secret gateway-rgs-tls -n kong

Reference Secret from Gateway
kong-gw-gateway.yml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: kong-gateway
  namespace: kong
spec:
  gatewayClassName: kong-class

  listeners:
  - name: https
    hostname: gateway-rgs.eastus.cloudapp.azure.com
    port: 443
    protocol: HTTPS

    tls:
      mode: Terminate

      certificateRefs:
      - kind: Secret
        name: gateway-rgs-tls

    allowedRoutes:
      namespaces:
        from: All

HTTPRoute

No TLS configuration here.

apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: example-1
spec:
  parentRefs:
  - name: kong-gateway
    namespace: kong

  hostnames:
  - gateway-rgs.eastus.cloudapp.azure.com

  rules:
  - backendRefs:
    - name: hello-world-1-svc
      port: 80

Auto Renewal Process

Certificate validity:

90 days


Cert-manager automatically renews around:

~30 days before expiry


Flow:

Old Secret
    |
Cert-manager renews
    |
New Secret
    |
Gateway reads updated secret
    |
HTTPS continues without downtime


No manual action required.

Enterprise AKS Pattern (Recommended)

Since you already work with AKS and Key Vault, the typical production setup is:

Azure DNS
    |
cert-manager
    |
Let's Encrypt DNS01 Challenge
    |
Azure Managed Identity
    |
Azure DNS Zone
    |
Kubernetes Secret
    |
Gateway


Advantages:

No HTTP validation required
Wildcard certificates supported
Automatic renewal
Suitable for production
Works well with Key Vault integration

Example wildcard:

*.apps.company.com


Then multiple HTTPRoutes can use the same Gateway certificate.

Recommended POC Progression
Kong Gateway (✅ done)
LoadBalancer Service (✅ done)
Azure DNS hostname (✅ done)
cert-manager installation
ClusterIssuer
Certificate
HTTPS Gateway listener (443)
HTTP → HTTPS redirect
Multiple HTTPRoutes (/app1, /app2, /app3)

This closely matches a real enterprise AKS ingress architecture.
