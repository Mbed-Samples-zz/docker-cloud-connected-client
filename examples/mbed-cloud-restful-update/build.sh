#!/bin/bash

echo "Create epoch time file /root/epoch_time.txt"
date +%s > /root/epoch_time.txt

echo "---> Use epoch time from .env MBED_CLOUD_UPDATE_EPOCH ${MBED_CLOUD_UPDATE_EPOCH}"
EPOCH_TIME=${MBED_CLOUD_UPDATE_EPOCH}

if [ -z "$UPGRADE_IMAGE_NAME" ]; then
    echo "---> Define UPGRADE_IMAGE_NAME in your .env file"
    echo "--->   e.g. UPGRADE_IMAGE_NAME='my_fota_upgrade.bin'"
    exit
else
    echo "---> Use UPGRADE_IMAGE_NAME from .env '${UPGRADE_IMAGE_NAME}'"
fi

GITHUB_REPO="manifest-tool"
GITHUB_URI="https://github.com/ARMmbed"

echo "---> Install software"
apk add --update \
    jq \
    git \
    gcc \
    build-base \
    python \
    py-pip \
    python-dev \
    libffi-dev \
    openssl-dev \
    openssh-client \
    curl \
    sponge

echo "---> Create .netrc for cloning private GitHub repos"
echo "machine github.com" > /root/.netrc
echo "login ${GITHUB_USER}" >> /root/.netrc
echo "password ${GITHUB_TOKEN}" >> /root/.netrc

echo "---> Make .ssh Source Download dirs"
mkdir -p /root/.ssh /root/Source /root/Download/manifest_tool/.update-certificates

echo "---> Copy over id_rsa private key, and set permissions"
cp /root/Creds/id_rsa /root/.ssh/id_rsa

echo "---> Create known_hosts"
touch /root/.ssh/known_hosts

echo "---> Add GitHub server key to known_hosts"
ssh-keyscan github.com >> /root/.ssh/known_hosts

echo "---> Install mbed cloud client tools"
pip install git+${GITHUB_URI}/${GITHUB_REPO}.git@${MBED_CLOUD_MANIFEST_TOOL_VERSION}

echo "---> cd /root/Download/manifest_tool"
cd /root/Download/manifest_tool

echo "---> Unarchive manifest data from epoch.qs_manifest_data.json"
jq -r '.json' /root/Share/${EPOCH_TIME}.qs.manifest.data.json > .manifest_tool.json
jq -r '.pem' /root/Share/${EPOCH_TIME}.qs.manifest.data.json > .update-certificates/default.key.pem
jq -r '.der' /root/Share/${EPOCH_TIME}.qs.manifest.data.json | base64 -d > .update-certificates/default.der

echo "---> UPLOAD ${UPGRADE_IMAGE_NAME} IMAGE"
# check and delete ${UPGRADE_IMAGE_NAME} image if it already exists?

echo "---> POST mbedcloud/v3/firmware-images upload firmware"
curl -s -X POST ${MBED_CLOUD_API_ENDPOINT}/v3/firmware-images/ -H 'authorization:Bearer '"${MBED_CLOUD_API_KEY}"'' -H 'content-type:multipart/form-data' -F datafile=@/root/Share/${UPGRADE_IMAGE_NAME} -F name=${UPGRADE_IMAGE_NAME} > ${EPOCH_TIME}-post-image-response.json

echo "---> Copy ${EPOCH_TIME}-post-image-response.json to /root/Share"
cp ${EPOCH_TIME}-post-image-response.json /root/Share

# ##### CREATE ${UPGRADE_IMAGE_NAME} MANIFEST

echo "---> Get ${UPGRADE_IMAGE_NAME} image url"
UPGRADE_IMAGE_URL=$(jq -r '.datafile' ${EPOCH_TIME}-post-image-response.json)

echo "---> Create a manifest by pulling out the datafile from the results.json"
manifest-tool create -u ${UPGRADE_IMAGE_URL} -p /root/Share/${UPGRADE_IMAGE_NAME} -o ${UPGRADE_IMAGE_NAME}.manifest

echo "---> Copy ${UPGRADE_IMAGE_NAME} manifest to /root/Share"
cp ${UPGRADE_IMAGE_NAME}.manifest /root/Share/

# ##### UPLOAD ${UPGRADE_IMAGE_NAME} MANIFEST

echo "---> Upload ${UPGRADE_IMAGE_NAME} manifest with cURL to mbed Cloud and save manifest resource ID"
curl -s -X POST ${MBED_CLOUD_API_ENDPOINT}/v3/firmware-manifests/ -H 'authorization:Bearer '"${MBED_CLOUD_API_KEY}"'' -H 'content-type:multipart/form-data' -F datafile=@/root/Share/${UPGRADE_IMAGE_NAME}.manifest -F name=${UPGRADE_IMAGE_NAME}.manifest > ${EPOCH_TIME}-post-manifest.json

echo "---> Copy ${EPOCH_TIME}-post-manifest.json to /root/Share"
cp ${EPOCH_TIME}-post-manifest.json /root/Share

# ##### CREATE GENERAL UPDATE FILTER

echo "---> Get ${UPGRADE_IMAGE_NAME} manifest classid"
MANIFEST_CLASSID=$(jq -r '.classId' /root/Download/manifest_tool/.manifest_tool.json | sed 's/-//g')

echo "---> Create ${UPGRADE_IMAGE_NAME} filter json struct for curl to use ${UPGRADE_IMAGE_NAME}.campaign_body.json"

# note this can probably be removed and just use jq to insert/create
echo '{"name":"","query":"","state":""}' > ${UPGRADE_IMAGE_NAME}.filter_body.json

jq '.name = "'${UPGRADE_IMAGE_NAME}' Filter"' ${UPGRADE_IMAGE_NAME}.filter_body.json | sponge ${UPGRADE_IMAGE_NAME}.filter_body.json
jq '.query = "'device_class=${MANIFEST_CLASSID}'"' ${UPGRADE_IMAGE_NAME}.filter_body.json | sponge ${UPGRADE_IMAGE_NAME}.filter_body.json
jq '.state = "bootstrapped"' ${UPGRADE_IMAGE_NAME}.filter_body.json | sponge ${UPGRADE_IMAGE_NAME}.filter_body.json

echo "---> Copy ${UPGRADE_IMAGE_NAME}.filter_body.json to /root/Share"
cp ${UPGRADE_IMAGE_NAME}.filter_body.json /root/Share

echo "---> Create ${UPGRADE_IMAGE_NAME} device filter and save response"
curl -s -X POST ${MBED_CLOUD_API_ENDPOINT}/v3/device-queries/ -H 'authorization:Bearer '"${MBED_CLOUD_API_KEY}"'' -H 'content-type:application/json' --data @${UPGRADE_IMAGE_NAME}.filter_body.json > ${EPOCH_TIME}-post-filter.json

echo "---> Copy ${EPOCH_TIME}-post-filter.json to /root/Share"
cp ${EPOCH_TIME}-post-filter.json /root/Share

# # ##### CREATE ${UPGRADE_IMAGE_NAME} UPDATE CAMPAIGN
echo "---> Get ${UPGRADE_IMAGE_NAME} manifest id"
MANIFEST_ID=$(jq -r '.id' ${EPOCH_TIME}-post-manifest.json)

echo "---> Get ${UPGRADE_IMAGE_NAME} manifest url"
MANIFEST_URL=$(jq -r '.datafile' ${EPOCH_TIME}-post-manifest.json)

# note this can probably be removed and just use jq to insert/create
echo '{"root_manifest_id":"","root_manifest_url":"","name":"","device_filter":"","state":""}' > ${UPGRADE_IMAGE_NAME}.campaign_body.json

echo "---> Create ${UPGRADE_IMAGE_NAME} campaign json struct for curl to use ${UPGRADE_IMAGE_NAME}.campaign_body.json"
jq '.root_manifest_id = "'${MANIFEST_ID}'"' ${UPGRADE_IMAGE_NAME}.campaign_body.json | sponge ${UPGRADE_IMAGE_NAME}.campaign_body.json
jq '.root_manifest_url = "'${MANIFEST_URL}'"' ${UPGRADE_IMAGE_NAME}.campaign_body.json | sponge ${UPGRADE_IMAGE_NAME}.campaign_body.json
jq '.name = "'${UPGRADE_IMAGE_NAME}' Campaign"' ${UPGRADE_IMAGE_NAME}.campaign_body.json | sponge ${UPGRADE_IMAGE_NAME}.campaign_body.json
jq '.device_filter = "state=registered&device_class='${MANIFEST_CLASSID}'"' ${UPGRADE_IMAGE_NAME}.campaign_body.json | sponge ${UPGRADE_IMAGE_NAME}.campaign_body.json
jq '.state = "draft"' ${UPGRADE_IMAGE_NAME}.campaign_body.json | sponge ${UPGRADE_IMAGE_NAME}.campaign_body.json

echo "---> Copy ${UPGRADE_IMAGE_NAME}.campaign_body.json to /root/Share"
cp ${UPGRADE_IMAGE_NAME}.campaign_body.json /root/Share

echo "---> Create ${UPGRADE_IMAGE_NAME} campaign and save response"
curl -s -X POST ${MBED_CLOUD_API_ENDPOINT}/v3/update-campaigns/ -H 'authorization:Bearer '"${MBED_CLOUD_API_KEY}"'' -H 'content-type:application/json' --data @${UPGRADE_IMAGE_NAME}.campaign_body.json > post-campaign-${EPOCH_TIME}.json

echo "---> Keeping the container running with a tail of the build logs"
tail -f /root/epoch_time.txt
