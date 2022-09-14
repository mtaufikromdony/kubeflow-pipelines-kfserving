#!/bin/bash

set -e

export GCP_PROJECT_ID="kubeflow-sandbox-project"
export OAUTH_CLIENT_ID="xxxxx.apps.googleusercontent.com"
export OAUTH_CLIENT_SECRET="xxxxxx"

export PUBLIC_IP_NAME="kfserving-public-ip"
export KFSERVING_ENDPOINT_PREFIX="kfserving"
export CE_HOSTNAME="$KFSERVING_ENDPOINT_PREFIX.endpoints.$GCP_PROJECT_ID.cloud.goog"

# create a clean working area
echo "# Cleaning up and creating staging area..."
echo "##########################################"
rm -rf ./.tmp && mkdir ./.tmp
echo ""
echo ""

# let's patch istio-ingressgateway
echo "# Patching istio-ingressgateway..."
echo "##################################"
kubectl -n istio-system patch svc istio-ingressgateway --type=json -p="$(cat ./templates/00-istio-ingressgateway-patch.json)" --dry-run=true -o yaml > ./.tmp/00-istio-ingressgateway-patch.yaml
kubectl -n istio-system apply -f ./.tmp/00-istio-ingressgateway-patch.yaml
echo ""
echo ""

# creating the public IP
echo "# Creating global public IP address..."
echo "######################################"
export PUBLIC_IP_ADDRESS=`gcloud compute addresses describe "$PUBLIC_IP_NAME" --global --format="value(address)" || echo ""`
if [ -z "$PUBLIC_IP_ADDRESS" ]; then
    echo "Creating public IP address with name $PUBLIC_IP_NAME..."
    gcloud compute addresses create "$PUBLIC_IP_NAME" --global
    export PUBLIC_IP_ADDRESS=`gcloud compute addresses describe "$PUBLIC_IP_NAME" --global --format="value(address)"`
fi
echo ""
echo ""

# create the endpoints DNS record
echo "# Creating cloud endpoints DNS record to the public IP address..."
echo "#################################################################"
CE_CONFIG_ID=`gcloud endpoints configs list --limit=1 --sort-by=~id --format="value(id)" --service="$CE_HOSTNAME" || echo ""`
if [ ! -z "$CE_CONFIG_ID" ]; then
    CE_CONF_IP=`gcloud endpoints configs describe --service="$CE_HOSTNAME" "$CE_CONFIG_ID" --format="value(endpoints.target)"`
fi
if [ -z "$CE_CONFIG_ID" ] || [ "$PUBLIC_IP_ADDRESS" != "$CE_CONF_IP" ]; then
    envsubst <templates/01-deploy-openapi.yaml >./.tmp/01-deploy-openapi.yaml
    gcloud endpoints services deploy ./.tmp/01-deploy-openapi.yaml
fi
echo ""
echo ""

# defining certificate
echo "# Creating SSL cretificate..."
echo "#############################"
envsubst <templates/02-cert-setup.yaml >./.tmp/02-cert-setup.yaml
kubectl -n istio-system apply -f ./.tmp/02-cert-setup.yaml
echo "\n\n"

# Creating the OAuth secret
# follow these steps: https://www.kubeflow.org/docs/gke/deploy/oauth-setup/
echo "# Creating secret with the OAuth client ID and client secret info..."
echo "####################################################################"
export OAUTH_CLIENT_ID_B64=`echo "$OAUTH_CLIENT_ID"|base64|tr -d '\n\r'`
export OAUTH_CLIENT_SECRET_B64=`echo "$OAUTH_CLIENT_SECRET"|base64|tr -d '\n\r'`
envsubst <templates/03-kfserving-api-secret.yaml >./.tmp/03-kfserving-api-secret.yaml
kubectl -n istio-system apply -f ./.tmp/03-kfserving-api-secret.yaml
echo ""
echo ""

# Apply the BackendConfig to be used by the ingress
echo "# Creating backend configuration..."
echo "###################################"
envsubst <templates/04-backend-config.yaml >./.tmp/04-backend-config.yaml
kubectl -n istio-system apply -f ./.tmp/04-backend-config.yaml
echo ""
echo ""

# annotate the gateway to use IAP config
echo "# Annotating the gateway to use the IAP config..."
echo "#################################################"
kubectl -n istio-system annotate service istio-ingressgateway "beta.cloud.google.com/backend-config"='{"default": "iap-config"}' --overwrite
echo ""
echo ""

# let's create the ingress
echo "# Creating ingress..."
echo "#####################"
envsubst <templates/05-create-ingress.yaml >./.tmp/05-create-ingress.yaml
kubectl apply -n istio-system -f ./.tmp/05-create-ingress.yaml
echo ""
echo "DONE"
echo ""
