#!/bin/sh
set -e

step="$1"

for f in $(ls -1 */*/Dockerfile)
do
    arch=$(dirname $(dirname $f))
    os_type=$(basename $(dirname $f))
    echo "$step.$os_type.$arch"
done
