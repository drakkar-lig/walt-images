ARG ALPINE_VERSION
FROM debian:stretch as builder

# builder image
# *************
# For now this is only used to build a linux kernel and associated modules
# for qemu-arm-32 and qemu-arm-64 walt nodes.
ENV RPI_VIRT_KERNEL_ARCHIVE="https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.10.61.tar.xz"

# setup package management
RUN echo deb http://deb.debian.org/debian stretch-backports main >> \
            /etc/apt/sources.list.d/backports.list && \
    echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

# install packages
RUN apt-get update && apt-get upgrade -y && apt-get install -y \
    vim net-tools procps subversion make gcc g++ libncurses5-dev bzip2 \
    wget cpio python unzip bc kpartx dosfstools debootstrap debian-archive-keyring \
    git flex bison pkg-config zlib1g-dev libglib2.0-dev \
    libpixman-1-dev gcc-arm-linux-gnueabi gcc-aarch64-linux-gnu libssl-dev kmod \
    dpkg-dev debhelper bash-completion shellcheck rdfind && \
    apt-get clean

# download and build a linux kernel compatible with qemu arm 'virt' machine
WORKDIR /root
RUN wget -O /tmp/linux.tar.xz $RPI_VIRT_KERNEL_ARCHIVE && \
    tar xf /tmp/linux.tar.xz && rm /tmp/linux.tar.xz
RUN mv linux-* linux
RUN mkdir /rpi_fs
WORKDIR /root/linux

# 32-bit version
ENV ARCH=arm
ENV CROSS_COMPILE=arm-linux-gnueabi-
ADD rpi/linux-arm32.config .config
RUN make olddefconfig && make -j
RUN make modules_install INSTALL_MOD_PATH=/rpi_fs
RUN mkdir -p /rpi_fs/boot/qemu-arm-32 && \
    cp arch/arm/boot/zImage /rpi_fs/boot/qemu-arm-32/kernel
RUN cp include/config/kernel.release /rpi_fs/boot/qemu-arm-32/

# 64-bit version
# note: for now there is no built-in decompressor for arm64,
# thus we deploy a plain Image.
ENV ARCH=arm64
ENV CROSS_COMPILE=aarch64-linux-gnu-
ADD rpi/linux-arm64.config .config
RUN make olddefconfig && make -j
RUN make modules_install INSTALL_MOD_PATH=/rpi_fs
RUN mkdir -p /rpi_fs/boot/qemu-arm-64 && \
    cp arch/arm64/boot/Image /rpi_fs/boot/qemu-arm-64/kernel
RUN cp include/config/kernel.release /rpi_fs/boot/qemu-arm-64/

# add various overlays
COPY overlays/generic overlays/ipxe overlays/rpi /rpi_fs/

# add a copy of SD-card boot files
# (needed to allow rpi3+ and later to boot without a SD card)
COPY --from=waltplatform/rpi-boot-builder /opt/boot_files /rpi_fs/boot/common-rpi/sd-card

# Target image
# ------------
FROM --platform=linux/arm/v6 arm32v6/alpine:${ALPINE_VERSION}

# specify which node models this image can handle
LABEL walt.node.models=rpi-b,rpi-b-plus,rpi-2-b,rpi-3-b,rpi-3-b-plus,rpi-4-b,qemu-arm-32,qemu-arm-64

# specify min walt server version needed
LABEL walt.server.minversion=5

# prepare and run customization
COPY --from=builder /rpi_fs /
RUN /root/customize.sh rpi
