#!/bin/bash

echo "Create epoch time file /root/epoch_time.txt"
date +%s > /root/epoch_time.txt
EPOCH_TIME=$(cat /root/epoch_time.txt)

ESP8266_VERSION=master

DEVICE_MANAGEMENT_CLIENT_VERSION=2.0.0
MBED_CLOUD_UPDATE_EPOCH=0

APP_BUILD_PROFILE=profiles/debug_size.json
UPGRADE_BUILD_PROFILE=profiles/debug_size.json
BOOTLOADER_BUILD_PROFILE=minimal-printf/profiles/release.json

MBED_OS_VERSION=mbed-os-5.10
MBED_OS_COMPILER=GCC_ARM

TARGET_NAME=NRF52840_DK

EXTRA_BUILD_OPTIONS="--build BUILD/${TARGET_NAME}/${MBED_OS_COMPILER}"

BOOTLOADER_GITHUB_REPO="mbed-bootloader"
BOOTLOADER_VERSION=v3.3.0
CLIENT_GITHUB_REPO="mbed-cloud-client-example"

GITHUB_URI="https://github.com/ARMmbed"

COMBINED_IMAGE_NAME=${EPOCH_TIME}.mbed-os.${TARGET_NAME}.cellular.wnc14a2a
UPGRADE_IMAGE_NAME=${COMBINED_IMAGE_NAME}-update

echo "---> Make Source dirs"
mkdir -p /root/Source

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
echo "mbed-os/features/nfc/*" >> .mbedignore
echo "mbed-os/components/wifi/esp8266-driver/*" >> .mbedignore
echo "BUILD/*" >> .mbedignore

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

######################### APPLICATION #########################

echo "---> cd /root/Source"
cd /root/Source

echo "---> Clone ${GITHUB_URI}/${CLIENT_GITHUB_REPO}"
git clone ${GITHUB_URI}/${CLIENT_GITHUB_REPO}.git

echo "---> cd /root/Source/${CLIENT_GITHUB_REPO}"
cd /root/Source/${CLIENT_GITHUB_REPO}

# echo "---> Run mbed config with APIKEY"
mbed config -G CLOUD_SDK_API_KEY ${MBED_CLOUD_API_KEY}
mbed device-management init -d "mbed.quickstart.company" --model-name "qs v1" --force -q

echo "---> Run mbed deploy ${DEVICE_MANAGEMENT_CLIENT_VERSION}"
mbed deploy ${DEVICE_MANAGEMENT_CLIENT_VERSION}

echo "---> Run mbed update ${DEVICE_MANAGEMENT_CLIENT_VERSION}"
mbed update ${DEVICE_MANAGEMENT_CLIENT_VERSION}

echo "---> Copy mbed_cloud_dev_credentials.c to project"
cp /root/Creds/mbed_cloud_dev_credentials.c .

echo "---> Modify .mbedignore and take out features causing compile errors"
echo "mbed-os/components/802.15.4_RF/*" >> .mbedignore
echo "mbed-os/components/wifi/esp8266-driver/*" >> .mbedignore
echo "BUILD/*" >> .mbedignore

# https://github.com/ARMmbed/mbed-cloud-client-example/pull/17
echo "---> Get WNC config and save to mbed_app.json"
wget -O mbed_app.json https://raw.githubusercontent.com/jflynn129/mbed-cloud-client-example/aedf5dd07e9dfb6502e803cd4a05e30f2c889a4f/wnc14a2a.json

# https://github.com/Avnet/wnc14a2a-driver/#90928b81747ef4b0fb4fdd94705142175e014b30
echo "---> Set up WNC config in mbed_app.json"
jq '.config."network-interface"."value" = "CELLULAR_WNC14A2A"' mbed_app.json | sponge mbed_app.json

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

echo "---> Set up WNC debug in mbed_app.json"
jq '.config."wnc_debug"."value" = 0' mbed_app.json | sponge mbed_app.json
jq '.config."wnc_debug_setting"."value" = "0x0c"' mbed_app.json | sponge mbed_app.json

echo "---> Enable mbed-trace.enable in mbed_app.json"
jq '.target_overrides."*"."mbed-trace.enable" = null' mbed_app.json | sponge mbed_app.json

echo "---> Change LED to ON"
sed -r -i -e 's/static DigitalOut led\(MBED_CONF_APP_LED_PINNAME, LED_OFF\);/static DigitalOut led(MBED_CONF_APP_LED_PINNAME, LED_ON);/' source/platform/mbed-os/mcc_common_button_and_led.cpp

echo "---> Change LED blink to LED1 in mbed_app.json"
jq '.config."led-pinname"."value" = "LED1"' mbed_app.json | sponge mbed_app.json

# New undocumented feature that removes the need to run the combine script
echo "---> Copy managed bootloader automatic application header mbed_lib.json to tools dir"
cp /root/Config/mbed_lib.json tools/

echo "---> Add target.app_offset in mbed_app.json"
jq '."target_overrides"."'${TARGET_NAME}'"."target.app_offset" = "0x3B400"' mbed_app.json | sponge mbed_app.json

echo "---> Add target.header_offset in mbed_app.json"
jq '."target_overrides"."'${TARGET_NAME}'"."target.header_offset" = "0x3B000"' mbed_app.json | sponge mbed_app.json

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

echo "---> Copy current application mbed_app.json to /root/Share/${EPOCH_TIME}-application-mbed_app.json"
cp mbed_app.json /root/Share/${EPOCH_TIME}-application-mbed_app.json

echo "---> Copy current application mbed_lib.json to /root/Share/${EPOCH_TIME}-application-mbed_lib.json"
cp mbed_lib.json /root/Share/${EPOCH_TIME}-application-mbed_lib.json

echo "---> Copy current application tools/mbed_lib.json to /root/Share/${EPOCH_TIME}-application-tools-mbed_lib.json"
cp tools/mbed_lib.json /root/Share/${EPOCH_TIME}-application-tools-mbed_lib.json

echo "---> Compile first mbed client"
mbed compile -m ${TARGET_NAME} -t ${MBED_OS_COMPILER} --profile ${APP_BUILD_PROFILE} ${EXTRA_BUILD_OPTIONS} >> ${EPOCH_TIME}-mbed-compile-client.log

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
    mbed compile -m ${TARGET_NAME} -t ${MBED_OS_COMPILER} --profile ${UPGRADE_BUILD_PROFILE} ${EXTRA_BUILD_OPTIONS} >> ${EPOCH_TIME}-mbed-compile-client.log

    echo "---> Copy build log to /root/Share/${EPOCH_TIME}-mbed-compile-client.log"
    cp ${EPOCH_TIME}-mbed-compile-client.log /root/Share

    echo "---> Copy upgrade image to share ${UPGRADE_IMAGE_NAME}.bin"
    cp BUILD/${TARGET_NAME}/${MBED_OS_COMPILER}/mbed-cloud-client-example_application.bin /root/Share/${UPGRADE_IMAGE_NAME}.bin

    echo "---> Run upgrade campaign using mbed device-management tool"
    echo "mbed device-management update device -p ~/Share/${UPGRADE_IMAGE_NAME}.bin -D my_connected_device_id"
fi

echo "---> Copy ${BOOTLOADER_GITHUB_REPO} ${CLIENT_GITHUB_REPO} builds to /root/Share/${EPOCH_TIME}-Source"
cp -R /root/Source /root/Share/${EPOCH_TIME}-Source

echo "---> Keeping the container running with a tail of the build logs"
tail -f /root/epoch_time.txt
