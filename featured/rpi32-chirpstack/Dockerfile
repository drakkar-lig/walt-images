# Step 1: build the root filesystem
# ---------------------------------
FROM debian:trixie as chirpstack-builder
ARG SRC_DIR="."
ARG MERGE_CONFIG_URL="https://raw.githubusercontent.com/u-boot/u-boot/refs/tags/v2025.10/scripts/kconfig/merge_config.sh"
ARG CS_GW_OS_GIT="https://github.com/chirpstack/chirpstack-gateway-os.git"
ARG CS_GW_OS_TAG="v4.9.0"

# -- Install the packages we need for this build step --
# mostly based on
# https://github.com/chirpstack/chirpstack-gateway-os/blob/master/Dockerfile-devel
RUN apt update && apt install -y \
        build-essential \
        ca-certificates \
        'clang' \
        'flex' \
        'bison' \
        'g++' \
        'gawk' \
        'gcc-multilib' \
        'g++-multilib' \
        'gettext' \
        'git' \
        'libncurses5-dev' \
        'libssl-dev' \
        'python3' \
        'python3-setuptools' \
        'rsync' \
        'unzip' \
        'zlib1g-dev' \
        'file' \
        'wget' \
        'quilt' \
        'vim' \
        'curl' \
        'cpio' \
        'zstd' \
        && rm -f -r '/var/lib/apt/' && \
        rm -f -r '/var/cache/apt/'

# -- Fetch everything we need for the build --
# 1. chirpstack-gateway-os github repo
RUN git clone "${CS_GW_OS_GIT}" /workdir
RUN cd /workdir && \
    git checkout -b "${CS_GW_OS_TAG}" "${CS_GW_OS_TAG}"
# 2. local files
COPY $SRC_DIR/build-files /build-files
# 3. a tool for merging openwrt config files
RUN wget -O /build-files/merge_config.sh ${MERGE_CONFIG_URL} && \
    chmod +x /build-files/merge_config.sh

# -- Compile chirpstack OS --
# chirpstack OS is openwrt + a few patches.
# 1. Prepare the build
WORKDIR /workdir

ARG QUILT_PATCHES="/workdir/conf/patches"
# adapted from <cs-os-gw>/Makefile init target
RUN git submodule init && \
    git submodule update && \
    cp feeds.conf.default openwrt/feeds.conf.default && \
    ln -s ../conf/files openwrt/files && \
    openwrt/scripts/feeds update -a && \
    openwrt/scripts/feeds install -a

# adapted from <cs-os-gw>/README.md
# and <cs-os-gw>/Makefile switch-env target
ARG ENV=full_raspberrypi_bcm27xx_bcm2709
RUN ln -sf ${ENV}/files conf/files && \
    ln -sf ${ENV}/patches conf/patches && \
    cp conf/${ENV}/.config openwrt/.config
RUN cd openwrt && quilt push -a

# 2. Update OpenWRT config and compile it
WORKDIR /workdir/openwrt
# File build-files/openwrt.config contains only the changes
# comparing to the default configuration. It has been generated
# by running:
# $ make menuconfig
# $ ./scripts/diffconfig.sh > openwrt.config
RUN /build-files/merge_config.sh -m .config \
       /build-files/openwrt.config && \
    make defconfig

# File build-files/kernel-config was obtained using this method:
# $ pwd
# /workdir/openwrt
# $ export FORCE_UNSAFE_CONFIGURE=1
# $ nice make -j$(nproc) kernel_menuconfig CONFIG_TARGET=env
# [...select additional kernel options...]
# $
# This generates the file at /workdir/openwrt/env/kernel-config.
#
# The additional options we selected are:
# * Initial RAM filesystem and RAM disk (initramfs/initrd) support
# * Support initial ramdisk/ramfs compressed using gzip
# * NFS v4.1 & v4.2 client filesystem versions
# * FUSE filesystem 
# * Support for exposing this kernel config at /proc/config.gz
RUN mkdir env
RUN cp /build-files/kernel-config env/

# When compiling openwrt as the "root" user,
# FORCE_UNSAFE_CONFIGURE=1 is needed.
ARG FORCE_UNSAFE_CONFIGURE=1
RUN /build-files/make.sh tools/compile
RUN [ ! -f .error_detected ]
RUN /build-files/make.sh download
RUN [ ! -f .error_detected ]
RUN /build-files/make.sh toolchain/compile
RUN [ ! -f .error_detected ]
RUN /build-files/make.sh world
RUN [ ! -f .error_detected ]

# 3. Create image root filesystem
RUN mkdir /image-rootfs
WORKDIR /image-rootfs
# The result of the openwrt build is an archive <arch>-rootfs.tar.gz.
# It contains the files contained on the 2nd partition of the generated
# SD card image.
# We unpack it at /image-rootfs.
RUN tar xf /workdir/openwrt/bin/targets/bcm27xx/bcm2709/*-rootfs.tar.gz
# Copy the various boot files (also resulting from the openwrt build)
# to /image-rootfs/boot. Those files were not included in the rootfs
# archive because they belong to the 1st partition of the SD card image.
RUN mkdir -p boot && \
    cd /workdir/openwrt/build_dir/target-*/linux-bcm27xx_bcm2709 && \
    cp -r *.dtb COPYING.linux LICENCE.broadcom bootcode.bin \
          fixup*.dat start*.elf vmlinux \
          linux-*/arch/arm/boot/dts/overlays \
          /image-rootfs/boot && \
    for dtbf in image-*.dtb; \
    do cp "$dtbf" "/image-rootfs/boot/${dtbf#image-}"; \
    done && \
    cd /workdir/openwrt/target/linux/bcm27xx/image && \
    cp config.txt distroconfig.txt /image-rootfs/boot
# Fetch local files we will need for OS customization
COPY $SRC_DIR/image-files /image-files
WORKDIR /image-rootfs/boot
# The kernel file must be named "kernel.img"
# (default name when not specified in config.txt)
RUN mv vmlinux kernel.img
# Activate serial console output for the Raspberry Pi firmware
# (useful for debugging).
RUN sed -i -e '/^enable_uart=1/a uart_2ndstage=1' config.txt
# We have specific kernel command line arguments for
# booting over NFS and running walt-init:
RUN cp /image-files/boot/cmdline.txt .

WORKDIR /image-rootfs
# We need to tune a few things to run the OS on NFS
# (see README-openwrt-on-nfs.md)
RUN cp /image-files/etc/config/network etc/config/network
RUN rm etc/rc.d/S*firewall
RUN cd /image-rootfs/dev && tar xf /image-files/dev-content.tar.gz

# WalT needs [image]:/run to be present
RUN mkdir -p run
# By default chirpstack sets a hostname "chirpstack-<hexa>".
# We want to keep the hostname provided by dhcp instead, i.e.,
# the walt node name.
RUN cp /image-files/etc/uci-defaults/99_set_hostname \
       etc/uci-defaults/
# We have to deal with the custom dropbear implementation
# of openwrt (see comment inside), no accepting pubkey
# at /root/.ssh/authorized_keys
RUN cp /image-files/etc/uci-defaults/50-dropbear \
       etc/uci-defaults/
# We disable the dnsmasq service OpenWRT provides, because it
# would overwrite /etc/resolv.conf, and the node will not
# really be an IP gateway anyway
RUN rm etc/rc.d/S*dnsmasq
# create node models boot directories
RUN cd boot && ln -s . rpi-3-b-plus

# Step 2: Build the final image
# -----------------------------
FROM --platform=linux/arm/v6 scratch
# specify which node models this image can handle
LABEL walt.node.models=rpi-3-b-plus
# specify min walt server version needed
LABEL walt.server.minversion=5
# copy file tree prepared above
COPY --from=chirpstack-builder /image-rootfs /
# set an entrypoint (handy when debugging)
ENTRYPOINT /bin/sh
