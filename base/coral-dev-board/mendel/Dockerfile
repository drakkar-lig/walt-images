FROM debian:bullseye as builder

ARG OS_VERSION

# builder image
# *************

# setup package management
RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

# install packages
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y vim net-tools procps unzip wget cpio file simg2img && \
    apt-get clean

# Download the system archive.
# We will extract its components and reorganize them appropriately to build a walt image.
# Note: we use enterprise-eagle-flashcard-* archive because it is used for the first
# device setup so it contains a few more initialization scripts than the other archive
# used for regular updates.
WORKDIR /root
RUN wget -O enterprise-eagle.zip https://dl.google.com/coral/mendel/enterprise/enterprise-eagle-flashcard-${OS_VERSION}.zip
RUN unzip enterprise-eagle.zip && mv enterprise-eagle-flashcard-${OS_VERSION} enterprise-eagle
WORKDIR /root/enterprise-eagle
# find offset of 1st partition on the SD card image, extract it
RUN eval "$(partx -o START -P flashcard_arm64.img)" && \
    dd bs=512 skip=$START if=flashcard_arm64.img of=flashcard_arm64_p1.ext4
# extract partition filesystem content
RUN mkdir p1 && debugfs -R "rdump / /root/enterprise-eagle/p1" flashcard_arm64_p1.ext4
WORKDIR /root/enterprise-eagle/p1
RUN mkdir /root/rootfs
RUN debugfs -R "rdump / /root/rootfs" rootfs.img
RUN debugfs -R "rdump / /root/rootfs/boot" boot.img
# note: home.img contains an empty filesystem

# Intermediary image with customizations
# --------------------------------------
FROM --platform=linux/arm/v6 scratch as customized

# copy filesystem prepared from builder step
COPY --from=builder /root/rootfs /

# copy overlay files
COPY overlays/mendel /

# add apt key
RUN curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -

# upgrade, install additional packages
RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && apt-get upgrade -y && \
    apt-get install -y busybox-static u-boot-tools && apt-get clean

# 10-set-mac-addresses is a script normally run once at 1st boot.
# This script catches the mac address of eth0, adds 1 to compute next address
# and writes files /etc/bluetooth/.bt_nv.bin and /lib/firmware/wlan/wlan_mac.bin
# accordingly, in order to set mac address of wifi and bluetooth interfaces.
# Since walt OS files do not persist, we edited this script to replace these
# two paths with symlinks targeting /persist/.overlay/<path>.
# The script is also run at each boot now, and is called from root's crontab.
# See overlays/mendel/bin/set-mac-addresses
RUN rm /etc/runonce.d/10-set-mac-addresses
RUN echo '@reboot /bin/set-mac-addresses' | crontab -

# Handle other run-once scripts
RUN rm /etc/runonce.d/00-e2fsresize         # on NFS root, we don't need this one
RUN rm /etc/runonce.d/01-generate-hostname  # walt server gives a hostname at boot
RUN rm /etc/runonce.d/97-set-datetime       # walt nodes are synchronized, we don't need this one
RUN rm /etc/runonce.d/99-reboot             # changes will be made now instead of at 1st boot, no reboot
# These commands should be temporarily diverted
RUN mv /usr/sbin/invoke-rc.d /usr/sbin/invoke-rc.d.diverted && ln -s /bin/true /usr/sbin/invoke-rc.d
RUN mv /sbin/udevadm /sbin/udevadm.diverted && ln -s /bin/true /sbin/udevadm
# Run the scripts
RUN export DEBIAN_FRONTEND=noninteractive && /usr/sbin/runonce
# Revert diversions
RUN mv /usr/sbin/invoke-rc.d.diverted /usr/sbin/invoke-rc.d
RUN mv /sbin/udevadm.diverted /sbin/udevadm
# Drop runonce services since they have now been run once
RUN rm -f /etc/runonce.d/* && systemctl disable runonce
# Enable ssh root login (with pubkey) and disable root password (for serial line)
RUN sed -re 's/^#?PermitRootLogin.*/PermitRootLogin prohibit-password/g' -i /etc/ssh/sshd_config
RUN passwd -d root
# Fix haveged entropy service not booting in its default conf
RUN sed -i -e 's/-w 1024/-w 1024 -d16/' /etc/default/haveged
# Disable unattended upgrades (we need reproducibility)
RUN systemctl disable unattended-upgrades
# Disable u-boot install service
RUN systemctl disable uboot-imx.service
# Disable vitalsd service (not working on default mendel OS either)
RUN systemctl disable vitalsd.service
# Create start.uboot
RUN cd /boot/coral-dev-board && ./generate-start-uboot.sh
# Cleanup unused boot files
RUN rm /boot/boot.scr /boot/u-boot.imx

# Target image
# ------------
FROM --platform=linux/arm/v6 scratch
ARG KERNEL_VERSION

# specify which node models this image can handle
LABEL walt.node.models=coral-dev-board

# specify min walt server version needed
LABEL walt.server.minversion=5

# copy filesystem from previous step
COPY --from=customized / /

# specify an entrypoint (handy for debugging)
ENTRYPOINT /bin/bash

