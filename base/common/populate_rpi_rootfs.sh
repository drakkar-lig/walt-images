#!/bin/sh

# fast repository which will speedup the image build
RPIOS32_DEBIAN_MIRROR_URL_FAST="https://ftp.halifax.rwth-aachen.de/raspbian/raspbian"
RPIOS64_DEBIAN_MIRROR_URL_FAST="https://ftp.halifax.rwth-aachen.de/debian"
RPIORG_DEBIAN_MIRROR_URL_FAST="https://ftp.halifax.rwth-aachen.de/raspberrypi/"
# official repositories which will be restored at the end of image build
RPIOS32_DEBIAN_MIRROR_URL_OFFICIAL="http://mirrordirector.raspbian.org/raspbian"
RPIOS64_DEBIAN_MIRROR_URL_OFFICIAL="http://deb.debian.org/debian/"
RPIORG_DEBIAN_MIRROR_URL_OFFICIAL="http://archive.raspberrypi.org/debian/"

RPIOS32_DEBIAN_SECTIONS="main contrib rpi"
RPIOS64_DEBIAN_SECTIONS="main contrib non-free non-free-firmware"

os_type="$1"
os_version="$2"
arch="$3"

populate_rootfs_debian() {
    if [ "${arch}" = "armhf" ]
    then
        keyring=raspbian-archive-keyring
        mirror_url_fast="$RPIOS32_DEBIAN_MIRROR_URL_FAST"
        mirror_url_official="$RPIOS32_DEBIAN_MIRROR_URL_OFFICIAL"
        sections="$RPIOS32_DEBIAN_SECTIONS"
    elif [ "${arch}" = "arm64" ]
    then
        keyring=debian-archive-keyring
        mirror_url_fast="$RPIOS64_DEBIAN_MIRROR_URL_FAST"
        mirror_url_official="$RPIOS64_DEBIAN_MIRROR_URL_OFFICIAL"
        sections="$RPIOS64_DEBIAN_SECTIONS"
    else
        echo "unexpected arch '${arch}'" >&2
        exit 1
    fi
        
    # populate target os filesystem
    debootstrap --no-check-gpg --arch=${arch} --foreign \
        --variant=minbase \
        --include ${keyring},apt-utils \
        $os_version "/rpi_fs" $mirror_url_fast
    # ensure /proc is a directory, not a symlink to the host /proc...
    [ -L /rpi_fs/proc ] && rm /rpi_fs/proc && mkdir /rpi_fs/proc

    # set an hostname
    echo "rpi-debian" > /rpi_fs/etc/hostname

    # prepare apt repository definitions
    echo deb $mirror_url_fast $os_version $sections \
            > "/rpi_fs/etc/apt/sources.list.fast" && \
    echo deb $RPIORG_DEBIAN_MIRROR_URL_FAST $os_version main \
            >> "/rpi_fs/etc/apt/sources.list.fast"
    echo deb $mirror_url_official $os_version $sections \
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
