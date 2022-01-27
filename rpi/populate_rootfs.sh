#!/bin/sh

RPI_DEBIAN_MIRROR_URL="http://mirrordirector.raspbian.org/raspbian"
RPI_DEBIAN_SECTIONS="main contrib rpi"

os_type="$1"
os_version="$2"

populate_rootfs_debian() {
    cd /rpi_fs; tar cfz ../rpi_fs_orig.tar.gz .; cd ..; rm -rf /rpi_fs
    
    # populate target os filesystem
    debootstrap --no-check-gpg --arch=armhf --foreign --variant=minbase \
        --include raspbian-archive-keyring,apt-utils \
        $os_version "/rpi_fs" $RPI_DEBIAN_MIRROR_URL
    echo "rpi-debian" > /rpi_fs/etc/hostname
    echo deb $RPI_DEBIAN_MIRROR_URL $os_version $RPI_DEBIAN_SECTIONS \
            > "/rpi_fs/etc/apt/sources.list.saved" && \
        echo deb http://archive.raspberrypi.org/debian/ $os_version main \
            >> "/rpi_fs/etc/apt/sources.list.saved"

    cd /rpi_fs; tar xfz ../rpi_fs_orig.tar.gz; rm ../rpi_fs_orig.tar.gz 
}

case "$os_type" in
    "alpine")
        # nothing to do, we will init the fs from
        # official alpine image
        ;;
    "debian")
        # we initiate the fs using debootstrap
        populate_rootfs_debian
        ;;
esac
