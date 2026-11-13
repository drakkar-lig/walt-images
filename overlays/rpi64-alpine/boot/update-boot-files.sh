#!/bin/sh
# rpi64-alpine: the firmware boots the kernel and initramfs directly
# (see common-rpi/config.txt), so there is nothing to generate here.
set -e
. /boot/update-boot-files-functions.sh

# Check boot files (no broken symlinks)
check_boot_files
