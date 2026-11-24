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

Closed (2026-11-24): the initramfs NFS mount retry of `pc-x86-64-openwrt`
(commit `4e834ac`) does not apply to chirpstack for now, since on rpi
boards the kernel mounts the NFS root itself, without an initramfs. The
user plans to rework the chirpstack image later (rpi5b support, which will
need an initramfs to boot as a VPN node); the retry can be reconsidered
then.

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
uses), and the k3s and RTKBase versions are pinned in `env.py`.

**Done** (commits `efe760f`, `4671dbc`), 2026-11-24:
- pull policy: with BuildKit, docker build uses a FROM image of the local
  image store (matching platform) without checking the registry, and
  resolves it on the registry only if it is missing. So local
  `waltplatform/*` and rpi-boot-builder images were already used as is
  (`--pull=never` is not needed), but external images (e.g.
  `arm32v7/alpine:3.24.4`, pulled on 2026-11-05) could be outdated.
  `build.py` now pulls the external FROM images, with their platform,
  before each build (tested with `make build.alpine.pc-x86-64`).
- external sources: all pinned (OpenWrt, ChirpStack and u-boot's
  `merge_config.sh` tags, k3s, RTKBase, nanopi-r5 release and
  linux-firmware, rpi kernel archive). Only distribution packages are
  not, which is expected.
- Alpine's kexec-tools is now taken from the release (`community`
  repository) instead of `edge/testing`. This code is disabled
  (`HAS_4671dbc=0`).

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

**Done** (commit `2bdccdc`). Checked on 2026-11-24: the k3s descriptions
(`env.py`) match the configuration of the live k3s-server node and the
walt docs, and `base/pc-x86-64/openwrt/README.md` matches the Dockerfile.

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

**Done** (walt-python-packages commit `cee2137d`, tag `future-v11`), tested
live on 2026-11-23. The blocking read was in `TCPServer` (common), so
server-main's TCP server (port 12347) had the same issue. A new connection
is now handled by a `ListenerWrapper` registered in the event loop: it
reads the request id only when data arrives (the end of the line must
arrive within 2 seconds), closes the connection if nothing arrives within
30 seconds, then creates the request listener and passes it the next
events. server-hub reads the target API line with the same 2 seconds
timeout. Remaining limit: a client sending half a line and then freezing
still blocks the process for up to 2 seconds; and later messages (e.g.,
pickled API calls) are still read with blocking reads.

Related cleanup, merged into commit `210b0a5b` ("evloop: make the event
loop the sole owner and closer of watched files"): since this commit, the
event loop gets the fd from the watched file, not from
`listener.fileno()`, so the unused `fileno()` methods of 21 listener
classes were removed (kept on `ProcessConnector`, `SensorLogsMonitor` and
file-like objects, which still need it).

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

**Done** (walt-python-packages commit `1ccd453e`, tag `future-v11`), tested
end to end on 2026-11-23: with a node moved to a switch port where walt
still recorded another node, `walt node reboot --hard <old node>` failed
with "detected another device on this switch port" (shortened after the
test), the obsolete topology entry was forgotten, and the
moved node kept running (walt-lldp-monitor was disabled in its image, since
it may already report such changes). When turning PoE off, `walt-set-poe`
receives the node MAC and reads the MACs detected on the port (LLDP
neighbor table and forwarding table, as `walt device rescan` does). If
other MACs but not the node one are detected, it exits with code 2 without
touching PoE, and the server forgets the topology entry. If nothing is
detected, or the tables cannot be read, the behavior is unchanged. The PoE
operation itself still uses the port mapping heuristics of `snmp/poe.py`
(they assume LLDP port number == ifIndex). The user filed the issue for a more
reliable mapping (`dot1dBasePortIfIndex`, etc.):
https://github.com/drakkar-lig/walt-python-packages/issues/170.
Remaining limit: `walt node reboot` still exits with 0 when the reboot
fails.

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

**Done** (walt-python-packages, tag `future-v11`), tested live on 2026-11-23:
- commit `67b28f2e`: the daemon exits with a failure status when a
  subprocess fails (it still exits with 0 on SIGTERM), and the unit has
  `RestartSec=5`.
- commit `7988a8dc`: server-hub holds the requests of walt clients (CSAPI)
  until server-main calls `release_csapi()` at the end of its startup
  workflow, which includes the startup of virtual nodes ("Ready." is
  printed at this time). The other APIs are forwarded immediately, since
  the startup uses them (`walt-exports-update` calls
  `SSAPI.get_exports_info()`). So a client request can no longer reach a
  vnode that is not registered yet; the `vnode_*` methods were left as is.

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
  The walt documentation in walt-python-packages also mentioned the Pi 400
  and the Coral board: **done** (commit `a854abfe`, tag `future-v11`).
- **Done** (commit `a2ddd44`). Remove the obsolete Mendel (coral-dev-board) image.
- `rpi32-rtk-base`: report upstream that rtkbase's
  `install_polkit_rules.sh` misdetects polkit through `dpkg-query -W`.
  The image works around this by installing `polkitd` explicitly.
  Filed by the user: https://github.com/Stefal/rtkbase/issues/566.
- **Done** (commits `f6449ef`, `f82c7d5`). Upgrade Alpine (deferred during the trixie
  migration): 3.18.4 -> 3.24.4. mkinitfs now builds a usr-merged
  initramfs and silently produced an incomplete one (no root mount)
  because of our `/sbin/mount.nbfs` symlink; fixed, and mkinitfs failures
  now abort the build.
- The rpi-2-b node did not reboot automatically after a kernel panic
  ("Mounting root: failed", then "SMP: failed to stop secondary CPUs"). A
  `panic=<seconds>` kernel parameter might help, to be checked.
  Checked on 2026-11-24: the rpi32 images already pass `panic=15` (u-boot
  script `compute-bootargs.sh`; rpi64 images in `cmdline-*.txt`). A panic
  triggered at runtime (`echo c > /proc/sysrq-trigger`) on rpi2b rebooted
  the node within ~30 s, both with rpi32-debian and rpi32-alpine kernels.
  The original hang ("Mounting root: failed" comes from Alpine's
  initramfs, during the Alpine upgrade) happened when "SMP: failed to stop
  secondary CPUs": the restart itself hung, probably intermittent.
  The hardware watchdog is already armed before the kernel starts
  (walt-node-boot, since 2023-01: `dtparam=watchdog=on` in config.txt, and
  u-boot `CONFIG_WATCHDOG_AUTOSTART`, 15 s, `WDT_BCM2835`), but the SD
  card of rpi2b has older boot files (`walt.date`: 2022-02-14), kept on
  purpose to test new images with old boot files. Possible explanation of
  the hang anyway: the rpi32 kernel has `WATCHDOG_HANDLE_BOOT_ENABLED=y`
  and `WATCHDOG_OPEN_TIMEOUT=0`, so it pets a watchdog left running by
  u-boot until userspace opens it, without limit. In the initramfs (or in
  images where nothing opens the watchdog, e.g. Alpine: only Debian sets
  systemd's `RuntimeWatchdogSec=180`), a CPU that was not stopped after
  the panic may keep petting it. Possible fixes (not done, to discuss):
  kernel parameter `watchdog.open_timeout=<s>` (the kernel stops petting
  if userspace did not open the watchdog in time; the command line is
  defined per image, so it can be added only to images whose userspace
  opens the watchdog), and a watchdog daemon in Alpine
  images (e.g. busybox `watchdog`). Draft issue:
  `issue-drafts/rpi-watchdog-support.md`.

## 14. walt client: exit codes and failures

**Done** for the exit codes (walt-python-packages commit `a94d381c`, tag
`future-v11`, implemented as planned below): failing commands now
exit with code 1. The workarounds in `tests/smoke.sh` remain useful with
older walt clients.

walt commands may return exit code 0 when something failed, which breaks
scripts (e.g., `tests/smoke.sh`, which now works around both cases below).
All commands should return a non-zero exit code on failure.

- **Root cause found** (2026-11-13): by convention, the `main()` method of a
  walt client command returns `False` on failure, and
  `client/walt/client/wrap.py` converts `SystemExit(False)` into exit code 1.
  But plumbum 2.x (the server pins `plumbum==2.0.2`, and the client accepts
  `plumbum>=1.7.2`) ends `Application._parse_and_dispatch()` with
  `return inst, retcode or 0`, so `False` becomes `0` before the wrapper
  sees it. Thus all walt commands returning `False` exit with code 0. For
  instance, `walt image clone docker:waltplatform/does-not-exist:latest x`
  prints "No such remote image" and exits 0. This was not noticed because
  plumbum was upgraded to 2.x recently.

  **Planned fix** (walt-python-packages, `client/walt/client/application.py`):
  convert the return value of `main()` in walt's own base class, before
  plumbum sees it, which works with both plumbum 1.x and 2.x:
  ```python
  class WalTApplication(cli.Application):
      def __init_subclass__(cls, **kwargs):
          super().__init_subclass__(**kwargs)
          main = cls.__dict__.get("main")
          if main is not None:
              @functools.wraps(main)
              def wrapped_main(self, *args, **kwargs):
                  res = main(self, *args, **kwargs)
                  if res is False:
                      return 1
                  if res is True:
                      return 0
                  return res
              # plumbum reads the positional arguments with
              # inspect.getfullargspec(), which ignores __wrapped__
              wrapped_main.__signature__ = inspect.signature(main)
              cls.main = wrapped_main
  ```
  Setting `__signature__` is required: without it, plumbum sees
  `(*args, **kwargs)`, so argument validators (such as `IMAGE_CLONE_URL`)
  are skipped and the help is wrong. This sketch was tested with plumbum
  2.0.2 (exit codes, validators, too many arguments, help). The `False`/`True` handling of
  `wrap.py` can then be removed. Check the commands whose `main()` is not
  defined in a `WalTApplication` subclass, and add a test such as:
  `walt image clone docker:waltplatform/does-not-exist:latest x; [ $? -eq 1 ]`.
- ~~`walt node wait --timeout <t>` did not return in some cases (node not
  booting).~~ **Not a bug** (analysed on 2026-11-23 from the server journal
  of 2026-11-13): `walt node wait --timeout 600` did time out after exactly
  600 s, but returned 0 because of the plumbum 2 issue above. `tests/smoke.sh`
  then ran its checks with `walt node run`, which waits for the node bootup
  without any timeout, and that command hung. Fixed by the exit code fix;
  `tests/smoke.sh` now also checks the output of `walt node wait` for
  "Timeout was reached" (walt-images commit `e03e6d2`, for older clients).

## 15. walt server: clone failure analysis

On 2026-11-13, `walt image clone --force docker:waltplatform/rpi32-alpine:latest
smoke-rpi32-alpine` failed with `podman.errors.exceptions.ImageNotFound`,
and the failure deleted the user's existing image (its backup remained as
`localhost/walt/clone-temp:a68d5ec5`).

The trigger was an image removed with `podman rmi`, outside of walt, while
the server's image store still listed it. **Not to be fixed**: the podman
repository is internal to walt (owned by root on production servers), so
this state is not possible there; users who build images themselves use
docker or `walt image build`.

Clone failures in a consistent state were reviewed (pull errors, which
raise an exception through `RegistryClientBase.checker()`; verification
steps returning `False`, which always run before any image is modified;
errors when tagging the cloned image): `WorkflowCleaner.cleanup()`
restores the backups correctly in these cases. No specific fix needed.
The only problem left is the exit code (see item 14).

## 16. walt image shell: failed systemd units on emulated images

**Done** (commits `f6fca5e`, `d729070`), tested on 2026-11-23. In
`walt image shell`, debian images start systemd in the container. On
emulated images (rpi32-debian on the amd64 server), the units declaring
credentials (`LoadCredential=`, `ImportCredential=`...) failed with
`243/CREDENTIALS`: systemd forks `(sd-mkdcreds)` in a new mount namespace,
and qemu-user rejects this `clone()` with EINVAL. The state was "degraded",
with systemd-journald, systemd-tmpfiles-setup, systemd-sysusers, etc.
failed. Native images (pc-trixie) were fine. `walt-image-shell-start` now
resets the credentials of these units with drop-ins in
`/run/systemd/system` (not saved in the image). postgresql worked even
before the fix. New test: `tests/image-shell-debian.sh <image>`
(postgresql in a derived image, built with `walt image build`; no node
needed): 1 failure on the current rpi32-debian build, 2 passes with the
fix.

To do:
- rebuild and publish the debian images to ship the fix.
- **Done** (commit `600385b`): `walt-image-shell-start` and
  `walt-image-shell-shutdown` never ran the scripts of
  `/bin/walt-image-shell-{start,shutdown}.d/` (`ls dir/*` already prints
  full paths, and the loop prefixed the directory again).
