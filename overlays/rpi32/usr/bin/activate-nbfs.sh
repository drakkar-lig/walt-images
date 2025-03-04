#!/bin/busybox sh

# activate: replace target of symlinks
cd /boot/common-rpi/
ln -sf start-nbfs.uboot start.uboot
