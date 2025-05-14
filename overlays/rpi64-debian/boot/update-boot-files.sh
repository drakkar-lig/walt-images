#!/bin/sh
# vim:ts=2:sw=2:et

set -e

. /boot/update-boot-files-functions.sh

update_boot_img() {
    if [ -e "boot.img" ]
    then
        echo "Updating $PWD/boot.img"
    else
        echo "Creating $PWD/boot.img"
    fi
    megas="$(du -L -b -s -BM . --exclude=boot.img | sed -e "s/M.*$//")"
    megas=$((megas+2))  # margin of 2MB for the size of the FAT image
    if [ -e "boot.img" ]
    then
        cur_megas="$(du -L -b -s -BM boot.img | sed -e "s/M.*$//")"
        if [ "$cur_megas" != "$megas" ]
        then
            # the size of files changed significantly, rebuild
            rm boot.img
        fi
    fi
    if [ ! -e "boot.img" ]
    then
        dd count=0 seek=$megas bs=1M of=boot.img status=none
        mkfs.vfat -n WALT_VPN boot.img
    fi
    mcopy -o -i boot.img $(ls -I boot.img) ::
}

# Generate /boot/rpi-5-b/boot.img, used for HTTP boot (VPN)
# ---------------------------------------------------------
cd /boot/rpi-5-b/
if outdated boot.img $(ls -I boot.img)
then
    update_boot_img
fi

# Check boot files (no broken symlinks)
# -------------------------------------
check_boot_files
