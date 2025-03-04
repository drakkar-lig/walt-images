# update addresses to handle possibly large initrds and
# uncompressed arm64 kernels
#
# notes:
# - see [uboot_src]: board/raspberry/rpi/rpi.env
#   for address constraints on ARM and Aarch64 --
#   we copied the same values here, except that they
#   were proposing pxe_file_addr_r=0x02500000, so
#   the downloaded file could not be larger than
#   0x00100000 (1 megabyte), whereas our FIT images
#   can be much larger that this. So we define a new
#   variable fit_dl_addr with enough room for large
#   FIT images.
# - we have a fixed scriptaddr=0x02400000 parameter
#   set by u-boot and used for storing start.uboot, so
#   it is too late to change this one now.
# - we may also have fit_dl_addr=0x05000000 already set
#   by u-boot in our newer versions of u-boot embedded
#   on sd-cards.
#
if test -n "$scriptaddr"
then
    if test "$scriptaddr" != "0x02400000"
    then
        echo "Unexpected existing definition of scriptaddr=$scriptaddr"
        echo "Should be 0x02400000. Aborting!"
        sleep 5
        reset
    fi
fi
if test -n "$fit_dl_addr"
then
    if test "$fit_dl_addr" != "0x05000000"
    then
        echo "Unexpected existing definition of fit_dl_addr=$fit_dl_addr"
        echo "Should be 0x05000000. Aborting!"
        sleep 5
        reset
    fi
fi
setenv  kernel_addr_r       0x00080000
setenv  scriptaddr          0x02400000  # cannot change this one
setenv  fdt_addr_r          0x02600000
setenv  ramdisk_addr_r      0x02700000
setenv  fit_dl_addr         0x05000000  # cannot change this one
setenv  kernel_comp_addr_r  0x08000000

# for allowing booti to decompress the kernel, we need
# kernel_comp_addr_r & kernel_comp_size
# note: this is a size, not an address!
setenv  kernel_comp_size    0x01000000
