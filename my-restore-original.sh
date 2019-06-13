

# get the OS disk uri for the problematic os disk from the Rescue VM which is currently attached to the rescue VM
datadisks=$(az vm show -g $g -n $rn | jq ".storageProfile.dataDisks")
managed=$(echo $datadisks | jq ".[0].managedDisk")
disk_uri="null"
disk_name="null"
if [[ $managed = "null" ]]
then
    disk_uri=$(echo $datadisks | jq ".[].vhd.uri" | sed s/\"//g)
    disk_name=$(az vm show -g $g -n $rn | jq ".storageProfile.dataDisks[0].name" | sed s/\"//g )

else
    disk_uri=$(echo $datadisks | jq ".[].managedDisk.id" | sed s/\"//g)
    disk_name=$(az vm show -g $g -n $rn | jq ".storageProfile.dataDisks[0].name" | sed s/\"//g )

fi


# Detach the Problematic OS disk from the Rescue VM
echo "Detaching the OS disk from the rescue VM"

if [[ $managed == "null" ]]
then
	az vm unmanaged-disk detach -g $g --vm-name $rn -n $disk_name 2>&1 > recover.log
else
	az vm disk detach -g $g --vm-name $rn -n $disk_name 2>&1 > recover.log
fi

# OS Disk Swap Procedure.
echo "Preparing for OS disk swap"
# Stop the Problematic VM
echo "Stopping and deallocating the Problematic Original VM"
az vm deallocate -g $g -n $vm 2>&1 > recover.log

# Perform the disk swap and verify
echo "Performing the OS disk Swap"


if [[ $managed == "null" ]]
then
#
# We do this for the unmanged VM via a break lease operation
#
az storage blob lease break -c vhds --account-name $storage_account -b $original_disk_name.vhd 2>&1 > recover.log
az storage blob copy start  -c vhds -b $original_disk_name.vhd --source-container vhds --source-blob $target_disk_name.vhd --account-name $storage_account 2>&1 > recover.log
else
    /bin/true
#swap=$(az vm update -g $g -n $vm --os-disk $(echo "${disk_uri//\"}") | jq ".storageProfile.osDisk.name")
#swap=$(az vm update -g $g -n $vm --os-disk $disk_uri)
fi

echo "Successfully swapped the OS disk. Now starting the Problematic VM with OS disk $swap"

# Start the Fixed VM after disk swap
az vm start -g $g -n $vm

echo "Start of the VM $vm Successful"
