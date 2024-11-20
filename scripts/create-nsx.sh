#!/bin/bash -e
set -o pipefail

source ../config/env.config

export GOVC_URL=$VIServer
export GOVC_USERNAME=$VIUsername
export GOVC_PASSWORD=$VIPassword
export GOVC_DATASTORE=$VMDatastore
export GOVC_NETWORK=$VMNetwork
export GOVC_INSECURE=true
#export GOVC_DATACENTER=$VMDatacenter
#export GOVC_CLUSTER=$VMCluster
##export GOVC_RESOURCE_POOL=
#export GOVC_RESOURCE_POOL=$VMCluster

#export GOVC_URL=$VCSAIPAddress
#export GOVC_USERNAME=administrator@vsphere.local
#export GOVC_PASSWORD=$VCSASSOPassword
#export GOVC_INSECURE=true
#export GOVC_DATACENTER=$NewVCDatacenterName
#export GOVC_DATASTORE="vsanDatastore"
#export GOVC_CLUSTER=$NewVCVSANClusterName
#export GOVC_NETWORK=$NewVCDVPGName
#export GOVC_RESOURCE_POOL=

echo "Deploying NSX Manager VM in the nested env ..."
envsubst < ../config/nsx.template.json > nsx.${NSXVM}.json
govc import.ova --options=nsx.${NSXVM}.json --name=${NSXVM} --json=true ${NSXOVA}
govc vm.change --c=4 --m=18432 --vm ${NSXVM}
govc vm.power -on ${NSXVM}
rm -f avi.${NSXVM}.json