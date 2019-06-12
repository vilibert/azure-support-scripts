#!/bin/bash

#Discover the stucture of the os-data-disk
==========================================

#get boot flaged partition
#-------------------------
boot_part=$(fdisk -l /dev/sdc | awk '$2 ~ /\*/ {print $1}')

#get partitions of sdc
#---------------------
partitions=$(fdisk -l /dev/sdc | awk '/^\/dev\/sdc/ {print $1}')

#get the root partition
#-----------------------
rescue_root=$(echo $partitions | sed "s|$boot_part||g")



#Mount the root part
#====================

mkdir /mnt/rescue-root
mount -o nouuid $rescue_root /mnt/rescue-root

#Mount the boot part
#===================

mkdir /mnt/rescue-boot
mount -o nouuid $boot_part /mnt/rescue-boot



#Mount the support filesystems
#==============================
#see also http://linuxonazure.azurewebsites.net/linux-recovery-using-chroot-steps-to-recover-vms-that-are-not-accessible/

for i in dev proc sys dev/pts; do mount -o bind /$i /mnt/rescue-root/$i; done


#################################
# Fix the fstab to allow a boot #
#################################
chroot /mnt/rescue-root << EOF
mv -f /etc/fstab{,.copy}
cat /etc/fstab.copy | awk '/\/ /{print}' >> /etc/fstab
cat /etc/fstab.copy | awk '/\/boot /{print}' >> /etc/fstab
cat /etc/fstab
exit
EOF


#Clean up everything
for i in dev/pts proc sys dev; do umount  /mnt/rescue-root/$i; done

umount /mnt/rescue-boot
umount /mnt/rescue-root                                                                                                                                                                              
rm -fr /mnt/rescue-*







