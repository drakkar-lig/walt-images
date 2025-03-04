# arguments needed in FROM statements
ARG OS_TYPE
ARG OS_VERSION

FROM debian:bullseye as builder

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
    wget cpio python unzip bc kpartx dosfstools debootstrap debian-archive-keyring \
    git flex bison pkg-config zlib1g-dev libglib2.0-dev \
    libpixman-1-dev gcc-arm-linux-gnueabi gcc-aarch64-linux-gnu libssl-dev kmod \
    dpkg-dev debhelper bash-completion shellcheck rdfind && \
    apt-get clean

# get and run script to populate rootfs
COPY base/common/populate_rpi_rootfs.sh /root
RUN nice /root/populate_rpi_rootfs.sh ${OS_TYPE} ${OS_VERSION} armhf

# add various overlays
COPY overlays/generic overlays/${OS_TYPE} \
     overlays/rpi overlays/mount.nbfs.armhf \
     overlays/rpi32 overlays/rpi32-${OS_TYPE} /rpi_fs/

# add a copy of SD-card boot files
# (needed to allow rpi3+ and later to boot without a SD card)
COPY --from=waltplatform/rpi-boot-builder \
            /opt/boot_files/cmdline.txt \
            /opt/boot_files/config.txt \
            /opt/boot_files/u-boot-rpi-3-b.img \
            /opt/boot_files/u-boot-rpi-4-b.img \
    /rpi_fs/boot/common-rpi/
# when using firmware network boot (boot without a SD card), dtb will be loaded
# directly by firmware, and u-boot should not make a new TFTP request for it.
# the firmware-provided dtb has custom modifications that u-boot cannot apply
# when loading another dtb, thus bypassing this secondary dtb loading preserves
# us from problems.
RUN sed -i -e "s/$/ u-boot:preserve_dtb/" /rpi_fs/boot/common-rpi/cmdline.txt

# Target image
# ------------
# we consider the official arm32v6 alpine image is suitable
# for raspberry pi boards
FROM --platform=linux/arm/v6 arm32v6/alpine:${OS_VERSION}
ARG KERNEL_VERSION

# specify which node models this image can handle
# unfortunately this official alpine image provides no kernel for the rpi4 board,
# so model rpi-4-b is excluded from our models.
# (linux-rpi2 packages used for models 2 & 3 works but we miss the
# broadcom genet ethernet driver.)
# future work: if building from aarch64 version, we could make an image
# for models rpi3b, rpi3b+ and rpi4b & rpi400.
LABEL walt.node.models=rpi-b,rpi-b-plus,rpi-2-b,rpi-3-b,rpi-3-b-plus

# specify min walt server version needed
LABEL walt.server.minversion=5

# prepare and run customization
COPY --from=builder /rpi_fs /
RUN nice /root/customize.sh rpi32 ${KERNEL_VERSION}

# set an entrypoint (handy when debugging)
ENTRYPOINT /bin/sh
