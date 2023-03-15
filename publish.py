#!/usr/bin/env python3
import sys, subprocess, tempfile
from pathlib import Path

if len(sys.argv) < 2:
    sys.exit("publish.sh must be called by make, not run directly.")

import env

def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, shell=True, **kwargs)

def get_node_models_of_image(image):
    result = run(
        """docker inspect --format '{{ index .Config.Labels "walt.node.models"}}' """ + image,
        stdout=subprocess.PIPE).stdout
    return result.decode('ascii').strip().split(',')

def get_base_image_description(os_type, model_type, desc_type):
    os_type_label = env.OS_TYPE_LABEL[os_type]
    board_models_label = env.LABELS_PER_BOARD_MODEL[model_type][desc_type]
    return env.BASE_IMAGE_SHORT_DESC_TEMPLATES[desc_type].format(
            os_type=os_type_label,
            board_models=board_models_label)

def get_featured_image_description(image_name, desc_type):
    return env.FEATURED_IMAGE_SHORT_DESC_TEMPLATES[image_name][desc_type]

# This function updates the short description and the long one (README section)
# of an image on the docker hub by running a docker container chko/docker-pushrm
# designed for this purpose.
def publish_description(hub_repo_name, short_desc, long_desc):
    with tempfile.TemporaryDirectory() as tmp_d:
        readme_text = env.IMAGE_OVERALL_TEMPLATE.format(image_description = long_desc)
        readme_path = Path(tmp_d) / 'README.md'
        readme_path.write_text(readme_text)
        result = run(
            f"""docker run --rm -t -v {readme_path}:/tmp/README.md \
                           -e DOCKER_USER="$DOCKER_USER" -e DOCKER_PASS="$DOCKER_PASSWORD" \
                           chko/docker-pushrm:1 \
                                 --file /tmp/README.md \
                                 --short "{short_desc}" \
                                 --debug \
                                 docker.io/{hub_repo_name}""")

image_descriptor = sys.argv[1].split('.')

if image_descriptor[0] == 'featured':
    name = image_descriptor[1]
    run(f'docker push waltplatform/{name}:latest')
    publish_description(f'waltplatform/{name}',
                        get_featured_image_description(name, 'short'),
                        get_featured_image_description(name, 'long'))
else:
    os_type, model_type = image_descriptor
    os_version = env.OS_VERSIONS[os_type]

    hub_repo_name = f"waltplatform/{model_type}-{os_type}"
    image_latest = f"{hub_repo_name}:latest"
    image_version = f"{hub_repo_name}:{os_version}"

    # publish
    run(f'docker push {image_latest}')
    run(f'docker push {image_version}')
    publish_description(hub_repo_name,
                get_base_image_description(os_type, model_type, 'short'),
                get_base_image_description(os_type, model_type, 'long'))

    # note: debian images are also the default image for each node model
    if os_type == "debian":
        if model_type == 'rpi':
            models = get_node_models_of_image(image_latest)
        else:
            models = [ model_type ]
        for model in models:
            hub_repo_name = f"waltplatform/{model}-default"
            image_model_default = f"{hub_repo_name}:latest"
            run(f'docker tag {image_latest} {image_model_default}')
            run(f'docker push {image_model_default}')
            publish_description(hub_repo_name,
                get_base_image_description('default', model, 'short'),
                get_base_image_description('default', model, 'long'))
