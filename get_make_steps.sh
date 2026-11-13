#!/bin/sh
set -e

step="$1"
base_or_featured="$2"

if [ "$base_or_featured" = "" -o "$base_or_featured" = "base" ]
then
    cd base
    for f in $(ls -1 */*/Dockerfile)
    do
        arch=$(dirname $(dirname $f))
        os_type=$(basename $(dirname $f))
        echo "$step.$os_type.$arch"
    done
    cd ..
fi

if [ "$base_or_featured" = "" -o "$base_or_featured" = "featured" ]
then
    cd featured
    for f in $(ls -1 */Dockerfile)
    do
        name=$(dirname $f)
        echo "$step.featured.$name"
    done
    cd ..
fi
