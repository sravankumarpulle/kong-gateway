# Kong Gateway API + Cert-Manager + Let's Encrypt on AKS
# Note: working everything tested
## Overview

### This Proof of Concept demonstrates:
```
Kong Gateway Community Edition
Kubernetes Gateway API
AKS LoadBalancer Service
Azure Public IP + DNS Label
NGINX Sample Application
HTTPRoute Routing
Cert-Manager
Let's Encrypt Integration
Automatic TLS Certificate Renewal
```


## Architecture
```
Internet
    |
    v
gateway-rgs.eastus.cloudapp.azure.com
    |
Azure Public IP
    |
AKS Load Balancer
    |
Kong Gateway
    |
Gateway API
    |
HTTPRoute
    |
ClusterIP Service
    |
NGINX Pod
```

## Prerequisites
> AKS Cluster,
> kubectl,
> Helm 3,
> Azure CLI.

Verify:
```
kubectl cluster-info

kubectl get nodes

# Create Namespace
kubectl create namespace kong

# Install Gateway API CRDs
kubectl get crd | grep gateway
```

Verify:

gatewayclasses.gateway.networking.k8s.io
gateways.gateway.networking.k8s.io
httproutes.gateway.networking.k8s.io

## Install Kong
Add Repository
```sh
helm repo add kong https://charts.konghq.com

helm repo update
```

kong-values.yml
```yaml
gateway:
  admin:
    http:
      enabled: true
  proxy:
    type: LoadBalancer
    http:
      enabled: true
    tls:
      enabled: true
```
Install Kong
```sh
helm install kong kong/ingress \
-f kong-values.yml \
-n kong

# Verify
kubectl get all -n kong
```

Expected:
kong-controller
kong-gateway

Get Public IP
```sh
kubectl get svc -n kong
```

Example:
kong-gateway-proxy   LoadBalancer   20.232.52.58

Configure Azure DNS Label

Find Public IP:
```sh
kubectl get svc kong-gateway-proxy -n kong
```

Assign DNS Label:
```sh
az network public-ip update \
--resource-group MC_<resourcegroup>_<akscluster>_<region> \
--name <public-ip-name> \
--dns-name gateway-rgs
```

DNS Name:
```
gateway-rgs.eastus.cloudapp.azure.com
```

Verify:
```sh
nslookup gateway-rgs.eastus.cloudapp.azure.com
```
## Install Cert-Manager
Add Repository
```sh
helm repo add jetstack https://charts.jetstack.io

helm repo update
```
### Install
```
helm install cert-manager jetstack/cert-manager \
--namespace cert-manager \
--create-namespace \
--set crds.enabled=true \
--set "extraArgs={--enable-gateway-api}"
```

Verify:
```
kubectl get pods -n cert-manager
```

### GatewayClass
kong-gw-class.yml
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: kong-class
  annotations:
    konghq.com/gatewayclass-unmanaged: "true"

spec:
  controllerName: konghq.com/kic-gateway-controller
```

Deploy:
```
kubectl apply -f kong-gw-class.yml
```

### Gateway
kong-gw-gateway.yml
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: kong-gateway
  namespace: kong
spec:
  gatewayClassName: kong-class
  listeners:
  - name: http
    hostname: gateway-rgs.eastus.cloudapp.azure.com
    port: 80
    protocol: HTTP

    allowedRoutes:
      namespaces:
        from: All

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
```

Deploy:
```
kubectl apply -f kong-gw-gateway.yml
```

### ClusterIssuer
clusterissuer.yaml
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod

spec:
  acme:
    email: yourgmail@gmail.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        gatewayHTTPRoute:
          parentRefs:
          - name: kong-gateway
            namespace: kong
```

Deploy:
```
kubectl apply -f clusterissuer.yaml
```

### Certificate
certificate.yaml
```yaml
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
```

Deploy:
```
kubectl apply -f certificate.yaml
```
### Sample Application
hello-deployment.yaml
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-world-1
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hello-world-1
  template:
    metadata:
      labels:
        app: hello-world-1
    spec:
      containers:
      - name: hello-world
        image: nginx:latest
        ports:
        - containerPort: 80
```

Deploy:
```
kubectl apply -f hello-deployment.yaml
```

### Service
hello-svc.yaml
```yaml
apiVersion: v1
kind: Service
metadata:
  name: hello-world-1-svc
spec:
  type: ClusterIP
  selector:
    app: hello-world-1
  ports:
  - port: 80
    targetPort: 80
```

Deploy:
```
kubectl apply -f hello-svc.yaml
```

### HTTPRoute
hello-world-1-route.yml
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: example-1
  annotations:
    konghq.com/strip-path: "true"
spec:
  parentRefs:
  - name: kong-gateway
    namespace: kong
  hostnames:
  - gateway-rgs.eastus.cloudapp.azure.com
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: hello-world-1-svc
      port: 80
      kind: Service
```

Deploy:
```
kubectl apply -f hello-world-1-route.yml
```

#### Verification Commands
```sh
# Kong
kubectl get all -n kong

kubectl get svc -n kong

# Gateway
kubectl get gateway -A

kubectl describe gateway kong-gateway -n kong


# Expected:

Accepted=True
Programmed=True

# HTTPRoute
kubectl get httproute -A

kubectl describe httproute example-1


#cExpected:

Accepted=True
ResolvedRefs=True

# Certificate
kubectl get certificate -A


Expected:
READY=True

# Certificate Request
kubectl get certificaterequest -A

# Orders
kubectl get orders -A

# Challenges
kubectl get challenge -A

# TLS Secret
kubectl get secret gateway-rgs-tls -n kong

# Testing
HTTP
curl http://gateway-rgs.eastus.cloudapp.azure.com

# HTTPS
curl https://gateway-rgs.eastus.cloudapp.azure.com
```

Expected:
```
Welcome to nginx!
```

### Automatic Renewal
```
Cert-Manager automatically:

1. Requests certificate from Let's Encrypt

2. Stores certificate in:
   gateway-rgs-tls

3. Renews certificate before expiry

4. Updates Kubernetes secret

5. Kong automatically uses renewed certificate

6. No manual intervention required
```

#### Useful Troubleshooting Commands
```sh
kubectl logs deployment/kong-controller -n kong

kubectl logs deployment/kong-gateway -n kong

kubectl logs deployment/cert-manager -n cert-manager

kubectl describe gateway kong-gateway -n kong

kubectl describe httproute example-1

kubectl describe certificate gateway-rgs-cert -n kong

kubectl describe challenge -n kong

kubectl describe order -n kong
```
# Cleanup
```sh
kubectl delete -f hello-world-1-route.yml

kubectl delete -f hello-svc.yaml

kubectl delete -f hello-deployment.yaml

kubectl delete -f certificate.yaml

kubectl delete -f clusterissuer.yaml

kubectl delete -f kong-gw-gateway.yml

kubectl delete -f kong-gw-class.yml

helm uninstall kong -n kong

helm uninstall cert-manager -n cert-manager

kubectl delete ns kong

kubectl delete ns cert-manager
```
### POC Outcome
```
 ✅ Kong Community Edition installed on AKS
 ✅ Gateway API implemented
 ✅ Public Azure LoadBalancer exposure
 ✅ Azure DNS hostname configured
 ✅ NGINX backend application deployed
 ✅ HTTPRoute routing configured
 ✅ Cert-Manager installed
 ✅ Let's Encrypt certificate issued
 ✅ Automatic TLS renewal enabled
 ✅ HTTPS endpoint accessible using public DNS hostname without manual certificate management.
```

"https://charts.konghq.com/"

"https://artifacthub.io/packages/helm/kong/ingress" 

"https://medium.com/@martin.hodges/using-kong-to-access-kubernetes-services-using-a-gateway-resource-with-no-cloud-provided-8a1bcd396be9"


<img width="1914" height="443" alt="image" src="https://github.com/user-attachments/assets/451f4fd7-e773-45e2-bc9c-c58f2ac66c94" />


<img width="1919" height="783" alt="image" src="https://github.com/user-attachments/assets/2db2722d-2ffb-4e00-9388-93b2b620722f" />


