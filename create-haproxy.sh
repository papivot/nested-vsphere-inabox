#!/bin/bash -e
set -o pipefail

source ./env.config

export GOVC_URL=$VCSAIPAddress
export GOVC_USERNAME=administrator@vsphere.local
export GOVC_PASSWORD=$VCSASSOPassword
export GOVC_DATASTORE=$VMDatastore
export GOVC_NETWORK=$VMNetwork
export GOVC_INSECURE=true
export GOVC_DATACENTER=$NewVCDatacenterName
export GOVC_DATASTORE="vsanDatastore"
export GOVC_CLUSTER=$NewVCVSANClusterName
export GOVC_NETWORK=$NewVCDVPGName
export GOVC_RESOURCE_POOL=

echo "Deploying HAProxy VM in the nested env ..."
envsubst < haproxy.template.json > haproxy.${HAProxyVM}.json
govc import.ova --options=haproxy.${HAProxyVM}.json --name=haproxy --json=true haproxy-v0.1.10.ova
rm -f haproxy.${HAProxyVM}.json
