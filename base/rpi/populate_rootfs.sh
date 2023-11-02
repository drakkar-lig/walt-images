#!/bin/sh

# fast repository which will speedup the image build
RPIOS_DEBIAN_MIRROR_URL_FAST="https://ftp.halifax.rwth-aachen.de/raspbian/raspbian"
RPIORG_DEBIAN_MIRROR_URL_FAST="https://ftp.halifax.rwth-aachen.de/raspberrypi/"
# official repositories which will be restored at the end of image build
RPIOS_DEBIAN_MIRROR_URL_OFFICIAL="http://mirrordirector.raspbian.org/raspbian"
RPIORG_DEBIAN_MIRROR_URL_OFFICIAL="http://archive.raspberrypi.org/debian/"

RPIOS_DEBIAN_SECTIONS="main contrib rpi"

os_type="$1"
os_version="$2"

populate_rootfs_debian() {
    # populate target os filesystem
    debootstrap --no-check-gpg --arch=armhf --foreign \
        --variant=minbase \
        --include raspbian-archive-keyring,apt-utils \
        $os_version "/rpi_fs" $RPIOS_DEBIAN_MIRROR_URL_FAST
    # ensure /proc is a directory, not a symlink to the host /proc...
    [ -L /rpi_fs/proc ] && rm /rpi_fs/proc && mkdir /rpi_fs/proc

    # set an hostname
    echo "rpi-debian" > /rpi_fs/etc/hostname

    # prepare apt repository definitions
    echo deb $RPIOS_DEBIAN_MIRROR_URL_FAST $os_version $RPIOS_DEBIAN_SECTIONS \
            > "/rpi_fs/etc/apt/sources.list.fast" && \
    echo deb $RPIORG_DEBIAN_MIRROR_URL_FAST $os_version main \
            >> "/rpi_fs/etc/apt/sources.list.fast"
    echo deb $RPIOS_DEBIAN_MIRROR_URL_OFFICIAL $os_version $RPIOS_DEBIAN_SECTIONS \
            > "/rpi_fs/etc/apt/sources.list.official" && \
    echo deb $RPIORG_DEBIAN_MIRROR_URL_OFFICIAL $os_version main \
            >> "/rpi_fs/etc/apt/sources.list.official"
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
