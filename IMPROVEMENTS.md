# walt-images: possible improvements

Notes collected while migrating the images to Debian trixie (branch `trixie`).
Ordered roughly by priority.

## 1. Integrate walt-node-boot into the build

**Done** (commit `d26cba3`, walt-node-boot fixes pushed to its master up to `f62855a`).

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

**Done**: the 3B+ was tested with `tests/smoke.sh` on 2026-11-13.

The Pi 4/400 now boots the arm64 `linux-image-rpi-v8` kernel through the
64-bit U-Boot (`config-64.txt`, `booti`), with the armhf userland. This was
tested on a Pi 4B, together with a non-regression test on a Pi 2B. A 3B+
still needs a non-regression test.

If the kernel grows, check the U-Boot load addresses in
`set-fetch-addresses.sh`. The kernel is at 0x80000 and the ramdisk at
0x2700000, which leaves about 38 MiB for the unpacked kernel; the current
rpi-v8 kernel is 25.6 MiB.

## 3. Other rpi32 images on Pi 4

- `rpi32-alpine`: **done** with the Alpine upgrade (commits `f6449ef`,
  `f82c7d5`). The armv7 Alpine kernel also lacks the BCMGENET ethernet
  driver, so `rpi32-alpine` (now armv7, models 2B, 3B and 3B+) keeps
  excluding the Pi 4, and the new `rpi64-alpine` image (aarch64, models
  3B+, 4B and 5B, booted directly by the firmware) supports it. The Pi 1
  models were dropped: recent Alpine versions provide a single `linux-rpi`
  kernel per architecture, and the armhf one only supports the Pi 1.
- `rpi32-sd-update`: **done** (commit `9a8a292`). The policy is to use a SD
  card on older models (<= 3B) and no SD card on newer ones (>= 3B+), so
  this image now only lists models up to 3B (its label was inherited from
  rpi32-debian). Thus the 32-bit U-Boot that walt-node-boot's `config.txt`
  selects for the Pi 4 on SD cards does not matter.

## 4. Harmonize the OpenWrt-based images

**Done** (commit `d766fb5`): like `pc-x86-64-openwrt` (commit `3642fd0`),
the chirpstack image now keeps the firewall enabled and
`/etc/init.d/walt-net` adds the walt-net device to firewall zone `walt`.

Remaining: the initramfs NFS mount retry of `pc-x86-64-openwrt` (commit
`4e834ac`) might also be useful for chirpstack on slow-negotiating links
(but on rpi boards the kernel mounts the NFS root itself, without an
initramfs).

## 5. Image metadata

- Architecture labels: **rejected**. Declaring the real ARM platform in the
  image metadata (tested with `docker build --platform`) works for clone,
  shell, build and boot, but podman then prints "image platform
  (linux/arm64) does not match the expected platform (linux/amd64)" in
  `walt image shell` and `walt image build`. Newer servers could pass
  `--platform` to podman, but older servers would show the warnings, and
  multi-stage user Dockerfiles would be affected. So images keep the amd64
  platform set by `docker build`, and the node model list remains the
  reference. This is documented in `README.md` ("Image architecture",
  commit `d78490c`).
- Multi-arch documentation: **done** (commit `7416415`). The Docker Hub long
  description of rpi32-debian explains its multi-arch setup (armhf userland
  plus an arm64 kernel on Pi 4, `raspbian.sources` restricted to armhf), and
  the alpine rpi images list their supported models.

## 6. Build tooling

**Done** (commits `d368a22`, `1988ae3`): `build.py` builds a missing local
parent image first (and otherwise indicates the date of the local image it
uses), and the k3s and RTKBase versions are pinned in `env.py`. Remaining:
the consistent pull policy, and Alpine's kexec-tools taken from
`edge/testing` (see the Alpine upgrade).

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

**Done** (commit `7d0ab45`): `tests/smoke.sh`. Image-specific checks
exist for the k3s images only; more can be added in
`tests/checks/<image>.sh`.

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

**Done** (commit `2bdccdc`).

- k3s featured images: document the node configuration they need:
  - `netsetup=NAT`
  - `boot.mode=hybrid-volatile`
  - `disks=8G[template=swap],16G[template=ext4]`, for the `/local` bind mount
- `pc-x86-64-openwrt`: document how to regenerate `build-files/kernel-config`
  (the procedure is currently only in a Dockerfile comment).

## 9. nbfs read-write mode (network-persistent boot mode)

The rename bug found on 2026-11-13 is fixed in nbfs commit `5e333c6` on
`etienne-dev`, which is deployed on the dev server. The cause was the SQL
UPDATE of `db_rename_entry()` placed inside an `assert()`, which is removed
with `-DNDEBUG`. Remaining issues found while debugging it:

- **State left by the buggy server.** Mounts used in rw mode before the fix
  keep stale lookup rows in `/var/lib/nbfsd/nbfsd-v3.db`. On `apu8-426`,
  after the fixed server was deployed, the node's nbfs client died during
  boot and during `apt update` (root fs gone: "Transport endpoint is not
  connected"). Expiring the mount (`update mounts set expiry = 0 where
  mount_id = <id>`, with nbfsd stopped, then letting nbfsd clean it up) fixed
  it. The client-side crash itself was not root-caused, since no console
  was available. A virtual node in network-persistent mode would make this
  easier. The rw mounts of the virtual nodes `vn-server`, `vn-server-trixie`,
  `vn-server-trixie2` and `vn-server-bookworm-old` were also used with
  the buggy server and may need the same reset.
- **nbfsd aborts on a missing lookup row.** `reverse_lookup()` calls
  `abort()` when an inode has no row, and `get_relative_path()` does the
  same when it cannot walk a path back. This kills the daemon for all
  clients. A per-request error such as ESTALE would be more robust.
- **Trash cleanup and inode numbers.** `clear_trash_content()` (called when
  a mount is opened) deletes lookup and request rows by inode number only
  (`entry_ino` is global, not per mount). Lookup inode numbers are sqlite
  rowids without AUTOINCREMENT, so they are reused after rows are deleted,
  for example when a mount expires. A trash entry left over from an expired
  mount could then discard rows that belong to another file or mount.
  Possible fixes: restrict the discards to the mount being opened, or clear
  the trash when the mount's cache expires.

## 10. walt server: one stuck node connection blocks the hub

On 2026-11-13, the `server-hub` process (pid 2307) was blocked in a
blocking `recv()` on a connection from `apu8-426` (192.168.222.47 to port
12345). The node had opened the connection and then lost its root
filesystem. All walt commands failed with "Network connection to WalT
server failed!", and nodes could not report that they had booted, so boot
timeouts caused reboot loops. Killing that TCP connection
(`ss -K dst 192.168.222.47 dport = <port>`) unblocked it. The hub should
use non-blocking reads or a timeout when it reads the first message of a
new connection.

## 11. walt server: check the switch port before turning PoE off

This item is for walt-python-packages, not walt-images.

**Problem.** The walt database (`walt device tree`) may still record an old
device on a switch port after that device was unplugged. If a different
node is now plugged into the same port, turning PoE off for the old device
cuts the power of the new one. This happens with:

- `walt node reboot --hard <old-node>`
- powersave, when the old device was a free node and its
  `powersave.timeout` expires

**Seen on 2026-11-13.** `walt device tree` still showed `node-dd68a7`, a
free node unplugged long ago, on `switch-8efa0f` port 5. `nanopi` had been
plugged into that port in the morning. When the powersave timeout of
`node-dd68a7` expired, the server turned PoE off on port 5 and so powered
`nanopi` off. `walt-lldp-monitor` (in the new images) corrects the
topology once the node has booted, but the node may not have finished
booting, or its LLDP daemon may not have seen the switch yet.

**Proposal.** Just before turning a port's PoE off, read the switch
forwarding table (FDB) for that port through SNMP:

- if a MAC address other than the expected node's is learned on the port,
  do not power it off. Mark the topology entry as obsolete
  (`forget_topology_entry_for_mac()`, as `node_bootup_event()` already does
  in `powersave.py`), and log or report an error that suggests running
  `walt device rescan`.
- if the expected MAC is learned, go ahead.
- if no MAC is learned, the device may be idle and its FDB entry may have
  expired (often after about 5 minutes). The server could either keep the
  current behaviour or ping the node first. For powersave, the safest
  choice is to skip the power-off.

**Where in the code** (`server/walt/server/`):

- `processes/main/poe.py`: `PoEManager.wf_nodes_set_poe()` /
  `_wf_sw_port_set_poe()` (runs `walt-set-poe`). A check step here would
  cover both callers when `poe_status` is False.
- callers: `processes/main/nodes/powersave.py` (`_check()`,
  `_wf_toggle_power_on_nodes()`) and `processes/main/nodes/reboot.py`
  (`wf_poe_reboot()`, `wf_poe_poweroff()`).
- `snmp/bridge.py`: `VLANCapableBridge.get_macs_per_port()` already reads
  `dot1qTpFdbPort` / `dot1qTpFdbStatus` (learned entries). Note that FDB
  port numbers are bridge port numbers (`dot1dBasePort`). They may need
  mapping (`dot1dBasePortIfIndex`) to the port numbering used for
  LLDP/PoE (see the port correlation logic in `snmp/poe.py`).

## 12. walt server: crash when a vnode reboots before it is registered

On 2026-11-13 at 12:30, `walt-server` crashed with
`KeyError: '52:54:00:ed:6a:16'` in `nodes/manager.py`,
`vnode_hard_reboot()` (`self.vnodes[node_mac]`). The server had just been
restarted, and `walt image clone --force` rebooted `vn-openwrt` before
`restore()` had registered its virtual node. `vnode_hard_reboot()` (and
probably the other `vnode_*` methods) should handle a missing entry, for
example by starting the vnode or reporting an error to the caller.

Also, systemd did not restart `walt-server` after this crash: the unit has
`Restart=on-failure`, but the daemon exited with status 0 ("Deactivated
successfully") despite the unhandled exception. The daemon should exit with
a non-zero status when a subprocess crashes. (At 12:20, during a disk-full
period, systemd did restart it, but the start rate limit stopped it after
6 failed attempts within 8 seconds; a `RestartSec=` of a few seconds would
let it retry for longer.)

## 13. Housekeeping

- **Done** (commit `13218f5`). Remove the Raspberry Pi 400 from the supported boards. It was added
  around 2020, at the request of a potential user, as an alternative while
  Pi 4 boards were hard to find. It was never tested on real hardware and
  was probably never used. This means removing `rpi-400` from the image
  labels, the `overlays/*/boot/rpi-400` directories, the `rpi-400` dtb
  entries in the FIT images, and `LABELS_PER_BOARD_MODEL` in `env.py`.
  The walt documentation in walt-python-packages still mentions the
  Pi 400 and the Coral board.
- **Done** (commit `a2ddd44`). Remove the obsolete Mendel (coral-dev-board) image.
- `rpi32-rtk-base`: report upstream that rtkbase's
  `install_polkit_rules.sh` misdetects polkit through `dpkg-query -W`.
  The image works around this by installing `polkitd` explicitly.
- **Done** (commits `f6449ef`, `f82c7d5`). Upgrade Alpine (deferred during the trixie
  migration): 3.18.4 -> 3.24.4. mkinitfs now builds a usr-merged
  initramfs and silently produced an incomplete one (no root mount)
  because of our `/sbin/mount.nbfs` symlink; fixed, and mkinitfs failures
  now abort the build.
- The rpi-2-b node did not reboot automatically after a kernel panic
  ("Mounting root: failed", then "SMP: failed to stop secondary CPUs"). A
  `panic=<seconds>` kernel parameter might help, to be checked.

## 14. walt client: exit codes and failures

walt commands may return exit code 0 when something failed, which breaks
scripts (e.g., `tests/smoke.sh`, which now works around both cases below).
All commands should return a non-zero exit code on failure.

- `walt image clone` returned 0 when the server raised an exception: on
  2026-11-13, cloning a newly built image from the docker daemon
  (`docker:waltplatform/rpi32-alpine:latest`) failed with
  `podman.errors.exceptions.ImageNotFound: 404 ... image not known`. The
  client printed the error but exited 0. The failure itself is a server bug:
  the clone workflow (`save_initial_images` / `remove_server_image` steps)
  tried to tag or remove `docker.io/waltplatform/rpi32-alpine:latest` in
  podman before the `pull_image` step, but this new image was not in
  podman's storage yet. After a manual `podman pull
  docker-daemon:waltplatform/rpi32-alpine:latest`, the clone succeeded.
  Probably the server's image store believed the image was already there
  (the docker daemon images are synced in `processes/main/images/store.py`).
- `walt node wait --timeout <t>` did not return in some cases (node not
  booting).
