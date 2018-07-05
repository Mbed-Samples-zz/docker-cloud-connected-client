#!/bin/bash

echo "Create epoch time file /root/epoch_time.txt"
date +%s > /root/epoch_time.txt
EPOCH_TIME=$(cat /root/epoch_time.txt)

EASY_CONNECT_VERSION=master
ESP8266_VERSION=master

MBED_CLOUD_VERSION=1.3.3
MBED_CLOUD_UPDATE_EPOCH=0
MBED_CLOUD_MANIFEST_TOOL_VERSION=master

BUILD_PROFILE=release

MBED_OS_VERSION=master
MBED_OS_COMPILER=GCC_ARM

TARGET_NAME=NRF52840_DK

BOOTLOADER_GITHUB_REPO="mbed-bootloader"
BOOTLOADER_VERSION=v3.3.0
CLIENT_GITHUB_REPO="mbed-cloud-client-example"

GITHUB_URI="https://github.com/ARMmbed"

COMBINED_IMAGE_NAME=${EPOCH_TIME}.mbed-os.${TARGET_NAME}.wifi.esp8266

if [ -z "$WIFI_SSID" ]; then
    echo "---> Define WIFI_SSID in your .env file"
    echo "--->   e.g. WIFI_SSID='my_wifi_ssid'"
    exit
else
    echo "---> Use WIFI_SSID from .env '${WIFI_SSID}'"
fi

echo "---> Make Source Download dirs"
mkdir -p /root/Source /root/Download/manifest_tool

######################## BOOTLOADER #########################

echo "---> cd /root/Source"
cd /root/Source

echo "---> Clone ${GITHUB_URI}/${BOOTLOADER_GITHUB_REPO}"
git clone ${GITHUB_URI}/${BOOTLOADER_GITHUB_REPO}.git

echo "---> cd /root/Source/${BOOTLOADER_GITHUB_REPO}"
cd /root/Source/${BOOTLOADER_GITHUB_REPO}

echo "---> Run mbed deploy ${BOOTLOADER_VERSION}"
mbed deploy ${BOOTLOADER_VERSION}

echo "---> Run mbed update ${BOOTLOADER_VERSION}"
mbed update ${BOOTLOADER_VERSION}

echo "---> Run mbed update ${MBED_OS_VERSION} on mbed-os"
cd mbed-os && mbed update ${MBED_OS_VERSION} && cd ..

echo "---> Modify .mbedignore and take out features causing compile errors"
echo "mbed-os/features/nvstore/*" >> .mbedignore
echo "mbed-os/features/cellular/*" >> .mbedignore
echo "mbed-os/features/lorawan/*" >> .mbedignore
echo "mbed-os/features/device_key/*" >> .mbedignore
echo "mbed-os/features/lwipstack/*" >> .mbedignore

echo "---> Set ${TARGET_NAME} details in mbed_app.json"
jq '."target_overrides"."'${TARGET_NAME}'"."flash-start-address" = "0x0"' mbed_app.json | sponge mbed_app.json
jq '."target_overrides"."'${TARGET_NAME}'"."flash-size" = "(1024*1024)"' mbed_app.json | sponge mbed_app.json
jq '."target_overrides"."'${TARGET_NAME}'"."sotp-section-1-address" = "(MBED_CONF_APP_FLASH_START_ADDRESS+1016*1024)"' mbed_app.json | sponge mbed_app.json
jq '."target_overrides"."'${TARGET_NAME}'"."sotp-section-1-size" = "(4*1024)"' mbed_app.json | sponge mbed_app.json
jq '."target_overrides"."'${TARGET_NAME}'"."sotp-section-2-address" = "(MBED_CONF_APP_FLASH_START_ADDRESS+1020*1024)"' mbed_app.json | sponge mbed_app.json
jq '."target_overrides"."'${TARGET_NAME}'"."sotp-section-2-size" = "(4*1024)"' mbed_app.json | sponge mbed_app.json
jq '."target_overrides"."'${TARGET_NAME}'"."update-client.application-details" = "(MBED_CONF_APP_FLASH_START_ADDRESS+212*1024)"' mbed_app.json | sponge mbed_app.json
jq '."target_overrides"."'${TARGET_NAME}'"."application-start-address" = "(MBED_CONF_APP_FLASH_START_ADDRESS+213*1024)"' mbed_app.json | sponge mbed_app.json
jq '."target_overrides"."'${TARGET_NAME}'"."max-application-size" = "DEFAULT_MAX_APPLICATION_SIZE"' mbed_app.json | sponge mbed_app.json
jq '."target_overrides"."'${TARGET_NAME}'"."target.OUTPUT_EXT" = "hex"' mbed_app.json | sponge mbed_app.json

echo "---> Copy current bootloader mbed_app.json to /root/Share/${EPOCH_TIME}-bootloader-mbed_app.json"
cp mbed_app.json /root/Share/${EPOCH_TIME}-bootloader-mbed_app.json

echo "---> Compile mbed bootloader"
mbed compile -m ${TARGET_NAME} -t ${MBED_OS_COMPILER} --profile minimal-printf/profiles/release.json >> mbed-compile-bootloader.log

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

echo "---> Copy wifi mbed_app.json config"
cp configs/wifi_esp8266_v4.json mbed_app.json

echo "---> Enable mbed-trace.enable in mbed_app.json"
jq '.target_overrides."*"."mbed-trace.enable" = 1' mbed_app.json | sponge mbed_app.json

# echo "---> Change LED to ON"
# sed -r -i -e 's/DigitalOut[ ]*led\(MBED_CONF_APP_LED_PINNAME, LED_OFF\);/DigitalOut led(MBED_CONF_APP_LED_PINNAME, LED_ON);/' source/platform/mbed-os/setup.cpp

echo "---> Set wifi SSID in config"
jq '.config."wifi-ssid".value = "\"'"${WIFI_SSID}"'\""' mbed_app.json | sponge mbed_app.json

echo "---> Set wifi password in config"
jq '.config."wifi-password".value = "\"'"${WIFI_PASS}"'\""' mbed_app.json | sponge mbed_app.json

echo "---> Change LED blink to LED1 in mbed_app.json"
jq '.config."led-pinname"."value" = "LED1"' mbed_app.json | sponge mbed_app.json

# New undocumented feature that removes the need to run the combine script
echo "---> Copy managed bootloader automatic application header mbed_lib.json to tools dir"
cp /root/Config/mbed_lib.json tools/

echo "---> Add target.app_offset in mbed_lib.json"
jq '.target_overrides."*"."target.app_offset" = "0x35400"' tools/mbed_lib.json | sponge tools/mbed_lib.json

echo "---> Add target.header_offset in mbed_lib.json"
jq '.target_overrides."*"."target.header_offset" = "0x35000"' tools/mbed_lib.json | sponge tools/mbed_lib.json

echo "---> Add ${TARGET_NAME}.target.bootloader_img in mbed_app.json"
jq '.target_overrides."'${TARGET_NAME}'"."target.bootloader_img" = "tools/mbed-bootloader-'${TARGET_NAME}'.hex"' mbed_app.json | sponge mbed_app.json

echo "---> Copy bootloader to tools dir"
cp /root/Source/${BOOTLOADER_GITHUB_REPO}/BUILD/${TARGET_NAME}/${MBED_OS_COMPILER}/${BOOTLOADER_GITHUB_REPO}.hex tools/mbed-bootloader-${TARGET_NAME}.hex

echo "---> Set storage-selector.filesystem"
jq '."target_overrides"."*"."storage-selector.filesystem" = "LITTLE"' mbed_app.json | sponge mbed_app.json

echo "---> Set storage-selector.storage"
jq '."target_overrides"."*"."storage-selector.storage" = "SPI_FLASH"' mbed_app.json | sponge mbed_app.json

# default is 1GB ifyou don't specify
echo "---> Set client_app.primary_partition_size"
jq '."target_overrides"."'${TARGET_NAME}'"."client_app.primary_partition_size" = 1048576' mbed_app.json | sponge mbed_app.json

echo "---> Disable auto partitioning"
jq '.target_overrides."*"."auto_partition" = 1' mbed_lib.json | sponge mbed_lib.json

# New serial buffer documentation
# https://github.com/ARMmbed/mbed-os/blob/master/targets/TARGET_NORDIC/TARGET_NRF5x/README.md#customization-1
echo "---> Set nordic.uart_0_fifo_size = 1024"
jq '."target_overrides"."'${TARGET_NAME}'"."nordic.uart_0_fifo_size" = 2048' mbed_app.json | sponge mbed_app.json

echo "---> Set nordic.uart_1_fifo_size = 1024"
jq '."target_overrides"."'${TARGET_NAME}'"."nordic.uart_1_fifo_size" = 1024' mbed_app.json | sponge mbed_app.json

echo "---> Set nordic.uart_dma_size = 32"
jq '."target_overrides"."'${TARGET_NAME}'"."nordic.uart_dma_size" = 32' mbed_app.json | sponge mbed_app.json

echo "---> Remove rxbuf from mbed_app.json"
jq 'del(.target_overrides."*"."drivers.uart-serial-rxbuf-size")' mbed_app.json | sponge mbed_app.json

echo "---> Set ${TARGET_NAME} details in mbed_app.json"
jq '."target_overrides"."'${TARGET_NAME}'"."target.OUTPUT_EXT" = "hex"' mbed_app.json | sponge mbed_app.json

echo "---> Set '${TARGET_NAME}' target.macros_add"
jq '."target_overrides"."'${TARGET_NAME}'"."target.macros_add" = ["PAL_INTERNAL_FLASH_SECTION_1_ADDRESS=0xFE000","PAL_INTERNAL_FLASH_SECTION_2_ADDRESS=0xFF000","PAL_INTERNAL_FLASH_SECTION_1_SIZE=0x1000","PAL_INTERNAL_FLASH_SECTION_2_SIZE=0x1000","PAL_INT_FLASH_NUM_SECTIONS=2","PAL_USE_INTERNAL_FLASH=1","PAL_USE_HW_ROT=0","PAL_USE_HW_RTC=0"]' mbed_app.json | sponge mbed_app.json

echo "---> Run mbed update ${MBED_OS_VERSION} on mbed-os"
cd mbed-os && mbed update ${MBED_OS_VERSION} && cd ..

echo "---> Remove MCU_NRF52840.features from mbed_app.json related to PR/7280"
jq '."target_overrides"."'${TARGET_NAME}'"."target.features_remove" = ["CRYPTOCELL310"]' mbed_app.json | sponge mbed_app.json

echo "---> Remove MCU_NRF52840.MBEDTLS_CONFIG_HW_SUPPORT from mbed_app.json related to PR/7280"
# jq '."MCU_NRF52840"."macros" |= map(select(. != "MBEDTLS_CONFIG_HW_SUPPORT"))' mbed-os/targets/targets.json | sponge mbed-os/targets/targets.json
jq '."target_overrides"."'${TARGET_NAME}'"."target.macros_remove" = ["MBEDTLS_CONFIG_HW_SUPPORT"]' mbed_app.json | sponge mbed_app.json

if [ "$EASY_CONNECT_VERSION" ]; then
    echo "---> Run mbed update on easy-connect ${EASY_CONNECT_VERSION}"
    cd easy-connect && mbed update ${EASY_CONNECT_VERSION} && cd ..
fi

if [ "$ESP8266_VERSION" ]; then
    echo "---> Run mbed update on ESP8266 driver ${ESP8266_VERSION}"
    cd easy-connect/esp8266-driver && mbed update ${ESP8266_VERSION} && cd ../..
fi

echo "---> Copy current application mbed_app.json to /root/Share/${EPOCH_TIME}-application-mbed_app.json"
cp mbed_app.json /root/Share/${EPOCH_TIME}-application-mbed_app.json

echo "---> Copy current application mbed_lib.json to /root/Share/${EPOCH_TIME}-application-mbed_lib.json"
cp tools/mbed_lib.json /root/Share/${EPOCH_TIME}-application-mbed_lib.json

echo "---> Compile first mbed client"
mbed compile -m ${TARGET_NAME} -t ${MBED_OS_COMPILER} --profile ${BUILD_PROFILE} >> ${EPOCH_TIME}-mbed-compile-client.log

echo "---> Copy build log to /root/Share/${EPOCH_TIME}-mbed-compile-client.log"
cp ${EPOCH_TIME}-mbed-compile-client.log /root/Share

echo "---> Copy the final binary or hex to the share directory"
cp BUILD/${TARGET_NAME}/${MBED_OS_COMPILER}/mbed-cloud-client-example.hex /root/Share/${COMBINED_IMAGE_NAME}.hex

# Check for an upgrade image name and build a second image
if [ "$UPGRADE_IMAGE_NAME" ]; then
    echo "---> Code change for upgrade image"
    sed -r -i -e 's/static DigitalOut led\(MBED_CONF_APP_LED_PINNAME, LED_OFF\);/static DigitalOut led(MBED_CONF_APP_LED_PINNAME, LED_ON);/' source/platform/mbed-os/common_button_and_led.cpp

    echo "---> Output a bin file for upgrades"
    jq '."target_overrides"."'${TARGET_NAME}'"."target.OUTPUT_EXT" = "bin"' mbed_app.json | sponge mbed_app.json

    echo "---> Copy current update mbed_app.json to /root/Share/${EPOCH_TIME}-update-mbed_app.json"
    cp mbed_app.json /root/Share/${EPOCH_TIME}-update-mbed_app.json

    echo "---> Copy current update mbed_lib.json to /root/Share/${EPOCH_TIME}-update-mbed_lib.json"
    cp tools/mbed_lib.json /root/Share/${EPOCH_TIME}-update-mbed_lib.json

    echo "---> Compile upgrade image"
    mbed compile -m ${TARGET_NAME} -t ${MBED_OS_COMPILER} --profile ${BUILD_PROFILE} >> ${EPOCH_TIME}-mbed-compile-client.log

    echo "---> Copy build log to /root/Share/${EPOCH_TIME}-mbed-compile-client.log"
    cp ${EPOCH_TIME}-mbed-compile-client.log /root/Share

    echo "---> Copy upgrade image to share ${EPOCH_TIME}-upgrade.bin"
    cp BUILD/${TARGET_NAME}/${MBED_OS_COMPILER}/mbed-cloud-client-example_application.bin /root/Share/${EPOCH_TIME}-${UPGRADE_IMAGE_NAME}.bin

    echo "---> Run upgrade campaign using manifest tool"
    echo "cd /root/Download/manifest_tool"
    echo "manifest-tool update device -p /root/Share/${EPOCH_TIME}-${UPGRADE_IMAGE_NAME}.bin -D my_connected_device_id"
fi

echo "---> Keeping the container running with a tail of the build logs"
tail -f /root/epoch_time.txt
