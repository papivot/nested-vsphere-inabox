#!/bin/bash -e
set -o pipefail

source ../config/env.config

export GOVC_URL=$VIServer
export GOVC_USERNAME=$VIUsername
export GOVC_PASSWORD=$VIPassword
export GOVC_DATASTORE=$VMDatastore
export GOVC_NETWORK=$VMNetwork
export GOVC_INSECURE=true
export GOVC_DATACENTER=$VMDatacenter
export GOVC_CLUSTER=$VMCluster
#export GOVC_RESOURCE_POOL=
#export GOVC_RESOURCE_POOL=$VMCluster

guest=${GUEST:-"vmkernel7Guest"}

echo "Powering off and deleting ESXi VMs..."
echo
for i in "${!NestedESXiHostname[@]}"; do
	echo "Destroying ${NestedESXiHostname[$i]}..."
	govc vm.destroy ${NestedESXiHostname[$i]}
	echo
done

echo "Powering off and deleting vCenter VMs..."
echo
govc vm.destroy ${VCSADisplayName}