#!/bin/sh

set -e

DEBUG=0  # set to 1 for easier debugging

if [ "$DEBUG" = 1 ]
then
    # indicate an error but exit sucessfully to let the
    # calling Dockerfile save this state.
    trap "echo ****** FIXME!!!!!!!!!!!! >&2; exit 0" EXIT
fi

PACKAGES="init ssh openssh-server usbutils \
    locales netcat-openbsd lldpd vim python3-pip python3-venv kexec-tools wget \
    htop e2fsprogs dosfstools iputils-ping python3-serial ntpdate ifupdown \
    lockfile-progs ptpd initramfs-tools nfs-common \
    nbd-client jq"
PACKAGES_RPI5_VPN="mtools curl"    # for VPN enrollment, boot.img
PACKAGES_NO_RECOMMENDS="cron"

PACKAGES_FIRMWARE="firmware-realtek firmware-bnx2 firmware-bnx2x firmware-qlogic \
    firmware-atheros firmware-brcm80211 firmware-misc-nonfree"
EXTRACT_IKCONFIG_URL="https://raw.githubusercontent.com/torvalds/linux/master/scripts/extract-ikconfig"

install_packages() {
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

image_kind="$1"
kernel_version="$2"

if [ -e "/root/tap-wrap.c" ]
then
    vpn_capable_image=1
else
    vpn_capable_image=0
fi

if [ "$image_kind" = "rpi32" -o "$image_kind" = "rpi64" ]
then
    # resume deboostrap process
    mv /bin/mount /bin/mount.saved
    ln -sf /bin/true /bin/mount
    /debootstrap/debootstrap --second-stage
    mv /bin/mount.saved /bin/mount

    # update apt repositories for faster build
    mv /etc/apt/sources.list.fast /etc/apt/sources.list
    if [ "$image_kind" = "rpi32" ]
    then
        # register Raspberry Pi Archive Signing Key
        apt-key add - < /root/82B129927FA3303E.pub
    fi
    mkdir -p /media/sdcard
elif [ "$image_kind" = "nanopi-r5c" ]
then
    /debootstrap/debootstrap --second-stage
fi

if [ -d /var/cache/apt/archives/partial ]
then
    chown _apt:root /var/cache/apt/archives/partial
    chmod 700 /var/cache/apt/archives/partial
fi

case "$image_kind" in
    "rpi32")
        PACKAGES="u-boot-tools raspi-utils rpi-eeprom raspberrypi-kernel \
                  raspberrypi-bootloader $PACKAGES $PACKAGES_FIRMWARE"
        arch=arm
        ;;
    "rpi64")
        PACKAGES="u-boot-tools raspi-utils raspi-firmware rpi-eeprom \
                  linux-image-rpi-v8 linux-image-rpi-2712 \
                  linux-headers-rpi-v8 linux-headers-rpi-2712 \
                  $PACKAGES $PACKAGES_RPI5_VPN $PACKAGES_FIRMWARE"
        arch=arm64
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
install_packages --no-install-recommends $PACKAGES_NO_RECOMMENDS

# restore diverted files
mv /etc/default/ptpd.new /etc/default/ptpd
[ -e "/etc/default/lldpd.new" ] && mv /etc/default/lldpd.new /etc/default/lldpd

# if source is provided (for images which support WalT VPN),
# compile tap-wrap
if [ -e "/root/tap-wrap.c" ]
then
    gcc -O2 -o /usr/bin/tap-wrap /root/tap-wrap.c
fi

# copy the directory tree /late to /
cd /late
cp -r . /

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

# generate boot files in relevant dirs
if [ -e /boot/update-boot-files.sh ]
then
    /boot/update-boot-files.sh
fi

if [ "$image_kind" = "rpi32" -o "$image_kind" = "rpi64" ]
then
    # let systemd use the watchdog with a 15s timeout
    sed -i -e 's/.*\(RuntimeWatchdogSec\).*/\1=15/g' \
           -e 's/.*\(RebootWatchdogSec\).*/\1=15/g' /etc/systemd/system.conf
fi

# Allow passwordless root login on the serial console,
# unless the image can be used on a VPN node
if [ "$vpn_capable_image" = 0 ]
then
    sed -i -e 's#^root:[^:]*:#root::#' /etc/shadow
fi

# Enable our custom systemd units
systemctl enable uptime-ready       # save uptime in /run when ready
systemctl enable walt-lldp-monitor  # notify LLDP neighbors to server
if [ "$image_kind" = "rpi64" ]
then
    systemctl enable boot-firmware.mount           # RPi OS requirement
    systemctl enable walt-vpn-auto-enroll.service  # as the name suggests
fi

# tweak for faster bootup
systemctl disable systemd-timesyncd
systemctl disable apt-daily.timer
systemctl disable apt-daily-upgrade.timer
systemctl disable exim4.service
if [ "$image_kind" = "rpi32" -o "$image_kind" = "rpi64" ]
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

if [ "$image_kind" = "rpi32" -o "$image_kind" = "rpi64" ]
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

if [ "$DEBUG" = 1 ]
then
    # remove the exit handler.
    trap "" EXIT
fi
