#!/bin/busybox sh

# activate: replace target of symlinks
cd /boot/common-ipxe/
ln -sf start-generic-nbfs.ipxe start-generic.ipxe
cd /boot/common-rpi/
ln -sf start-nbfs.uboot start.uboot
