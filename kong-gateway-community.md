# Kong Gateway API on AKS - End-to-End POC

## This README demonstrates deploying Kong Gateway Community Edition on AKS using Gateway API, exposing a sample NGINX application through a public Azure LoadBalancer IP and DNS hostname.

Architecture
Internet
    |
    v
Azure Public IP
    |
Azure Load Balancer
    |
Kong Gateway (LoadBalancer Service)
    |
Gateway
    |
HTTPRoute
    |
Service (ClusterIP)
    |
NGINX Pod

Prerequisites
AKS Cluster
kubectl configured
Helm installed
Gateway API CRDs installed

Verify:
```sh
kubectl get gatewayclass
kubectl api-resources | grep gateway

# Create Namespace
kubectl create namespace kong

# Add Kong Helm Repository
helm repo add kong https://charts.konghq.com

helm repo update


# Verify:

helm search repo kong
```
Kong Values File

Create:

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
      enabled: false
```

Install Kong
```sh
helm install kong kong/ingress \
-f kong-values.yml \
-n kong
```

Verify:
```sh
helm list -n kong
```

Expected:
```
NAME  NAMESPACE STATUS
kong  kong      deployed

Verify Kong Pods
kubectl get all -n kong


# Expected:

kong-controller
kong-gateway

# Both should be:
Running

# Get Public IP
kubectl get svc -n kong


# Example:

NAME                 TYPE           EXTERNAL-IP
kong-gateway-proxy   LoadBalancer   20.220.100.50
```

Store the external IP.

Configure Azure DNS Label

Find Load Balancer Public IP:
```
kubectl get svc kong-gateway-proxy -n kong
```

Get Azure Public IP resource:
```
az network public-ip list \
--resource-group MC_<rg>_<aks>_<region> \
-o table
```

Assign DNS label:
```
az network public-ip update \
--resource-group MC_<rg>_<aks>_<region> \
--name <publicip-name> \
--dns-name gateway-rgs
```

Azure generates:
```
gateway-rgs.eastus.cloudapp.azure.com
```

Verify:
```
nslookup gateway-rgs.eastus.cloudapp.azure.com
```
GatewayClass
### kong-gw-class.yml
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
```sh
kubectl apply -f kong-gw-class.yml
```
Gateway

Update hostname with Azure DNS hostname.

### kong-gw-gateway.yml
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: kong-gateway
  namespace: kong
spec:
  gatewayClassName: kong-class

  listeners:
  - name: world-selector
    hostname: gateway-rgs.eastus.cloudapp.azure.com
    port: 80
    protocol: HTTP

    allowedRoutes:
      namespaces:
        from: All
```

Deploy:
```sh
kubectl apply -f kong-gw-gateway.yml


# Verify:
kubectl get gateway -n kong
```
Sample Application Deployment
### hello-deployment.yaml
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
```sh
kubectl apply -f hello-deployment.yaml
```
Service
### hello-svc.yaml
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

Verify:
```
kubectl get svc
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
Verification Commands

GatewayClass:
```
kubectl get gatewayclass
```

Gateway:
```
kubectl get gateway -A
```

HTTPRoute:
```
kubectl get httproute -A
```

Pods:
```
kubectl get pods -A
```

Services:
```
kubectl get svc -A
```
```sh
# Deployments:

kubectl get deploy -A


# Describe Gateway:

kubectl describe gateway kong-gateway -n kong


# Describe Route:

kubectl describe httproute example-1

# Testing

# Get Kong Public IP:

kubectl get svc kong-gateway-proxy -n kong
```

Example:

20.220.100.50


Test via DNS:

curl http://gateway-rgs.eastus.cloudapp.azure.com


Expected:

Welcome to nginx!

Troubleshooting
```
# Check accepted routes:

kubectl get httproute -A


# Check gateway:

kubectl describe gateway kong-gateway -n kong


# Check Kong logs:

kubectl logs deployment/kong-controller -n kong

kubectl logs deployment/kong-gateway -n kong


# Check service endpoints:

kubectl get endpoints hello-world-1-svc


# Check route status:

kubectl describe httproute example-1

# Cleanup
kubectl delete -f hello-world-1-route.yml

kubectl delete -f hello-svc.yaml

kubectl delete -f hello-deployment.yaml

kubectl delete -f kong-gw-gateway.yml

kubectl delete -f kong-gw-class.yml

helm uninstall kong -n kong

kubectl delete namespace kong
```

This gives you a complete Kong Gateway API POC on AKS with:

✅ Kong Community Edition
 ✅ Gateway API
 ✅ Public Azure LoadBalancer IP
 ✅ Azure DNS hostname (gateway-rgs.eastus.cloudapp.azure.com)
 ✅ NGINX backend application
 ✅ HTTPRoute-based traffic routing
 ✅ End-to-end validation commands and cleanup steps.

"https://medium.com/@martin.hodges/using-kong-to-access-kubernetes-services-using-a-gateway-resource-with-no-cloud-provided-8a1bcd396be9"
