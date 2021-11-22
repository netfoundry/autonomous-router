FROM ubuntu:focal

RUN mkdir -p /opt/netfoundry/ziti/ziti-router
ADD ziti-router /opt/netfoundry/ziti/ziti-router/
CMD ["/opt/netfoundry/ziti/ziti-router/ziti-router", "run", "/etc/netfoundry/config.yml"]
