#!/bin/sh
set -e

arch="$1"

. /boot/update-boot-files-functions.sh

# Generate start.txt and start.uboot scripts
# ------------------------------------------
cd /boot/common-rpi
if outdated start.uboot u-boot-scripts/*
then
    ./generate-uboot-script.sh start.txt start.uboot \
        "set-download-cmd" \
        "analyse-given-bootargs" \
        "compute-bootargs" \
        "set-fetch-addresses" \
        "fetch" \
        "boot-${arch}"
fi

# Generate initrd.uboot files
# ---------------------------
cd /boot
# detect rpi model dirs by their dtb file
for model_dtb in */dtb
do
    model=$(dirname $model_dtb)
    cd /boot/$model

    if [ -e "kernel.extension" ]
    then
        # use kernel.extension file (debian-style)
        extension="$(cat "kernel.extension")"
        full_kernel_version="$(get_kernel_version_from_extension "$extension")"
        initrd_orig="../initrd.img-${full_kernel_version}"
        initrd_uboot="${initrd_orig}.uboot"
        create_link=1
    else
        # use initrd link target (alpine-style)
        initrd_uboot="$(readlink initrd)"
        initrd_orig="$(echo $initrd_uboot | sed -e 's/.uboot//')"
    fi

    # if initrd is not created yet for this model, exit and
    # we will continue when recalled.
    if [ ! -e "$initrd_orig" ]
    then
        echo "$initrd_orig not created yet, exiting."
        exit 0
    fi

    # create u-boot image if outdated
    if outdated "$initrd_uboot" "$initrd_orig"
    then
        echo "Generating $initrd_uboot"
        mkimage -A $arch -T ramdisk -C none -n uInitrd \
                -d "${initrd_orig}" "${initrd_uboot}"
    fi

    # create link if needed
    if [ ! -e /boot/$model/initrd ]
    then
        ln -sf "${initrd_uboot}" /boot/$model/initrd
    fi
done

# Generate FIT images
# -------------------
# dtb files are very small compared to kernel and initrd, so we can store
# several of them into a FIT image without significantly increasing its size.
# Thus we generate one single fit image for all rpi models having the same
# kernel and initrd. For instance, in the Debian case, we will generate a
# single FIT image for rpi-b and rpi-b-plus, storing 1 kernel, 1 initrd
# and 2 dtbs.

ordered_rpi_models() {
    cd /boot
    ls -1d rpi-* | sed -e 's/rpi-\([2-9]\)/\1 \0/g' -e 's/rpi-\([^2-9]\)/1 \0/g' \
                 | sort -n \
                 | cut -d " " -f 2
}

cd /boot
tmpdir=$(mktemp -d)

prev_kernel=""
prev_initrd=""
prev_dtb=""
series_model=""
series_models=""

for model in $(ordered_rpi_models)
do
    kernel="$(readlink ${model}/kernel)"
    initrd="$(readlink ${model}/initrd)"
    dtb="$(readlink ${model}/dtb)"

    if [ "$kernel" != "$prev_kernel" -o "$initrd" != "$prev_initrd" ]
    then
        series_model="$model"
        series_models="$series_models $model"
    fi

    echo "$model" >> $tmpdir/$series_model

    prev_kernel="$kernel"
    prev_initrd="$initrd"
    prev_dtb="$dtb"
done

for series_model in $series_models
do
    deps="/boot/common-rpi/start.txt"
    deps="$deps /boot/${series_model}/kernel"
    deps="$deps /boot/${series_model}/initrd"
    for model in $(cat $tmpdir/$series_model)
    do
        deps="$deps /boot/${model}/dtb"
    done

    if ! outdated /boot/${series_model}/fit.uboot $deps
    then
        continue
    fi

    # generate f.its header
    cat > $tmpdir/f.its << EOF
/dts-v1/;

/ {
        description = "${series_model} series FIT Image";
        #address-cells = <1>;

        images {
                kernel {
                        description = "Kernel";
                        data = /incbin/("/boot/${series_model}/kernel");
                        type = "kernel";
                        arch = "${arch}";
                        os = "linux";
                        compression = "none";
                        hash {
                                algo = "sha1";
                        };
                };
                initrd {
                        description = "Initrd";
                        data = /incbin/("/boot/${series_model}/initrd");
                        type = "ramdisk";
                        arch = "${arch}";
                        os = "linux";
                        compression = "none";
                        hash {
                                algo = "sha1";
                        };
                };
EOF

    # generate f.its dtb sections
    for model in $(cat $tmpdir/$series_model)
    do
        cat >> $tmpdir/f.its << EOF
                ${model}-dtb {
                        description = "${model} DTB";
                        data = /incbin/("/boot/${model}/dtb");
                        type = "flat_dt";
                        arch = "${arch}";
                        compression = "none";
                        hash {
                                algo = "sha1";
                        };
                };
EOF
    done

    # generate f.its footer
    cat >> $tmpdir/f.its << EOF
                script {
                    data = /incbin/("/boot/common-rpi/start.txt");
                    type = "script";
                };
        };

        configurations {
                default = "start-script";

                start-script {
                        script = "script";
                };
        };
};
EOF

    # compile as a FIT image
    echo "Generating /boot/${series_model}/fit.uboot"
    mkimage -f $tmpdir/f.its /boot/${series_model}/fit.uboot

    for model in $(cat $tmpdir/$series_model)
    do
        # generate fit.uboot symlinks for secondary models
        if [ "$model" != "$series_model" ]
        then
            ln -sf ../$series_model/fit.uboot /boot/$model/
        fi
        # generate fit-start.uboot symlinks since we now handle
        # starting with only one u-boot transfer (i.e., this FIT
        # image), and then execute the script it contains.
        ln -sf fit.uboot /boot/$model/fit-start.uboot
    done
done

rm -rf $tmpdir

# Check boot files (no broken symlinks)
# -------------------------------------
check_boot_files
