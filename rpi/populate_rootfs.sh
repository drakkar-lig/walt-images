#!/bin/sh

RPI_DEBIAN_MIRROR_URL="http://mirrordirector.raspbian.org/raspbian"
RPI_DEBIAN_SECTIONS="main contrib rpi"

os_type="$1"
os_version="$2"

populate_rootfs_debian() {
    # populate target os filesystem
    debootstrap --no-merged-usr --no-check-gpg --arch=armhf --foreign \
        --variant=minbase \
        --include raspbian-archive-keyring,apt-utils \
        $os_version "/rpi_fs" $RPI_DEBIAN_MIRROR_URL
    # ensure /proc is a directory, not a symlink to the host /proc...
    [ -L /rpi_fs/proc ] && rm /rpi_fs/proc && mkdir /rpi_fs/proc

    # set an hostname
    echo "rpi-debian" > /rpi_fs/etc/hostname

    # prepare apt repository definitions
    echo deb $RPI_DEBIAN_MIRROR_URL $os_version $RPI_DEBIAN_SECTIONS \
            > "/rpi_fs/etc/apt/sources.list.saved" && \
        echo deb http://archive.raspberrypi.org/debian/ $os_version main \
            >> "/rpi_fs/etc/apt/sources.list.saved"
}

case "$os_type" in
    "alpine")
        # not much to do, we will later init the fs from
        # official alpine image
        mkdir /rpi_fs
        ;;
    "debian")
        # we initiate the fs using debootstrap
        populate_rootfs_debian
        ;;
esac
