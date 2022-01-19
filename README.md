# README #

### build ###
* docker build -t <image_namge> .
* docker save <image_name> --output <image_name>.tar

### prerequist ###
* config.yml needs to be generated correctly before calling the docker containter to enroll.
* <ROUTER_NAME>.jwt is under the same dir.

### Start the docker ###
* load the image: docker image load -i <ROUTER_NAME>.tar
assume you put the "config.yml" and jwt under "router1" directory, to start the docker container:
* docker run -v /home/ziggy/router2/:/etc/netfoundry/ --env NF_REG_NAME=<ROUTER_NAME> --dns="8.8.8.8" <image_name>
