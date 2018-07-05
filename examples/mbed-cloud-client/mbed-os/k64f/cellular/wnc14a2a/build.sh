#!/bin/bash

echo "Create epoch time file /root/epoch_time.txt"
date +%s > /root/epoch_time.txt
EPOCH_TIME=$(cat /root/epoch_time.txt)

EASY_CONNECT_VERSION=master

MBED_CLOUD_VERSION=1.3.3
MBED_CLOUD_UPDATE_EPOCH=0
MBED_CLOUD_MANIFEST_TOOL_VERSION=master

BUILD_PROFILE=release

MBED_OS_VERSION=masater
MBED_OS_COMPILER=GCC_ARM

TARGET_NAME=K64F

BOOTLOADER_GITHUB_REPO="mbed-bootloader"
BOOTLOADER_VERSION=v3.3.0
CLIENT_GITHUB_REPO="mbed-cloud-client-example"

GITHUB_URI="https://github.com/ARMmbed"

COMBINED_IMAGE_NAME=${EPOCH_TIME}.mbed-os.${TARGET_NAME}.cellular.wnc14a2a
UPGRADE_IMAGE_NAME=${COMBINED_IMAGE_NAME}-update

echo "---> Make Source Download dirs"
mkdir -p /root/Source /root/Download/manifest_tool

######################### MANIFEST TOOL #########################

echo "---> Install mbed cloud client tools"
pip install git+${GITHUB_URI}/manifest-tool.git@${MBED_CLOUD_MANIFEST_TOOL_VERSION}

echo "---> cd /root/Download/manifest_tool"
cd /root/Download/manifest_tool

echo "---> Initialize manifest tool"
manifest-tool init -d "mbed.quickstart.company" -m "qs v1" -q --force -a ${MBED_CLOUD_API_KEY}

echo "---> Install mbed-cloud-sdk"
pip install mbed-cloud-sdk

######################### APPLICATION #########################

echo "---> cd /root/Source"
cd /root/Source

echo "---> Clone ${GITHUB_URI}/${CLIENT_GITHUB_REPO}"
git clone ${GITHUB_URI}/${CLIENT_GITHUB_REPO}.git

echo "---> cd /root/Source/${CLIENT_GITHUB_REPO}"
cd /root/Source/${CLIENT_GITHUB_REPO}

echo "---> Run mbed deploy ${MBED_CLOUD_VERSION}"
mbed deploy ${MBED_CLOUD_VERSION}

echo "---> Run mbed update ${MBED_CLOUD_VERSION}"
mbed update ${MBED_CLOUD_VERSION}

echo "---> cp /root/Download/manifest_tool/update_default_resources.c"
cp /root/Download/manifest_tool/update_default_resources.c .

echo "---> Copy mbed_cloud_dev_credentials.c to project"
cp /root/Creds/mbed_cloud_dev_credentials.c .

# https://github.com/ARMmbed/mbed-cloud-client-example/pull/17
echo "---> Get WNC config and save to mbed_app.json"
wget -O mbed_app.json https://raw.githubusercontent.com/jflynn129/mbed-cloud-client-example/aedf5dd07e9dfb6502e803cd4a05e30f2c889a4f/wnc14a2a.json

# https://github.com/Avnet/wnc14a2a-driver/#90928b81747ef4b0fb4fdd94705142175e014b30
echo "---> Set up WNC config in mbed_app.json"
jq '.config."network-interface"."value" = "CELLULAR_WNC14A2A"' mbed_app.json | sponge mbed_app.json

echo "---> Enable mbed-trace.enable in mbed_app.json"
jq '.target_overrides."*"."mbed-trace.enable" = 1' mbed_app.json | sponge mbed_app.json

echo "---> Change LED to ON"
sed -r -i -e 's/static DigitalOut led\(MBED_CONF_APP_LED_PINNAME, LED_OFF\);/static DigitalOut led(MBED_CONF_APP_LED_PINNAME, LED_ON);/' source/platform/mbed-os/common_button_and_led.cpp

echo "---> Change LED to LED1 in mbed_app.json"
jq '.config."led-pinname"."value" = "LED1"' mbed_app.json | sponge mbed_app.json

echo "---> Set storage-selector.filesystem"
jq '."target_overrides"."*"."storage-selector.filesystem" = "LITTLE"' mbed_app.json | sponge mbed_app.json

echo "---> Set storage-selector.storage"
jq '."target_overrides"."*"."storage-selector.storage" = "SD_CARD"' mbed_app.json | sponge mbed_app.json

# default is 1GB ifyou don't specify
echo "---> Set client_app.primary_partition_size"
jq '."target_overrides"."'${TARGET_NAME}'"."client_app.primary_partition_size" = 1048576' mbed_app.json | sponge mbed_app.json

echo "---> Disable auto partitioning"
jq '.target_overrides."*"."auto_partition" = 0' mbed_lib.json | sponge mbed_lib.json

echo "---> Run mbed update ${MBED_OS_VERSION} on mbed-os"
cd mbed-os && mbed update ${MBED_OS_VERSION} && cd ..

echo "---> Run mbed update on easy-connect ${EASY_CONNECT_VERSION}"
cd easy-connect && mbed update ${EASY_CONNECT_VERSION} && cd ..

echo "---> Copy current application mbed_app.json to /root/Share/${EPOCH_TIME}-application-mbed_app.json"
cp mbed_app.json /root/Share/${EPOCH_TIME}-application-mbed_app.json

echo "---> Compile first mbed client"
mbed compile -m ${TARGET_NAME} -t ${MBED_OS_COMPILER} --profile ${BUILD_PROFILE} >> ${EPOCH_TIME}-mbed-compile-client.log

echo "---> Copy build log to /root/Share/${EPOCH_TIME}-mbed-compile-client.log"
cp ${EPOCH_TIME}-mbed-compile-client.log /root/Share

echo "---> Run the combine script to get a bootloader"
python tools/combine_bootloader_with_app.py -m k64f -b tools/mbed-bootloader-k64f-block_device-sotp-v3_3_0.bin -a BUILD/${TARGET_NAME}/${MBED_OS_COMPILER}/mbed-cloud-client-example.bin -o ${COMBINED_IMAGE_NAME}.bin

echo "---> Copy the final ${COMBINED_IMAGE_NAME} to the share directory"
cp ${COMBINED_IMAGE_NAME}.bin /root/Share/

# Check for an upgrade image name and build a second image
if [ "$UPGRADE_IMAGE_NAME" ]; then
    echo "---> Change LED to LED2 in mbed_app.json"
    jq '.config."led-pinname"."value" = "LED2"' mbed_app.json | sponge mbed_app.json

    echo "---> Compile upgrade image"
    mbed compile -m ${TARGET_NAME} -t ${MBED_OS_COMPILER} --profile ${BUILD_PROFILE} >> ${EPOCH_TIME}-mbed-compile-client.log

    echo "---> Copy build log to /root/Share/${EPOCH_TIME}-mbed-compile-client.log"
    cp ${EPOCH_TIME}-mbed-compile-client.log /root/Share

    echo "---> Copy upgrade image to share ${UPGRADE_IMAGE_NAME}.bin"
    cp BUILD/${TARGET_NAME}/${MBED_OS_COMPILER}/mbed-cloud-client-example_application.bin /root/Share/${UPGRADE_IMAGE_NAME}.bin

    echo "---> Run upgrade campaign using manifest tool"
    echo "cd /root/Download/manifest_tool"
    echo "manifest-tool update device -p /root/Share/${UPGRADE_IMAGE_NAME}.bin -D my_connected_device_id"
fi

echo "---> Keeping the container running with a tail of the build logs"
tail -f /root/epoch_time.txt
