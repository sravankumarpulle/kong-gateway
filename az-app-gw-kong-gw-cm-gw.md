# AKS + Private Kong Gateway + Azure Application Gateway + Key Vault TLS + Gateway API + Cert Manager POC
## Overview

This Proof of Concept demonstrates an enterprise-grade architecture where:
```
Kong Gateway Community Edition runs on AKS
Kong Gateway is exposed only through a Private Internal Load Balancer
Azure Application Gateway exposes public HTTP/HTTPS
TLS certificates are generated using Cert-Manager and Let's Encrypt
Certificates are exported and uploaded to Azure Key Vault
Azure Application Gateway retrieves certificates from Key Vault
Gateway API is used for routing
Sample NGINX application is exposed
```
Architecture
```
HTTP Flow
User
  |
  v
http://gateway-rgs.eastus.cloudapp.azure.com
  |
Azure Public IP
(4.255.118.236)
  |
Application Gateway
Port 80
  |
Backend Pool
10.224.0.5
  |
Private Kong Gateway
  |
HTTPRoute
  |
Service
  |
NGINX Pod
```

### HTTPS Flow
```
User
  |
  v
https://gateway-rgs.eastus.cloudapp.azure.com
  |
Application Gateway HTTPS Listener
Port 443
  |
Certificate stored in Key Vault
  |
Backend Pool
10.224.0.5
  |
Private Kong Gateway
  |
HTTPRoute
  |
Service
  |
NGINX Pod
```

### Azure Resources
```
Subscription:
Azure subscription 1

Region:
East US

Resource Group:
rgs-gateway

AKS Cluster:
rgs-gateway

Application Gateway:
agw-konggw

Managed Identity:
agw-konggw-mi

Hostname:
gateway-rgs.eastus.cloudapp.azure.com

Application Gateway Public IP:
4.255.118.236

Private Kong LB IP:
10.224.0.5
```

### Prerequisites
```
Local Tools
az version

kubectl version

helm version

openssl version
```
#### Step 1 - Create Public IP
```sh
az network public-ip create \
--resource-group rgs-gateway \
--name appgw-pip \
--sku Standard \
--allocation-method Static


# Assign DNS label:

az network public-ip update \
--resource-group rgs-gateway \
--name appgw-pip \
--dns-name gateway-rgs

# Verify:
nslookup gateway-rgs.eastus.cloudapp.azure.com
```
Expected:  4.255.118.236

### Step 2 - Create AKS VNet
VNet
aks-vnet-68496693


Example:
```sh
az network vnet create \
--resource-group rgs-gateway \
--name aks-vnet-68496693 \
--address-prefixes 10.224.0.0/16 \
--subnet-name aks-subnet \
--subnet-prefixes 10.224.0.0/24

# Step 3 - Create Application Gateway VNet
az network vnet create \
--resource-group rgs-gateway \
--name aks-app-gwvnet \
--address-prefixes 10.225.0.0/16 \
--subnet-name appgw-subnet \
--subnet-prefixes 10.225.0.0/24

# Step 4 - Create VNet Peering
AKS VNet → App Gateway VNet
az network vnet peering create \
--resource-group rgs-gateway \
--vnet-name aks-vnet-68496693 \
--name aks-to-appgw \
--remote-vnet aks-app-gwvnet \
--allow-vnet-access

# App Gateway → AKS VNet
az network vnet peering create \
--resource-group rgs-gateway \
--vnet-name aks-app-gwvnet \
--name appgw-to-aks \
--remote-vnet aks-vnet-68496693 \
--allow-vnet-access
```
### Step 5 - Install Kong Gateway
Repository
```sh
helm repo add kong https://charts.konghq.com
helm repo update
```
#### kong-values.yaml
Private Internal Load Balancer
```yaml
gateway:
  admin:
    http:
      enabled: true

  proxy:
    type: LoadBalancer

    annotations:
      service.beta.kubernetes.io/azure-load-balancer-internal: "true"

    http:
      enabled: true

    tls:
      enabled: true
```

Install
```sh
kubectl create namespace kong

helm install kong kong/ingress \
-f kong-values.yaml \
-n kong

# Verify
kubectl get svc -n kong
```
Expected
kong-gateway-proxy

EXTERNAL-IP
10.224.0.5

### Step 6 - Install Cert Manager
```sh
helm repo add jetstack https://charts.jetstack.io
helm repo update
```
Install:
```sh
helm install cert-manager jetstack/cert-manager \
--namespace cert-manager \
--create-namespace \
--set crds.enabled=true \
--set "extraArgs={--enable-gateway-api}"

# Verify
kubectl get pods -n cert-manager
```

### Step 7 - GatewayClass
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

### Step 8 - Gateway
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
    protocol: HTTP
    port: 80

    allowedRoutes:
      namespaces:
        from: All

  - name: https
    hostname: gateway-rgs.eastus.cloudapp.azure.com
    protocol: HTTPS
    port: 443

    tls:
      mode: Terminate
      certificateRefs:
      - name: gateway-rgs-tls
        kind: Secret

    allowedRoutes:
      namespaces:
        from: All
```

### Step 9 - Deploy Sample Application
Deployment
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
      - name: nginx
        image: nginx:latest

        ports:
        - containerPort: 80
```
##### Service
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
#### HTTPRoute
```yaml
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
  - matches:
    - path:
        type: PathPrefix
        value: /

    backendRefs:
    - name: hello-world-1-svc
      kind: Service
      port: 80
```
### Step 10 - Create Application Gateway
```
Resource Group:
rgs-gateway

Name:
agw-konggw

SKU:
Standard_v2

Frontend:
Public

Public IP:
appgw-pip

Subnet:
appgw-subnet
```

### Step 11 - Configure HTTP Listener (Port 80)
```
Frontend
Public IP
appgw-pip

Backend Pool
Name:
aks-kong-gw

IP:
10.224.0.5

Backend Settings
Protocol:
HTTP

Port:
80

Health Probe
Name:
kong-probe

Protocol:
HTTP

Host:
gateway-rgs.eastus.cloudapp.azure.com

Path:
/

Port:
80

Listener
Name:
default-listner

Protocol:
HTTP

Port:
80

Hostname:
gateway-rgs.eastus.cloudapp.azure.com

Rule
Name:
default

Priority:
100

Listener:
default-listner

Backend Pool:
aks-kong-gw

Backend Settings:
default
```

### Step 12 - Verify HTTP
```
curl http://gateway-rgs.eastus.cloudapp.azure.com
```

Expected
```
Welcome to nginx
```

#### Step 13 - Generate TLS Certificate Using Cert Manager

##### ClusterIssuer
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod-r
spec:
  acme:
    email: yourgmail@gmail.com
    server: https://acme-v02.api.letsencrypt.org/directory

    privateKeySecretRef:
      name: letsencrypt-prod-r
    solvers:
    - http01:
        gatewayHTTPRoute:
          parentRefs:
          - name: kong-gateway
            namespace: kong
```

##### Certificate
```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: gateway-rgs-cert-r
  namespace: kong

spec:
  secretName: gateway-rgs-tls-r
  issuerRef:
    name: letsencrypt-prod-r
    kind: ClusterIssuer
  dnsNames:
  - gateway-rgs.eastus.cloudapp.azure.com
```
##### Step 14 - Export Certificate
```sh
kubectl get secret gateway-rgs-tls-r \
-n kong \
-o jsonpath='{.data.tls\.crt}' | base64 -d > cert.crt

kubectl get secret gateway-rgs-tls-r \
-n kong \
-o jsonpath='{.data.tls\.key}' | base64 -d > cert.key
```
##### Step 15 - Create PFX
Password
```
M3rc3d3s@2026
```

Generate
```sh
openssl pkcs12 -export \
-out gateway-rgs.pfx \
-inkey cert.key \
-in cert.crt \
-passout pass:M3rc3d3s@2026
```

##### Step 16 - Create Key Vault
```sh
az keyvault create \
--resource-group rgs-gateway \
--name kv-konggw \
--location eastus
```
Required Role for Upload
```
User requires:   Key Vault Certificates Officer
or
Key Vault Administrator
```
###### Upload PFX
```
Portal

Key Vault
  |
Certificates
  |
Import
  |
Select
gateway-rgs.pfx
```
```
Password:  M3rc3d3s@2026
```

##### Step 17 - Create Managed Identity
```sh 
az identity create \
--resource-group rgs-gateway \
--name agw-konggw-mi

# Verify

az identity show \
-g rgs-gateway \
-n agw-konggw-mi
```

##### Step 18 - Assign Identity To App Gateway
```sh
az network application-gateway identity assign \
--resource-group rgs-gateway \
--gateway-name agw-konggw \
--identity $(az identity show \
-g rgs-gateway \
-n agw-konggw-mi \
--query id -o tsv)

# Verify
az network application-gateway show \
-g rgs-gateway \
-n agw-konggw \
--query identity
```

##### Step 19 - Grant Key Vault Access
```
Role:
Key Vault Secrets User

Assign to:
agw-konggw-mi

Required Permissions:
Get
List
Secret
Certificate
```

#### Step 20 - Create HTTPS Listener
```
Application Gateway

Listener Name:
https-listner

Protocol:
HTTPS

Port:
443

Hostname:
gateway-rgs.eastus.cloudapp.azure.com

Certificate:
gateway-rgs
(from Key Vault)

Step 21 - Create HTTPS Rule
Name:
https

Priority:
101

Listener:
https-listner

Backend Pool:
aks-kong-gw

Backend:
10.224.0.5

Backend Settings:
default

Backend Port:
80
```

## Final Architecture
```
User
   |
HTTPS : 443
   |
Azure Public IP
4.255.118.236
   |
Application Gateway
HTTPS Listener
Certificate from Key Vault
   |
Backend Pool
10.224.0.5
   |
Private Kong Gateway
   |
HTTPRoute
   |
ClusterIP Service
   |
NGINX Pod
```

### Verification
```sh 
kubectl get gateway -A
kubectl get httproute -A
kubectl get certificate -A
kubectl get certificaterequest -A
kubectl get orders -A
kubectl get challenge -A
kubectl get secret -n kong

# HTTP:
curl http://gateway-rgs.eastus.cloudapp.azure.com

# HTTPS:
curl -k https://gateway-rgs.eastus.cloudapp.azure.com

# Expected:
Welcome to nginx
```

## POC Outcome
```
✅ AKS deployed
✅ Kong Gateway Community installed
✅ Private Internal Load Balancer configured
✅ Application Gateway deployed
✅ VNet peering configured
✅ Gateway API implemented
✅ HTTP routing working
✅ Cert Manager installed
✅ Let's Encrypt certificate generated
✅ Certificate uploaded to Key Vault
✅ Managed Identity configured
✅ Application Gateway HTTPS enabled
✅ Private Kong exposed securely through Public Application Gateway
✅ NGINX sample application accessible through HTTP and HTTPS
```
### aks 
<img width="1919" height="690" alt="image" src="https://github.com/user-attachments/assets/90f4eae8-18c1-4207-a51e-bc4349fdfe51" />

### aks vnet
<img width="1919" height="558" alt="image" src="https://github.com/user-attachments/assets/bfc22a51-1d7a-4d43-8e68-d532eacede03" />

### application gw vnet and peering for both vnet's
<img width="1918" height="564" alt="image" src="https://github.com/user-attachments/assets/352d34ee-2fe8-419e-88d0-12dcdc91c3f6" />

### Managed identity 
<img width="1919" height="489" alt="image" src="https://github.com/user-attachments/assets/b72bfc65-7031-47dc-b848-0f8f02aad610" />

### Mi Roles 
<img width="1907" height="495" alt="image" src="https://github.com/user-attachments/assets/ffddf153-6662-44a1-92ad-f06e64833dc0" />

### AKV Certs should be uploaded after - certs created in aks  -- user role is requires to upload certs
<img width="1919" height="437" alt="image" src="https://github.com/user-attachments/assets/41b30415-8bd8-4724-9567-8b0c9cd3ad58" />

### public ip address
<img width="1919" height="636" alt="image" src="https://github.com/user-attachments/assets/c5f6d50d-26f1-470f-9410-f6f12bb8f79f" />

### Application gw overview 
<img width="1903" height="875" alt="image" src="https://github.com/user-attachments/assets/7a856957-3311-4179-91bf-3ba50e568180" />

### configuration 
<img width="1919" height="871" alt="image" src="https://github.com/user-attachments/assets/b8d34cc8-f99e-422b-a586-2322f1987e77" />

### 1 backend pool
<img width="1919" height="476" alt="image" src="https://github.com/user-attachments/assets/bad8ed2f-5dd9-4e3e-a86e-5eb77893b331" />

### 1.1 kong-default-pool
<img width="1912" height="542" alt="image" src="https://github.com/user-attachments/assets/34a2ad70-6168-4c40-8b62-65a87f6d17c5" />

### 1.2 aks-kong-gw
here 2 association comes from rules 
<img width="1911" height="700" alt="image" src="https://github.com/user-attachments/assets/55d6550b-c868-484f-9170-6956488a7adf" />


### 2 backend setting 
<img width="1908" height="484" alt="image" src="https://github.com/user-attachments/assets/6cda241c-01e7-43fe-8b91-8afe70dba659" />
### 2.1 default 
<img width="1912" height="778" alt="image" src="https://github.com/user-attachments/assets/0f37627a-dd56-446e-b6cb-b94eaaabfe95" />
<img width="1919" height="838" alt="image" src="https://github.com/user-attachments/assets/dbb2703c-3da4-4c32-a569-b92a0ae11ecd" />

### 2.2 backend health 
<img width="1919" height="695" alt="image" src="https://github.com/user-attachments/assets/b2c88539-8cbc-4dc8-bae0-b64eef879453" />

### 3 frontend ip 
<img width="1908" height="431" alt="image" src="https://github.com/user-attachments/assets/10f80ce4-e526-41af-8152-f031e239f25d" />

### 3.1  public
<img width="1919" height="554" alt="image" src="https://github.com/user-attachments/assets/982a64c4-0d6d-4191-813a-9e0c0a1b6be4" />
### 3.2 
<img width="1917" height="399" alt="image" src="https://github.com/user-attachments/assets/e20343c0-b313-4306-ab79-4b9c21255e74" />

### 4 Listner
<img width="1919" height="861" alt="image" src="https://github.com/user-attachments/assets/b88b08ed-bf49-4cd3-86bc-2b33f0523efe" />
### 4.1 https-listner - public 
<img width="1919" height="858" alt="image" src="https://github.com/user-attachments/assets/90191d7e-7ee4-4341-9840-bc58992db4f1" />

### 4.2 default-listerner
<img width="1918" height="858" alt="image" src="https://github.com/user-attachments/assets/75cd5085-3f04-447a-96a8-38e0635e9823" />

### 4 listner tls cer
<img width="1918" height="540" alt="image" src="https://github.com/user-attachments/assets/28bd6787-2a28-4e0c-bbb4-2221cc3620c8" />
### 4 Tls cert upload from azure kv with password 
<img width="1918" height="628" alt="image" src="https://github.com/user-attachments/assets/e6bf1c92-cd76-4003-8a7d-31af9dcb927f" />

### 5 Rules imp
<img width="1919" height="587" alt="image" src="https://github.com/user-attachments/assets/1289925c-2263-40d1-8194-7ee93fb375bb" />

### 5.1  http
<img width="1919" height="435" alt="image" src="https://github.com/user-attachments/assets/c288b3cf-7966-40ea-ad78-28cc53291741" />
<img width="1911" height="653" alt="image" src="https://github.com/user-attachments/assets/2b9e7b4c-38c7-4e2a-bb57-83ec9deeef9a" />
<img width="1918" height="407" alt="image" src="https://github.com/user-attachments/assets/a9a32dff-2dc2-48c4-9e70-e341044134ab" />

### 5.2 https
<img width="1919" height="460" alt="image" src="https://github.com/user-attachments/assets/28a68eb4-81af-492e-abd4-6fdebeecb478" />
