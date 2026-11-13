# walt-images: possible improvements

Notes collected while migrating the images to Debian trixie (branch `trixie`).
Ordered roughly by priority.

## 1. Integrate walt-node-boot into the build

**Problem.** Three Dockerfiles take boot files from the intermediate
image `waltplatform/rpi-boot-builder` that walt-node-boot produces:

- `base/rpi32/debian/Dockerfile`
- `base/rpi32/alpine/Dockerfile`
- `featured/rpi32-sd-update/Dockerfile`

These boot files are U-Boot binaries, `config*.txt` and firmware files. Since
`COPY --from=` only reads an image, the build silently uses whatever is in the
local Docker cache, or else whatever is on Docker Hub. The Docker Hub version
dates from 2022: its 32-bit U-Boot runs `distro_bootcmd`, not the WalT
bootcmd, and it has no 64-bit U-Boot. Nothing records which walt-node-boot
commit the binaries come from.

**Proposal.**

- Add walt-node-boot as a git submodule, for example at `walt-node-boot/`. It
  pins the commit, and updating the boot binaries becomes a reviewable
  submodule bump.
- Tag the builder image with the submodule commit:
  `waltplatform/rpi-boot-builder:<short-sha>`. Before building an image that
  needs it, `build.py` (or the Makefile) checks whether this tag exists
  locally. If not, it tries `docker pull`, and if that fails it builds the
  image from `walt-node-boot/rpi`. That build takes several minutes, mostly
  compiling U-Boot, but only happens once per submodule bump.
- Pass the tag to the Dockerfiles through a build argument, and point
  `COPY --from` at an alias stage:
  ```dockerfile
  ARG RPI_BOOT_BUILDER=waltplatform/rpi-boot-builder:latest
  FROM ${RPI_BOOT_BUILDER} AS rpi-boot-files
  ...
  COPY --from=rpi-boot-files /opt/boot_files/... ...
  ```
  This avoids picking up an unrelated `:latest` by accident.
- Optionally, publish the tagged builder image on Docker Hub when releasing,
  so that most builds can pull it instead of compiling U-Boot.

**Fixes needed in walt-node-boot first.** These are currently only in a
scratch clone.

- `rpi/Dockerfile`: `FROM debian:bullseye` fails because bullseye-security
  now returns 404 (LTS ended). Move to `debian:bookworm` (or trixie) and
  replace `python` with `python3`.
- The 32-bit U-Boot tarball comes from `ftp.denx.de`, which may be
  unreachable. Use the GitHub archive instead:
  `https://github.com/u-boot/u-boot/archive/refs/tags/v2023.10.tar.gz`,
  downloaded with `wget -O u-boot.tar.gz` and followed by
  `mv u-boot-* u-boot`.

## 2. Test the rpi32-debian boot on all Raspberry Pi models

The Pi 4/400 now boots the arm64 `linux-image-rpi-v8` kernel through the
64-bit U-Boot (`config-64.txt`, `booti`), with the armhf userland. This was
tested on a Pi 4B, together with a non-regression test on a Pi 2B. A 3B+
still needs a non-regression test.

If the kernel grows, check the U-Boot load addresses in
`set-fetch-addresses.sh`. The kernel is at 0x80000 and the ramdisk at
0x2700000, which leaves about 38 MiB for the unpacked kernel; the current
rpi-v8 kernel is 25.6 MiB.

## 3. Other rpi32 images on Pi 4

- `rpi32-alpine` still takes `u-boot-rpi-4-b.img`, the 32-bit U-Boot.
  Check whether its armv7 kernel has `CONFIG_BCMGENET` (the trixie Debian
  rpi-v7 kernel does not). If not, use the same 64-bit U-Boot and kernel
  approach as rpi32-debian. Can be done as part of the Alpine upgrade.
- `rpi32-sd-update`: check which U-Boot files it now gets from the rebuilt
  builder image.

## 4. Harmonize the OpenWrt-based images

`pc-x86-64-openwrt` now leaves the walt-net interface alone (commit
`efe9657`):

- `/etc/config/network` has the loopback only.
- `/etc/init.d/walt-net` adds the device to firewall zone `walt` at bootup.
- netifd and the firewall remain enabled.

`featured/rpi32-chirpstack` still removes the firewall and dnsmasq rc
scripts instead. Reusing the same overlay would:

- give both images the same behaviour;
- let users enable the OpenWrt firewall or add more interfaces in the
  chirpstack image.

The initramfs NFS mount retry (commit `75b0b41`) might also be useful there
on slow-negotiating links.

## 5. Image metadata

- Add image architecture labels: a declared architecture per image instead
  of relying on the node model list. This was deferred during the migration.
- Note that rpi32-debian is now multi-arch: armhf userland plus an arm64
  kernel package on Pi 4/400, with `Architectures: armhf` restricting
  `raspbian.sources`. Document this somewhere visible to users, because
  `apt` will show `:arm64` packages.

## 6. Build tooling

- `build.py` doesn't know the dependencies between images. For example,
  `rpi32-rtk-base` is `FROM rpi32-debian:latest`. Building a featured image
  silently uses whatever base image is in the local cache. The Makefile or
  `build.py` could declare and build dependencies first, possibly
  including the `rpi-boot-builder` image from item 1.
- Use a consistent pull policy (`--pull=never` for local base images,
  explicit pulls for external ones) so that builds are reproducible.
- Pin the external sources fetched at build time (OpenWrt and ChirpStack tags
  are pinned; check the others).

## 7. Smoke tests

Add a small script, for example `tests/smoke.sh <image> <node>`, that runs:

- `walt image clone --force docker:waltplatform/<image>:latest`
- `walt node boot`
- `walt node wait`
- a few `walt node run` checks, chosen per image: kernel version, the network
  root is mounted read-only, key services are running, `apt update` works
  when NAT is on

This would make it quicker to re-test all images on hardware before a
release.

## 8. Documentation

- k3s featured images: document the node configuration they need:
  - `netsetup=NAT`
  - `boot.mode=hybrid-volatile`
  - `disks=8G[template=swap],16G[template=ext4]`, for the `/local` bind mount
- `pc-x86-64-openwrt`: document how to regenerate `build-files/kernel-config`
  (the procedure is currently only in a Dockerfile comment).

## 9. Known issue found during tests: rename on an nbfs root

On `apu8-426` (pc-x86-64, network-persistent mode), the trixie pc-x86-64
image mounts its root filesystem with nbfs (`fuse.nbfs`). There, renaming a
file loses it:

```sh
echo b > g.tmp; mv g.tmp g   # mv returns 0
ls                           # neither g.tmp nor g is listed
cat g                        # "Out of streams resources" (ENOSR)
```

`rm -rf` of the directory then fails with "Directory not empty". As a
consequence, `apt update` fails (its "store" method renames the downloaded
index files). With the same node on the bookworm image (NFS root), the same
test passes. The `mount.nbfs` client in `overlays/mount.nbfs.amd64` was
last updated in commit `0fcec1e` (2026-11-10). The bug may be in that
client or in the server's nbfsd. Not yet analysed.

## 10. Housekeeping

- Remove the Raspberry Pi 400 from the supported boards. It was added
  around 2020, at the request of a potential user, as an alternative while
  Pi 4 boards were hard to find. It was never tested on real hardware and
  was probably never used. This means removing `rpi-400` from the image
  labels, the `overlays/*/boot/rpi-400` directories, the `rpi-400` dtb
  entries in the FIT images, and `LABELS_PER_BOARD_MODEL` in `env.py`.
- Remove the obsolete Mendel (coral-dev-board) image.
- `rpi32-rtk-base`: report upstream that rtkbase's
  `install_polkit_rules.sh` misdetects polkit through `dpkg-query -W`.
  The image works around this by installing `polkitd` explicitly.
- Upgrade Alpine (deferred during the trixie migration).
