#!/bin/sh
set -e

os_type="$1"
os_version="$2"
model_type="$3"

if [ "$3" = "" ]
then
	echo "publish.sh must be called by make, not run directly."
	exit 1
fi

image_latest="waltplatform/$model_type-$os_type:latest"
image_version="waltplatform/$model_type-$os_type:$os_version"

docker push $image_latest
docker push $image_version

get_node_models_of_image() {
    image="$1"
    docker inspect --format '{{ index .Config.Labels "walt.node.models"}}' "$image" | tr ',' ' '
}

# note: debian images are also the default image for each node model
if [ "$os_type" = "debian" ]
then
	case "$model_type" in
		"pc-x86-64")
			models="pc-x86-64"
			;;
		"pc-x86-32")
			models="pc-x86-32"
			;;
		"rpi")
			models="$(get_node_models_of_image $image_latest)"
			;;
    esac
    for model in $models
    do
        image_model_default="waltplatform/${model}-default:latest"
        docker tag $image_latest $image_model_default
        docker push $image_model_default
    done
fi
