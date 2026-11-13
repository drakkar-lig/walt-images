# boot
# note: rpi-4-b uses a 64-bit u-boot and kernel on rpi32-debian
echo 'Booting kernel...'
if test "$cpu" = "armv8"
then
    echo booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_selected}
    booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_selected} || reset
else
    echo bootz ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_selected}
    bootz ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_selected} || reset
fi
