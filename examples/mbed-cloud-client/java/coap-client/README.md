##### Ubuntu 12.04 + Java CoAP LWM2M Example Client

Build the base container and the example container

`docker-compose -f examples/mbed-cloud-java-coap-client-example/mbed_os_dev.12.04.yml -f examples/mbed-cloud-java-coap-client-example/compose.yml up -d`

Run the example container which does one firmware build

Watch the active log while the container is building and running

`docker logs -f mbed-cloud-java-coap-client-example`

Destroy the container and keep the base mbed_os_dev image

`docker-compose -f examples/mbed-cloud-java-coap-client-example/mbed_os_dev.12.04.yml -f examples/mbed-cloud-java-coap-client-example/compose.yml down`

##### Debugging or ad-hoc usage of the container

Get a shell in to the running container to poke around

`docker exec -it mbed-cloud-java-coap-client-example bash`