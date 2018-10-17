#!/bin/bash

echo "Create epoch time file ~/epoch_time.txt"
date +%s > ~/epoch_time.txt
EPOCH_TIME=$(cat ~/epoch_time.txt)

ESP8266_VERSION=master

DEVICE_MANAGEMENT_CLIENT_VERSION=2.0.1.1

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

COMBINED_IMAGE_NAME=${EPOCH_TIME}.mbed-os.${TARGET_NAME}.wifi.esp8266
# UPGRADE_IMAGE_NAME=${COMBINED_IMAGE_NAME}-update

if [ -z "$WIFI_SSID" ]; then
    echo "---> Define WIFI_SSID in your .env file"
    echo "--->   e.g. WIFI_SSID='my_wifi_ssid'"
    exit
else
    echo "---> Use WIFI_SSID from .env '${WIFI_SSID}'"
fi

echo "---> Make ~/Source dir"
mkdir -p ~/Source

######################## BOOTLOADER #########################

echo "---> cd ~/Source"
cd ~/Source

echo "---> Clone ${GITHUB_URI}/${BOOTLOADER_GITHUB_REPO}"
git clone ${GITHUB_URI}/${BOOTLOADER_GITHUB_REPO}.git

echo "---> cd ~/Source/${BOOTLOADER_GITHUB_REPO}"
cd ~/Source/${BOOTLOADER_GITHUB_REPO}

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

echo "---> Modify .mbedignore add storage dir for >= mbed-os 5.10"
sed -i '/mbed-os\/features\/storage\/\*/d' .mbedignore

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

echo "---> Copy current bootloader mbed_app.json to ~/Share/${EPOCH_TIME}-bootloader-mbed_app.json"
cp mbed_app.json ~/Share/${EPOCH_TIME}-bootloader-mbed_app.json

# note commit https://github.com/ARMmbed/spif-driver/commit/ac01c514ebd32cc2fd0c01eb2a5455e11589e36e
# broke the build so we're going back to a hash.  The code basically say if using mbed 5.10
# do #error and use the one now in mbed-os
# https://jira.arm.com/browse/MBEDOSTEST-167
# The issue is the one in mbed-os does not build properly you must now do
# #include "mbed-os/components/storage/blockdevice/COMPONENT_SPIF/SPIFBlockDevice.h
# and the config symbols are not found
echo "---> Add the spif-driver to use SPI flash"
mbed add https://github.com/ARMmbed/spif-driver/#39a918e5d0bfc7b5e6ab96228cc68e00cc93f9a2

echo "---> Include to use SPI flash SPIF driver"
sed -r -i -e 's/#include "SDBlockDevice.h"/#include "SPIFBlockDevice.h"/' source/main.cpp

# Not elegant need to improve
echo "---> Switch bootloader to use SPI flash SPIF driver"
sed -r -i -e 's/SDBlockDevice sd\(MBED_CONF_SD_SPI_MOSI, MBED_CONF_SD_SPI_MISO,/SPIFBlockDevice sd\(MBED_CONF_SPIF_DRIVER_SPI_MOSI, MBED_CONF_SPIF_DRIVER_SPI_MISO,/' source/main.cpp
sed -r -i -e 's/                 MBED_CONF_SD_SPI_CLK,  MBED_CONF_SD_SPI_CS\);/                   MBED_CONF_SPIF_DRIVER_SPI_CLK, MBED_CONF_SPIF_DRIVER_SPI_CS\);/' source/main.cpp

echo "---> Compile mbed bootloader"
mbed compile -m ${TARGET_NAME} -t ${MBED_OS_COMPILER} --profile ${BOOTLOADER_BUILD_PROFILE} ${EXTRA_BUILD_OPTIONS} >> mbed-compile-bootloader.log

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
echo "mbed-os/components/wifi/esp8266-driver/*" >> .mbedignore
echo "BUILD/*" >> .mbedignore

echo "---> Copy mbed_cloud_dev_credentials.c to project"
cp ~/Creds/mbed_cloud_dev_credentials.c .

echo "---> Copy wifi mbed_app.json config"
cp configs/wifi_esp8266_v4.json mbed_app.json

echo "---> Enable mbed-trace.enable in mbed_app.json"
jq '.target_overrides."*"."mbed-trace.enable" = null' mbed_app.json | sponge mbed_app.json

echo "---> Change LED to ON"
sed -r -i -e 's/static DigitalOut led\(MBED_CONF_APP_LED_PINNAME, LED_OFF\);/static DigitalOut led(MBED_CONF_APP_LED_PINNAME, LED_ON);/' source/platform/mbed-os/mcc_common_button_and_led.cpp

echo "---> Adding wifi interface in mbed_app.json"
jq '."target_overrides"."'${TARGET_NAME}'"."target.network-default-interface-type" = "WIFI"' mbed_app.json | sponge mbed_app.json

echo "---> Set wifi SSID in config"
jq '.target_overrides."NRF52840_DK"."nsapi.default-wifi-ssid" = "\"'"${WIFI_SSID}"'\""' mbed_app.json | sponge mbed_app.json

echo "---> Set wifi password in config"
jq '.target_overrides."NRF52840_DK"."nsapi.default-wifi-password" = "\"'"${WIFI_PASS}"'\""' mbed_app.json | sponge mbed_app.json

echo "---> Set ESP8266 RTS/CTS hwardware flow control in config"
jq '.target_overrides."NRF52840_DK"."esp8266.rts" = "NC"' mbed_app.json | sponge mbed_app.json
jq '.target_overrides."NRF52840_DK"."esp8266.cts" = "NC"' mbed_app.json | sponge mbed_app.json

echo "---> Change LED blink to LED1 in mbed_app.json"
jq '.config."led-pinname"."value" = "LED1"' mbed_app.json | sponge mbed_app.json

echo "---> Add target.app_offset in mbed_app.json"
jq '."target_overrides"."'${TARGET_NAME}'"."target.app_offset" = "0x3B400"' mbed_app.json | sponge mbed_app.json

echo "---> Add target.header_offset in mbed_app.json"
jq '."target_overrides"."'${TARGET_NAME}'"."target.header_offset" = "0x3B000"' mbed_app.json | sponge mbed_app.json

echo "---> Add ${TARGET_NAME}.target.bootloader_img in mbed_app.json"
jq '.target_overrides."'${TARGET_NAME}'"."target.bootloader_img" = "mbed-os/tools/bootloaders/mbed-bootloader-'${TARGET_NAME}'.hex"' mbed_app.json | sponge mbed_app.json

echo "---> Copy bootloader to tools dir"
cp ~/Source/${BOOTLOADER_GITHUB_REPO}/BUILD/${TARGET_NAME}/${MBED_OS_COMPILER}/${BOOTLOADER_GITHUB_REPO}.hex mbed-os/tools/bootloaders/mbed-bootloader-${TARGET_NAME}.hex

# Note you implicitly get LITTLEFS with recent code changes
# https://github.com/ARMmbed/mbed-os/blob/master/features/storage/system_storage/SystemStorage.cpp#L83
echo "---> Set SPIF storage type"
jq '."target_overrides"."'${TARGET_NAME}'"."target.components_add" = ["SPIF"]' mbed_app.json | sponge mbed_app.json

echo "---> Remove SD storage type"
jq '.target_overrides."*"."target.components_add" |= . - ["SD"]' mbed_app.json | sponge mbed_app.json

# default is 1GB ifyou don't specify
echo "---> Set client_app.primary_partition_size"
jq '."target_overrides"."'${TARGET_NAME}'"."client_app.primary_partition_size" = 1048576' mbed_app.json | sponge mbed_app.json

echo "---> Disable auto partitioning"
jq '.target_overrides."*"."auto_partition" = 1' mbed_lib.json | sponge mbed_lib.json

echo "---> Enable auto formatting"
jq '."config"."mcc-no-auto-format"."help" = "If this is null autoformat will occur"' mbed_app.json | sponge mbed_app.json
jq '."config"."mcc-no-auto-format"."value" = null' mbed_app.json | sponge mbed_app.json

# New serial buffer documentation
# https://github.com/ARMmbed/mbed-os/blob/master/targets/TARGET_NORDIC/TARGET_NRF5x/README.md#customization-1
# echo "---> Set nordic.uart_0_fifo_size = 2048"
# jq '."target_overrides"."'${TARGET_NAME}'"."nordic.uart_0_fifo_size" = 2048' mbed_app.json | sponge mbed_app.json

# echo "---> Set nordic.uart_1_fifo_size = 1024"
# jq '."target_overrides"."'${TARGET_NAME}'"."nordic.uart_1_fifo_size" = 1024' mbed_app.json | sponge mbed_app.json

echo "---> Set nordic.uart_dma_size = 32"
jq '."target_overrides"."'${TARGET_NAME}'"."nordic.uart_dma_size" = 32' mbed_app.json | sponge mbed_app.json

echo "---> Remove rxbuf from mbed_app.json"
jq 'del(.target_overrides."*"."drivers.uart-serial-rxbuf-size")' mbed_app.json | sponge mbed_app.json

echo "---> Set ${TARGET_NAME} details in mbed_app.json"
jq '."target_overrides"."'${TARGET_NAME}'"."target.OUTPUT_EXT" = "hex"' mbed_app.json | sponge mbed_app.json

# echo "---> Set '${TARGET_NAME}' target.macros_add"
# jq '."target_overrides"."'${TARGET_NAME}'"."target.macros_add" |= . + ["PAL_USE_INTERNAL_FLASH=1","PAL_USE_HW_ROT=0","PAL_USE_HW_RTC=0","PAL_INT_FLASH_NUM_SECTIONS=2"]' mbed_app.json | sponge mbed_app.json

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

if [ "$ESP8266_VERSION" ]; then
    echo "---> Add ESP8266 driver ${ESP8266_VERSION}"
    mbed add https://github.com/ARMmbed/esp8266-driver

    echo "---> Update ESP8266 driver to ${ESP8266_VERSION}"
    cd esp8266-driver && mbed update ${ESP8266_VERSION} && cd ..
fi

echo "---> Copy current application mbed_app.json to ~/Share/${EPOCH_TIME}-application-mbed_app.json"
cp mbed_app.json ~/Share/${EPOCH_TIME}-application-mbed_app.json

echo "---> Copy current application mbed_lib.json to ~/Share/${EPOCH_TIME}-application-mbed_lib.json"
cp mbed_lib.json ~/Share/${EPOCH_TIME}-application-mbed_lib.json

echo "---> Compile first mbed client"
mbed compile -m ${TARGET_NAME} -t ${MBED_OS_COMPILER} --profile ${APP_BUILD_PROFILE} ${EXTRA_BUILD_OPTIONS} >> ${EPOCH_TIME}-mbed-compile-client.log

echo "---> Copy build log to ~/Share/${EPOCH_TIME}-mbed-compile-client.log"
cp ${EPOCH_TIME}-mbed-compile-client.log ~/Share

echo "---> Copy the final binary or hex to the share directory"
cp BUILD/${TARGET_NAME}/${MBED_OS_COMPILER}/mbed-cloud-client-example.hex ~/Share/${COMBINED_IMAGE_NAME}.hex

# Check for an upgrade image name and build a second image
if [ "$UPGRADE_IMAGE_NAME" ]; then
    echo "---> Disable auto formatting"
    jq '."config"."mcc-no-auto-format"."help" = "If this is null autoformat will occur"' mbed_app.json | sponge mbed_app.json
    jq '."config"."mcc-no-auto-format"."value" = 1' mbed_app.json | sponge mbed_app.json

    echo "---> Change LED blink to LED2 in mbed_app.json"
    jq '.config."led-pinname"."value" = "LED2"' mbed_app.json | sponge mbed_app.json

    echo "---> Output a bin file for upgrades"
    jq '."target_overrides"."'${TARGET_NAME}'"."target.OUTPUT_EXT" = "bin"' mbed_app.json | sponge mbed_app.json

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
