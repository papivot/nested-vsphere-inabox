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
export GOVC_RESOURCE_POOL=$VMCluster

guest=${GUEST:-"vmkernel7Guest"}

echo "Starting Nested ESXi deployment loop..."
echo
for i in "${!NestedESXiHostname[@]}"; do
	export esxi_name=${NestedESXiHostname[$i]}
	export esxi_ip=${NestedESXiIPs[$i]}
  	envsubst < ../config/esxi.template.json > esxi.${NestedESXiHostname[$i]}.json

	echo "Creating VM ${NestedESXiHostname[$i]}..."
	govc import.ova --options=esxi.${NestedESXiHostname[$i]}.json --name=${NestedESXiHostname[$i]} -ds=${VMDatastore} ${NestedESXiApplianceOVA}

	echo "Updating VM ${NestedESXiHostname[$i]} with config values provided ..."
	govc vm.change --c=${NestedESXivCPU} --m=${NestedESXivMEM} -g=${guest} --vm ${NestedESXiHostname[$i]}
#	govc vm.network.add --net.adapter=vmxnet3 --net=${NestedESXiNetwork1} --vm ${NestedESXiHostname[$i]}
#	govc vm.network.add --net.adapter=vmxnet3 --net=${NestedESXiNetwork2} --vm ${NestedESXiHostname[$i]}
#	govc vm.change -e ethernet2.filter4.name=dvfilter-maclearn -e ethernet2.filter4.onFailure=failOpen --vm ${NestedESXiHostname[$i]}
#	govc vm.change -e ethernet3.filter4.name=dvfilter-maclearn -e ethernet3.filter4.onFailure=failOpen --vm ${NestedESXiHostname[$i]}

	echo "Upgrading HW version of VM ${NestedESXiHostname[$i]} ..."
	govc vm.upgrade --vm ${NestedESXiHostname[$i]}

	echo "Updating vApp sepcific infrormation for VM ${NestedESXiHostname[$i]} ..."
	govc vm.change -e guestinfo.hostname=${NestedESXiHostname[$i]} -e guestinfo.ipaddress=${NestedESXiIPs[$i]} -e guestinfo.netmask=${VMNetmask} -e guestinfo.gateway=${VMGateway} --vm ${NestedESXiHostname[$i]}
	govc vm.change -e guestinfo.dns=${VMDNS} -e guestinfo.domain=${VMDomain} -e guestinfo.ntp=${VMNTP} -e guestinfo.syslog=${VMSyslog} --vm ${NestedESXiHostname[$i]}
	govc vm.change -e guestinfo.password=${VMPassword} -e guestinfo.ssh=True -e guestinfo.createvmfs=False --vm ${NestedESXiHostname[$i]}

	echo "Powering on VM ${NestedESXiHostname[$i]} ..."
	govc vm.power -on ${NestedESXiHostname[$i]}
	rm esxi.${NestedESXiHostname[$i]}.json
	echo
done

echo "Waiting Nested ESXi hostd process to start..."
echo
for i in "${!NestedESXiHostname[@]}"; do

	GOVC_URL=${NestedESXiIPs[$i]}
	GOVC_USERNAME="root"
	GOVC_PASSWORD=$VMPassword

	echo "Waiting for ${NestedESXiHostname[$i]} hostd via ${GOVC_URL} ..."
	while true; do
  		if govc about 2>/dev/null; then
    			break
  		fi
  		printf "."
  		sleep 2
	done
done

echo
echo "Sleeping for 1 minute for things to stablize..."
echo
sleep 60

echo "Creating VSAN disks after Nested ESXi have been powered on ..."
echo
for i in "${!NestedESXiHostname[@]}"; do
	GOVC_URL=$VIServer
	GOVC_USERNAME=$VIUsername
	GOVC_PASSWORD=$VIPassword
	echo "Creating disks on ${NestedESXiHostname[$i]} for use by vSAN ..."
  	govc vm.disk.change --disk.filePath="[${GOVC_DATASTORE}] ${NestedESXiHostname[$i]}/${NestedESXiHostname[$i]}_1.vmdk" --size=${NestedESXiCachingvDisk}G --vm ${NestedESXiHostname[$i]}
  	govc vm.disk.change --disk.filePath="[${GOVC_DATASTORE}] ${NestedESXiHostname[$i]}/${NestedESXiHostname[$i]}_2.vmdk" --size=${NestedESXiCapacityvDisk}G --vm ${NestedESXiHostname[$i]}
done

echo
echo "Completing Configurations on Nested ESXi hosts..."
echo
for i in "${!NestedESXiHostname[@]}"; do

        GOVC_URL=${NestedESXiIPs[$i]}
        GOVC_USERNAME="root"
        GOVC_PASSWORD=$VMPassword
	GOVC_DATACENTER=""
	GOVC_RESOURCE_POOL=""
  	echo "Rescanning ${NestedESXiHostname[$i]} HBA for new devices..."
  	disk=($(govc host.storage.info -rescan | grep /vmfs/devices/disks | awk '{print $1}' | sort))

	echo "Configuring NTP for ${NestedESXiHostname[$i]} ..."
	govc host.date.change -server ${VMNTP}

	for id in TSM TSM-SSH ntpd ; do
  		printf "Enabling service %s for ${NestedESXiHostname[$i]} ...\n" $id
  		govc host.service enable $id
  		govc host.service start $id
	done

	echo "Disabling VSAN device monitoring for ${NestedESXiHostname[$i]} ..."
	govc host.esxcli system settings advanced set -o /LSOM/VSANDeviceMonitoring -i 0
	# A setting of 1 means that vSwp files are created thin, with 0% Object Space Reservation
	govc host.esxcli system settings advanced set -o /VSAN/SwapThickProvisionDisabled -i 1
	govc host.esxcli system settings advanced set -o /VSAN/FakeSCSIReservations -i 1
	govc host.esxcli system settings advanced set -o /UserVars/SuppressCoredumpWarning -i 1

	echo "Setting hostname for ${NestedESXiHostname[$i]} ..."
	govc host.esxcli system hostname set -H ${NestedESXiHostname[$i]}.${VMDomain}

	echo "Done with ${NestedESXiHostname[$i]} !!"
	echo
done
