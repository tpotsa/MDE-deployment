# Overview

Crates an external HTTPS load balancer for MC deployed from the marketplace

## Installation

### 1. Get mc cluster credentials 
```
gcloud container clusters get-credentials <name>
```

### 2. Install helm chart

```
helm install mc-http-lb . --set ingress.domain=<mc>.<environment>.<gmde.cloud>
```

### 3. Create an A record

Once the Load Balancer is created, take its external IP address and create an A record for the domain name you selected in Step #2

### 4. Wait for SSL certificate to be provisioned
Once the Load Balancer picks the IP for the domain name, it will finish provisioning the SSL certificate. This may take up to an hour.  

### 5. Change the Base Domain Name in MC

Use `intelligent-manufacturing-con-1-nginx` service IP to access the MC admin console by navigating to `http:<IP>/admin-ui/settings/domain`, and change the Base Domain Name to the domain name you selected in Step #2

