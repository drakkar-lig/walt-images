#!/bin/sh
# vim:ts=2:sw=2:et

set -e

. /boot/update-boot-files-functions.sh

update_boot_img() {
    proto="$1"
    if [ -e "boot-${proto}.img" ]
    then
        echo "Updating $PWD/boot-${proto}.img"
    else
        echo "Creating $PWD/boot-${proto}.img"
    fi
    megas="$(du -L -b -s -BM . --exclude="boot*.img" | sed -e "s/M.*$//")"
    megas=$((megas+2))  # margin of 2MB for the size of the FAT image
    if [ -e "boot-${proto}.img" ]
    then
        cur_megas="$(du -L -b -s -BM boot-${proto}.img | sed -e "s/M.*$//")"
        if [ "$cur_megas" != "$megas" ]
        then
            # the size of files changed significantly, rebuild
            rm "boot-${proto}.img"
        fi
    fi
    if [ ! -e "boot-${proto}.img" ]
    then
        dd count=0 seek=$megas bs=1M of="boot-${proto}.img" status=none
        mkfs.vfat -n WALT_VPN "boot-${proto}.img"
    fi
    mcopy -o -i boot-${proto}.img $(ls -I "boot*.img") ::
}

# Generate /boot/rpi-5-b/boot-[nfs|nbfs].img, used for HTTP boot (VPN)
# --------------------------------------------------------------------
cd /boot/rpi-5-b/
# note: keep nfs as last protocol of the loop (it will be the default)
for proto in nbfs nfs
do
    ln -sf cmdline-${proto}.txt /boot/common-rpi/cmdline.txt
    if outdated boot-${proto}.img $(ls -I "boot*.img")
    then
        update_boot_img ${proto}
    fi
done

# Check boot files (no broken symlinks)
# -------------------------------------
check_boot_files
