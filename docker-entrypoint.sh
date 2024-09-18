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

# 10/26/2023
# add health check config
# add proxy support, with environmental varibale "HTTPS_PROXY"

# 01/19/2024
# user ziti_auto_enroll.py to generate router config

# 04/25/2024
# fix issue with 1.0.0 release.

# 05/30/2024
# harden the detection of registrion by adding the old cert file

# 09/17/2024
# Version: 1.0. Support V8 network and lower environment for registration.
#               Also use ziti_auto_enroll to download binary also.

VERSION="1.0"

set -e -o pipefail

LOGFILE="ziti-router.log"

# register router
# this will be edge only with tunnerl in host mode
register_router()
{
    mkdir -p /etc/netfoundry/certs
    # For 0.30.0 and above, the ctrl port is 443
    ziti_main_version=$(echo $zitiVersion| awk -F "." '{print $1}')
    ziti_dot_version=$(echo $zitiVersion| awk -F "." '{print $2}')
    
    if [ "$ziti_main_version" -lt "1" ] && [ "$ziti_dot_version" -lt "30" ]; then
        ZITI_CTRL_ADVERTISED_PORT="80"
    else
        ZITI_CTRL_ADVERTISED_PORT="443"
    fi 

    # create proxy setting if exist
    if [[ -n "${HTTPS_PROXY:-}" ]]; then
        PROXY_TYPE=$(echo $HTTPS_PROXY |awk -F ':' '{print $1}')
        PROXY_ADDRESS=$(echo $HTTPS_PROXY |awk -F ':' '{print $2}')
        PROXY_ADDRESS=$(echo $PROXY_ADDRESS |awk -F '/' '{print $3}')
        PROXY_PORT=$(echo $HTTPS_PROXY |awk -F ':' '{print $3}')
        #echo TYPE: $PROXY_TYPE
        #echo ADDRESS: $PROXY_ADDRESS
        #echo PORT: $PROXY_PORT

        /ziti_router_auto_enroll -n -j docker.jwt --tunnelListener 'host' --installDir /etc/netfoundry \
        --controllerFabricPort $ZITI_CTRL_ADVERTISED_PORT \
        --proxyType $PROXY_TYPE --proxyAddress $PROXY_ADDRESS --proxyPort $PROXY_PORT \
        --downloadUrl $upgradelink --skipSystemd

    else
        /ziti_router_auto_enroll -n -j docker.jwt --tunnelListener 'host' --installDir /etc/netfoundry \
        --controllerFabricPort $ZITI_CTRL_ADVERTISED_PORT \
        --downloadUrl $upgradelink --skipSystemd
    fi
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
        #CONTROLLER_REP=$(curl -s -k -H -X "https://${CONTROLLER_ADDRESS}:443/edge/v1/version")
        # for ha, we will need to use different endpoint.
        CONTROLLER_REP=$(curl -s -k -H -X "https://${CONTROLLER_ADDRESS}:443/edge/client/v1/version")
        
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
    controller_main_version=$(echo $CONTROLLER_VERSION| awk -F "." '{print $1}')
    # strip off v
    controller_main_version=$(echo "${controller_main_version//v}")
    controller_dot_version=$(echo $CONTROLLER_VERSION| awk -F "." '{print $2}')
    
    # do not continue if the version is not supported.
    if [ "$controller_main_version" -lt "1" ]  && [ "$controller_dot_version" -lt "27" ]; then
        echo "Your version is not supported"
        exit 1
    fi

    if [ "$controller_main_version" -lt "1" ]  && [ "$controller_dot_version" -lt "29" ]; then
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
echo Version: $VERSION

cd /etc/netfoundry/

aarch=$(uname -m)
echo $aarch
CERT_FILE="certs/cert.pem"
CERT_FILE_OLD="certs/client.cert"

if [[ -n "${REG_KEY:-}" ]]; then
    # user supplied Registration KEY
    if [[ -s "${CERT_FILE}" ]]; then
        # there is certificate file already, so we ignore the reg key.
        echo "INFO: Found cert file ${CERT_FILE}"
        echo "      REG key ignored."
    elif [[ -s "${CERT_FILE_OLD}" ]]; then
        # there is certificate file already, so we ignore the reg key.
        echo "INFO: Found cert file ${CERT_FILE_OLD}"
        echo "      REG key ignored."
    else
        echo REGKEY: $REG_KEY

        firsttwo="${REG_KEY:0:2}"
        length=${#REG_KEY}

        # check which network the key comes from
        if [[ $length == "11" ]]; then
            # V8 production network
            reg_url="https://gateway.production.netfoundry.io/core/v3/edge-router-registrations/${REG_KEY}"
        elif [[ $length == "10" ]]; then
            # V7 production network
            reg_url="https://gateway.production.netfoundry.io/core/v2/edge-routers/register/${REG_KEY}"
        elif [[ $firsttwo == "SA" ]]; then
            if [[ $length == "12" ]]; then
                reg_url="https://gateway.sandbox.netfoundry.io/core/v2/edge-routers/register/${REG_KEY}"
            elif [[ $length == "13" ]]; then
                reg_url="https://gateway.sandox.netfoundry.io/core/v3/edge-router-registrations/${REG_KEY}"
            else
                echo Sandbox Registration code: $REGKEY is not correct, Length: $length
                exit
            fi
        elif [[ $firsttwo == "ST" ]]; then
                if [[ $length == "12" ]]; then
                reg_url="https://gateway.staging.netfoundry.io/core/v2/edge-routers/register/${REG_KEY}"
            elif [[ $length == "13" ]]; then
                reg_url="https://gateway.staging.netfoundry.io/core/v3/edge-router-registrations/${REG_KEY}"
            else
                    echo Staging Registration code: $REGKEY is not correct, Length: $length
                exit
                fi
        else
                echo Registration code: $REGKEY is not correct, Length: $length
            exit
        fi

        # contact console to get router information.
        response=$(curl -k -d -H "Content-Type: application/json" -X POST ${reg_url})
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

        # get the ziti version
        zitiVersion=$(echo $response |jq -r .productMetadata.zitiVersion)

        # need to figure out CONTROLLER verion
        #CONTROLLER_REP=$(curl -s -k -H -X "https://${networkControllerHost}:443/edge/v1/version")
        # for ha, we will need to use different endpoint.
        CONTROLLER_REP=$(curl -s -k -H -X "https://${networkControllerHost}:443/edge/client/v1/version")
        
        if jq -e . >/dev/null 2>&1 <<<"$CONTROLLER_REP"; then
            CONTROLLER_VERSION=$(echo ${CONTROLLER_REP} | jq -r .data.version)
        else
            echo "!!!!!!!!!!Retrieve controller verion Failed."
        fi

        # save jwt retrieved from console, and register router
        echo $jwt > docker.jwt

        # create router config
        register_router

    fi
else
    if [[ -s "${CERT_FILE}" || -s "${CERT_FILE_OLD}" ]]; then
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

# if we get here, we are running the autonomous router in normal mode
echo "Autonomous router mode"
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
    if pgrep -x "/opt/openziti/bin/ziti" > /dev/null
    then
        echo ziti is running
    else
        # ziti not running, restart
        /opt/openziti/bin/ziti router run config.yml $OPS &
    fi
done
    
    

