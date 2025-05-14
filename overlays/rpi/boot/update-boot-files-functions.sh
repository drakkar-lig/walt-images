#!/bin/sh

outdated() {
    dst="$1"
    shift
    if [ ! -e "$dst" ]
    then
        return 0   # yes, rebuild
    elif [ "$(find -L "$@" -newer "$dst" | wc -l)" -gt 0 ]
    then
        return 0   # yes, rebuild
    else
        return 1   # no, we're up-to-date
    fi
}

get_kernel_version_from_extension() {
    ext="$1"
    # we may have for instance extensions "+" and "-v7+", thus looking
    # for entries ending with "+" is not enough, and that's why we
    # return the shortest matching entry.
    cd /lib/modules
    ls -1 | grep -- "$ext$" | awk '{ print length, $0 }' | sort -n | \
        cut -d" " -f2 | head -n 1
}

check_boot_files() {
    # The file tree at /boot is very complex, with files coming from different
    # sources ([repo_dir]/overlays/<overlay>, 'raspberrypi-bootloader' package,
    # file copies from 'waltplatform/rpi-boot-builder' image, files generated
    # by this script) and many cross-references using symlinks. The existence
    # of broken symlinks is a good sign of an issue, so let's check that.
    if [ $(find /boot -xtype l | wc -l) -ne 0 ]
    then
        echo "Issue detected in /boot. Found the following broken symlinks:"
        find /boot -xtype l
        exit 1
    fi
}
