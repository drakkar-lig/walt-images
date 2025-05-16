# boot
echo 'Booting kernel...'
echo bootz ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_selected}
bootz ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_selected} || reset
