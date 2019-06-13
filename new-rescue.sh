#!/bin/bash

# Module : new-rescue.sh
# Author : Marcus Lachmanez (malachma@microsoft.com, Azure Linux Escalation Team), Sriharsha B S (sribs@microsoft.com, Azure Linux Escalation Team),  Dinesh Kumar Baskar (dibaskar@microsoft.com, Azure Linux Escalation Team)
# Date : 13th August 2018
# Description : BASH form of New-AzureRMRescueVM powershell command.

help="\n
========================================================================================\n
new-rescue.sh --> BASH form of New-AzureRMRescueVM powershell command.\n
========================================================================================\n\n\n

========================================================================================\n
Disclaimer\n
========================================================================================\n\n
Do not use this script on an Encrypted VM. This script does not store the encrypted settings.
\n\n\n

========================================================================================\n
Description\n
========================================================================================\n\n
You may run this script if you may require a temporary (Rescue VM) for troubleshooting of the OS Disk.\n
This Script Performs the following operation :\n
1. Stop and Deallocate the Problematic Original VM\n
2. Make a OS Disk Copy of the Original Problematic VM depending on the type of Disks\n
3. Create a Rescue VM (based on the Original VM's Distribution and SKU) and attach the OS Disk copy to the Rescue VM\n
4. Start the Rescue VM for troubleshooting.\n\n\n

=========================================================================================\n
Arguments and Usage\n
=========================================================================================\n\n
All the arguments are mandatory. However, arguments may be passed in any order\n
1. --rescue-vm-name : Name of the Rescue VM Name\n
2. -u or --username : Rescue VM's Username\n
3. -g or --resource-group : Problematic Original VM's Resource Group\n
4. -n or --name : Problematic Original VM\n
5. -p or --password : Rescue VM's Password\n
6. -s or --subscription : Subscription Id where the respective resources are present.\n\n

Usage Example: ./new-rescue.sh --recue-vm-name debianRescue -g debian -n debian9 -s  xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx -u sribs -p Welcome@1234\n\n\n
"

POSITIONAL=()
echo $#
if [[ $# -ne 12 ]]
then
    echo -e $help
    exit;
fi
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -g|--resource-group)
    g="$2"
    shift # past argument
    shift # past value
    ;;
    -n|--name)
    vm="$2"
    shift # past argument
    shift # past value
    ;;
    -s|--subscription)
    subscription="$2"
    shift # past argument
    shift # past value
    ;;
    -u|--username)
    user="$2"
    shift # past argument
    shift # past value
    ;;
    --rescue-vm-name)
    rn="$2"
    shift # past argument
    shift
    ;;
    -p|--password)
    password="$2"
    shift # past argument
    shift
    ;;
    *)    # unknown option
    echo -e $help
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    exit;
    ;;
esac
done

# Check whether user has an azure account
acc=$(az account show)
echo $acc
if [[ -z $acc ]]
then
    echo "Please login using az login command"
    exit;
fi

# Check if user has a valid azure subscription. If yes, select the subscription as the default subscription
subvalid=$(az account list | jq ".[].id" | grep -i $subscription)
if [[ $(echo "${subvalid//\"}") != "$subscription" || -z $subvalid ]]
then
    echo "No Subscription $subscription exists"
    exit;
fi
az account set --subscription $subscription

vm_details=$(az vm show -g $g -n $vm)
location=$(echo $vm_details | jq '.location' | tr -d '"')

echo "Stopping and deallocating the Problematic Original VM"
az vm deallocate -g $g -n $vm 2>&1 > /dev/null
echo "VM is stopped" 

os_disk=$(echo $vm_details| jq ".storageProfile.osDisk")
managed=$(echo $os_disk | jq ".managedDisk")
offer=$(echo $vm_details | jq ".storageProfile.imageReference.offer")
publisher=$(echo $vm_details | jq ".storageProfile.imageReference.publisher")
sku=$(echo $vm_details | jq ".storageProfile.imageReference.sku")
version=$(echo $vm_details | jq ".storageProfile.imageReference.version")

urn=$(echo "${publisher//\"}:${offer//\"}:${sku//\"}:${version//\"}")
disk_uri="null"
resource_group=$g

if [[ $managed -eq "null" ]]    
then
    disk_uri=$(echo $os_disk | jq ".vhd.uri")
    disk_uri=$(echo "${disk_uri//\"}")

    #see http://mywiki.wooledge.org/BashFAQ/073 for further information about the next lines
    original_disk_name=${disk_uri##*/}
    original_disk_name=${original_disk_name%.*}  
    target_disk_name=$original_disk_name-copy

    storage_account=${disk_uri%%.*} 
    storage_account=${storage_account#*//}

    echo "creating a copy of the OS disk"
    az storage blob copy start --destination-blob $target_disk_name.vhd --destination-container vhds --account-name $storage_account --source-uri $disk_uri 2>&1 > recover.log


    echo "Creating the rescue VM $rn"
    az vm create --use-unmanaged-disk --name $rn -g $g --location $location --admin-username $user --admin-password $password --image $urn --storage-sku Standard_LRS 2>&1 > recover.log 
    echo "New VM is created"

    echo "Attach the OS-Disk copy to the rescue VM:$rn"
    az vm unmanaged-disk attach --vm-name $rn -g $g --name origin-os-disk  --vhd-uri "https://$storage_account.blob.core.windows.net/vhds/$target_disk_name.vhd" 2>&1 > recover.log

else
    disk_uri=$(echo $os_disk | jq ".managedDisk.id")
    disk_uri=$(echo "${disk_uri//\"}")
    echo "##### Generatnig Snapshot #######"
    source_disk_name=`echo $disk_uri | awk -F"/" '{print $NF}'`
    snapshot_name="`echo $disk_uri | awk -F"/" '{print $NF}' | sed 's/_/-/g'`-`date +%d-%m-%Y-%T | sed 's/:/-/g'`"
    target_disk_name="`echo $disk_uri | awk -F"/" '{print $NF}'`-copy-`date +%d-%m-%Y-%T | sed 's/:/-/g'`"
    az snapshot create -g $resource_group -n $snapshot_name --source $source_disk_name -l $location

    echo "##### Creating Disk from Snapshot #######"

    snapshotId=$(az snapshot show --name $snapshot_name --resource-group $resource_group --query [id] -o tsv)
    az disk create --resource-group $resource_group --name $target_disk_name -l $location --sku Standard_LRS --source $snapshotId

    az vm create --name $rn -g $g --location $location --admin-username $user --admin-password $password --image $urn --storage-sku Standard_LRS
    az vm disk attach -g $g --vm-name $rn --disk  $target_disk_name
fi
 
#
# Execute a specific task
#
echo "Fixing the issue on the OS-Disk copy"
az vm extension set --resource-group $g   --vm-name $rn --name customScript   --publisher Microsoft.Azure.Extensions   --settings ./script.json 2>&1 > recover.log

source my-restore-original.sh
