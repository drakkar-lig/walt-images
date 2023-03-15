
# notes:
# * for image consistency the version of the default kernel package in the
#   repositories identified by ALPINE_VERSION and DEBIAN_VERSION should be
#   the same as KERNEL_VERSION (at least major and minor numbers).
KERNEL_VERSION = "5.10.63"
KERNEL_ARCHIVE = f"https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-{KERNEL_VERSION}.tar.xz"
OS_VERSIONS = {
    'alpine': "3.13.7",
    'debian': "bullseye",
    'openwrt': "21.02.3"
}

LABELS_PER_BOARD_MODEL = {
    'rpi': { 'short': 'Rpi boards', 'long': 'various Raspberry Pi models' },
    'rpi-b': { 'short': 'Rpi B boards', 'long': 'Raspberry Pi B boards' },
    'rpi-b-plus': { 'short': 'Rpi B+ boards', 'long': 'Raspberry Pi B+ boards' },
    'rpi-2-b': { 'short': 'Rpi 2B boards', 'long': 'Raspberry Pi 2B boards' },
    'rpi-3-b': { 'short': 'Rpi 3B boards', 'long': 'Raspberry Pi 3B boards' },
    'rpi-3-b-plus': { 'short': 'Rpi 3B+ boards', 'long': 'Raspberry Pi 3B+ boards' },
    'rpi-4-b': { 'short': 'Rpi 4B boards', 'long': 'Raspberry Pi 4B boards' },
    'rpi-400': { 'short': 'Rpi 400 keyboards', 'long': 'Raspberry Pi 400 keyboards' },
    'qemu-arm-32': { 'short': '32-bit ARM qemu VMs', 'long': '32-bit ARM qemu VMs' },
    'qemu-arm-64': { 'short': '64-bit ARM qemu VMs', 'long': '64-bit ARM qemu VMs' },
    'pc-x86-32': { 'short': '32-bit PC machines', 'long': '32-bit PC machines' },
    'pc-x86-64': { 'short': '64-bit PC machines', 'long': '64-bit PC machines' },
}

OS_TYPE_LABEL = {
    'default': 'Default',
    'debian': 'Debian OS',
    'alpine': 'Alpine OS',
    'openwrt': 'OpenWRT',
}

IMAGE_OVERALL_TEMPLATE = """
![walt logo](https://pimlig.imag.fr/wp-content/uploads/2019/03/logo-walt-123.png)
**WalT** project allows to build **highly configurable platforms for network experiments**.

**Check-out the [website](https://walt-project.liglab.fr) for more info.**

{image_description}

---
![walt animated use case](https://walt-project.liglab.fr/-/wikis/walt.gif)
"""

BASE_IMAGE_SHORT_DESC_TEMPLATES = {
    'short': "{os_type} WALT image for {board_models}",
    'long': "This image is the {os_type} WalT image for {board_models}."
}

FEATURED_IMAGE_SHORT_DESC_TEMPLATES = {
    'rpi-sd-update': {
        'short': "WALT image for automatic RPi SD updates",
        'long': """\
This image allows to automatically update the network bootloader and firmware files
stored on the SD card of Raspberry Pi nodes."""
    }
}

