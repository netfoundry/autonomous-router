FROM ubuntu:jammy as build

RUN apt update && apt-get install -y
RUN apt install -y jq curl procps iproute2 python3 pip
RUN pip install -r https://raw.githubusercontent.com/netfoundry/ziti_router_auto_enroll/main/requirements.txt

ADD https://raw.githubusercontent.com/netfoundry/ziti_router_auto_enroll/main/ziti_router_auto_enroll.py /

RUN pyinstaller -F /ziti_router_auto_enroll.py

#RUN mkdir -p /opt/netfoundry/ziti/ziti-router
#ADD ziti-router /opt/netfoundry/ziti/ziti-router/

FROM cgr.dev/chainguard/wolfi-base
RUN apk update && apk add --no-cache --update-cache bash curl jq iproute2
COPY --from=build /dist/ziti_router_auto_enroll /
COPY ./docker-entrypoint.sh /
RUN chmod +x /docker-entrypoint.sh

ENTRYPOINT [ "/docker-entrypoint.sh" ]
CMD [ "run" ]

#CMD ["/opt/netfoundry/ziti/ziti-router/ziti-router", "run", "/etc/netfoundry/config.yml"]
