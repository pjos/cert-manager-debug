#!/bin/bash

# https://superuser.com/questions/126121/how-to-create-my-own-certificate-chain
# https://access.redhat.com/documentation/en-us/red_hat_codeready_workspaces/2.1/html/installation_guide/installing-codeready-workspaces-in-tls-mode-with-self-signed-certificates_crw

CA_CN="Red Hat CodeReadyContainers"
DOMAIN=*.apps-crc.testing
OPENSSL_CNF=/etc/ssl/openssl.cnf

if [ ! -f rootCA.key ]; then 
    openssl genrsa -out rootCA.key 4096
    openssl req -x509 \
    -new -nodes \
    -key rootCA.key \
    -sha256 \
    -days 9650 \
    -out rootCA.crt \
    -subj /CN="SelfSigned Root CA v1.0" \
    -reqexts SAN \
    -extensions SAN \
    -config <(cat ${OPENSSL_CNF} \
        <(printf '[SAN]\nbasicConstraints=critical, CA:TRUE\nkeyUsage=keyCertSign, cRLSign, digitalSignature'))

    openssl genrsa -out intermediate.key 2048
    openssl req \
        -new -nodes \
        -key intermediate.key \
        -sha256 \
        -subj /CN="Intermediate v1.0" \
        -reqexts SAN \
        -extensions SAN \
        -config <(cat ${OPENSSL_CNF} \
        <(printf '[SAN]\nbasicConstraints=critical, CA:TRUE\nkeyUsage=keyCertSign, cRLSign, digitalSignature')) \
        -out intermediate.csr

    openssl req -x509 \
        -sha256 \
        -days 1000 \
        -in intermediate.csr \
        -CA rootCA.crt \
        -CAkey rootCA.key \
        -out intermediate.crt


    openssl genrsa -out domain.key 2048
    openssl req -new -sha256 \
        -key domain.key \
        -subj "/O=CRC/CN=${DOMAIN}" \
        -reqexts SAN \
        -config <(cat ${OPENSSL_CNF} \
            <(printf "\n[SAN]\nsubjectAltName=DNS:${DOMAIN}\nbasicConstraints=critical, CA:TRUE\nkeyUsage=digitalSignature, keyEncipherment, keyAgreement, dataEncipherment\nextendedKeyUsage=serverAuth")) \
        -out domain.csr

    openssl x509 \
        -req \
        -sha256 \
        -extfile <(printf "subjectAltName=DNS:${DOMAIN}\nbasicConstraints=critical, CA:TRUE\nkeyUsage=digitalSignature, keyEncipherment, keyAgreement, dataEncipherment\nextendedKeyUsage=serverAuth") \
        -days 365 \
        -in domain.csr \
        -CA intermediate.crt \
        -CAkey intermediate.key \
        -CAcreateserial -out domain.crt

    cat intermediate.crt >> domain.crt
    #cat rootCA.crt >> domain.crt
fi
echo "------------------------------------------------------------------------------"

#-x509_strict
openssl verify  -CAfile rootCA.crt -untrusted intermediate.crt domain.crt

echo "------------------------------------------------------------------------------"

minikube status > /dev/null || {
    minikube start --addons=ingress --vm=true --memory=6144 --cpus=4
} 

kubectl get namespace sandbox > /dev/null 2>&1 && kubectl delete namespace sandbox
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.10.1/cert-manager.yaml
sleep 30 


kubectl create -f - <<EOF
---
apiVersion: v1
kind: Namespace
metadata:
  labels:
    kubernetes.io/metadata.name: sandbox
  name: sandbox
---
apiVersion: v1
kind: Secret
metadata:
  name: ca-key-pair
  namespace: sandbox
data:
  tls.crt: $(cat domain.crt | base64 -w0)
  tls.key: $(cat domain.key | base64 -w0)
---
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: ca-issuer
  namespace: sandbox
spec:
  ca:
    secretName: ca-key-pair
EOF

echo "kubectl get issuers ca-issuer -n sandbox -o wide"
kubectl get issuers ca-issuer -n sandbox -o wide
export IMAGE_NAME=test-cert
kubectl create -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ${IMAGE_NAME}
spec:
  commonName: gateway.com
  dnsNames:
    - 192.168.0.1
  issuerRef:
    kind: Issuer
    name: ca-issuer
  secretName: ${IMAGE_NAME}-tls-secret
EOF
sleep 5
kubectl get certificates test-cert -oyaml