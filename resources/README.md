##### Mbed OS Development Container

Build the base container and the example container

`docker-compose -f resources/mbed_os_dev.yml build`

Run the example container which does three firmware builds

`docker-compose -f resources/mbed_os_dev.yml up -d`

Stop and remove the container

`docker-compose -f resources/mbed_os_dev.yml down`

This will give you a container with the Mbed build environment

##### Debugging or ad-hoc usage of the container

Get a shell in to the running container to poke around

`docker exec -it mbed_os_dev bash`