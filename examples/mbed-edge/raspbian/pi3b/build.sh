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

git clone git@github.com:armmbed/mbed-edge.git && cd mbed-edge

git clone git@github.com:armmbed/edge-ble-protocol-translator.git mept-ble

echo "add_subdirectory (mept-ble)" >> CMakeLists.txt

echo 'export MEPT_BLE_TRACE_LEVEL="DEBUG"' >> ~/.profile
export MEPT_BLE_TRACE_LEVEL="DEBUG"

cp ~/Creds/mbed_cloud_dev_credentials.c config

git submodule init
git submodule update

mkdir build && cd build

cmake -DDEVELOPER_MODE=ON -DFIRMWARE_UPDATE=OFF .. && make

cd bin

./edge-core --reset-storage &

./mept-ble --edge-domain-socket=/tmp/edge.sock --protocol-translator-name=mept-ble --endpoint-postfix=-rigado --bluetooth-interface=hci0&

# echo "---> Copy builds to /root/Share/${EPOCH_TIME}-Source"
# cp -R /root/Source /root/Share/${EPOCH_TIME}-Source

echo "---> Keeping the container running with a tail of the build logs"
tail -f ~/epoch_time.txt
