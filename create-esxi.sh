#!/bin/bash -e
set -o pipefail

source ./env.config

export GOVC_URL=$VIServer
export GOVC_USERNAME=$VIUsername
export GOVC_PASSWORD=$VIPassword
export GOVC_DATASTORE=$VMDatastore
export GOVC_NETWORK=$VMNetwork
export GOVC_INSECURE=true

guest=${GUEST:-"vmkernel7Guest"}

echo "Starting Nested ESXi deployment loop..."
echo
for i in "${!NestedESXiHostname[@]}"; do
	export esxi_name=${NestedESXiHostname[$i]}
	export esxi_ip=${NestedESXiIPs[$i]}
  	envsubst < esxi.template.json > esxi.${NestedESXiHostname[$i]}.json

	echo "Creating VM ${NestedESXiHostname[$i]}..."
	govc import.ova --options=esxi.${NestedESXiHostname[$i]}.json --name=${NestedESXiHostname[$i]} ${NestedESXiApplianceOVA}

	echo "Updating VM ${NestedESXiHostname[$i]} with config values provided ..."
	govc vm.change --c=${NestedESXivCPU} --m=${NestedESXivMEM} -g=${guest} --vm ${NestedESXiHostname[$i]}
	govc vm.network.add --net.adapter=vmxnet3 --net=${NestedESXiNetwork1} --vm ${NestedESXiHostname[$i]}
	govc vm.network.add --net.adapter=vmxnet3 --net=${NestedESXiNetwork2} --vm ${NestedESXiHostname[$i]}
	govc vm.change -e ethernet2.filter4.name=dvfilter-maclearn -e ethernet2.filter4.onFailure=failOpen --vm ${NestedESXiHostname[$i]}
	govc vm.change -e ethernet3.filter4.name=dvfilter-maclearn -e ethernet3.filter4.onFailure=failOpen --vm ${NestedESXiHostname[$i]}

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
  	govc vm.disk.change --disk.filePath="[${GOVC_DATASTORE}] ${NestedESXiHostname[$i]}/${NestedESXiHostname[$i]}_1.vmdk" --size=8G --vm ${NestedESXiHostname[$i]}
  	govc vm.disk.change --disk.filePath="[${GOVC_DATASTORE}] ${NestedESXiHostname[$i]}/${NestedESXiHostname[$i]}_2.vmdk" --size=140G --vm ${NestedESXiHostname[$i]}
done

echo
echo "Completing Configurations on Nested ESXi hosts..."
echo
for i in "${!NestedESXiHostname[@]}"; do

        GOVC_URL=${NestedESXiIPs[$i]}
        GOVC_USERNAME="root"
        GOVC_PASSWORD=$VMPassword
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

	#echo "Granting Admin permissions for user $username on ${name}..."
	#govc permissions.set -principal $username -role Admin

	echo "Enabling guest ARP inspection to get vm IPs without vmtools on ${NestedESXiHostname[$i]} ..."
	govc host.esxcli system settings advanced set -o /UserVars/SuppressCoredumpWarning -i 1
	#echo "Opening firewall for serial port traffic for ${name}..."
	#govc host.esxcli network firewall ruleset set -r remoteSerialPort -e true

	echo "Setting hostname for ${NestedESXiHostname[$i]} ..."
	govc host.esxcli system hostname set -H ${NestedESXiHostname[$i]}.${VMDomain}

	#echo "Enabling MOB for ${name}..."
	#govc host.option.set Config.HostAgent.plugins.solo.enableMob true

	echo "Done with ${NestedESXiHostname[$i]} !!"
	#unset GOVC_USERNAME GOVC_PASSWORD
	echo
done
