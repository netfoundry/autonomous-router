#!/usr/bin/env bash

#
# Copyright 2022 NetFoundry Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

set -e -u -o pipefail

LOGFILE="ziti-router.log"

# create router config for docker
# this will be edge only with tunnerl in host mode
create_router_config()
{
    # this is ip we going to use
    localip=$(ip addr show eth0 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)

    #define identity
    mkdir -p certs
    export ZITI_ROUTER_IDENTITY_CERT="certs/client.cert"
    export ZITI_ROUTER_IDENTITY_SERVER_CERT="certs/server.cert"
    export ZITI_ROUTER_IDENTITY_KEY="certs/server.key"
    export ZITI_ROUTER_IDENTITY_CA="certs/cas.cert"

    #define the address for controller (getting from console)
    export ZITI_CTRL_ADVERTISED_ADDRESS=${networkControllerHost}
    #controller port (default)
    export ZITI_CTRL_PORT="80"

    # router ip and port to put in config
    export ZITI_EDGE_ROUTER_IP_OVERRIDE=${localip}
    export ZITI_EDGE_ROUTER_PORT=443

    ziti/ziti create config router edge --private -n "docker" -o config.yml
}

get_controller_version()
{
    echo "Check ziti controller verion"
    CONTROLLER_ADDRESS=$(cat config.yml |  grep "endpoint" |awk -F ':' '{print $3}')

    echo -e "controller_address: ${CONTROLLER_ADDRESS}"

    if [ -z $CONTROLLER_ADDRESS ]
    then
        echo "No controller address found, no upgrade"
    else
        #CONTROLLER_VERSION=$(curl -s -k -H -X "https://${CONTROLLER_ADDRESS}:443/edge/v1/version" |jq -r .data.version)
        CONTROLLER_REP=$(curl -s -k -H -X "https://${CONTROLLER_ADDRESS}:443/edge/v1/version")
        
        if jq -e . >/dev/null 2>&1 <<<"$CONTROLLER_REP"; then
            CONTROLLER_VERSION=$(echo ${CONTROLLER_REP} | jq -r .data.version)
        else
            echo "!!!!!!!!!!Retrieve controller verion Failed."
        fi

    fi

    echo -e "controller_version: ${CONTROLLER_VERSION}"
}

# download ziti binary from the link saved in "upgradelink"
download_ziti_binary()
{
    echo -e "version link: ${upgradelink}"

    rm -f ziti-linux.tar.gz

    curl -L -s -o ziti-linux.tar.gz ${upgradelink}

    ## maybe check if the file is downloaded?

    mkdir -p ziti
    rm -f ziti/ziti-router
    rm -f ziti/ziti

    #extract ziti-router
    tar xf ziti-linux.tar.gz ziti/ziti-router
    tar xf ziti-linux.tar.gz ziti/ziti
    chmod +x ziti/ziti-router
    chmod +x ziti/ziti
    mv ziti/ziti-router .
    # mv ziti/ziti .

    #cleanup the download
    rm ziti-linux.tar.gz

}

# figure out the link for ziti binary, then call download to get the correct binary.
upgrade_ziti_router()
{
    upgrade_release="${CONTROLLER_VERSION:1}"
    echo -e "Upgrading ziti version to ${upgrade_release}"
    response=$(curl -k -d -H "Accept: application/json" -X GET https://gateway.production.netfoundry.io/core/v2/network-versions?zitiVersion=${upgrade_release})
    #upgradelink="https://github.com/openziti/ziti/releases/download/v"${upgrade_release}"/ziti-linux-amd64-"${upgrade_release}".tar.gz"

    echo ${response} > mopresponse.json
    if jq -e . >/dev/null 2>&1 <<<"${response}"; then
        upgradelink=$(echo ${response} | jq -r '._embedded["network-versions"][0].jsonNode.zitiBinaryBundleLinuxAMD64')
        download_ziti_binary
    else
        echo "!!!!!!!!!!Retrieve from console Failed."
    fi
}

#
# main code starts here
#
# look to see if the ziti-router is already registered
cd /etc/netfoundry/

CERT_FILE="certs/client.cert"
if [[ -n "${REG_KEY:-}" ]]; then
    if [[ -s "${CERT_FILE}" ]]; then
        echo "INFO: Found cert file ${CERT_FILE}"
        echo " do we need to overwrite? "
    else
        echo REGKEY: $REG_KEY
        response=$(curl -k -d -H "Content-Type: application/json" -X POST https://gateway.production.netfoundry.io/core/v2/edge-routers/register/${REG_KEY})
        echo $response >reg_response
        jwt=$(echo $response |jq -r .edgeRouter.jwt)
        networkControllerHost=$(echo $response |jq -r .networkControllerHost)
        upgradelink=$(echo $response |jq -r .productMetadata.zitiBinaryBundleLinuxAMD64)
        #echo $jwt
        #echo $networkControllerHost
        #echo $upgradelink

        # download the binaries
        download_ziti_binary
        # create router config
        create_router_config
        # save jwt retrieved from console, and register router
        echo $jwt > docker.jwt
        ./ziti-router enroll config.yml -j docker.jwt
    fi
else
    if [[ -s "${CERT_FILE}" ]]; then
        echo "INFO: Found cert file"
    else
        echo "ERROR: Need to specify REG_KEY for registration"
        exit 1
    fi
fi


# now check if edge router version is same as controller
get_controller_version

if [[ -f "ziti-router" ]]; then
    ZITI_VERSION=$(./ziti-router version 2>/dev/null)
else
    ZITI_VERSION="Not Found"
fi
 
echo Router version: $ZITI_VERSION

# check if the version is the same
if [ "$CONTROLLER_VERSION" == "$ZITI_VERSION" ]; then
    echo "Ziti version match, no download necessary"
else
    upgrade_ziti_router
fi

echo "INFO: running ziti-router"
ZITI_VERSION=$(./ziti-router version 2>/dev/null)
./ziti-router run config.yml >$LOGFILE 2>&1 &

set -x
while true; do
    sleep 60
    get_controller_version

    if [ -z "$CONTROLLER_VERSION" ]; then
        echo "Controller version not found, skip upgrade check"
    else
        if [ "$CONTROLLER_VERSION" != "$ZITI_VERSION" ]; then
            pkill ziti-router
            upgrade_ziti_router
            ZITI_VERSION=$(./ziti-router version 2>/dev/null)
            echo "INFO: restarting ziti-router"
            ./ziti-router run config.yml >>$LOGFILE 2>&1 &
        fi
    fi
done
    
    

