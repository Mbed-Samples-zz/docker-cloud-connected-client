#!/bin/bash

echo "Create epoch time file /root/epoch_time.txt"
date +%s > /root/epoch_time.txt
EPOCH_TIME=$(cat /root/epoch_time.txt)

echo "---> Make Source Download .ssh dirs"
mkdir -p /root/Source /root/Download/manifest_tool /root/.ssh

echo "---> Copy over id_rsa private key, and set permissions"
cp /root/Creds/id_rsa /root/.ssh/id_rsa

echo "---> Create known_hosts"
touch /root/.ssh/known_hosts

echo "---> Add GitHub server key to known_hosts"
ssh-keyscan github.com >> /root/.ssh/known_hosts

echo "---> Create .netrc for cloning private GitHub repos"
echo "machine github.com" > /root/.netrc
echo "login ${GITHUB_USER}" >> /root/.netrc
echo "password ${GITHUB_TOKEN}" >> /root/.netrc

EASY_CONNECT_VERSION=master
ESP8266_VERSION=master

MBED_CLOUD_VERSION=1.4.0
MBED_CLOUD_UPDATE_EPOCH=0
MBED_CLOUD_MANIFEST_TOOL_VERSION=master

APP_BUILD_PROFILE=profiles/debug_size.json
UPGRADE_BUILD_PROFILE=profiles/debug_size.json
BOOTLOADER_BUILD_PROFILE=minimal-printf/profiles/release.json

MBED_OS_VERSION=master
MBED_OS_COMPILER=GCC_ARM

TARGET_NAME=NRF52840_DK

BOOTLOADER_GITHUB_REPO="mbed-bootloader"
BOOTLOADER_VERSION=v3.3.0
CLIENT_GITHUB_REPO="mbed-cloud-client-example"

GITHUB_URI="https://github.com/ARMmbed"

COMBINED_IMAGE_NAME=${EPOCH_TIME}.mbed-os.${TARGET_NAME}.cellular.els61.tcp.ppp
UPGRADE_IMAGE_NAME=${COMBINED_IMAGE_NAME}-update

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
jq '."target_overrides"."'${TARGET_NAME}'"."sotp-section-1-address" = "0xfe000"' mbed_app.json | sponge mbed_app.json
jq '."target_overrides"."'${TARGET_NAME}'"."sotp-section-1-size" = "4096"' mbed_app.json | sponge mbed_app.json
jq '."target_overrides"."'${TARGET_NAME}'"."sotp-section-2-address" = "0xff000"' mbed_app.json | sponge mbed_app.json
jq '."target_overrides"."'${TARGET_NAME}'"."sotp-section-2-size" = "4096"' mbed_app.json | sponge mbed_app.json
jq '."target_overrides"."'${TARGET_NAME}'"."update-client.application-details" = "0x3B000"' mbed_app.json | sponge mbed_app.json
jq '."target_overrides"."'${TARGET_NAME}'"."application-start-address" = "0x3B400"' mbed_app.json | sponge mbed_app.json
jq '."target_overrides"."'${TARGET_NAME}'"."max-application-size" = "DEFAULT_MAX_APPLICATION_SIZE"' mbed_app.json | sponge mbed_app.json
jq '."target_overrides"."'${TARGET_NAME}'"."target.OUTPUT_EXT" = "hex"' mbed_app.json | sponge mbed_app.json

jq '."target_overrides"."'${TARGET_NAME}'"."update-client.storage-address" = "(1024*1024*1)"' mbed_app.json | sponge mbed_app.json
jq '."target_overrides"."'${TARGET_NAME}'"."update-client.storage-size" = "(1024*1024*1)"' mbed_app.json | sponge mbed_app.json
jq '."target_overrides"."'${TARGET_NAME}'"."update-client.storage-locations" = 1' mbed_app.json | sponge mbed_app.json

# note: this is not needed for the client since it calls the driver to get
# this information
echo "---> Set the block/page size on the SOTP region"
jq '."target_overrides"."'${TARGET_NAME}'"."update-client.storage-page" = 1' mbed_app.json | sponge mbed_app.json

echo "---> Remove MCU_NRF52840.features from mbed_app.json related to PR/7280"
jq '."target_overrides"."'${TARGET_NAME}'"."target.features_remove" = ["CRYPTOCELL310"]' mbed_app.json | sponge mbed_app.json

echo "---> Remove MCU_NRF52840.MBEDTLS_CONFIG_HW_SUPPORT from mbed_app.json related to PR/7280"
jq '."target_overrides"."'${TARGET_NAME}'"."target.macros_remove" = ["MBEDTLS_CONFIG_HW_SUPPORT"]' mbed_app.json | sponge mbed_app.json

echo "---> Set '${TARGET_NAME}' target.macros_add"
jq '."target_overrides"."'${TARGET_NAME}'"."target.macros_add" |= . + ["PAL_USE_INTERNAL_FLASH=1","PAL_USE_HW_ROT=0","PAL_USE_HW_RTC=0","PAL_INT_FLASH_NUM_SECTIONS=2"]' mbed_app.json | sponge mbed_app.json

echo "---> Copy current bootloader mbed_app.json to /root/Share/${EPOCH_TIME}-bootloader-mbed_app.json"
cp mbed_app.json /root/Share/${EPOCH_TIME}-bootloader-mbed_app.json

echo "---> Add the spif-driver to use SPI flash"
mbed add spif-driver

echo "---> Include to use SPI flash SPIF driver"
sed -r -i -e 's/#include "SDBlockDevice.h"/#include "SPIFBlockDevice.h"/' source/main.cpp

# Not elegant need to improve
echo "---> Switch bootloader to use SPI flash SPIF driver"
sed -r -i -e 's/SDBlockDevice sd\(MBED_CONF_SD_SPI_MOSI, MBED_CONF_SD_SPI_MISO,/SPIFBlockDevice sd\(MBED_CONF_SPIF_DRIVER_SPI_MOSI, MBED_CONF_SPIF_DRIVER_SPI_MISO,/' source/main.cpp
sed -r -i -e 's/                 MBED_CONF_SD_SPI_CLK,  MBED_CONF_SD_SPI_CS\);/                   MBED_CONF_SPIF_DRIVER_SPI_CLK, MBED_CONF_SPIF_DRIVER_SPI_CS\);/' source/main.cpp

echo "---> Compile mbed bootloader"
mbed compile -m ${TARGET_NAME} -t ${MBED_OS_COMPILER} --profile ${BOOTLOADER_BUILD_PROFILE} >> mbed-compile-bootloader.log

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

echo "---> Clone ${GITHUB_URI}/ciot-example for Gemalto drivers"
git clone ${GITHUB_URI}/ciot-example.git

echo "---> cd /root/Source/${CLIENT_GITHUB_REPO}"
cd /root/Source/${CLIENT_GITHUB_REPO}

echo "---> Run mbed deploy ${MBED_CLOUD_VERSION}"
mbed deploy ${MBED_CLOUD_VERSION}

echo "---> Run mbed update ${MBED_CLOUD_VERSION}"
mbed update ${MBED_CLOUD_VERSION}

echo "---> Copy Gemalto drivers to ${CLIENT_GITHUB_REPO} project"
cp -R /root/Source/ciot-example/source/cellular/targets/GEMALTO mbed-os/features/cellular/framework/targets

echo "---> cp /root/Download/manifest_tool/update_default_resources.c"
cp /root/Download/manifest_tool/update_default_resources.c .

echo "---> Copy mbed_cloud_dev_credentials.c to project"
cp /root/Creds/mbed_cloud_dev_credentials.c .

# https://github.com/ARMmbed/mbed-cloud-client-example/pull/17
echo "---> Get WNC config and save to mbed_app.json"
wget -O mbed_app.json https://raw.githubusercontent.com/jflynn129/mbed-cloud-client-example/aedf5dd07e9dfb6502e803cd4a05e30f2c889a4f/wnc14a2a.json

# https://github.com/Avnet/wnc14a2a-driver/#90928b81747ef4b0fb4fdd94705142175e014b30
echo "---> Set up CELLULAR interface config in mbed_app.json"
jq '.config."network-interface"."value" = "CELLULAR"' mbed_app.json | sponge mbed_app.json

echo "---> Set CELLULAR_DEVICE=GEMALTO_ELS61 '${TARGET_NAME}' target.macros_add"
jq '."target_overrides"."'${TARGET_NAME}'"."target.macros_add" |= . + ["CELLULAR_DEVICE=GEMALTO_ELS61", "MDMRXD=D0", "MDMTXD=D1", "MDMCTS=D2", "MDMRTS=D3"]' mbed_app.json | sponge mbed_app.json

echo "---> Set up cellular options in mbed_app.json"
jq '."config"."sock-type" = "tcp"' mbed_app.json | sponge mbed_app.json

jq '."config"."sim-pin-code"."help" = "SIM PIN code"' mbed_app.json | sponge mbed_app.json
jq '."config"."sim-pin-code"."value" = "\"1234\""' mbed_app.json | sponge mbed_app.json

jq '."config"."apn"."help" = "The APN string to use for this SIM/network, set to 0 if none"' mbed_app.json | sponge mbed_app.json
jq '."config"."apn"."value" = 0' mbed_app.json | sponge mbed_app.json

jq '."config"."username"."help" = "The user name string to use for this APN, set to zero if none"' mbed_app.json | sponge mbed_app.json
jq '."config"."username"."value" = 0' mbed_app.json | sponge mbed_app.json

jq '."config"."password"."help" = "The password string to use for this APN, set to zero if none"' mbed_app.json | sponge mbed_app.json
jq '."config"."password"."value" = 0' mbed_app.json | sponge mbed_app.json

jq '."config"."trace-level"."help" = "Options are TRACE_LEVEL_ERROR,TRACE_LEVEL_WARN,TRACE_LEVEL_INFO,TRACE_LEVEL_DEBUG"' mbed_app.json | sponge mbed_app.json
jq '."config"."trace-level"."value" = "TRACE_LEVEL_DEBUG"' mbed_app.json | sponge mbed_app.json
jq '."config"."trace-level"."macro_name" = "MBED_TRACE_MAX_LEVEL"' mbed_app.json | sponge mbed_app.json

echo "---> Set cellular ${TARGET_NAME} overrides"
jq '."target_overrides"."'${TARGET_NAME}'"."ppp-cell-iface.apn-lookup" = false' mbed_app.json | sponge mbed_app.json
jq '."target_overrides"."'${TARGET_NAME}'"."cellular.use-apn-lookup" = false' mbed_app.json | sponge mbed_app.json
jq '."target_overrides"."'${TARGET_NAME}'"."lwip.ipv4-enabled" = true' mbed_app.json | sponge mbed_app.json
jq '."target_overrides"."'${TARGET_NAME}'"."lwip.ethernet-enabled" = false' mbed_app.json | sponge mbed_app.json
jq '."target_overrides"."'${TARGET_NAME}'"."lwip.ppp-enabled" = true' mbed_app.json | sponge mbed_app.json
jq '."target_overrides"."'${TARGET_NAME}'"."lwip.tcp-enabled" = true' mbed_app.json | sponge mbed_app.json
jq '."target_overrides"."'${TARGET_NAME}'"."cellular.debug-at" = true' mbed_app.json | sponge mbed_app.json

echo "---> Set platform.stdio ${TARGET_NAME} overrides"
jq '."target_overrides"."'${TARGET_NAME}'"."platform.stdio-convert-newlines" = true' mbed_app.json | sponge mbed_app.json
jq '."target_overrides"."'${TARGET_NAME}'"."platform.stdio-baud-rate" = 115200' mbed_app.json | sponge mbed_app.json
jq '."target_overrides"."'${TARGET_NAME}'"."platform.stdio-buffered-serial" = true' mbed_app.json | sponge mbed_app.json
jq '."target_overrides"."'${TARGET_NAME}'"."platform.default-serial-baud-rate" = 115200' mbed_app.json | sponge mbed_app.json

########## SERIAL CONFIG ##########
#
#
echo "---> Enable increase drivers.uart-serial-txbuf-size mbed_app.json"
jq '.target_overrides."*"."drivers.uart-serial-txbuf-size" = 4096' mbed_app.json | sponge mbed_app.json
jq '.target_overrides."*"."drivers.uart-serial-rxbuf-size" = 4096' mbed_app.json | sponge mbed_app.json

# New serial buffer documentation
# https://github.com/ARMmbed/mbed-os/blob/master/targets/TARGET_NORDIC/TARGET_NRF5x/README.md#customization-1
echo "---> Set nordic.uart_0_fifo_size = 2048"
jq '."target_overrides"."'${TARGET_NAME}'"."nordic.uart_0_fifo_size" = 2048' mbed_app.json | sponge mbed_app.json

echo "---> Set nordic.uart_1_fifo_size = 2048"
jq '."target_overrides"."'${TARGET_NAME}'"."nordic.uart_1_fifo_size" = 2048' mbed_app.json | sponge mbed_app.json

echo "---> Set nordic.uart_dma_size = 32"
jq '."target_overrides"."'${TARGET_NAME}'"."nordic.uart_dma_size" = 32' mbed_app.json | sponge mbed_app.json

echo "---> Remove rxbuf from mbed_app.json"
jq 'del(.target_overrides."*"."drivers.uart-serial-rxbuf-size")' mbed_app.json | sponge mbed_app.json
#
#
########## SERIAL CONFIG ##########

echo "---> Enable mbed-trace.enable in mbed_app.json"
jq '.target_overrides."*"."mbed-trace.enable" = null' mbed_app.json | sponge mbed_app.json

echo "---> Change LED to ON"
sed -r -i -e 's/static DigitalOut led\(MBED_CONF_APP_LED_PINNAME, LED_OFF\);/static DigitalOut led(MBED_CONF_APP_LED_PINNAME, LED_ON);/' source/platform/mbed-os/common_button_and_led.cpp

echo "---> Change LED blink to LED1 in mbed_app.json"
jq '.config."led-pinname"."value" = "LED1"' mbed_app.json | sponge mbed_app.json

# New undocumented feature that removes the need to run the combine script
echo "---> Copy managed bootloader automatic application header mbed_lib.json to tools dir"
cp /root/Config/mbed_lib.json tools/

echo "---> Add target.app_offset in mbed_lib.json"
jq '.target_overrides."*"."target.app_offset" = "0x3B400"' tools/mbed_lib.json | sponge tools/mbed_lib.json

echo "---> Add target.header_offset in mbed_lib.json"
jq '.target_overrides."*"."target.header_offset" = "0x3B000"' tools/mbed_lib.json | sponge tools/mbed_lib.json

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

echo "---> Enable auto formatting"
jq '."config"."mcc-no-auto-format"."help" = "If this is null autoformat will occur"' mbed_app.json | sponge mbed_app.json
jq '."config"."mcc-no-auto-format"."value" = null' mbed_app.json | sponge mbed_app.json

echo "---> Set ${TARGET_NAME} details in mbed_app.json"
jq '."target_overrides"."'${TARGET_NAME}'"."target.OUTPUT_EXT" = "hex"' mbed_app.json | sponge mbed_app.json

echo "---> Set '${TARGET_NAME}' target.macros_add"
jq '."target_overrides"."'${TARGET_NAME}'"."target.macros_add" |= . + ["MBEDTLS_USER_CONFIG_FILE=\"mbedTLSConfig_mbedOS.h\"", "PAL_USE_INTERNAL_FLASH=1","PAL_USE_HW_ROT=0","PAL_USE_HW_RTC=0","PAL_INT_FLASH_NUM_SECTIONS=2"]' mbed_app.json | sponge mbed_app.json

echo "---> Run mbed update ${MBED_OS_VERSION} on mbed-os"
cd mbed-os && mbed update ${MBED_OS_VERSION} && cd ..

echo "---> Remove MCU_NRF52840.features from mbed_app.json related to PR/7280"
jq '."target_overrides"."'${TARGET_NAME}'"."target.features_remove" = ["CRYPTOCELL310"]' mbed_app.json | sponge mbed_app.json

echo "---> Remove MCU_NRF52840.MBEDTLS_CONFIG_HW_SUPPORT from mbed_app.json related to PR/7280"
jq '."target_overrides"."'${TARGET_NAME}'"."target.macros_remove" = ["MBEDTLS_CONFIG_HW_SUPPORT"]' mbed_app.json | sponge mbed_app.json

echo "---> Set ${TARGET_NAME} SOTP details in mbed_lib.json"
jq '."target_overrides"."'${TARGET_NAME}'"."sotp-section-1-address" = "0xfe000"' mbed_lib.json | sponge mbed_lib.json
jq '."target_overrides"."'${TARGET_NAME}'"."sotp-section-1-size" = "4096"' mbed_lib.json | sponge mbed_lib.json
jq '."target_overrides"."'${TARGET_NAME}'"."sotp-section-2-address" = "0xff000"' mbed_lib.json | sponge mbed_lib.json
jq '."target_overrides"."'${TARGET_NAME}'"."sotp-section-2-size" = "4096"' mbed_lib.json | sponge mbed_lib.json

jq '."target_overrides"."'${TARGET_NAME}'"."update-client.application-details" = "0x3B000"' mbed_app.json | sponge mbed_app.json
jq '."target_overrides"."'${TARGET_NAME}'"."update-client.storage-address" = "(1024*1024*1)"' mbed_app.json | sponge mbed_app.json
jq '."target_overrides"."'${TARGET_NAME}'"."update-client.storage-size" = "(1024*1024*1)"' mbed_app.json | sponge mbed_app.json
jq '."target_overrides"."'${TARGET_NAME}'"."update-client.storage-locations" = 1' mbed_app.json | sponge mbed_app.json

if [ "$EASY_CONNECT_VERSION" ]; then
    echo "---> Run mbed update on easy-connect ${EASY_CONNECT_VERSION}"
    cd easy-connect && mbed update ${EASY_CONNECT_VERSION} && cd ..
fi

echo "---> Copy current application mbed_app.json to /root/Share/${EPOCH_TIME}-application-mbed_app.json"
cp mbed_app.json /root/Share/${EPOCH_TIME}-application-mbed_app.json

echo "---> Copy current application mbed_lib.json to /root/Share/${EPOCH_TIME}-application-mbed_lib.json"
cp mbed_lib.json /root/Share/${EPOCH_TIME}-application-mbed_lib.json

echo "---> Copy current application tools/mbed_lib.json to /root/Share/${EPOCH_TIME}-application-tools-mbed_lib.json"
cp tools/mbed_lib.json /root/Share/${EPOCH_TIME}-application-tools-mbed_lib.json

echo "---> Compile first mbed client"
mbed compile -m ${TARGET_NAME} -t ${MBED_OS_COMPILER} --profile ${APP_BUILD_PROFILE} >> ${EPOCH_TIME}-mbed-compile-client.log

echo "---> Copy build log to /root/Share/${EPOCH_TIME}-mbed-compile-client.log"
cp ${EPOCH_TIME}-mbed-compile-client.log /root/Share

echo "---> Copy the final binary or hex to the share directory"
cp BUILD/${TARGET_NAME}/${MBED_OS_COMPILER}/mbed-cloud-client-example.hex /root/Share/${COMBINED_IMAGE_NAME}.hex

# Check for an upgrade image name and build a second image
if [ "$UPGRADE_IMAGE_NAME" ]; then
    echo "---> Disable auto formatting"
    jq '."config"."mcc-no-auto-format"."help" = "If this is null autoformat will occur"' mbed_app.json | sponge mbed_app.json
    jq '."config"."mcc-no-auto-format"."value" = 1' mbed_app.json | sponge mbed_app.json

    echo "---> Change LED blink to LED2 in mbed_app.json"
    jq '.config."led-pinname"."value" = "LED2"' mbed_app.json | sponge mbed_app.json

    echo "---> Output a bin file for upgrades"
    jq '."target_overrides"."'${TARGET_NAME}'"."target.OUTPUT_EXT" = "bin"' mbed_app.json | sponge mbed_app.json

    echo "---> Copy current update mbed_app.json to /root/Share/${EPOCH_TIME}-update-mbed_app.json"
    cp mbed_app.json /root/Share/${EPOCH_TIME}-update-mbed_app.json

    echo "---> Compile upgrade image"
    mbed compile -m ${TARGET_NAME} -t ${MBED_OS_COMPILER} --profile ${UPGRADE_BUILD_PROFILE} >> ${EPOCH_TIME}-mbed-compile-client.log

    echo "---> Copy build log to /root/Share/${EPOCH_TIME}-mbed-compile-client.log"
    cp ${EPOCH_TIME}-mbed-compile-client.log /root/Share

    echo "---> Copy upgrade image to share ${UPGRADE_IMAGE_NAME}.bin"
    cp BUILD/${TARGET_NAME}/${MBED_OS_COMPILER}/mbed-cloud-client-example_application.bin /root/Share/${UPGRADE_IMAGE_NAME}.bin

    echo "---> Run upgrade campaign using manifest tool"
    echo "cd /root/Download/manifest_tool"
    echo "manifest-tool update device -p /root/Share/${UPGRADE_IMAGE_NAME}.bin -D my_connected_device_id"
fi

echo "---> Copy manifest_tool ${BOOTLOADER_GITHUB_REPO} ${CLIENT_GITHUB_REPO} builds to /root/Share/${EPOCH_TIME}-Source"
cp -R /root/Source /root/Share/${EPOCH_TIME}-Source
cp -R /root/Download/manifest_tool /root/Share/${EPOCH_TIME}-Source

echo "---> Keeping the container running with a tail of the build logs"
tail -f /root/epoch_time.txt
