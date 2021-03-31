#!/bin/bash -e

source ../config/env.config

export GOVC_URL=$VIServer
export GOVC_USERNAME=$VIUsername
export GOVC_PASSWORD=$VIPassword
export GOVC_DATASTORE=$VMDatastore
export GOVC_NETWORK=$VMNetwork
export GOVC_INSECURE=true
export VCInstallFile="/mnt/vcenter/vcsa-cli-installer/lin64/vcsa-deploy"

envsubst < ../config/vcenter.template.json > vcenter.${VCSADisplayName}.json

if [[ ! -f "${VCInstallFile}" ]]; then
    echo "${VCInstallFile} does not exist. Mount the VCenter Installation ISO to ${VCSAInstallerPath} and retry again. Exiting..."
    exit 1
fi

/mnt/vcenter/vcsa-cli-installer/lin64/vcsa-deploy install --accept-eula --acknowledge-ceip --no-ssl-certificate-verification vcenter.${VCSADisplayName}.json --terse

export GOVC_URL=${VCSAIPAddress}
export GOVC_USERNAME='administrator@vsphere.local'
export GOVC_PASSWORD=$VCSASSOPassword

echo "Waiting for ${VCSAIPAddress} hostd ..."
while true; do
	if govc about 2>/dev/null; then
    		break
  	fi
  printf "."
  sleep 2
done
rm -f vcenter.${VCSADisplayName}.json
