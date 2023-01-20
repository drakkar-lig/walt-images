#!/usr/bin/env python3
import sys, subprocess

if len(sys.argv) < 4:
	sys.exit("publish.sh must be called by make, not run directly.")

import env

def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, shell=True, **kwargs)

def get_node_models_of_image(image):
    result = run(
        """docker inspect --format '{{ index .Config.Labels "walt.node.models"}}' """ + image,
        stdout=subprocess.PIPE).stdout
    return result.decode('ascii').strip().split(',')

image_descriptor = sys.argv[1].split('.')

if image_descriptor[0] == 'featured':
    name = image_descriptor[1]
    run(f'docker push waltplatform/{name}:latest')
else:
    os_type, model_type = image_descriptor
    os_version = env.OS_VERSIONS[os_type]

    image_latest = f"waltplatform/{model_type}-{os_type}:latest"
    image_version = f"waltplatform/{model_type}-{os_type}:{os_version}"

    # publish
    run(f'docker push {image_latest}')
    run(f'docker push {image_version}')

    # note: debian images are also the default image for each node model
    if os_type == "debian":
        if model_type == 'rpi':
            models = get_node_models_of_image(image_latest)
        else:
            models = [ model_type ]
        for model in models:
            image_model_default = f"waltplatform/{model}-default:latest"
            run(f'docker tag {image_latest} {image_model_default}')
            run(f'docker push {image_model_default}')
