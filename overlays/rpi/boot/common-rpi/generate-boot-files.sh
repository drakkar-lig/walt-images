#!/bin/sh
set -e

# Generate start-*.uboot scripts
# ------------------------------

cd /boot/common-rpi
for proto in nbfs nfs nfs4
do
    ./generate-uboot-script.sh start-${proto}.uboot \
        "set-download-cmd" \
        "analyse-given-bootargs" \
        "compute-${proto}-bootargs" \
        "compute-bootargs" \
        "fetch-and-boot"
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
                        arch = "arm";
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
                        arch = "arm";
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
                        arch = "arm";
                        compression = "none";
                        hash {
                                algo = "sha1";
                        };
                };
EOF
    done

    # generate f.its footer
    cat >> $tmpdir/f.its << EOF
        };
};
EOF

    # compile as a FIT image
    mkimage -f $tmpdir/f.its /boot/${series_model}/fit.uboot

    # generate symlinks for secondary models
    for model in $(cat $tmpdir/$series_model)
    do
        if [ "$model" != "$series_model" ] 
        then
            ln -s ../$series_model/fit.uboot /boot/$model/
        fi
    done
done

rm -rf $tmpdir
