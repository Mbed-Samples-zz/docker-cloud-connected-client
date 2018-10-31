#!/bin/bash

echo "Create epoch time file ~/epoch_time.txt"
date +%s > ~/epoch_time.txt
EPOCH_TIME=$(cat ~/epoch_time.txt)

ESP8266_VERSION=master

DEVICE_MANAGEMENT_CLIENT_VERSION=2.0.1.1

APP_BUILD_PROFILE=profiles/size.json
UPGRADE_BUILD_PROFILE=profiles/debug_size.json
BOOTLOADER_BUILD_PROFILE=minimal-printf/profiles/release.json

MBED_OS_VERSION=mbed-os-5.10.1
MBED_OS_COMPILER=GCC_ARM

TARGET_NAME=K64F

EXTRA_BUILD_OPTIONS="--build BUILD/${TARGET_NAME}/${MBED_OS_COMPILER}"

BOOTLOADER_GITHUB_REPO="mbed-bootloader"
BOOTLOADER_VERSION=v3.5.0
CLIENT_GITHUB_REPO="mbed-cloud-client-example"

GITHUB_URI="https://github.com/ARMmbed"

COMBINED_IMAGE_NAME=${EPOCH_TIME}.mbed-os.${TARGET_NAME}.cellular.els61.tcp.ppp
# UPGRADE_IMAGE_NAME=${COMBINED_IMAGE_NAME}-update

######################### APPLICATION #########################

echo "---> cd ~/Source"
cd ~/Source

echo "---> Clone ${GITHUB_URI}/${CLIENT_GITHUB_REPO}"
git clone ${GITHUB_URI}/${CLIENT_GITHUB_REPO}.git

echo "---> cd ~/Source/${CLIENT_GITHUB_REPO}"
cd ~/Source/${CLIENT_GITHUB_REPO}

# echo "---> Run mbed config with APIKEY"
mbed config -G CLOUD_SDK_API_KEY ${MBED_CLOUD_API_KEY}
mbed device-management init -d "mbed.quickstart.company" --model-name "qs v1" --force -q

echo "---> Run mbed deploy ${DEVICE_MANAGEMENT_CLIENT_VERSION}"
mbed deploy ${DEVICE_MANAGEMENT_CLIENT_VERSION}

echo "---> Run mbed update ${DEVICE_MANAGEMENT_CLIENT_VERSION}"
mbed update ${DEVICE_MANAGEMENT_CLIENT_VERSION}

echo "---> Modify .mbedignore and take out features causing compile errors"
echo "mbed-os/components/802.15.4_RF/*" >> .mbedignore
echo "BUILD/*" >> .mbedignore

echo "---> Copy mbed_cloud_dev_credentials.c to project"
cp ~/Creds/mbed_cloud_dev_credentials.c .

echo "---> Copy reference config from esp save to mbed_app.json"
cp configs/wifi_esp8266_v4.json mbed_app.json

echo "---> Remove extra targets in mbed_app.json"
jq -S 'del(."target_overrides"."NUCLEO_F429ZI")' mbed_app.json | sponge mbed_app.json
jq -S 'del(."target_overrides"."STM_EMAC")' mbed_app.json | sponge mbed_app.json

echo "---> Remove esp8266 vars in mbed_app.json"
 jq -S 'del(."target_overrides"."*"."drivers.uart-serial-txbuf-size")' mbed_app.json | sponge mbed_app.json
 jq -S 'del(."target_overrides"."*"."esp8266.rx")' mbed_app.json | sponge mbed_app.json
 jq -S 'del(."target_overrides"."*"."esp8266.tx")' mbed_app.json | sponge mbed_app.json
 jq -S 'del(."target_overrides"."*"."esp8266.provide-default")' mbed_app.json | sponge mbed_app.json
 jq -S 'del(."target_overrides"."*"."nsapi.default-wifi-security")' mbed_app.json | sponge mbed_app.json
 jq -S 'del(."target_overrides"."*"."nsapi.default-wifi-ssid")' mbed_app.json | sponge mbed_app.json
 jq -S 'del(."target_overrides"."*"."nsapi.default-wifi-password")' mbed_app.json | sponge mbed_app.json

echo "---> Add CELLULAR default interface config in mbed_app.json"
jq -S '."target_overrides"."'${TARGET_NAME}'"."target.network-default-interface-type" = "CELLULAR"' mbed_app.json | sponge mbed_app.json

# https://github.com/Avnet/wnc14a2a-driver/#90928b81747ef4b0fb4fdd94705142175e014b30
echo "---> Set up CELLULAR interface config in mbed_app.json"
jq -S '.config."network-interface"."value" = "CELLULAR"' mbed_app.json | sponge mbed_app.json

echo "---> Add LWIP feature"
jq -S '."target_overrides"."'${TARGET_NAME}'"."target.features_add" |= . + ["LWIP"]' mbed_app.json | sponge mbed_app.json

echo "---> Set CELLULAR_DEVICE=GEMALTO_CINTERION '${TARGET_NAME}' target.macros_add"
jq -S '."target_overrides"."'${TARGET_NAME}'"."target.macros_add" |= . + ["CELLULAR_DEVICE=GEMALTO_CINTERION", "MDMRXD=D0", "MDMTXD=D1", "MDMCTS=NC", "MDMRTS=NC"]' mbed_app.json | sponge mbed_app.json

echo "---> Set up cellular options in mbed_app.json"
jq -S '."config"."sock-type" = "tcp"' mbed_app.json | sponge mbed_app.json

jq -S '."config"."sim-pin-code"."help" = "SIM PIN code"' mbed_app.json | sponge mbed_app.json
jq -S '."config"."sim-pin-code"."value" = "\"1234\""' mbed_app.json | sponge mbed_app.json

jq -S '."config"."apn"."help" = "The APN string to use for this SIM/network, set to 0 if none"' mbed_app.json | sponge mbed_app.json
jq -S '."config"."apn"."value" = 0' mbed_app.json | sponge mbed_app.json

jq -S '."config"."username"."help" = "The user name string to use for this APN, set to zero if none"' mbed_app.json | sponge mbed_app.json
jq -S '."config"."username"."value" = 0' mbed_app.json | sponge mbed_app.json

jq -S '."config"."password"."help" = "The password string to use for this APN, set to zero if none"' mbed_app.json | sponge mbed_app.json
jq -S '."config"."password"."value" = 0' mbed_app.json | sponge mbed_app.json

jq -S '."config"."trace-level"."help" = "Options are TRACE_LEVEL_ERROR,TRACE_LEVEL_WARN,TRACE_LEVEL_INFO,TRACE_LEVEL_DEBUG"' mbed_app.json | sponge mbed_app.json
jq -S '."config"."trace-level"."value" = "TRACE_LEVEL_DEBUG"' mbed_app.json | sponge mbed_app.json
jq -S '."config"."trace-level"."macro_name" = "MBED_TRACE_MAX_LEVEL"' mbed_app.json | sponge mbed_app.json

echo "---> Set cellular ${TARGET_NAME} overrides"
jq -S '."target_overrides"."'${TARGET_NAME}'"."ppp-cell-iface.apn-lookup" = false' mbed_app.json | sponge mbed_app.json
jq -S '."target_overrides"."'${TARGET_NAME}'"."cellular.use-apn-lookup" = false' mbed_app.json | sponge mbed_app.json
jq -S '."target_overrides"."'${TARGET_NAME}'"."lwip.ipv4-enabled" = true' mbed_app.json | sponge mbed_app.json
jq -S '."target_overrides"."'${TARGET_NAME}'"."lwip.ethernet-enabled" = false' mbed_app.json | sponge mbed_app.json
jq -S '."target_overrides"."'${TARGET_NAME}'"."lwip.ppp-enabled" = true' mbed_app.json | sponge mbed_app.json
jq -S '."target_overrides"."'${TARGET_NAME}'"."lwip.tcp-enabled" = true' mbed_app.json | sponge mbed_app.json
jq -S '."target_overrides"."'${TARGET_NAME}'"."cellular.debug-at" = true' mbed_app.json | sponge mbed_app.json

echo "---> Set platform.stdio ${TARGET_NAME} overrides"
jq -S '."target_overrides"."*"."platform.stdio-convert-newlines" = true' mbed_app.json | sponge mbed_app.json
jq -S '."target_overrides"."*"."platform.stdio-baud-rate" = 115200' mbed_app.json | sponge mbed_app.json
jq -S '."target_overrides"."*"."platform.stdio-buffered-serial" = true' mbed_app.json | sponge mbed_app.json
jq -S '."target_overrides"."*"."platform.default-serial-baud-rate" = 115200' mbed_app.json | sponge mbed_app.json

echo "---> Remove rxbuf from mbed_app.json"
jq -S 'del(.target_overrides."*"."drivers.uart-serial-rxbuf-size")' mbed_app.json | sponge mbed_app.json

echo "---> Enable mbed-trace.enable in mbed_app.json"
jq -S '.target_overrides."*"."mbed-trace.enable" = null' mbed_app.json | sponge mbed_app.json

echo "---> Change LED blink to LED1 in mbed_app.json"
jq -S '.config."led-pinname"."value" = "LED1"' mbed_app.json | sponge mbed_app.json

echo "---> Enable auto formatting"
jq -S '."config"."mcc-no-auto-format"."help" = "If this is null autoformat will occur"' mbed_app.json | sponge mbed_app.json
jq -S '."config"."mcc-no-auto-format"."value" = null' mbed_app.json | sponge mbed_app.json

echo "---> Remove rxbuf from mbed_app.json"
jq -S 'del(.target_overrides."*"."drivers.uart-serial-rxbuf-size")' mbed_app.json | sponge mbed_app.json

echo "---> Change LED to ON"
sed -r -i -e 's/static DigitalOut led\(MBED_CONF_APP_LED_PINNAME, LED_OFF\);/static DigitalOut led(MBED_CONF_APP_LED_PINNAME, LED_ON);/' source/platform/mbed-os/mcc_common_button_and_led.cpp

echo "---> Run mbed update ${MBED_OS_VERSION} on mbed-os"
cd mbed-os && mbed update ${MBED_OS_VERSION} && cd ..

echo "---> Copy current application mbed_app.json to /root/Share/${EPOCH_TIME}-application-mbed_app.json"
cp mbed_app.json /root/Share/${EPOCH_TIME}-application-mbed_app.json

echo "---> Copy current application mbed_app.json to ~/Share/${EPOCH_TIME}-application-mbed_app.json"
cp mbed_app.json ~/Share/${EPOCH_TIME}-application-mbed_app.json

echo "---> Copy current application mbed_lib.json to ~/Share/${EPOCH_TIME}-application-mbed_lib.json"
cp mbed_lib.json ~/Share/${EPOCH_TIME}-application-mbed_lib.json

echo "---> Compile first mbed client"
mbed compile -m ${TARGET_NAME} -t ${MBED_OS_COMPILER} --profile ${APP_BUILD_PROFILE} ${EXTRA_BUILD_OPTIONS} >> ${EPOCH_TIME}-mbed-compile-client.log

echo "---> Copy build log to ~/Share/${EPOCH_TIME}-mbed-compile-client.log"
cp ${EPOCH_TIME}-mbed-compile-client.log ~/Share

echo "---> Copy the final binary or hex to the share directory"
cp BUILD/${TARGET_NAME}/${MBED_OS_COMPILER}/mbed-cloud-client-example.bin ~/Share/${COMBINED_IMAGE_NAME}.bin

# Check for an upgrade image name and build a second image
if [ "$UPGRADE_IMAGE_NAME" ]; then
    echo "---> Disable auto formatting"
    jq -S '."config"."mcc-no-auto-format"."help" = "If this is null autoformat will occur"' mbed_app.json | sponge mbed_app.json
    jq -S '."config"."mcc-no-auto-format"."value" = 1' mbed_app.json | sponge mbed_app.json

    echo "---> Change LED blink to LED2 in mbed_app.json"
    jq -S '.config."led-pinname"."value" = "LED2"' mbed_app.json | sponge mbed_app.json

    echo "---> Output a bin file for upgrades"
    jq -S '."target_overrides"."'${TARGET_NAME}'"."target.OUTPUT_EXT" = "bin"' mbed_app.json | sponge mbed_app.json

    echo "---> Copy current update mbed_app.json to ~/Share/${EPOCH_TIME}-update-mbed_app.json"
    cp mbed_app.json ~/Share/${EPOCH_TIME}-update-mbed_app.json

    echo "---> Compile upgrade image"
    mbed compile -m ${TARGET_NAME} -t ${MBED_OS_COMPILER} --profile ${UPGRADE_BUILD_PROFILE} --build BUILD/${TARGET_NAME}/${MBED_OS_COMPILER} >> ${EPOCH_TIME}-mbed-compile-client.log

    echo "---> Copy build log to ~/Share/${EPOCH_TIME}-mbed-compile-client.log"
    cp ${EPOCH_TIME}-mbed-compile-client.log ~/Share

    echo "---> Copy upgrade image to share ${UPGRADE_IMAGE_NAME}.bin"
    cp BUILD/${TARGET_NAME}/${MBED_OS_COMPILER}/mbed-cloud-client-example_application.bin ~/Share/${UPGRADE_IMAGE_NAME}.bin

    echo "---> Run upgrade campaign using mbed device-management tool"
    echo "mbed device-management update device -p ~/Share/${UPGRADE_IMAGE_NAME}.bin -D my_connected_device_id"
fi

echo "---> Copy ${BOOTLOADER_GITHUB_REPO} ${CLIENT_GITHUB_REPO} builds to /root/Share/${EPOCH_TIME}-Source"
cp -R /root/Source /root/Share/${EPOCH_TIME}-Source

echo "---> Keeping the container running with a tail of the build logs"
tail -f ~/epoch_time.txt
