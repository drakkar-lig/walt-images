#!/bin/bash

LOG_DIR="/persist/logs/rpi-serial-monitor"
CUR_LOG="$LOG_DIR/current.log"
LOG_ARCHIVE_DIR="$LOG_DIR/archive"

# find serial port
if [ -e "/dev/ttyS0" ]
then
	port="/dev/ttyS0"
else
	port="/dev/ttyAMA0"
fi

# rotate the logs
mkdir -p "$LOG_DIR" "$LOG_ARCHIVE_DIR"
if [ -e "$CUR_LOG" ]
then
    ts_prefix=$(date -r "$CUR_LOG" "+%d%m%y_%H%M%S")
    mv "$CUR_LOG" "$LOG_ARCHIVE_DIR/$ts_prefix.log"
fi

# start screen in detached mode with minicom command
exec screen -D -m -- minicom -C "$CUR_LOG" -D $port
