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

## 12. Housekeeping

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
