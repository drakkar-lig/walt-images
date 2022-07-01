
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
