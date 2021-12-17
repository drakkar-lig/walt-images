#!/bin/sh

PACKAGES="alpine-base openrc nfs-utils openssh-server \
    netcat-openbsd lldpd vim py3-pip linux-firmware htop"

image_kind="$1"

# kexec feature is not activated in alpine kernels
# set to 1 if we recompile a kernel with kexec
HAS_KEXEC=0

case "$image_kind" in
    "rpi")
        PACKAGES="linux-rpi linux-rpi2 uboot-tools \
                  raspberrypi-bootloader \
                  raspberrypi  $PACKAGES"
        mv /root/mount.nbfs.static.rpi /sbin/mount.nbfs
        mv /root/activate-nbfs-rpi.sh /usr/bin/activate-nbfs.sh
        ;;
    "pc-x86-32")
        PACKAGES="linux-lts $PACKAGES"
        mv /root/mount.nbfs.static.i386 /sbin/mount.nbfs
        mv /root/activate-nbfs-pc.sh /usr/bin/activate-nbfs.sh
        ;;
    "pc-x86-64")
        PACKAGES="linux-lts $PACKAGES"
        mv /root/mount.nbfs.static.amd64 /sbin/mount.nbfs
        mv /root/activate-nbfs-pc.sh /usr/bin/activate-nbfs.sh
        ;;
esac

if [ "$HAS_KEXEC" != 0 ]
then
    # add "testing" repo section
    echo "@testing http://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories
    PACKAGES="$PACKAGES kexec-tools@testing"
fi

# Install packages
apk add $PACKAGES

# enable services startup
rc-update add bootmisc sysinit
rc-update add devfs sysinit
rc-update add sysfs sysinit
rc-update add networking sysinit

rc-update add sshd default
rc-update add lldpd default

# enable login on serial line
sed -i -e 's/^#ttyS0\(.*\)ttyS0\(.*\)$/console\1console\2/' /etc/inittab

# generate sshd host keys
# note: the walt server with overwrite the ECDSA keypair when the
# the image is mounted.
ssh-keygen -A

# TODO: Install walt python packages
# pip3 install /root/*.whl
# This command works but is not useful for now:
# - kexec feature is not activated in alpine kernels
# - we should call walt-node-setup then to activate
#   walt logs daemon, but the current code only handles systemd
#   services.

# Enable fast reboots using fake ipxe and kexec
if [ "$HAS_KEXEC" != 0 ]
then
    ln -s $(which walt-ipxe-kexec-reboot) /bin/walt-reboot
fi

case "$image_kind" in
    "rpi")
        # boot files for qemu arm nodes (e.g. VPN)
        mv /root/boot/common-ipxe /boot/common-ipxe
        mv /root/boot/qemu-arm-32/* /boot/qemu-arm-32/
        mv /root/boot/qemu-arm-64/* /boot/qemu-arm-64/
        # boot files for various rpi models
        mv /root/boot/rpi-* /boot/
        mv /root/boot/common-rpi /boot/
        ;;
    "pc-x86-32")
        # allow 32-bit and 64-bit nodes
        mv /root/boot/common-ipxe /boot/common-ipxe
        mv /root/boot/common-pc /boot/common-pc
        mv /root/boot/pc-x86-32 /boot/pc-x86-32
        mv /root/boot/pc-x86-64 /boot/pc-x86-64
        ;;
    "pc-x86-64")
        # allow 64-bit only
        mv /root/boot/common-ipxe /boot/common-ipxe
        mv /root/boot/common-pc /boot/common-pc
        mv /root/boot/pc-x86-64 /boot/pc-x86-64
        ;;
esac

# update initramfs with ability to use nfs & nbfs
echo 'kernel/fs/nfs/*' > /etc/mkinitfs/features.d/netroot.modules
echo 'kernel/fs/fuse/*' >> /etc/mkinitfs/features.d/netroot.modules
echo '/sbin/mount.nfs' > /etc/mkinitfs/features.d/netroot.files
echo '/sbin/mount.nbfs' >> /etc/mkinitfs/features.d/netroot.files
echo '/sbin/mount.netroot' >> /etc/mkinitfs/features.d/netroot.files
echo 'features="base keymap kms virtio network dhcp netroot"' > /etc/mkinitfs/mkinitfs.conf
for kversion in $(ls /lib/modules) 
do
    mkinitfs $kversion
done
chmod a+r /boot/initramfs-*     # for TFTP access

if [ "$image_kind" = "rpi" ]
then
    # create a u-boot image for initrd
    for f in initramfs-rpi initramfs-rpi2
    do
        mkimage -A arm -T ramdisk -C none -n uInitrd -d /boot/$f /boot/common-rpi/$f.uboot
    done
fi

# Allow passwordless root login on the serial console
sed -i -e 's#^root:[^:]*:#root::#' /etc/shadow

# cleanup
rm -rf /root/*
