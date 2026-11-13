#!/bin/sh

# activate nbfs (called by the walt server, see /etc/walt/image.spec):
# replace the target of the cmdline.txt symlink
cd /boot/common-rpi/
ln -sf cmdline-nbfs.txt cmdline.txt
