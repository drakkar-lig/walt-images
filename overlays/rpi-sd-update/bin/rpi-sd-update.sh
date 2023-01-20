#!/bin/bash

SD_DEVICE=/dev/mmcblk0
PART_DEVICE=/dev/mmcblk0p1

expected_exit()
{
    code=$1
    trap - EXIT
    if [ "$code" -eq 0 ]
    then
        # indicate success: green led on, red led off
        echo default-on > /sys/class/leds/led0/trigger
        echo none > /sys/class/leds/led1/trigger
    else
        # indicate failure: green led off, red led blinking
        echo none > /sys/class/leds/led0/trigger
        echo timer > /sys/class/leds/led1/trigger
    fi
    exit $code
}

unexpected_exit()
{
    trap - EXIT
    echo "Unexpected exit!" >&2
    walt-log-echo rpi-sd-update "Completed -- Unexpected exit!"
    # indicate unexpected exit: green led off, red led blinking with heartbeat style
    echo none > /sys/class/leds/led0/trigger
    echo heartbeat > /sys/class/leds/led1/trigger
    exit
}

resize_last_partition()
{
    disk_sector_size=$(blockdev --getss $SD_DEVICE)
    partx_sector_size=512   # partx unit is always 512-bytes sectors

    # note: we need to pass partition offsets and size to sfdisk
    # using the disk sector size as unit.
    # conversions should be carefully written to avoid integer overflows
    # (partition offset and size may be large if converted to bytes...)

    if [ "$(blkid -o value -s PTTYPE $SD_DEVICE)" = "gpt" ]
    then
        # move backup GPT data structures to the end of the disk, otherwise
        # sfdisk might not allow the partition to span
        sgdisk -e $SD_DEVICE
    fi

    eval $(partx -o NR,START,TYPE -P $SD_DEVICE | tail -n 1)
    # convert partition start offset unit from 'partx sector size' to 'disk sector size'
    START=$((START/(disk_sector_size/partx_sector_size)))

    # do not specify the size => it will extend to the end of the disk
    part_def=" $NR : start=$START, type=$TYPE"

    # we delete, then re-create the partition with same information
    # except the size
    sfdisk --no-reread $SD_DEVICE >/dev/null 2>&1 << EOF || true
$(sfdisk -d $SD_DEVICE | head -n -1)
$part_def
EOF
    partx -u $SD_DEVICE  # notify the kernel
}

# Stop in case of issue
set -e
trap unexpected_exit EXIT
cd /

# check we have an SD card plugged in and valid
if [ ! -b "$PART_DEVICE" ]
then
    message="Update BYPASSED (no SD card or broken one)"
    walt-log-echo rpi-sd-update "Completed -- $message"
    expected_exit 1
fi

# Set green LED to 'timer'
echo timer > /sys/class/leds/led0/trigger

# Mount SD card read-only
mountpoint /media/sdcard >/dev/null || mount -o ro /media/sdcard

# If files are already up-to-date, umount and exit
if diff -q /media/sdcard/walt.date /opt/walt/rpi-sd/walt.date >/dev/null
then
    # already up-to-date
    umount /media/sdcard
    walt-log-echo rpi-sd-update "Completed -- Already up-to-date."
    expected_exit 0
fi

# If filesystem was never expanded over SD card, do it now
if [ ! -f "/media/sdcard/walt.expanded" ]
then
    walt-log-echo rpi-sd-update "Expanding file system over the whole SD card space."
    saved=$(mktemp -d)
    cp -r /media/sdcard $saved
    umount /media/sdcard
    resize_last_partition
    mkfs -t vfat "$PART_DEVICE"
    mount -o rw /media/sdcard
    cp -r $saved/sdcard/* /media/sdcard/
    rm -rf $saved
    touch /media/sdcard/walt.expanded
    mount -o remount,ro /media/sdcard
fi

walt-log-echo rpi-sd-update "Updating files."
mount -o remount,rw /media/sdcard
cd /media/sdcard
files=$(ls -1 | grep -v obsolete | grep -v walt.expanded)
saved_dir="/media/sdcard/obsolete/$(date +%s.%N)/"
mkdir -p $saved_dir
mv $files $saved_dir
cp -r /opt/walt/rpi-sd/* .
cd /

walt-log-echo rpi-sd-update "Verifying."
umount /media/sdcard
mount -o ro /media/sdcard
if diff -q /media/sdcard/walt.date /opt/walt/rpi-sd/walt.date
then    # OK same file
    message="Update was successful."
    code=0
else
    message="Update FAILED! (SD card seems broken)"
    code=1
fi
umount /media/sdcard
walt-log-echo rpi-sd-update "Completed -- $message"
expected_exit $code
