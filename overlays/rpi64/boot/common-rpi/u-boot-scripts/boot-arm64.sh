# boot
echo 'Booting kernel...'
echo booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_selected}
booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_selected} || reset
