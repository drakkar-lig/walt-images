
# notes:
# * for image consistency the version of the default kernel package in the
#   repositories identified by ALPINE_VERSION and DEBIAN_VERSION should be
#   the same as KERNEL_VERSION (at least major and minor numbers).
KERNEL_VERSION = "6.1.60"
KERNEL_ARCHIVE = f"https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-{KERNEL_VERSION}.tar.xz"
OS_VERSIONS = {
    'alpine': "3.18.4",
    'debian': "bookworm",
    'openwrt': "21.02.3",
    'mendel': "20211117215217",
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
    'coral-dev-board': { 'short': 'Coral Dev Boards', 'long': 'Google Coral Dev Boards' },
}

DEFAULT_OS_TYPE_PER_BOARD_MODEL = {
    'rpi-b': 'debian',
    'rpi-b-plus': 'debian',
    'rpi-2-b': 'debian',
    'rpi-3-b': 'debian',
    'rpi-3-b-plus': 'debian',
    'rpi-4-b': 'debian',
    'rpi-400': 'debian',
    'qemu-arm-32': 'debian',
    'qemu-arm-64': 'debian',
    'pc-x86-32': 'debian',
    'pc-x86-64': 'debian',
    'coral-dev-board': 'mendel',
}

OS_TYPE_LABEL = {
    'default': 'Default',
    'debian': 'Debian OS',
    'alpine': 'Alpine OS',
    'openwrt': 'OpenWRT',
    'mendel': 'Mendel Linux',
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
    },
    'rpi-serial-monitor': {
        'short': "WALT image for monitoring the serial line of another board",
        'long': """\
This image allows to use a Raspberry Pi node to log or view in realtime
the serial line output of another Raspberry Pi board. (Serial line pins
of those two boards must be bridged together.)"""
    },
    'pc-x86-64-k3s-server': {
        'short': "WALT image for turning a pc-x86-64 node into a Kubernetes server",
        'long': """\
This image allows to turn pc-x86-64 node into a single-node Kubernetes (k3s) cluster.
(See "pc-x86-64-k3s-agent" for adding more k3s nodes to this cluster.)"""
    },
    'pc-x86-64-k3s-agent': {
        'short': "WALT image for turning a pc-x86-64 node into a Kubernetes node",
        'long': """\
This image allows to add a k3s node to a cluster.
(See also "pc-x86-64-k3s-server".)"""
    },
    'rpi-rtk-base': {
        'short': "WALT image with RTKBase GPS software for raspberry pi boards",
        'long': """\
This walt Raspberry Pi image embeds RTKBase frontend and scripts for
managing U-Blox ZED-F9P Gnss Receiver."""
    }
}

