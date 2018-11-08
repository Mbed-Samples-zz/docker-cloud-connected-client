### Prerequisites for Raspbian

Install Docker Compose

    pip install docker-compose

Add yourself to group

    sudo usermod -aG docker pi

Add path to profile

    echo "export PATH=$PATH:/home/pi/.local/bin" >> .profile

Update your current PATH

    source ~/.profile

##### Containers with Compose

Build the base container and the example container

`docker-compose -f ../../../../resources/raspbian_dev.yml -f compose.yml up -d`

Run the example container which does one firmware build

Watch the active log while the container is building and running

`docker logs -f <CONTAINER_NAME>`

Destroy the container and keep the base image

`docker-compose -f ../../../../resources/raspbian_dev.yml -f compose.yml down`

##### Debugging or ad-hoc usage of the container

Get a shell in to the running container to poke around

`docker exec -it <CONTAINER_NAME> bash`