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

# Ensure that ziti-edge-tunnel's identity is stored on a volume
# so we don't throw away the one-time enrollment token

#IDENTITIES_DIR="/ziti-edge-tunnel"
#if ! mountpoint "${IDENTITIES_DIR}" &>/dev/null; then
#    echo "ERROR: please run this image with a volume mounted on ${IDENTITIES_DIR}" >&2
#    exit 1
#fi

# if identity file, else multiple identities dir
cd /etc/netfoundry/
if [[ -n "${NF_REG_NAME:-}" ]]; then
    CERT_FILE="certs/client.cert.pem"
    if [[ -s "${CERT_FILE}" ]]; then
        echo "INFO: found cert file ${CERT_FILE}"
	# so we don't need to enroll again
    # look for enrollment token
    else
        JWT_FILE="${NF_REG_NAME}.jwt"
        if [[ -f "${JWT_FILE:-}" ]]; then
            echo "INFO: enrolling ${JWT_FILE}"
	    mkdir -p certs
            /opt/netfoundry/ziti/ziti-router/ziti-router enroll config.yml -j "${JWT_FILE}"
        else
            echo "INFO: ${NF_REG_NAME}.jwt was not found" >&2
            exit 1
        fi
    fi
fi



echo "INFO: running ziti-router"
set -x
/opt/netfoundry/ziti/ziti-router/ziti-router run config.yml
