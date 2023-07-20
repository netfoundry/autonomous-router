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

# This version supports ziti 0.27.1 or above.  we are using single binary for
# all ziti functionality now

# 7/19/2023
# Support ziti version 0.29.0 tarball
# move executable to /opt/openziti/bin (for execution)
# direct ziti output to the container. user can now retrieve log with 
#    docker logs -f <container>
# monitor ziti process, if process goes away, restart it

set -e -o pipefail

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
    # 0.29.0 renamed environment variable
    export ZITI_CTRL_ADVERTISED_PORT="80"

    # router ip and port to put in config
    export ZITI_EDGE_ROUTER_IP_OVERRIDE=${localip}
    export ZITI_EDGE_ROUTER_PORT=443

    # 0.29.0 renamed environment variable
    export ZITI_ROUTER_IP_OVERRIDE=${localip}
    export ZITI_ROUTER_PORT=443
    

    /opt/openziti/bin/ziti create config router edge --private -n "docker" -o config.yml
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

    rm -f ziti

    #base on the verion, we extract the right ziti out of the tarball
    controller_dot_version=$(echo $CONTROLLER_VERSION| awk -F "." '{print $2}')

    if [ "$controller_dot_version" -lt "29" ]; then
        tar xf ziti-linux.tar.gz ziti/ziti --strip-components 1
    else
        tar xf ziti-linux.tar.gz ziti
    fi

    # change it to be executable
    chmod +x ziti

    #cleanup the download
    rm ziti-linux.tar.gz

    ls -l

    ### copy to /opt
    mkdir -p /opt/openziti/bin
    cp ziti /opt/openziti/bin
    ls -la /opt/openziti/bin
}

# figure out the link for ziti binary, then call download to get the correct binary.
upgrade_ziti()
{
    upgrade_release="${CONTROLLER_VERSION:1}"
    echo -e "Upgrading ziti version to ${upgrade_release}"
    response=$(curl -k -d -H "Accept: application/json" -X GET https://gateway.production.netfoundry.io/core/v2/network-versions?zitiVersion=${upgrade_release})
    #upgradelink="https://github.com/openziti/ziti/releases/download/v"${upgrade_release}"/ziti-linux-amd64-"${upgrade_release}".tar.gz"
    
    aarch=$(uname -m)
    echo ${response} > mopresponse.json
    if jq -e . >/dev/null 2>&1 <<<"${response}"; then
	if [[ $aarch == "aarch64" ]]; then
            upgradelink=$(echo ${response} | jq -r '._embedded["network-versions"][0].jsonNode.zitiBinaryBundleLinuxARM64')
        elif [[ $aarch == "armv7l" ]]; then
            upgradelink=$(echo ${response} | jq -r '._embedded["network-versions"][0].jsonNode.zitiBinaryBundleLinuxARM')
        else
            upgradelink=$(echo ${response} | jq -r '._embedded["network-versions"][0].jsonNode.zitiBinaryBundleLinuxAMD64')
        fi
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

aarch=$(uname -m)
echo $aarch
CERT_FILE="certs/client.cert"

if [[ -n "${REG_KEY:-}" ]]; then
    # user supplied Registration KEY
    if [[ -s "${CERT_FILE}" ]]; then
        # there is certificate file already, so we ignore the reg key.
        echo "INFO: Found cert file ${CERT_FILE}"
        echo "      REG key ignored."
    else
        echo REGKEY: $REG_KEY

        # contact console to get router information.
        response=$(curl -k -d -H "Content-Type: application/json" -X POST https://gateway.production.netfoundry.io/core/v2/edge-routers/register/${REG_KEY})
        echo $response >reg_response
        jwt=$(echo $response |jq -r .edgeRouter.jwt)
        networkControllerHost=$(echo $response |jq -r .networkControllerHost)

        # get the link to the binary based on the architecture.
        if [[ $aarch == "aarch64" ]]; then
            upgradelink=$(echo $response |jq -r .productMetadata.zitiBinaryBundleLinuxARM64)
        elif [[ $aarch == "armv7l" ]]; then
            upgradelink=$(echo ${response} | jq -r .productMetadata.zitiBinaryBundleLinuxARM)
        else
            upgradelink=$(echo $response |jq -r .productMetadata.zitiBinaryBundleLinuxAMD64)
        fi
        #echo $jwt
        #echo $networkControllerHost
        #echo $upgradelink

        # need to figure out CONTROLLER verion
        CONTROLLER_REP=$(curl -s -k -H -X "https://${networkControllerHost}:443/edge/v1/version")
        
        if jq -e . >/dev/null 2>&1 <<<"$CONTROLLER_REP"; then
            CONTROLLER_VERSION=$(echo ${CONTROLLER_REP} | jq -r .data.version)
        else
            echo "!!!!!!!!!!Retrieve controller verion Failed."
        fi

        # download the binaries
        download_ziti_binary
        # create router config
        create_router_config
        # save jwt retrieved from console, and register router
        echo $jwt > docker.jwt
        /opt/openziti/bin/ziti router enroll config.yml -j docker.jwt
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

# copy the ziti local copy (on the host) to /opt/openziti/bin .
if [[ ! -f "/opt/openziti/bin/ziti" ]] && [ -f "ziti" ]; then
    echo "Copy saved ziti file to execute dir"
    mkdir -p /opt/openziti/bin
    cp ziti /opt/openziti/bin
fi

if [[ -f "/opt/openziti/bin/ziti" ]]; then
    ZITI_VERSION=$(/opt/openziti/bin/ziti -v 2>/dev/null)
else
    ZITI_VERSION="Not Found"
fi
 
echo Router version: $ZITI_VERSION

# check if the version is the same
if [ "$CONTROLLER_VERSION" == "$ZITI_VERSION" ]; then
    echo "Ziti version match, no download necessary"
else
    upgrade_ziti
fi

echo "INFO: running ziti-router"

# turn on the verbose mode if user defines it
if [ -z "$VERBOSE" ]; then
   OPS=""
else
   OPS="-v"
fi

ZITI_VERSION=$(/opt/openziti/bin/ziti -v 2>/dev/null)
/opt/openziti/bin/ziti router run config.yml $OPS &

set -x
while true; do
    sleep 60
    get_controller_version

    if [ -z "$CONTROLLER_VERSION" ]; then
        echo "Controller version not found, skip upgrade check"
    else
        if [ "$CONTROLLER_VERSION" != "$ZITI_VERSION" ]; then
            pkill ziti
            upgrade_ziti
            ZITI_VERSION=$(/opt/openziti/bin/ziti -v 2>/dev/null)
            echo "INFO: restarting ziti-router"
            /opt/openziti/bin/ziti router run config.yml $OPS &
        fi
    fi

    ## check if ziti is running or not
    if pgrep -x "ziti" > /dev/null
    then
        echo ziti is running
    else
        # ziti not running, restart
        /opt/openziti/bin/ziti router run config.yml $OPS &
    fi
done
    
    

