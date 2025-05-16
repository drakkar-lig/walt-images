
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
# * kgdboc="..." may make the kernel bootup fail (and hang!) in some cases
#   (support for kgdb may just be missing in the kernel)
setenv excluded_bootargs "root kgdboc"
setenv preserved_bootargs ""
setenv preserve_dtb 0

for arg in "${given_bootargs}"
do
	arg_continue=1
	if test "$arg_continue" = 1
	then
		# if we find an argument "u-boot:<var>", define <var>=1
		# if we find an argument "u-boot:<var>=<value>", define <var>=<value>
		setenv uboot_arg "none"
		setexpr uboot_arg sub "u-boot:" "" "${arg}"
		if test "${uboot_arg}" != "none" -a "${uboot_arg}" != "${arg}"
		then
			setenv uboot_arg_name "none"
			setexpr uboot_arg_name sub "=.*" "" "${uboot_arg}"
			if test "${uboot_arg_name}" != "none" -a "${uboot_arg_name}" != "${uboot_arg}"
			then
				setexpr uboot_arg_value sub ".*=" "" "${uboot_arg}"
			else
				setenv uboot_arg_name "${uboot_arg}"
				setenv uboot_arg_value "1"
			fi
			echo "setenv $uboot_arg_name $uboot_arg_value"
			setenv $uboot_arg_name $uboot_arg_value
			arg_continue=0
		fi
	fi
	for excluded in "${excluded_bootargs}"
	do
		if test "$arg_continue" = 1
		then
			setexpr rootprefix sub "(${excluded}).*" "${excluded}" "${arg}"
			if test "$rootprefix" = "${excluded}"
			then
				arg_continue=0	# ignore this argument
			fi
		fi
	done
	if test "$arg_continue" = 1
	then
		# OK, we can keep this bootarg given by the firmware
		setenv preserved_bootargs "${preserved_bootargs} ${arg}"
	fi
done
