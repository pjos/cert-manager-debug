#!/bin/bash

# https://superuser.com/questions/126121/how-to-create-my-own-certificate-chain
# https://access.redhat.com/documentation/en-us/red_hat_codeready_workspaces/2.1/html/installation_guide/installing-codeready-workspaces-in-tls-mode-with-self-signed-certificates_crw

CA_CN="Red Hat CodeReadyContainers"
DOMAIN=*.apps-crc.testing
OPENSSL_CNF=/etc/ssl/openssl.cnf

if [ ! -f rootCA.key ]; then 
    echo "------------------------------------------------------------------------------"
    echo " rootCA"
    echo "------------------------------------------------------------------------------"
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

    echo "------------------------------------------------------------------------------"
    echo " intermediate"
    echo "------------------------------------------------------------------------------"
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

    echo "------------------------------------------------------------------------------"
    echo " intermediate crt"
    echo "------------------------------------------------------------------------------"
    openssl req -x509 \
        -sha256 \
        -days 1000 \
        -in intermediate.csr \
        -copy_extensions copyall \
        -CA rootCA.crt \
        -CAkey rootCA.key \
        -out intermediate.crt

    echo "------------------------------------------------------------------------------"
    echo " leaf"
    echo "------------------------------------------------------------------------------"
    openssl genrsa -out domain.key 2048
    openssl req -new -sha256 \
        -key domain.key \
        -subj "/O=cert-manager/CN=${DOMAIN}" \
        -reqexts SAN \
        -extensions SAN \
        -config <(cat ${OPENSSL_CNF} \
          <(printf '[SAN]\nbasicConstraints=critical, CA:TRUE\nkeyUsage=keyCertSign, cRLSign, digitalSignature')) \
        -out domain.csr

    openssl x509 \
        -req \
        -sha256 \
        -days 365 \
        -in domain.csr \
        -copy_extensions copyall \
        -CA intermediate.crt \
        -CAkey intermediate.key \
        -out domain.crt

    cat intermediate.crt >> domain.crt
    cat rootCA.crt >> domain.crt
fi

echo "------------------------------------------------------------------------------"
echo "openssl verify -x509_strict -CAfile rootCA.crt -untrusted intermediate.crt domain.crt"
openssl verify -x509_strict -CAfile rootCA.crt -untrusted intermediate.crt domain.crt
echo "------------------------------------------------------------------------------"

