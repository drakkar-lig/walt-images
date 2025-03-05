#!/bin/sh
set -e

step="$1"
base_or_featured="$2"

if [ "$base_or_featured" = "" -o "$base_or_featured" = "base" ]
then
    cd base
    # note: mendel build is broken (probably an issue with
    # DNS filtering at LIG), so we exclude it. Google did not
    # update it in recent years anyway.
    for f in $(ls -1 */*/Dockerfile | grep -v mendel)
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
