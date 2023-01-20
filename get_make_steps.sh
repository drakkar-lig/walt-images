#!/bin/sh
set -e

step="$1"

cd base
for f in $(ls -1 */*/Dockerfile)
do
    arch=$(dirname $(dirname $f))
    os_type=$(basename $(dirname $f))
    echo "$step.$os_type.$arch"
done
cd ..

cd featured
for f in $(ls -1 */Dockerfile)
do
    name=$(dirname $f)
    echo "$step.featured.$name"
done
cd ..
