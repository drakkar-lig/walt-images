#!/bin/sh
set -e

# Raspberry Pi OS is based on two apt repositories:
# - the debian repository for the architecture (official debian for arm64,
#   raspbian for armhf)
# - the archive.raspberrypi.com repository, with rpi-specific packages
#   (kernel, firmware, etc.)
# debootstrap can only handle the first one, so we just prepare the apt
# configuration for the second one here.
# The signing key of archive.raspberrypi.com is provided by the overlay
# "rpi-debian" (file etc/apt/trusted.gpg.d/raspberrypi-archive-bootstrap.asc).
# This allows customize.sh to install package "raspberrypi-archive-keyring",
# which then takes over the management of this key.
RPIOS32_DEBIAN_MIRROR_URL="http://raspbian.raspberrypi.com/raspbian/"
RPIOS64_DEBIAN_MIRROR_URL="http://deb.debian.org/debian/"
RPIOS64_DEBIAN_SECURITY_MIRROR_URL="http://deb.debian.org/debian-security/"
RPIORG_DEBIAN_MIRROR_URL="http://archive.raspberrypi.com/debian/"

RPIOS32_DEBIAN_SECTIONS="main contrib rpi"
RPIOS64_DEBIAN_SECTIONS="main contrib non-free non-free-firmware"

os_type="$1"
os_version="$2"
arch="$3"

sources_dir="/rpi_fs/etc/apt/sources.list.d"

populate_rootfs_debian() {
    if [ "${arch}" = "armhf" ]
    then
        # the raspbian keyring is not available in the builder
        # (debian) image, so we cannot verify signatures here.
        gpg_opt="--no-check-gpg"
        keyring=raspbian-archive-keyring
        mirror_url="$RPIOS32_DEBIAN_MIRROR_URL"
    elif [ "${arch}" = "arm64" ]
    then
        # debian-archive-keyring is installed in the builder image
        gpg_opt=""
        keyring=debian-archive-keyring
        mirror_url="$RPIOS64_DEBIAN_MIRROR_URL"
    else
        echo "unexpected arch '${arch}'" >&2
        exit 1
    fi

    # populate target os filesystem
    debootstrap $gpg_opt --arch=${arch} --foreign \
        --variant=minbase \
        --include ${keyring},apt-utils \
        $os_version "/rpi_fs" $mirror_url
    # ensure /proc is a directory, not a symlink to the host /proc...
    [ -L /rpi_fs/proc ] && rm /rpi_fs/proc && mkdir /rpi_fs/proc

    # set an hostname
    echo "rpi-debian" > /rpi_fs/etc/hostname

    # prepare apt repository definitions (deb822 format)
    # note: customize.sh will remove /etc/apt/sources.list written
    # by debootstrap.
    mkdir -p "$sources_dir"
    if [ "${arch}" = "armhf" ]
    then
        # note: the image also uses the arm64 architecture for the 64-bit
        # kernel of rpi-4-b and rpi-400 (see customize.sh), which is
        # available in the archive.raspberrypi.com repository only.
        cat > "$sources_dir/raspbian.sources" << EOF
Types: deb
URIs: $RPIOS32_DEBIAN_MIRROR_URL
Suites: $os_version
Components: $RPIOS32_DEBIAN_SECTIONS
Architectures: armhf
EOF
    else
        cat > "$sources_dir/debian.sources" << EOF
Types: deb
URIs: $RPIOS64_DEBIAN_MIRROR_URL
Suites: $os_version $os_version-updates
Components: $RPIOS64_DEBIAN_SECTIONS
Signed-By: /usr/share/keyrings/debian-archive-keyring.pgp

Types: deb
URIs: $RPIOS64_DEBIAN_SECURITY_MIRROR_URL
Suites: $os_version-security
Components: $RPIOS64_DEBIAN_SECTIONS
Signed-By: /usr/share/keyrings/debian-archive-keyring.pgp
EOF
    fi
    cat > "$sources_dir/raspi.sources" << EOF
Types: deb
URIs: $RPIORG_DEBIAN_MIRROR_URL
Suites: $os_version
Components: main
EOF
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
