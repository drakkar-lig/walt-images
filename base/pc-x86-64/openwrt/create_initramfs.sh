#!/bin/bash
set -e

ORIG_ROOTFS=~/openwrt/build_dir/target-x86_64_musl/root-x86
TARGET_ROOTFS=/root/initrd

is_dynamic_binary() {
    file "$1" | grep -q "executable.*dynamically linked"
}

copy_files() {
    source_dir="$1"
    dest_dir="$2"
    shift 2
    for f in "$@"
    do
        f=$(realpath -s --relative-to "$source_dir" "$f")
        cd "$source_dir" 
        if [ -e "$dest_dir/$f" ]
        then
            # already copied
            continue
        fi
        echo "$f"
        mkdir -p "$(dirname "$dest_dir/$f")"
        if [ -h "$f" ]
        then
            target=$(readlink "$f")
            # identify symlink target file
            if [ "${target:0:1}" = "/" ]
            then    # absolute
                target_f="$source_dir$target"
            else    # relative
                cd $(dirname "$f")
                target_f="$(realpath -s "$target")"
                cd "$source_dir"
            fi
            # copy symlink itself
            ln -s "$target" "$dest_dir/$f"
            # recursively copy symlink target file
            copy_files "$source_dir" "$dest_dir" "$target_f"
        elif is_dynamic_binary "$f"
        then
            # $f is a dynamically linked binary executable
            # get library dependencies
            libs=$(chroot . ldd "$f" | awk "{print \"${source_dir}\" \$(NF-1)}")
            # copy binary file itself
            cp -a "$f" "$dest_dir/$f"
            # recursively copy library dependencies
            copy_files "$source_dir" "$dest_dir" $libs
        else
            # other kind of files, just copy
            cp -a "$f" "$dest_dir/$f"
        fi
    done
}

# copy a kernel module and its dependencies
copy_module() {
    local name f dep
    for name in "$1" "${1//_/-}" "${1//-/_}"
    do
        f="$MODULES_DIR/$name.ko"
        [ -e "$ORIG_ROOTFS/$f" ] && break
    done
    if [ ! -e "$ORIG_ROOTFS/$f" ]
    then
        echo "ERROR: kernel module $1 not found." >&2
        return 1
    fi
    [ -e "$TARGET_ROOTFS/$f" ] && return 0   # already copied
    copy_files $ORIG_ROOTFS $TARGET_ROOTFS "$ORIG_ROOTFS/$f"
    for dep in $(strings -a "$ORIG_ROOTFS/$f" | \
                 sed -n 's/^depends=//p' | tr ',' ' ')
    do
        copy_module "$dep"
    done
}

# copy files
cd $ORIG_ROOTFS
copy_files $ORIG_ROOTFS $TARGET_ROOTFS \
           bin/busybox sbin/mount.nfs sbin/mount.nfs4 \
           bin/sh \
           sbin/ip sbin/modprobe sbin/kmodloader

# copy network drivers commonly found on physical PCs (the kernel
# only embeds the virtio network driver); init loads them using
# kmodloader and the module list at /etc/modules-boot.d/.
# (r8169 needs the realtek PHY driver)
NIC_MODULES="e1000 e1000e igb igc realtek r8169 tg3"
cd $ORIG_ROOTFS
MODULES_DIR=$(echo lib/modules/*)
mkdir -p $TARGET_ROOTFS/etc/modules-boot.d
for mod in $NIC_MODULES
do
    copy_module $mod
    echo $mod >> $TARGET_ROOTFS/etc/modules-boot.d/30-walt-nics
done

# build cpio archive
cd $TARGET_ROOTFS
find . | cpio -o -H newc --quiet | gzip -9 > /root/initramfs.cpio.gz
