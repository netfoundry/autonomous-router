# README #

## build ##
* docker build -t <image_namge> .
* docker save <image_name> --output <image_name>.tar

## docker-entrypoint.sh ##
* default build uses the docker-entrypoint.sh
* the default docker image uses environmental variable "REG_KEY" (taken from nfconsole)
* if you pass in environmental variable "VERBOSE", ziti will run under verbose mode.

### Start the docker ###
* load the image: docker image load -i <ROUTER_NAME>.tar
* docker run -v /home/ziggy/router2/:/etc/netfoundry/ --env REG_KEY=<Registration Key> <image_name>
if you want to run router in verbose mode:
* docker run -v /home/ziggy/router2/:/etc/netfoundry/ --env REG_KEY=<Registration Key> --env VERBOSE=1 <image_name>


## docker-entrypoint-for-config.sh ##

### Dockerfile change ###
add ziti-router binary to docker file:
'''
RUN mkdir -p /opt/netfoundry/ziti/ziti-router
ADD ziti-router /opt/netfoundry/ziti/ziti-router/
'''

### prerequisite ### ###
* config.yml needs to be generated correctly before calling the docker container to enroll.
* <ROUTER_NAME>.jwt is under the same dir.

### Start the docker ###
* load the image: docker image load -i <ROUTER_NAME>.tar
assume you put the "config.yml" and jwt under "router1" directory, to start the docker container:
* docker run -v /home/ziggy/router2/:/etc/netfoundry/ --env NF_REG_NAME=<ROUTER_NAME> --dns="8.8.8.8" <image_name>
