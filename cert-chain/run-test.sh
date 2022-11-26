#!/bin/bash

minikube status > /dev/null || {
    minikube start --addons=ingress --vm=true --memory=6144 --cpus=4
} 

# Create NS "sandbox" if needed
kubectl get namespace sandbox > /dev/null 2>&1 || kubectl create namespace sandbox
# Check if cert-manager installation is present
kubectl get namespace cert-manager > /dev/null 2>&1 || {
  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.10.1/cert-manager.yaml 
  sleep 30
}

kubectl delete secret ca-key-pair -n cert-manager > /dev/null 2>&1
kubectl delete clusterissuer ca-issuer -n cert-manager > /dev/null 2>&1
 
kubectl create -f - <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: ca-key-pair
  namespace: cert-manager
data:
  tls.crt: $(cat domain.crt | base64 -w0)
  tls.key: $(cat domain.key | base64 -w0)
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: ca-issuer
  namespace: cert-manager
spec:
  ca:
    secretName: ca-key-pair
EOF

echo "kubectl get issuers ca-issuer -n sandbox -o wide"
kubectl get clusterissuers ca-issuer -n cert-manager -o wide


export IMAGE_NAME=test-cert
kubectl delete secret ${IMAGE_NAME}-tls-secret -n sandbox > /dev/null 2>&1
kubectl delete Certificate ${IMAGE_NAME} -n sandbox > /dev/null 2>&1

kubectl create -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ${IMAGE_NAME}
spec:
  commonName: "cert-manager issuer"
  dnsNames:
    - nuc.domain.com
  issuerRef:
    kind: ClusterIssuer
    name: ca-issuer
  secretName: ${IMAGE_NAME}-tls-secret
EOF
sleep 5
#kubectl get certificates test-cert -oyaml

kubectl get secret ${IMAGE_NAME}-tls-secret -n sandbox -o jsonpath='{ .data.tls\.crt }' | base64 -d 2> /dev/null > /tmp/tls.crt
kubectl get secret ${IMAGE_NAME}-tls-secret -n sandbox -o jsonpath='{ .data.ca\.crt }'  | base64 -d 2> /dev/null > /tmp/ca.crt

echo "ca.crt"
openssl storeutl -text -noout -certs /tmp/ca.crt | grep Subject:
echo "tls.crt"
openssl storeutl -text -noout -certs /tmp/tls.crt | grep Subject:

rm -f /tmp/ca.crt /tmp/tls.crt