#!/bin/sh
THIS_DIR=$(dirname $0)
mkimage -A arm64 -O linux -T script -C none -n "start.uboot" \
        -d $THIS_DIR/start.uboot.txt "$THIS_DIR/start.uboot"


