boot_cmd="none"
expected_fdtaddr=

if test "$has_fit" = "1" -a "$use_fit" = "1"
then
	# if u-boot can handle fit images, we can speedup boot
	# because we just need one more transfer, or none
	# if u-boot started by downloading fit-start.uboot

	if test "$fit_ready" != "1"
	then
		# download fit image
		setenv dl_addr $fit_dl_addr
		setenv dl_file "fit.uboot"
		run dl_cmd
	fi

	# extract kernel
	imxtract $fit_dl_addr "kernel" ${kernel_addr_r} || reset

	# extract initrd
	imxtract $fit_dl_addr "initrd" ${ramdisk_addr_r} || reset

	# extract dtb if needed
	if test "$preserve_dtb" != "1"
	then
		imxtract $fit_dl_addr "${node_model}-dtb" ${fdt_addr_r} || reset
	fi
else
	# legacy method: download individual files

	# download kernel
	setenv dl_addr ${kernel_addr_r}
	setenv dl_file "kernel"
	run dl_cmd

	# download initrd
	setenv dl_addr ${ramdisk_addr_r}
	setenv dl_file "initrd"
	run dl_cmd

	# download dtb if needed
	if test "$preserve_dtb" != "1"
	then
		setenv dl_addr ${fdt_addr_r}
		setenv dl_file "dtb"
		run dl_cmd
	fi
fi

# select the dtb (device-tree-blob)
if test "$preserve_dtb" = "1"
then
	# fdt_addr: address where the board firmware stored the dtb initially
	# loaded (the one passed to u-boot itself)
	setenv fdt_selected "${fdt_addr}"
else
	# fdt_addr_r: address where we downloaded (or extracted from the fit
	# image) the dtb from the walt image
	setenv fdt_selected "${fdt_addr_r}"
fi
