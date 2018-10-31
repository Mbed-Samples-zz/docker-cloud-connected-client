#!/bin/bash

echo "Create epoch time file ~/epoch_time.txt"
date +%s > ~/epoch_time.txt
EPOCH_TIME=$(cat ~/epoch_time.txt)

ESP8266_VERSION=master

DEVICE_MANAGEMENT_CLIENT_VERSION=2.0.1.1

APP_BUILD_PROFILE=profiles/size.json

MBED_OS_VERSION=master
MBED_OS_COMPILER=GCC_ARM

TARGET_NAME=NRF52840_DK

EXTRA_BUILD_OPTIONS="--build BUILD/${TARGET_NAME}/${MBED_OS_COMPILER}"

CLIENT_GITHUB_REPO="mbed-cloud-client-example"

GITHUB_URI="https://github.com/ARMmbed"

COMBINED_IMAGE_NAME=${EPOCH_TIME}.mbed-os.${TARGET_NAME}.wifi.esp8266.prebuilt.bootloader

if [ -z "$WIFI_SSID" ]; then
    echo "---> Define WIFI_SSID in your .env file"
    echo "--->   e.g. WIFI_SSID='my_wifi_ssid'"
    exit
else
    echo "---> Use WIFI_SSID from .env '${WIFI_SSID}'"
fi

echo "---> Make ~/Source dir"
mkdir -p ~/Source ~/.ssh

echo "---> Create .netrc for cloning private GitHub repos"
echo "machine github.com" > /root/.netrc
echo "login ${GITHUB_USER}" >> /root/.netrc
echo "password ${GITHUB_TOKEN}" >> /root/.netrc

echo "---> Copy over id_rsa private key, and set permissions"
cp /root/Creds/id_rsa /root/.ssh/id_rsa

echo "---> Create known_hosts"
touch /root/.ssh/known_hosts

echo "---> Add GitHub server key to known_hosts"
ssh-keyscan github.com >> /root/.ssh/known_hosts

######################## BOOTLOADER #########################
BOOTLOADER_GITHUB_REPO="mbed-bootloader"
BOOTLOADER_VERSION=v3.5.0
BOOTLOADER_BUILD_PROFILE=minimal-printf/profiles/release.json

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

echo "---> Modify .mbedignore adding BUILD/* dir"
echo "BUILD/*" >> .mbedignore

echo "---> Copy current bootloader mbed_app.json to ~/Share/${EPOCH_TIME}-bootloader-mbed_app.json"
cp mbed_app.json ~/Share/${EPOCH_TIME}-bootloader-mbed_app.json

# note commit https://github.com/ARMmbed/spif-driver/commit/ac01c514ebd32cc2fd0c01eb2a5455e11589e36e
# broke the build so we're going back to a hash.  The code basically says if using mbed 5.10
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

echo "---> Clone dlfryar/mbed-cloud-client-example-internal for configs"
git clone https://github.com/dlfryar/mbed-cloud-client-example-internal && cd mbed-cloud-client-example-internal && git checkout NRF52840_DK_config && cd ..

echo "---> cd ~/Source/${CLIENT_GITHUB_REPO}"
cd ~/Source/${CLIENT_GITHUB_REPO}

echo "---> Run mbed deploy ${DEVICE_MANAGEMENT_CLIENT_VERSION}"
mbed deploy ${DEVICE_MANAGEMENT_CLIENT_VERSION}

# echo "---> Run mbed config with APIKEY"
mbed config -G CLOUD_SDK_API_KEY ${MBED_CLOUD_API_KEY}
mbed device-management init -d "mbed.quickstart.company" --model-name "qs v1" --force -q

echo "---> Run mbed update ${DEVICE_MANAGEMENT_CLIENT_VERSION}"
mbed update ${DEVICE_MANAGEMENT_CLIENT_VERSION}

echo "---> Modify .mbedignore and take out features causing compile errors"
echo "mbed-os/components/802.15.4_RF/*" >> .mbedignore
echo "mbed-os/components/wifi/esp8266-driver/*" >> .mbedignore
echo "BUILD/*" >> .mbedignore

echo "---> Copy mbed_cloud_dev_credentials.c to project"
cp ~/Creds/mbed_cloud_dev_credentials.c .

echo "---> Copy wifi mbed_app.json config"
cp /root/Source/mbed-cloud-client-example-internal/configs/wifi_esp8266_v4.json mbed_app.json

echo "---> Change LED to ON"
sed -r -i -e 's/static DigitalOut led\(MBED_CONF_APP_LED_PINNAME, LED_OFF\);/static DigitalOut led(MBED_CONF_APP_LED_PINNAME, LED_ON);/' source/platform/mbed-os/mcc_common_button_and_led.cpp

echo "---> Set wifi SSID in config"
jq -S '.target_overrides."NRF52840_DK"."nsapi.default-wifi-ssid" = "\"'"${WIFI_SSID}"'\""' mbed_app.json | sponge mbed_app.json

echo "---> Set wifi password in config"
jq -S '.target_overrides."NRF52840_DK"."nsapi.default-wifi-password" = "\"'"${WIFI_PASS}"'\""' mbed_app.json | sponge mbed_app.json

echo "---> Delete target.app_offset in mbed_app.json"
jq 'del(."target_overrides"."'${TARGET_NAME}'"."target.app_offset")' mbed_app.json | sponge mbed_app.json

echo "---> Delete target.bootloader_img in mbed_app.json"
jq 'del(."target_overrides"."'${TARGET_NAME}'"."target.bootloader_img")' mbed_app.json | sponge mbed_app.json

echo "---> Disable auto partitioning"
jq -S '.target_overrides."*"."auto_partition" = 1' mbed_lib.json | sponge mbed_lib.json

echo "---> Zero out rxbuf from mbed_app.json"
jq -S '.target_overrides."'${TARGET_NAME}'"."drivers.uart-serial-rxbuf-size" = 0' mbed_app.json | sponge mbed_app.json

echo "---> Set ${TARGET_NAME} details in mbed_app.json"
jq -S '."target_overrides"."'${TARGET_NAME}'"."target.OUTPUT_EXT" = "hex"' mbed_app.json | sponge mbed_app.json

echo "---> Update event thread stack size for esp in mbed_app.json"
jq -S '."target_overrides"."'${TARGET_NAME}'"."events.shared-stacksize" = 1536' mbed_app.json | sponge mbed_app.json

echo "---> Add ${TARGET_NAME}.target.bootloader_img in mbed_app.json"
jq -S '.target_overrides."'${TARGET_NAME}'"."target.bootloader_img" = "mbed-os/tools/bootloaders/mbed-bootloader-'${TARGET_NAME}'.hex"' mbed_app.json | sponge mbed_app.json

echo "---> Add target.app_offset in mbed_app.json"
jq '."target_overrides"."'${TARGET_NAME}'"."target.app_offset" = "0x3B400"' mbed_app.json | sponge mbed_app.json

echo "---> Run mbed update ${MBED_OS_VERSION} on mbed-os"
cd mbed-os && mbed update ${MBED_OS_VERSION} && cd ..

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

echo "---> Copy bootloader to tools dir"
cp ~/Source/${BOOTLOADER_GITHUB_REPO}/BUILD/${TARGET_NAME}/${MBED_OS_COMPILER}/${BOOTLOADER_GITHUB_REPO}.hex mbed-os/tools/bootloaders/mbed-bootloader-${TARGET_NAME}.hex

# echo "---> Copy bootloader to tools dir"
# cp /root/Config/mbed-bootloader-spif-nvstore-v3_5_0.hex mbed-os/tools/bootloaders/mbed-bootloader-${TARGET_NAME}.hex

echo "---> Update main thread stack sizes"
jq -S '."config"."main-stack-size"."help" = "Adjust the stack size for the main thread"' mbed_app.json | sponge mbed_app.json
jq -S '."config"."main-stack-size"."value" = 6000' mbed_app.json | sponge mbed_app.json

echo "---> Update user thread stack sizes"
jq -S '."config"."thread-stack-size"."help" = "Adjust the stack size for the user threads"' mbed_app.json | sponge mbed_app.json
jq -S '."config"."thread-stack-size"."value" = 2000' mbed_app.json | sponge mbed_app.json

echo "---> Compile first mbed client"
mbed compile -m ${TARGET_NAME} -t ${MBED_OS_COMPILER} --profile ${APP_BUILD_PROFILE} ${EXTRA_BUILD_OPTIONS} >> ${EPOCH_TIME}-mbed-compile-client.log

echo "---> Copy build log to ~/Share/${EPOCH_TIME}-mbed-compile-client.log"
cp ${EPOCH_TIME}-mbed-compile-client.log ~/Share

echo "---> Copy the final binary or hex to the share directory"
cp BUILD/${TARGET_NAME}/${MBED_OS_COMPILER}/mbed-cloud-client-example.hex ~/Share/${COMBINED_IMAGE_NAME}.hex

echo "---> Copy builds to /root/Share/${EPOCH_TIME}-Source"
cp -R /root/Source /root/Share/${EPOCH_TIME}-Source

echo "---> Keeping the container running with a tail of the build logs"
tail -f ~/epoch_time.txt
