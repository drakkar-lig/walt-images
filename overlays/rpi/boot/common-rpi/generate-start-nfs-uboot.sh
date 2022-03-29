#!/bin/sh
set -e
# Just execute this script to generate rpi.uboot script.
if [ "$(which mkimage)" = "" ]
then
    echo "Error: u-boot's mkimage tool is needed (cf. u-boot-tools package). ABORTED."
    exit
fi

SCRIPT=$(mktemp)
cat $0 | sed '1,/SCRIPT_START$/d' > $SCRIPT
mkimage -A arm -O linux -T script -C none -n start-nfs-uboot.scr -d $SCRIPT start-nfs.uboot
echo "start-nfs.uboot was generated in the current directory."
rm $SCRIPT
exit

######################## SCRIPT_START
echo 'Env variables:'
echo '--------------'
printenv
echo

setenv walt_init "/bin/walt-init"

# In a usual boot scenario, Raspberry pi boards start their firmware, which loads
# device tree file (dtb), linux kernel, and optional initramfs from the SD card.

# In the case of walt, the linux kernel is replaced by u-boot. Thus u-boot is started
# and loads a 1st stage u-boot script from the SD card. This 1st stage script then
# loads /start.uboot using TFTP, and the TFTP request is redirected to this script
# embedded in image. As a result this script is run. It is reponsible for loading
# kernel, dtb, and optional initramfs from the walt image.

# Unfortunately, the firmware of Raspberry pi boards makes custom changes in the
# device tree before passing it to linux kernel (or u-boot in our case). In our case,
# since the device tree on the SD card (loaded by the firmware) is not the one on
# the walt image, these changes are not automatically applied to the final device
# tree. Thus issues may occur, such as kernel panics because of missing bootargs
# or issues with harware support (e.g. SD card on rpi4).

# Bootargs are passed using the "/chosen" node of the device-tree, so this script
# can read them from the device tree given by the firmware and pass them again to
# the kernel (see the code below). This fixes one part of the problem.

# Other subtle changes to the device tree are hard to detect and re-apply.
# However, board models raspberry pi 3b+ and 4b allow another form of network boot,
# where files usually read from the SD card are read using TFTP requests. walt
# redirects these TFTP requests to the image files. On the image side, these files
# are mostly a copy of the files usually found on the SD-card: thus the firmware
# will load u-boot too, and bootstrap the usual procedure. However, we can consider
# in this case that the dtb file loaded by the firmware from TFTP is the final one,
# since it is stored on walt image. So in this case, this script can just reuse the
# device tree given by the firmware and pass it to the kernel. The fact this device
# tree contains the modifications brought by the firmware should solve our problem.
# In order to let this script know we are in this case, the cmdline.txt file embedded
# on the walt image must specify "preserve_dtb=1".

echo 'Analysing bootargs given by firmware...'
# tell u-boot to look at the given device-tree
fdt addr $fdt_addr
# read "/chosen" node, property "bootargs", and store its value in variable "given_bootargs"
fdt get value given_bootargs /chosen bootargs
# but there is a little more to deal with.
# if cmdline.txt is missing or empty on the SD card, the firmware will set some "default"
# boot arguments.
# in this case, we have to remove some of them:
# * root=, rootfstype=, rootwait are not set correctly for walt context
# * kgdboc="..."  may make the kernel bootup fail (and hang!) in some cases
#   (support for kgdb may just be missing in the kernel)
setenv bootargs ""
setenv preserve_dtb 0
for arg in "${given_bootargs}"
do
    if test "$arg" = "preserve_dtb=1"
    then
        setenv preserve_dtb 1
    else
        setexpr rootprefix sub "(root).*" "root" "${arg}"
        if test "$rootprefix" != "root"
        then
            setexpr kgdbprefix sub "(kgdboc).*" "kgdboc" "${arg}"
            if test "$kgdbprefix" != "kgdboc"
            then
                # OK, we can keep this bootarg given by the firmware
                setenv bootargs "${bootargs} ${arg}"
            fi
        fi
    fi
done

# retrieve or select the dtb (device-tree-blob)
if test "$preserve_dtb" = "1"
then
    # If the board firmware has retrieved files directly, it could
    # load the device tree file stored on the walt image directly and pass it
    # to u-boot.
    setenv fdt_selected "${fdt_addr}"
else
    # We are probably booting using the SD card, which means the
    # dtb loaded by the firmware is the one on the SD card. We need the one
    # in the walt image instead.
    tftp ${fdt_addr_r} ${serverip}:dtb || reset
    setenv fdt_selected "${fdt_addr_r}"
fi

# retrieve kernel and initrd
tftp ${kernel_addr_r} ${serverip}:kernel || reset
tftp ${ramdisk_addr_r} ${serverip}:initrd || reset

# compute kernel command line args
setenv nfs_root "${serverip}:/var/lib/walt/nodes/${ipaddr}/fs"
setenv nfs_opts "ro,vers=3,nolock,nocto,acregmin=157680000,acregmax=157680000,acdirmin=157680000,acdirmax=157680000"
setenv nfs_bootargs "root=/dev/nfs boot=netroot rootfstype=netroot nfsroot=${nfs_root},${nfs_opts}"
setenv ip_param "ip=${ipaddr}:${serverip}:${gatewayip}:${netmask}:${hostname}::off"
setenv ip_conf "${ip_param} BOOTIF=01-${ethaddr}"
setenv other_bootargs "init=${walt_init} panic=15 net.ifnames=0 biosdevname=0"
setenv bootargs "$bootargs $nfs_bootargs $ip_conf $other_bootargs"

# boot
echo 'Booting kernel...'
bootz ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_selected} || reset
