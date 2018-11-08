#!/bin/bash

echo "Create epoch time file ~/epoch_time.txt"
date +%s > ~/epoch_time.txt
EPOCH_TIME=$(cat ~/epoch_time.txt)

BOOTLOADER_BUILD_PROFILE=minimal-printf/profiles/release.json

MBED_OS_COMPILER=GCC_ARM

TARGET_NAME=NRF52840_DK

EXTRA_BUILD_OPTIONS="--build BUILD/${TARGET_NAME}/${MBED_OS_COMPILER}"

BOOTLOADER_GITHUB_REPO="mbed-bootloader"
BOOTLOADER_VERSION=v3.5.0

GITHUB_URI="https://github.com/ARMmbed"

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

# 29C3C
# Layout

# Edit struct
# 0x06, 0x10, 0x32, 0xfd, 0x76, 0x04, 0xe7, 0x97, 0x85, 0x15
# 0x2e, 0x00, 0x17, 0x5d, 0xcf, 0xc1, 0x5d, 0xfe, 0x06, 0xcb
# mbed_bootloader_info.h
sed -r -i -e 's/    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, \\/    0x06, 0x10, 0x32, 0xfd, 0x76, 0x04, 0xe7, 0x97, 0x85, 0x15, \\/g' mbed_bootloader_info.h
sed -r -i -e 's/    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00  \\/    0x2e, 0x00, 0x17, 0x5d, 0xcf, 0xc1, 0x5d, 0xfe, 0x06, 0xcb\\/g' mbed_bootloader_info.h



echo "---> Compile mbed bootloader"
mbed compile -m ${TARGET_NAME} -t ${MBED_OS_COMPILER} --profile ${BOOTLOADER_BUILD_PROFILE} ${EXTRA_BUILD_OPTIONS} >> mbed-compile-bootloader.log

echo "---> Copy bootloader to /root/Share/${EPOCH_TIME}-mbed-bootloader-nrf52840_dk-spif-block_device-nvstore-v3_5_0.hex"
cp BUILD/${TARGET_NAME}/${MBED_OS_COMPILER}/${BOOTLOADER_GITHUB_REPO}.hex /root/Share/${EPOCH_TIME}-mbed-bootloader-nrf52840_dk-spif-block_device-nvstore-v3_5_0.hex

echo "---> Copy builds to /root/Share/${EPOCH_TIME}-Source"
cp -R /root/Source /root/Share/${EPOCH_TIME}-Source

echo "---> Keeping the container running with a tail of the build logs"
tail -f ~/epoch_time.txt
