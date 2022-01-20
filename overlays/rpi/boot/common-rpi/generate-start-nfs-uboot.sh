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

# Some bootargs are normally given by the firmware when it runs the linux kernel.
# They are passed using the "/chosen" node of the device-tree.
# In our case the firmware calls u-boot, so we have to read them now in order to
# pass them again to the kernel.

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
for arg in "${given_bootargs}"
do
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
done

# retrieve the dtb (device-tree-blob), kernel and initrd
tftp ${fdt_addr_r} ${serverip}:dtb || reset
tftp ${kernel_addr_r} ${serverip}:kernel || reset
tftp ${ramdisk_addr_r} ${serverip}:initrd || reset

# compute kernel command line args
setenv nfs_root "${serverip}:/var/lib/walt/nodes/${ipaddr}/fs"
setenv nfs_opts "ro,vers=3,nolock,nocto,acregmin=157680000,acregmax=157680000,acdirmin=157680000,acdirmax=157680000"
setenv nfs_bootargs "root=/dev/nfs rootfstype=netroot nfsroot=${nfs_root},${nfs_opts}"
setenv ip_param "ip=${ipaddr}:${serverip}:${gatewayip}:${netmask}:${hostname}::off"
setenv ip_conf "${ip_param} BOOTIF=01-${ethaddr}"
setenv other_bootargs "init=${walt_init} panic=15 net.ifnames=0 biosdevname=0"
setenv bootargs "$bootargs $nfs_bootargs $ip_conf $other_bootargs"

# boot
echo 'Booting kernel...'
bootz ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r} || reset
