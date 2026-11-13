# pc-x86-64 OpenWrt image

## Build files

* `build-files/openwrt.config`: changes compared to the default OpenWrt
  configuration (`make defconfig` expands it).
* `build-files/kernel-config`: changes to the default kernel configuration
  of the target (applied last by OpenWrt, see `LINUX_KCONFIG_LIST` in
  `include/target.mk`). Among other things, it builds NFS client and fuse
  support into the kernel, exposes the kernel config at `/proc/config.gz`,
  and disables CPU microcode late loading.

To change the kernel configuration, open a shell in the builder stage:
```
$ docker build --build-arg OS_TYPE=openwrt --build-arg OS_VERSION=<version> \
        --target openwrt-builder -t openwrt-builder \
        -f base/pc-x86-64/openwrt/Dockerfile .
$ docker run -it --rm --pull=never openwrt-builder bash
# cd /root/openwrt
# FORCE_UNSAFE_CONFIGURE=1 make kernel_menuconfig CONFIG_TARGET=env
```
This updates `env/kernel-config`: copy it back to `build-files/kernel-config`.
Keep the options that the new settings make visible in this file, so that the
kernel "oldconfig" step can run non-interactively.

## Network root filesystem and walt-net interface

The initramfs (`initrd_skeleton/`, `create_initramfs.sh`) loads the network
drivers commonly found on PCs, configures the boot interface and mounts the
root filesystem over NFS (retrying while the link comes up).

This interface must never be reconfigured afterwards, otherwise the root
filesystem would be lost. Since netifd resets the link of any interface it
manages, the walt-net interface is not declared in `/etc/config/network`.
Instead, `/etc/init.d/walt-net` detects it at bootup and attaches it to the
firewall zone `walt`, which accepts all traffic (the node must remain
reachable by the server). Consequently, dnsmasq cannot serve DHCP on walt-net.
