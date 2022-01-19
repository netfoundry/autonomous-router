FROM ubuntu:focal

RUN mkdir -p /opt/netfoundry/ziti/ziti-router
ADD ziti-router /opt/netfoundry/ziti/ziti-router/

COPY ./docker-entrypoint.sh /
RUN chmod +x /docker-entrypoint.sh

ENTRYPOINT [ "/docker-entrypoint.sh" ]
CMD [ "run" ]

#CMD ["/opt/netfoundry/ziti/ziti-router/ziti-router", "run", "/etc/netfoundry/config.yml"]
