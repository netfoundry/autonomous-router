FROM ubuntu:jammy

RUN apt update && apt-get install -y
RUN apt install -y jq
RUN apt install -y curl
RUN apt install -y procps
RUN apt install -y iproute2
RUN apt install -y python3
RUN apt install -y pip
RUN pip install -r https://raw.githubusercontent.com/netfoundry/ziti_router_auto_enroll/main/requirements.txt
RUN apt update && apt-get install -y

ADD https://raw.githubusercontent.com/netfoundry/ziti_router_auto_enroll/main/ziti_router_auto_enroll.py /

#RUN mkdir -p /opt/netfoundry/ziti/ziti-router
#ADD ziti-router /opt/netfoundry/ziti/ziti-router/

COPY ./docker-entrypoint.sh /
RUN chmod +x /docker-entrypoint.sh

ENTRYPOINT [ "/docker-entrypoint.sh" ]
CMD [ "run" ]

#CMD ["/opt/netfoundry/ziti/ziti-router/ziti-router", "run", "/etc/netfoundry/config.yml"]
