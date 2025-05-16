#!/bin/busybox sh

# activate: replace target of cmdline.txt symlink
cd /boot/common-rpi/
ln -sf cmdline-nbfs.txt cmdline.txt
