#!/bin/sh
set -e

os_type="$1"
os_version="$2"
model_type="$3"
kernel_version="$4"
kernel_archive="$5"

if [ "$5" = "" ]
then
	echo "build.sh must be called by make, not run directly."
	exit 1
fi

build_args="--build-arg OS_TYPE=$os_type --build-arg OS_VERSION=$os_version"

# rpi model is more complex
if [ "$model_type" = "rpi" ]
then
    case "$os_type" in
        "alpine")
            # we consider the official arm32v6 alpine image is suitable
            # for raspberry pi boards
            base_image="arm32v6/alpine:$os_version"
            ;;
        "debian")
            # we generate a filesystem hierarchy in the builder step
            # by using debootstrap (see rpi/Dockerfile and rpi/populate_rootfs.sh)
            base_image="scratch"
            ;;
    esac

    build_args="$build_args --build-arg KERNEL_VERSION=$kernel_version \
							--build-arg KERNEL_ARCHIVE=$kernel_archive \
                            --build-arg BASE_IMAGE=$base_image"
fi

docker build $build_args -f $model_type/Dockerfile \
		--tag=waltplatform/$model_type-$os_type:latest .
docker tag waltplatform/$model_type-$os_type:latest \
			waltplatform/$model_type-$os_type:$os_version

