##### RESTful firmware update campaign creation

Make sure you update .env with the spoch time
of a build you did previously.  This image assumes
you have already built one of the client examples
that creates mbed_os_dev.

.env

    `MBED_CLOUD_UPDATE_EPOCH=some_epoch_time`


Run the example container making RESTful calls to setup campaign

`docker-compose -f examples/mbed-cloud-update-restful/compose.yml up -d`

Stop and remove the container

`docker-compose -f examples/mbed-cloud-update-restful/compose.yml down`

This will create the update campaign, manifest, and filter in Mbed Cloud

note: if you already have these elements in mbed cloud there will
be an error reflecting that in the .json files created from curl
that are copied to the share directory.

###### Debugging

Watch the container output after running 'up -d' from above.

`docker logs -f mbed-cloud-update-restful`

Get a shell in to the running container to poke around

`docker exec -it mbed-cloud-update-restful sh`