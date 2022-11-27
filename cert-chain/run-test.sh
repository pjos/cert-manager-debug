#!/bin/bash

# check if minikube is installed, if so, check if it's up and running
type minikube > /dev/null 2>&1 && {
  minikube status > /dev/null || {
      minikube start --addons=ingress --vm=true --memory=6144 --cpus=4
  } 
}

type kubectl > /dev/null 2>&1 || {
  echo "[ERROR] Unable to find kubectl, aborting ...."
  exit 1
}

# Create NS "sandbox" if needed
kubectl get namespace sandbox > /dev/null 2>&1 || kubectl create namespace sandbox
kubectl config set-context --current --namespace=sandbox

# Check if cert-manager installation is present
kubectl get crd clusterissuers.cert-manager.io > /dev/null 2>&1 || {
  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.10.1/cert-manager.yaml 
  sleep 30
}

ISSUER_NS=sandbox
ISSUER_KIND=Issuer

kubectl delete secret ca-key-pair -n ${ISSUER_NS}  > /dev/null 2>&1
kubectl delete ${ISSUER_KIND} ca-issuer -n ${ISSUER_NS} > /dev/null 2>&1

kubectl create -f - <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: ca-key-pair
  namespace: ${ISSUER_NS}
data:
  tls.crt: $(cat domain.crt | base64 -w0)
  tls.key: $(cat domain.key | base64 -w0)
---
apiVersion: cert-manager.io/v1
kind: ${ISSUER_KIND}
metadata:
  name: ca-issuer
  namespace: ${ISSUER_NS}
spec:
  ca:
    secretName: ca-key-pair
EOF

#echo "kubectl get ${ISSUER_KIND} ca-issuer -n ${ISSUER_NS} -o wide"
kubectl get ${ISSUER_KIND} ca-issuer -n ${ISSUER_NS} --no-headers -o wide


export IMAGE_NAME=test-cert
kubectl delete secret ${IMAGE_NAME}-tls-secret -n sandbox > /dev/null 2>&1
kubectl delete Certificate ${IMAGE_NAME} -n sandbox > /dev/null 2>&1

kubectl create -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ${IMAGE_NAME}
  namespace: sandbox
spec:
  commonName: "cert-manager issuer"
  dnsNames:
    - nuc.domain.com
  issuerRef:
    kind: ${ISSUER_KIND}
    name: ca-issuer
  secretName: ${IMAGE_NAME}-tls-secret
EOF

kubectl delete secret password-secret -n sandbox > /dev/null 2>&1
kubectl delete certificate ${IMAGE_NAME}-jks -n sandbox > /dev/null 2>&1
kubectl delete secret ${IMAGE_NAME}-jks-secret -n sandbox > /dev/null 2>&1

kubectl create -f - <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: password-secret
  namespace: sandbox
type: Opaque
data:
  password: $(echo -n 'changeme' | base64)
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata: 
  name: ${IMAGE_NAME}-jks
  namespace: sandbox
spec:
  secretName: ${IMAGE_NAME}-jks-secret
  dnsNames:
  - foo.example.com
  - bar.example.com
  issuerRef:
    kind: ${ISSUER_KIND}
    name: ca-issuer
  keystores:
    jks:
      create: true
      passwordSecretRef: # Password used to encrypt the keystore
        key: password
        name: password-secret
    pkcs12:
      create: true
      passwordSecretRef: # Password used to encrypt the keystore
        key: password
        name: password-secret
EOF

sleep 3
#kubectl get certificates test-cert -oyaml

kubectl get secret ${IMAGE_NAME}-tls-secret -n sandbox -o jsonpath='{ .data.tls\.crt }' | base64 -d 2> /dev/null > /tmp/tls.crt
kubectl get secret ${IMAGE_NAME}-tls-secret -n sandbox -o jsonpath='{ .data.ca\.crt }'  | base64 -d 2> /dev/null > /tmp/ca.crt
kubectl get secret ${IMAGE_NAME}-jks-secret -n sandbox -o jsonpath='{ .data.truststore\.jks }'  | base64 -d 2> /dev/null > /tmp/truststore.jks
kubectl get secret ${IMAGE_NAME}-jks-secret -n sandbox -o jsonpath='{ .data.keystore\.jks }'  | base64 -d 2> /dev/null > /tmp/keystore.jks


echo "ca.crt"
openssl storeutl -text -noout -certs /tmp/ca.crt | grep Subject:
echo "tls.crt"
openssl storeutl -text -noout -certs /tmp/tls.crt | grep Subject:
echo "keystore.jks"
keytool -list -keystore /tmp/keystore.jks -storepass changeme -v 2> /dev/null |grep Owner:


if [ -z "$DEBUG" ]; then 
  kubectl delete secret ${IMAGE_NAME}-tls-secret -n sandbox > /dev/null 2>&1
  kubectl delete Certificate ${IMAGE_NAME} -n sandbox > /dev/null 2>&1  
  kubectl delete ${ISSUER_KIND} ca-issuer -n ${ISSUER_NS} > /dev/null 2>&1
  kubectl delete secret password-secret -n sandbox > /dev/null 2>&1
  kubectl delete certificate ${IMAGE_NAME}-jks -n sandbox > /dev/null 2>&1
  kubectl delete secret ${IMAGE_NAME}-jks-secret -n sandbox > /dev/null 2>&1
  kubectl delete secret ca-key-pair -n ${ISSUER_NS}  > /dev/null 2>&1
  kubectl delete namespace sandbox
  rm -f /tmp/ca.crt /tmp/tls.crt /tmp/keystore.jks /tmp/truststore.jks
fi