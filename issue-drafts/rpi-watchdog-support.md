**Target:** https://github.com/drakkar-lig/walt-python-packages/issues (mostly about walt-images)

**Title:** Raspberry Pi nodes: use the hardware watchdog in all images, to recover from hung reboots

### Context

A Raspberry Pi 2B node booting an Alpine image (`rpi32-alpine`) did not reboot after a kernel panic. The console showed "Mounting root: failed" (Alpine's initramfs), the panic, then "SMP: failed to stop secondary CPUs", and the board stayed stuck. The kernel already receives `panic=15`, and a panic triggered at runtime (`echo c > /proc/sysrq-trigger`) reboots the same node in about 30 seconds, with both the Debian and Alpine kernels. So in this case the restart itself hung, and only the hardware watchdog could have recovered the node.

How the bcm2835 watchdog is currently used:
- **Before the kernel:** since January 2023, the boot files built by walt-node-boot arm it: `dtparam=watchdog=on` in `config.txt`, and u-boot with `CONFIG_WATCHDOG_AUTOSTART` (15 s, `WDT_BCM2835` driver). But boards that boot from a SD card (models <= 3B) may have older boot files: the SD card of this node has `walt.date` = Feb 14, 2022, so nothing arms the watchdog before userspace opens it. (Image `rpi32-sd-update` can update these files, but nodes deployed long ago should keep working with their old SD cards.)
- **In the kernel:** both the Raspberry Pi OS kernel of our Debian images and the kernel config in walt-images have `CONFIG_WATCHDOG_HANDLE_BOOT_ENABLED=y` and `CONFIG_WATCHDOG_OPEN_TIMEOUT=0`. If the bootloader left the watchdog running, the kernel resets it on its own until userspace opens `/dev/watchdog`, with no time limit. During early boot (initramfs), or in an image where nothing opens the watchdog, a CPU that kept running after the panic can therefore keep resetting the watchdog forever.
- **In userspace:** only the Debian images use it: systemd with `RuntimeWatchdogSec=180` and `RebootWatchdogSec=180` (set in `overlays/debian/root/customize.sh`). Nothing opens it in the Alpine images (`rpi32-alpine`, `rpi64-alpine`). The OpenWrt-based `rpi32-chirpstack` image should be checked (procd normally handles the watchdog).

### Proposal

1. **Alpine images:** open the watchdog in userspace, e.g. with busybox's `watchdog` applet started early by OpenRC (a timeout similar to the Debian images, and a short reset interval). After a panic or a hang, the resets stop and the board reboots.
2. **Early boot and old boot files:** pass `watchdog.open_timeout=<seconds>` on the kernel command line (u-boot script `compute-bootargs.sh` for rpi32 images, `cmdline-*.txt` for rpi64 images), e.g. a few minutes. Then the kernel stops resetting a watchdog armed by the bootloader if userspace does not open it in time, which covers a hang in the initramfs. This requires that every Raspberry Pi image opens the watchdog (item 1), otherwise nodes would reboot after this delay. With old boot files the watchdog is not armed before userspace, so this only helps with recent boot files; item 1 helps in both cases once userspace is running.
3. **Other images and boards:** check the watchdog in the other node images (rpi64-debian, nanopi-r5c, featured images based on rpi32-debian inherit systemd's setting; chirpstack/procd).
4. **Test:** with both old (2022) and recent SD card boot files, check that a node reboots:
   - after a runtime panic (`echo c > /proc/sysrq-trigger`);
   - when it hangs without a panic, e.g. `kill -STOP` on the watchdog daemon or systemd's watchdog disabled at runtime (the board must reboot after the watchdog timeout);
   - after a failure in the initramfs (Alpine), if it can be reproduced.
