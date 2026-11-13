# arguments needed in FROM statements
ARG OS_TYPE
ARG OS_VERSION

# Raspberry Pi boot files built by walt-node-boot (git submodule);
# build.py sets this argument (see get_rpi_boot_builder() there).
ARG RPI_BOOT_BUILDER
FROM ${RPI_BOOT_BUILDER} AS rpi-boot-files

FROM debian:trixie as builder

# arguments needed in image build steps
ARG OS_TYPE
ARG OS_VERSION
ARG KERNEL_VERSION
ARG KERNEL_ARCHIVE

# builder image
# *************

# setup package management
RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

# install packages
RUN apt-get update && apt-get upgrade -y && apt-get install -y \
    vim net-tools procps subversion make gcc g++ libncurses5-dev bzip2 \
    wget cpio python3 unzip bc kpartx dosfstools debootstrap debian-archive-keyring \
    git flex bison pkg-config zlib1g-dev libglib2.0-dev \
    libpixman-1-dev gcc-arm-linux-gnueabi gcc-aarch64-linux-gnu libssl-dev kmod \
    dpkg-dev debhelper bash-completion shellcheck rdfind && \
    apt-get clean

# get and run script to populate rootfs
COPY base/common/populate_rpi_rootfs.sh /root
RUN nice /root/populate_rpi_rootfs.sh ${OS_TYPE} ${OS_VERSION} armhf

# add various overlays
COPY overlays/generic overlays/${OS_TYPE} overlays/rpi \
     overlays/rpi-uboot overlays/rpi32-uboot overlays/mount.nbfs.armhf \
     overlays/rpi32-${OS_TYPE} /rpi_fs/

# add a copy of SD-card boot files
# (needed to allow rpi3+ and later to boot without a SD card)
COPY --from=rpi-boot-files \
            /opt/boot_files/cmdline.txt \
            /opt/boot_files/config.txt \
            /opt/boot_files/u-boot-rpi-3-b.img \
    /rpi_fs/boot/common-rpi/
# when using firmware network boot (boot without a SD card), dtb will be loaded
# directly by firmware, and u-boot should not make a new TFTP request for it.
# the firmware-provided dtb has custom modifications that u-boot cannot apply
# when loading another dtb, thus bypassing this secondary dtb loading preserves
# us from problems.
RUN sed -i -e "s/$/ u-boot:preserve_dtb/" /rpi_fs/boot/common-rpi/cmdline.txt

# Alpine base
# -----------
# we use the official armv7 alpine image.
# notes:
# * in recent alpine versions (checked with 3.24), a single kernel package "linux-rpi" is
#   available per architecture: the armhf (armv6) one only supports
#   the rpi 1 (B, B+), and the armv7 one supports models 2B, 3B and 3B+.
#   Both have the same kernel version string, so they cannot be installed
#   together, and we dropped the rpi 1 models.
# * the armv7 kernel lacks the ethernet driver of the rpi 4 (BCMGENET);
#   see rpi64-alpine for models 3B+, 4B and 5B.
# * the platform of this stage must be specified, otherwise docker looks
#   for a variant of the image for the build host platform (e.g.,
#   linux/amd64), and arm32v7/alpine has none. The target image retrieves
#   the content of this stage ("COPY --from=alpine_base / /"), so this
#   does not change the platform declared in the metadata of the final
#   image (see "Image architecture" in README.md).
FROM --platform=linux/arm/v7 arm32v7/alpine:${OS_VERSION} as alpine_base

# Target image
# ------------
FROM --platform=linux/arm/v7 scratch
ARG KERNEL_VERSION

# specify which node models this image can handle
LABEL walt.node.models=rpi-2-b,rpi-3-b,rpi-3-b-plus

# specify min walt server version needed
LABEL walt.server.minversion=5

# prepare and run customization
COPY --from=alpine_base / /
COPY --from=builder /rpi_fs /
RUN nice /root/customize.sh rpi32 ${KERNEL_VERSION}

# set an entrypoint (handy when debugging)
ENTRYPOINT /bin/sh
