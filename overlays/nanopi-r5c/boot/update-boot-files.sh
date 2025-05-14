#!/bin/sh
mkdir -p /boot/nanopi-r5c
cd /boot/nanopi-r5c
ln -sf ../*.dtb dtb
mkimage -A arm64 -T ramdisk -C none -n uInitrd -d ../initrd.* initrd
ln -sf ../vmlinuz* kernel
for proto in nfs nfs4 nbfs
do
    mkimage -A arm -O linux -T script -C none -n "start-${proto}.uboot" \
        -d start-uboot-${proto}.txt start-${proto}.uboot
done
if [ ! -e start.uboot ]
then
    ln -s start-nfs.uboot start.uboot   # default is nfs3
fi
