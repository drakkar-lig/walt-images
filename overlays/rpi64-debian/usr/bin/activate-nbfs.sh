#!/bin/busybox sh

# activate nbfs:
# replace targets of cmdline.txt and boot.img symlinks
cd /boot/common-rpi/
ln -sf cmdline-nbfs.txt cmdline.txt
cd /boot/rpi-5-b/
ln -sf boot-nbfs.img boot.img
