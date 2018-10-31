##### Mbed Bootloader

Build the base container and the example container

`docker-compose -f ../../../../resources/mbed_os_dev.yml -f compose.yml up -d`

Run the example container which does one firmware build

Watch the active log while the container is building and running

`docker logs -f <CONTAINER_NAME>`

Destroy the container and keep the base mbed_os_dev image

`docker-compose -f ../../../../resources/mbed_os_dev.yml -f compose.yml down`

This will give you the following files:

    - softdevice + bootloader (Nordic special case)

##### Debugging or ad-hoc usage of the container

Get a shell in to the running container to poke around

`docker exec -it <CONTAINER_NAME> bash`