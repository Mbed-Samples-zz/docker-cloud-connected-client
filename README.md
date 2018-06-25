# Sequence

- Clone repo with Dockerfile(s) and Compose files
- Build containers with Compose
- Run containers (Mbed OS development container, Firmware upgrade build container, quickstart microservice(s))
- Connect to the microservices and/or use the generated binaries to run through the upgrade process

## Prepare your environment and credentials

Create/copy your Arm Mbed Cloud credential files in the `./creds/` subdirectory

**mbed_cloud_dev_credentials.c**

&nbsp;&nbsp;&nbsp;&nbsp;Downloaded from the [portal](https://portal.us-east-1.mbedcloud.com)

**.env**

Update the Docker Compose environment file `./.env` and add the following contents

    MBED_CLOUD_API_KEY=my_mbed_cloud_api_key_for_us_east
- MBED_CLOUD_API_KEY is used by cURL when setting up a RESTful upgrade

## Docker Compose

Build containers for Mbed development and cloud client firmware upgrade images and quickstart.
See each example folder for the Compose command syntax.  Note they should all be executed
from this directory context.


[mbed-cloud-client-example](examples/mbed-cloud-client)

&nbsp;&nbsp;&nbsp;&nbsp;[mbed-cloud-client/mbed-os/nrf52840_dk/wifi/esp8266](examples/mbed-cloud-client/mbed-os/nrf52840_dk/wifi/esp8266)

&nbsp;&nbsp;&nbsp;&nbsp;[examples/mbed-cloud-client/mbed-os/nrf52840_dk/cellular/wnc14a2a](examples/mbed-cloud-client/mbed-os/nrf52840_dk/cellular/wnc14a2a)

&nbsp;&nbsp;&nbsp;&nbsp;[examples/mbed-cloud-client/mbed-os/k64f/cellular/wnc14a2a](examples/mbed-cloud-client/mbed-os/k64f/cellular/wnc14a2a)

&nbsp;&nbsp;&nbsp;&nbsp;[examples/mbed-cloud-client/java/coap-client](examples/mbed-cloud-client/java/coap-client)

[mbed-cloud-update-restful](examples/mbed-cloud-restful-update)

[mbed_os_dev](resources)