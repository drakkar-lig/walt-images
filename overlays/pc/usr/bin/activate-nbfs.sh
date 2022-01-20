#!/bin/busybox sh

# activate: replace target of symlinks
cd /boot/common-ipxe/
ln -sf start-generic-nbfs.ipxe start-generic.ipxe
