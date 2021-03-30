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

echo "Creating datacenter $NewVCDatacenterName ..."
govc datacenter.create $NewVCDatacenterName

echo "Creating cluster $NewVCVSANClusterName ..."
govc cluster.create $NewVCVSANClusterName

echo "Enable HA, DRS and VSAN on $NewVCVSANClusterName ..."
govc cluster.change -drs-enabled -vsan-enabled -ha-enabled $NewVCVSANClusterName

echo
echo "Creating dvs $NewVCVDSName ..."
govc dvs.create -product-version 7.0.0 -mtu 1600 $NewVCVDSName
govc dvs.portgroup.add -dvs ${NewVCVDSName} -type earlyBinding -nports 16 ${NewVCDVPGName}

echo
echo "Creating dvs $NewVCVDSName1 ..."
govc dvs.create -product-version 7.0.0 -mtu 1600  ${NewVCVDSName1}
govc dvs.portgroup.add -dvs $NewVCVDSName1 -type earlyBinding -nports 16 $NewVCDVPGName1

echo
echo "Creating dvs $NewVCVDSName2 ..."
govc dvs.create -product-version 7.0.0 -mtu 1600  $NewVCVDSName2
govc dvs.portgroup.add -dvs $NewVCVDSName2 -type earlyBinding -nports 16 $NewVCDVPGName2

for i in "${!NestedESXiHostname[@]}"; do
	echo
	echo "Adding Host ${NestedESXiHostname[$i]} to $NewVCVSANClusterName ..."
	govc cluster.add -noverify -force -hostname ${NestedESXiHostname[$i]}.${VMDomain} -username root -password ${VMPassword}
	govc dvs.add -dvs ${NewVCVDSName} -pnic vmnic1 ${NestedESXiHostname[$i]}.${VMDomain}
	govc dvs.add -dvs ${NewVCVDSName1} -pnic vmnic2 ${NestedESXiHostname[$i]}.${VMDomain}
	govc dvs.add -dvs ${NewVCVDSName2} -pnic vmnic3 ${NestedESXiHostname[$i]}.${VMDomain}
	govc host.vnic.service -host ${NestedESXiHostname[$i]}.${VMDomain} -enable vsan vmk0
  	govc host.vnic.service -host ${NestedESXiHostname[$i]}.${VMDomain} -enable vmotion vmk0

	disks=(`govc host.storage.info -host=${NestedESXiHostname[$i]}.${VMDomain} | grep disk | sort |awk '{print $1}'`)
        size=(`govc host.storage.info -host=${NestedESXiHostname[$i]}.${VMDomain}  | grep disk | sort |awk '{print $3}' | cut -d. -f1`)
        for j in "${!disks[@]}"; do
                if [ ${size[$j]} = $NestedESXiCachingvDisk ] ; then
                        cachedisk=`echo ${disks[$j]}|cut -d/ -f5-`
                elif [ ${size[$j]} = $NestedESXiCapacityvDisk ]; then
                        datadisk=`echo ${disks[$j]}|cut -d/ -f5-`
                fi
        done

        echo "Configuring VSAN storage on host - ${NestedESXiHostname[$i]}.${VMDomain} using Cache disk: $cachedisk and Data disk: $datadisk..."
        govc host.esxcli -host=${NestedESXiHostname[$i]}.${VMDomain} vsan storage tag add -d $datadisk -t capacityFlash
        govc host.esxcli -host=${NestedESXiHostname[$i]}.${VMDomain} vsan storage add -s $cachedisk -d $datadisk
done

echo
echo "Creating Storage Policy on vCenter ..."

# Does not work.. needs fixing.
#govc tags.category.create -d "Default tag for WCP storage" -t Datastore pacific-tag-catagory
#govc tags.create -d "Default tag for WCP storage" -c pacific-tag-catagory pacific-storage-tag
#govc tags.attach -c pacific-tag-catagory pacific-storage-tag /${GOVC_DATACENTER}/datastore/${GOVC_DATASTORE}
#govc storage.policy.create -category pacific-tag-catagory -tag pacific-tag-catagory pacific-gold-storage-policy

echo "Creating WCP Content Library on vCenter ..."
govc library.create -sub=https://wp-content.vmware.com/v2/latest/lib.json  -sub-ondemand=true Kubernetes
