#!/bin/bash

set -e 

export ISTIO_VERSION=1.6.2
export KNATIVE_VERSION=v0.15.0
export KFSERVING_VERSION=v0.3.0
curl -L https://git.io/getLatestIstio | sh -
cd istio-${ISTIO_VERSION}

# Create istio-system namespace
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: istio-system
  labels:
    istio-injection: disabled
EOF

# Create istio operator
cat << EOF > ./istio-minimal-operator.yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  values:
    global:
      proxy:
        autoInject: disabled
      useMCP: false
      # The third-party-jwt is not enabled on all k8s.
      # See: https://istio.io/docs/ops/best-practices/security/#configure-third-party-service-account-tokens
      jwtPolicy: first-party-jwt
  addonComponents:
    pilot:
      enabled: true
    tracing:
      enabled: true
    kiali:
      enabled: true
    prometheus:
      enabled: true
  components:
    ingressGateways:
      - name: istio-ingressgateway
        enabled: true
      - name: cluster-local-gateway
        enabled: true
        label:
          istio: cluster-local-gateway
          app: cluster-local-gateway
        k8s:
          service:
            type: ClusterIP
            ports:
            - port: 15020
              name: status-port
            - port: 80
              name: http2
            - port: 443
              name: https
EOF

bin/istioctl manifest apply -f istio-minimal-operator.yaml

# Install Knative
kubectl apply --filename https://github.com/knative/serving/releases/download/${KNATIVE_VERSION}/serving-crds.yaml
kubectl apply --filename https://github.com/knative/serving/releases/download/${KNATIVE_VERSION}/serving-core.yaml
kubectl apply --filename https://github.com/knative/net-istio/releases/download/${KNATIVE_VERSION}/release.yaml

# Install Cert Manager
kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v0.15.1/cert-manager.yaml
kubectl wait --for=condition=available --timeout=600s deployment/cert-manager-webhook -n cert-manager
cd ..
# Install KFServing
if [[ -d kfserving ]]; then
  cd kfserving
  git pull
else
  git clone https://github.com/kubeflow/kfserving.git
  cd kfserving
fi

K8S_MINOR=$(kubectl version | perl -ne 'print $1."\n" if /Server Version:.*?Minor:"(\d+)"/')
if [[ $K8S_MINOR -gt 17 ]]; then
  echo "Kubernetes minor version must be <= 17 got ${K8S_MINOR}"
  exit 1
elif [[ $K8S_MINOR -lt 16 ]]; then
  kubectl apply -f install/${KFSERVING_VERSION}/kfserving.yaml --validate=false
else
  kubectl apply -f install/${KFSERVING_VERSION}/kfserving.yaml
fi

echo "========== Test KFServing Installation =========="
echo "Check KFServing controller installation"
sleep 30
kubectl get po -n kfserving-system 
echo "========== Create KFServing test inference service =========="
kubectl get namespace kfserving-test || kubectl create namespace kfserving-test
kubectl apply -f docs/samples/v1alpha2/sklearn/sklearn.yaml -n kfserving-test
sleep 60

n=0
until [ "$n" -ge 5 ]
do
  echo "========== Check KFServing InferenceService status =========="
  STATUS=`kubectl get inferenceservices sklearn-iris -n kfserving-test`
  echo "$STATUS"
  if [[ $STATUS == *"http:"* ]]; then
    break
  fi
  n=$((n+1))
  echo "Servce does not seem to be ready, retrying after 60 seconds..."
  sleep 60
done

sleep 10
export INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
sleep 5
echo "========== Curl the InferenceService from ingress gateway =========="
SERVICE_HOSTNAME=$(kubectl get inferenceservice sklearn-iris -n kfserving-test -o jsonpath='{.status.url}' | cut -d "/" -f 3)
curl -v -H "Host: ${SERVICE_HOSTNAME}" http://${INGRESS_HOST}:${INGRESS_PORT}/v1/models/sklearn-iris:predict -d @./docs/samples/v1alpha2/sklearn/iris-input.json

# Clean up
rm -rf istio-${ISTIO_VERSION}
