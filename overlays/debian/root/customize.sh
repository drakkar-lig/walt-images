#!/bin/sh

set -e

PACKAGES="init ssh openssh-server usbutils texinfo \
    locales netcat-openbsd lldpd vim python3-pip python3-venv kexec-tools wget \
    htop e2fsprogs dosfstools iputils-ping python3-serial ntpdate ifupdown \
    lockfile-progs avahi-daemon libnss-mdns cron ptpd initramfs-tools nfs-common"
PACKAGES_FIRMWARE="firmware-realtek firmware-bnx2 firmware-bnx2x firmware-qlogic \
    firmware-atheros firmware-brcm80211 firmware-misc-nonfree"
EXTRACT_IKCONFIG_URL="https://raw.githubusercontent.com/torvalds/linux/master/scripts/extract-ikconfig"

install_packages() {
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

get_kernel_version_from_extension() {
    ext="$1"
    # we may have for instance extensions "+" and "-v7+", thus looking for entries
    # ending with "+" is not enough, and that's why we return the shortest matching
    # entry.
    cd /lib/modules
    ls -1 | grep -- "$ext$" | awk '{ print length, $0 }' | sort -n | cut -d" " -f2 | head -n 1
}

image_kind="$1"
kernel_version="$2"

if [ "$image_kind" = "rpi" ]
then
    # resume deboostrap process
    mv /bin/mount /bin/mount.saved
    ln -sf /bin/true /bin/mount
    /debootstrap/debootstrap --second-stage
    mv /bin/mount.saved /bin/mount

    # update apt repositories for faster build
    mv /etc/apt/sources.list.fast /etc/apt/sources.list

    # register Raspberry Pi Archive Signing Key
    apt-key add - < /root/82B129927FA3303E.pub
elif [ "$image_kind" = "nanopi-r5c" ]
then
    /debootstrap/debootstrap --second-stage
fi

case "$image_kind" in
    "rpi")
        PACKAGES="u-boot-tools raspi-utils rpi-eeprom raspberrypi-kernel \
                  raspberrypi-bootloader $PACKAGES $PACKAGES_FIRMWARE"
        ;;
    "nanopi-r5c")
        # note: firmware added by Dockerfile
        PACKAGES="u-boot-tools linux-image-arm64 \
                  rfkill wireless-regdb wpasupplicant $PACKAGES"
        ;;
    "pc-x86-32")
        PACKAGES="linux-image-686-pae $PACKAGES $PACKAGES_FIRMWARE"
        ;;
    "pc-x86-64")
        PACKAGES="linux-image-amd64 $PACKAGES $PACKAGES_FIRMWARE"
        ;;
esac

case "$image_kind" in
    "pc-x86-32"|"pc-x86-64")
        if [ -f /etc/apt/sources.list ]
        then
                # add non-free apt section
                sed -i -e 's/main/main non-free/g' /etc/apt/sources.list
        else
                # new source format, >= bookworm, add non-free-firmware section
                sed -i -e 's/main/main non-free-firmware/g' \
                            /etc/apt/sources.list.d/debian.sources
        fi
        ;;
esac

# those files should be temporarily diverted for the package installation to pass
mv /etc/default/ptpd /etc/default/ptpd.new
[ -e "/etc/default/lldpd" ] && mv /etc/default/lldpd /etc/default/lldpd.new

# Install packages
install_packages $PACKAGES

# restore diverted files
mv /etc/default/ptpd.new /etc/default/ptpd
[ -e "/etc/default/lldpd.new" ] && mv /etc/default/lldpd.new /etc/default/lldpd

# Install walt python packages
python3 -m venv /opt/walt-node
/opt/walt-node/bin/pip install --upgrade pip
/opt/walt-node/bin/pip install /root/*.whl
/opt/walt-node/bin/walt-node-setup

# Configure locale
echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen
echo 'fr_FR.UTF-8 UTF-8' >> /etc/locale.gen
locale-gen

# extract missing kernel config files (ik=in-kernel)
# and generate initramfs images
cd /tmp
wget $EXTRACT_IKCONFIG_URL
if [ "$image_kind" = "rpi" ]
then
    sh /tmp/extract-ikconfig /boot/qemu-arm-32/kernel \
        > "/boot/config-$(cat /boot/qemu-arm-32/kernel.release)"
    sh /tmp/extract-ikconfig /boot/qemu-arm-64/kernel \
        > "/boot/config-$(cat /boot/qemu-arm-64/kernel.release)"
fi

for kversion in $(ls /lib/modules)
do
    if [ ! -f "/boot/config-$kversion" ]
    then
        sh /tmp/extract-ikconfig \
            "/lib/modules/$kversion/kernel/kernel/configs.ko"*  \
            > "/boot/config-$kversion"
    fi
    update-initramfs -u -k $kversion
done
rm /tmp/extract-ikconfig

# link or create u-boot image in relevant dirs
if [ "$image_kind" = "rpi" ]
then
    cd /boot
    # link arm32 and arm64 initrd files
    ln -s ../initrd.img-${kernel_version}-arm32 qemu-arm-32/initrd
    ln -s ../initrd.img-${kernel_version}-arm64 qemu-arm-64/initrd

    # detect rpi model dirs by their dtb file
    for model_dtb in */dtb
    do
        model=$(dirname $model_dtb)

        # compute full kernel version including extension
        extension="$(cat "$model/kernel.extension")"
        full_kernel_version="$(get_kernel_version_from_extension "$extension")"

        # create u-boot image
        # (if not already done for a model having the same kernel)
        initrd_name="initrd.img-${full_kernel_version}"
        if [ ! -f "/boot/$initrd_name.uboot" ]
        then
            mkimage -A arm -T ramdisk -C none -n uInitrd \
                    -d "/boot/$initrd_name" "/boot/$initrd_name.uboot"
        fi

        # link into relevant dir
        ln -s "../$initrd_name.uboot" /boot/$model/initrd
    done

    # generate other boot files
    /boot/common-rpi/generate-boot-files.sh

    # let systemd use the watchdog with a 15s timeout
    sed -i -e 's/.*\(RuntimeWatchdogSec\).*/\1=15/g' \
           -e 's/.*\(RebootWatchdogSec\).*/\1=15/g' /etc/systemd/system.conf
elif [ "$image_kind" = "nanopi-r5c" ]
then
    mkdir -p /boot/nanopi-r5c
    cd /boot/nanopi-r5c
    ln -s ../*.dtb dtb
    mkimage -A arm64 -T ramdisk -C none -n uInitrd -d ../initrd.* initrd
    ln -s ../vmlinuz* kernel
    for proto in nfs nfs4 nbfs
    do
        mkimage -A arm -O linux -T script -C none -n "start-${proto}.uboot" \
            -d start-uboot-${proto}.txt start-${proto}.uboot
    done
    ln -s start-nfs.uboot start.uboot   # default is nfs3
fi

# Allow passwordless root login on the serial console
sed -i -e 's#^root:[^:]*:#root::#' /etc/shadow

# enable service to save uptime in /run when ready
systemctl enable uptime-ready

# tweak for faster bootup
systemctl disable systemd-timesyncd
systemctl disable apt-daily.timer
systemctl disable apt-daily-upgrade.timer
systemctl disable exim4.service
if [ "$image_kind" = "rpi" ]
then
    systemctl disable rpi-eeprom-update
fi
for timer_unit in $(ls /etc/systemd/system/timers.target.wants)
do
    systemctl disable "$timer_unit"
done

# tweak system for kexec:
# * disable kexec-load.service, we don't want to load the
#   same kernel automatically because image may have changed
#   when we reboot the node
# * we keep kexec.service activated, which will be triggered
#   at the end of the OS shutdown if a kexec kernel was
#   previously loaded (i.e, by walt-ipxe-kexec-reboot)
systemctl disable kexec-load.service

if [ "$image_kind" = "rpi" ]
then
    # restore official apt repositories
    mv /etc/apt/sources.list.official /etc/apt/sources.list
fi

# File policy-rc.d is available by default in debian images on docker hub
# to prevent apt to start services immediately after they are installed.
# Since in "walt image shell" we now start systemd, we can now restore
# this default behavior.
rm -f /usr/sbin/policy-rc.d

# cleanup
rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/apt/*
rm -rf /root/*
