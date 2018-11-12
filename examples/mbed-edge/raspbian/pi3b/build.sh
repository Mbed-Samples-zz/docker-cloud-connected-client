#!/bin/bash

echo "Create epoch time file ~/epoch_time.txt"
date +%s > ~/epoch_time.txt
EPOCH_TIME=$(cat ~/epoch_time.txt)

echo "---> Make .ssh Source Download dirs"
mkdir -p ~/.ssh ~/Source

echo "---> Copy over id_rsa private key, and set permissions"
cp ~/Creds/id_rsa ~/.ssh/id_rsa

echo "---> Create known_hosts"
touch ~/.ssh/known_hosts

echo "---> Add GitHub server key to known_hosts"
ssh-keyscan github.com >> ~/.ssh/known_hosts

echo "---> Create .netrc for cloning private GitHub repos"
echo "machine github.com" > ~/.netrc
echo "login ${GITHUB_USER}" >> ~/.netrc
echo "password ${GITHUB_TOKEN}" >> ~/.netrc

echo "---> Clone mbed-edge"
git clone git@github.com:armmbed/mbed-edge.git && cd mbed-edge

echo "---> Clone BLE protocol translator"
git clone git@github.com:armmbed/edge-ble-protocol-translator.git mept-ble

echo "---> Update build vars for Edge"

echo "add_subdirectory (mept-ble)" >> CMakeLists.txt
echo 'export MEPT_BLE_TRACE_LEVEL="DEBUG"' >> ~/.profile
export MEPT_BLE_TRACE_LEVEL="DEBUG"

echo "---> Copy mbed_cloud_dev_credentials.c"
cp ~/Creds/mbed_cloud_dev_credentials.c config

echo "---> Init git submodule build env"
git submodule init
git submodule update

echo "---> Change to build directory"
mkdir build && cd build

echo "---> cmake Mbed Edge"
cmake -DDEVELOPER_MODE=ON -DFIRMWARE_UPDATE=OFF .. && make

echo "---> Change to bin directory"
cd bin

echo "---> Run Edge Core in background"
./edge-core --reset-storage &

echo "---> Run Mbed Edge protocol translator in background"
./mept-ble --edge-domain-socket=/tmp/edge.sock --protocol-translator-name=mept-ble --endpoint-postfix=-rigado --bluetooth-interface=hci0&

# echo "---> Copy builds to /root/Share/${EPOCH_TIME}-Source"
# cp -R /root/Source /root/Share/${EPOCH_TIME}-Source

echo "---> Change to source directory"
cd ~/Source

echo "---> Clone bluetooth examples"
git clone https://github.com/ARMmbed/mbed-os-example-ble.git && cd mbed-os-example-ble/BLE_GattServer

echo "---> Mbed deploy on examples"
mbed deploy

echo "---> Compile mbed-os-example-ble/BLE_GattServer"
mbed compile -t GCC_ARM -m NRF52_DK

echo "---> Copy mbed-os-example-ble/BLE_GattServer to ~/Share"
cp BUILD/NRF52_DK/GCC_ARM/BLE_GattServer.hex /root/Share/${EPOCH_TIME}-BLE_GattServer.hex

echo "---> Keeping the container running with a tail of the build logs"
tail -f ~/epoch_time.txt
