#!/bin/bash

echo "Create epoch time file /root/epoch_time.txt"
date +%s > /root/epoch_time.txt
EPOCH_TIME=$(cat /root/epoch_time.txt)

echo "---> Change to /root"
cd /root

echo "---> Call v3/users to get account id data structure"
curl -s -X GET https://api.us-east-1.mbedcloud.com/v3/users -H 'Authorization: Bearer '"${API_KEY}"'' -H 'Content-Type: application/json' > users.json

echo "---> Set account id from v3/users results"
ACCOUNT_ID=$(jq -r '.data[0]."account_id"')

echo "---> Clone java-coap"
git clone https://github.com/ARMmbed/java-coap

echo "---> Change to /root/java-coap"
cd java-coap

echo "---> Maven install the project"
mvn package install -DskipTests

ENDPOINT_NAME=$(uuid)
# https://github.com/ARMmbed/java-coap/issues/3

# Remove existing keys and keystore
rm -rf keystore

mkdir keystore && cd keystore

curl -s -X GET \
  https://api.us-east-1.mbedcloud.com/v3/server-credentials/lwm2m \
  -H 'Authorization: Bearer '"${API_KEY}"'' \
  -H 'Cache-Control: no-cache' \
  -H 'Content-Type: application/json' | python -c 'import sys, json; print json.load(sys.stdin)["server_certificate"]' > lwm2m_server_ca_certificate.pem

# create self signed CA
# upload it to cloud and
# create device certificate signed by that CA.

###########  CA

# Create private key for the LWM2M CA certificate
openssl ecparam -out my_ca_private_key.pem -name prime256v1 -genkey

# Self-sign public CA cert with private key - upload this to mbed cloud
openssl req -key my_ca_private_key.pem -new -sha256 -x509 -days 12775 -out my_ca_public_cert.pem -subj /CN=CA -config <(echo '[req]'; echo 'distinguished_name=dn'; echo '[dn]'; echo '[ext]'; echo 'basicConstraints=CA:TRUE') -extensions ext

###########  DEVICE

# Create device private key
openssl ecparam -out lwm2m_device_private_key.pem -name prime256v1 -genkey

# Convert private key to DER format
openssl ec -in lwm2m_device_private_key.pem -out lwm2m_device_private_key.der -outform der

# Create a certificate signing request (CSR) for the private key
openssl req -key lwm2m_device_private_key.pem -new -sha256 -out lwm2m_device_private_key_csr.pem -subj /CN=${ENDPOINT_NAME}

# Sign the certificate signing request (CSR) with the CA private key and certificate -
openssl x509 -req -in lwm2m_device_private_key_csr.pem -sha256 -out lwm2m_device_cert.der -outform der -CA my_ca_public_cert.pem -CAkey my_ca_private_key.pem -CAcreateserial -days 3650

openssl x509 -req -in lwm2m_device_private_key_csr.pem -sha256 -out lwm2m_device_cert.pem -outform pem -CA my_ca_public_cert.pem -CAkey my_ca_private_key.pem -CAcreateserial -days 3650

# View the DER encoded lwm2m device certificate - convenience only
openssl x509 -in lwm2m_device_cert.der -inform der -text -noout

# Create a PKCS #12 archive to store cryptography objects so we can create a Java keystore from it
openssl pkcs12 -export -in lwm2m_device_cert.pem -inkey lwm2m_device_private_key.pem -out my_lwm2m_device_keystore_certs.p12 -name mbed-cloud-${ENDPOINT_NAME} -password pass:secret

# Create Java keystore importing the PKCS #12 archive
keytool -keystore example-client-device-keystore.jks -storepass secret -importkeystore -srcstorepass secret -srckeystore my_lwm2m_device_keystore_certs.p12 -srcstoretype PKCS12 -noprompt

# mbed-cloud-${ENDPOINT_NAME}
# Import our CA cert we created above to the Java keystore
keytool -keystore example-client-device-keystore.jks -storepass secret -import -alias lwm2m_server_ca_certificate -file lwm2m_server_ca_certificate.pem -noprompt

# Examine the keystore
keytool -list -v -storepass secret -keystore example-client-device-keystore.jks

CERT=$(cat my_ca_public_cert.pem | sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/\\n/g')
echo -n "{\"name\": \"Dexter Fryar my_ca_public_cert.pem\", \"description\": \"LWM2M self signed certificate for testing https://github.com/ARMmbed/java-coap/example-client\", \"certificate\": \"${CERT}\", \"service\": \"lwm2m\"}" > payload.json

# Upload the certificate to mbedcloud if you didn't use the portal
curl -X POST \
  -d @payload.json \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer '"${API_KEY}"'' \
  -H 'Cache-Control: no-cache' \
  https://api.us-east-1.mbedcloud.com/v3/trusted-certificates

printf "\n\n\nRUN THE CLIENT: ./run.sh -k ../../keystore/example-client-device-keystore.jks 'coaps://lwm2m.us-east-1.mbedcloud.com:5684/rd?ep=${ENDPOINT_NAME}&aid=${ACCOUNT_ID}'\n\n"

cd ../example-client

./run.sh -k ../keystore/example-client-device-keystore.jks "coaps://lwm2m.us-east-1.mbedcloud.com:5684/rd?ep=${ENDPOINT_NAME}&aid=${ACCOUNT_ID}"

# debugging container
# tail -f /root/epoch_time.txt