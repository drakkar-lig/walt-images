#!/usr/bin/env python3
import sys, subprocess
from pathlib import Path

if len(sys.argv) < 2:
	sys.exit("build.sh must be called by make, not run directly.")

import env

image_descriptor = sys.argv[1].split('.')

if image_descriptor[0] == 'featured':
    name = image_descriptor[1]
    subprocess.run(f'nice docker build \
        -f featured/{name}/Dockerfile \
        --tag=waltplatform/{name}:latest .',
        check=True, shell=True)
else:
    os_type, model_type = image_descriptor
    os_version = env.OS_VERSIONS[os_type]

    build_args=f"--build-arg OS_TYPE={os_type} --build-arg OS_VERSION={os_version}"

    # rpi model is more complex
    if model_type == "rpi":
        build_args += f" --build-arg KERNEL_ARCHIVE={env.KERNEL_ARCHIVE} \
                         --build-arg KERNEL_VERSION={env.KERNEL_VERSION}"


    # docker build
    print(f'nice docker build {build_args} \
            -f base/{model_type}/{os_type}/Dockerfile \
            --tag=waltplatform/{model_type}-{os_type}:latest .')
    subprocess.run(f'nice docker build {build_args} \
            -f base/{model_type}/{os_type}/Dockerfile \
            --tag=waltplatform/{model_type}-{os_type}:latest .',
            check=True, shell=True)
        
    # add another docker tag indicating version
    subprocess.run(f'docker tag waltplatform/{model_type}-{os_type}:latest \
            waltplatform/{model_type}-{os_type}:{os_version}',
            check=True, shell=True)
