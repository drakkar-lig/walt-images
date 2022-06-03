#!/bin/sh
set -e

os_type="$1"
os_version="$2"
model_type="$3"
kernel_version="$4"
kernel_archive="$5"
tmp_dir=$(mktemp -d)

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
            # unfortunately this image provides no kernel for the rpi4 board,
            # so model rpi-4-b is excluded from our models.
            # (linux-rpi2 packages used for models 2 & 3 works but we miss the
            # broadcom genet ethernet driver.)
            # future work: if building from aarch64 version, we could make an image
            # for models rpi3b, rpi3b+ and rpi4b.
            models="rpi-b,rpi-b-plus,rpi-2-b,rpi-3-b,rpi-3-b-plus,qemu-arm-32,qemu-arm-64"
            ;;
        "debian")
            # we generate a filesystem hierarchy in the builder step
            # by using debootstrap (see rpi/Dockerfile and rpi/populate_rootfs.sh)
            base_image="scratch"
            models="rpi-b,rpi-b-plus,rpi-2-b,rpi-3-b,rpi-3-b-plus,rpi-4-b,qemu-arm-32,qemu-arm-64"
            ;;
    esac

    build_args="$build_args --build-arg MODELS=$models \
                            --build-arg KERNEL_VERSION=$kernel_version \
							--build-arg KERNEL_ARCHIVE=$kernel_archive \
                            --build-arg BASE_IMAGE=$base_image"
fi

dockerfile=$tmp_dir/Dockerfile
cp $model_type/Dockerfile $dockerfile

if [ -f "$model_type/$os_type/Dockerfile.extension" ]
then
    cat "$model_type/$os_type/Dockerfile.extension" >> $dockerfile
fi

docker build $build_args -f $dockerfile \
		--tag=waltplatform/$model_type-$os_type:latest .
docker tag waltplatform/$model_type-$os_type:latest \
			waltplatform/$model_type-$os_type:$os_version

rm -rf $tmp_dir
