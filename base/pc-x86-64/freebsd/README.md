# pc-x86-64-freebsd

A WalT image running FreeBSD on pc-x86-64 nodes, physical or virtual.

Status: **prototype**. It boots on virtual nodes in the default boot mode
(`boot.mode=network-volatile`), `walt node save` works, and the image can be
modified with `walt image shell`, `walt image cp` and `walt image build`.
Other boot modes probably do not work yet, and physical nodes were less
tested (see the end of this file). It is based on FreeBSD 14.3 (`OS_VERSIONS` in `env.py`), whose
support has ended.

It requires a WalT server >= 11 (label `walt.server.minversion`), which
brings the server-side changes listed below.

Build it with `make build.freebsd.pc-x86-64`.


## Overview

A WalT OS image is a container image, and WalT uses it in two ways:
- a node boots it over the network: the server exports the image
  filesystem over NFS, and the node runs `/bin/walt-init` from it, which
  prepares the root filesystem according to the boot mode, then starts the
  real init process of the OS;
- the server runs it as a container with podman (`walt image shell`, `RUN`
  instructions of `walt image build`, `walt image cp`).

FreeBSD differs from Linux in both cases: its boot chain does not fit how
virtual nodes boot, `walt-init` relies on Linux features (overlayfs, bind
mounts, `pivot_root`...), and its binaries cannot run on the Linux kernel of
the server. The next sections explain how each of these problems was solved.


## Booting

### Physical nodes

WalT nodes boot iPXE, which runs `/boot/<model>/start.ipxe` from the image
(here `files/start.ipxe`, installed at `/boot/pc-x86-64/start.ipxe`). On a
physical node, this script loads FreeBSD's own network boot loader:
`/boot/pxeboot` (legacy BIOS, a PXE NBP binary) or `/boot/loader.efi` (UEFI).
The FreeBSD loader then reads its configuration
(`files/walt-loader.conf`, installed at `/boot/loader.conf.d/walt.conf`),
loads the kernel over the network, and the kernel mounts its root filesystem
over NFS (read-only, see `root_rw_mount="NO"` in `files/walt-rc.conf`), then
runs `/bin/walt-init` instead of `/sbin/init` (`init_path` in the loader
configuration).

### Virtual nodes

For performance reasons, virtual nodes do not run a real iPXE: the WalT
server emulates its first steps (the "fake iPXE"), interprets
`start.ipxe`, and finally starts qemu with options `-kernel` (and `-initrd`,
`-append`) pointing to the files the script loads. But option `-kernel` only
accepts a few binary formats (e.g., a Linux kernel), and not FreeBSD's
`pxeboot`, which is a PXE NBP binary.

So, on virtual nodes (detected by `${manufacturer}` being `QEMU`),
`start.ipxe` loads `/boot/pc-x86-64/pxeboot.lkrn` instead: this is iPXE
itself, compiled in the Linux kernel format (`.lkrn`, stage 3 of the
Dockerfile), embedding two images:
- `files/call-pxeboot.ipxe`, a script which runs automatically;
- a copy of FreeBSD's `pxeboot`.

The script finds the network interface the node booted from (`${mac}`),
opens it (`ifopen`, which initializes the UNDI environment `pxeboot` needs),
and chainloads the embedded `pxeboot`. The rest is like on physical nodes.

So, on a virtual node, the boot chain is: fake iPXE → qemu `-kernel
pxeboot.lkrn` → iPXE → FreeBSD `pxeboot` → FreeBSD kernel →
`/bin/walt-init`.

Server-side changes (walt >= 11):
- FreeBSD's `pxeboot` (14.3) always uses a DHCP transaction ID of zero, so it
  may take a broadcast DHCP offer intended for another node, and reuse this
  IP address. walt-server-dhcpd sends a unicast reply to this specific client
  (commit "walt-server-dhcpd: workaround buggy FreeBSD pxeboot"). This is
  fixed in FreeBSD sources after 14.3.
- `pxeboot` loads the kernel with NFS over UDP, so the NFS server of the
  WalT server now accepts UDP (commit "nfsd: allow udp").


## walt-init on FreeBSD

`walt-init` (provided by the WalT server, see `walt-init`,
`walt-init-common` and `walt-boot-modes` in the server package) is a shell
script built for Linux. Since walt 11 ("walt-init refactor for freebsd"),
the functions it uses for OS-specific operations can be redefined in
`[image]:/bin/walt-init-overrides`, which `walt-init` sources if present.
This image provides `files/walt-init-overrides`, which works around these
differences:

- **No overlay filesystem.** The union of the read-only image and of a
  writable layer uses `mount -t unionfs` instead (`walt_mount_union`); the
  module is loaded by the boot loader (`unionfs_load="YES"`). Unlike overlayfs,
  it needs no work directory.
- **No bind mounts.** `mount -o bind` is emulated with `mount -t nullfs`,
  except for virtual filesystems (`proc`, `dev`, `run`), which are mounted
  again instead. A nullfs mount keeps its source busy, so it cannot be
  unmounted afterwards.
- **No move mounts.** `mount -o move` is emulated with a bind mount of the
  whole mount sub-tree, followed by unmounting the sources when possible
  (errors are ignored).
- **No `pivot_root`.** `walt_switch_root_fs` moves the other mounts below
  the new root (at the "put old" location), then uses `chroot`. Since
  `chroot` does not change how `mount` lists the mount points, a helper
  detects the current root by mounting a test filesystem and analysing the
  output of `mount`.
- **Different filesystem names.** `devtmpfs` → `devfs`, `proc` →
  `linprocfs`; `sysfs` (and `/sys`) is ignored.
- **`/run` cannot be bound.** The memory filesystem is mounted below
  `<finalfs>/run`, so binding `/run` would create a filesystem loop, which
  FreeBSD refuses. A new tmpfs is mounted instead, and the content is
  copied.
- **Busybox has no `mount` or `umount` applet on FreeBSD**, so the native
  commands are used (the memory filesystem receives `mount_nullfs`,
  `mount_unionfs`, the dynamic linker and `cp`, needed for option `-x`).
- **Other differences:** no `sync` NFS mount option (`walt_mount_persistent`
  mounts the persistent directory with `nfsv3,nolockd`), no `modprobe`
  (no extra kernel module is needed), and the console is `ttyu0` on virtual
  nodes (serial line) instead of `console`.

The other boot-time files:
- `files/walt-loader.conf`: the loader configuration. For debugging the
  bootup of a virtual node, `boot_serial="YES"` can be uncommented, but do
  not publish such an image: physical nodes without a serial line would
  fail to boot.
- `files/walt-rc.conf` (`/etc/rc.conf`): the root filesystem stays
  read-only for the rc scripts (walt-init already prepared it), and sshd
  is enabled (root login with keys only).
- `/etc/ttys`: terminals are started on existing devices (`onifexists`)
  instead of only on the console (`onifconsole`).
- `/etc/hostid` and `/boot/entropy` are normally created by the FreeBSD
  installer, the Dockerfile generates them (so all nodes booting a given
  build of this image share the same host ID).

### walt node save

On Linux, the upper directory of an overlay filesystem represents deleted
files as "whiteouts" (character devices 0:0), which `walt node save`
includes in the archive of changes it sends to the server. With FreeBSD
unionfs, whiteouts are `DT_WHT` directory entries of the tmpfs upper
directory, which regular tools do not show, and `bsdtar` ignores them. So the
image provides `/bin/walt-list-hidden-whiteouts` (`files/
walt_list_hidden_whiteouts.c`, compiled in the last stage), which lists
them using `__opendir2(path, DTF_NODUP)`. Since walt 11,
`walt-dump-diff-tar` runs it when present and adds the corresponding
overlay-compatible whiteouts to the archive.


## Running FreeBSD binaries on the WalT server (qemu bsd-user)

`walt image shell`, the `RUN` instructions of `walt image build` (and of
this Dockerfile), and `walt image cp` run commands of the image in a
container on the WalT server, i.e., on a Linux kernel. For Linux images of
another architecture, the binfmt_misc support of the kernel and qemu-user
handle this transparently. But the FreeBSD binaries of this image use the
FreeBSD system call interface, which neither the Linux kernel nor the
usual qemu-user (Linux user mode) understand.

QEMU has a "bsd-user" mode, which emulates the FreeBSD system calls, but
for FreeBSD hosts only. The image uses a fork of it
([qemu-bsd-user-l4b](https://github.com/rhelmot/qemu-bsd-user-l4b),
"Linux for BSD", pinned commit), which also runs on Linux hosts, built
statically for the `x86_64-bsd-user` target and installed at
`/usr/sbin/qemu-freebsd-execve` (stage 1 of the Dockerfile).

Since FreeBSD binaries have no binfmt_misc entry on the server, the image
declares the label `walt.image.bin.interpreter=/usr/sbin/qemu-freebsd-execve`.
Since walt 11 ("images: handle optional walt.image.bin.interpreter label"),
the server prefixes the commands it runs in a container of such an image with
this interpreter (see `walt-run-container` in the server package). The
`ENTRYPOINT` and `SHELL` of the image use it too, so `docker run` (and
`RUN` lines with docker or podman) work as well.

The fork worked for simple programs only, so we patched it in order to run
usual applications, such as `pkg`, `git`, `curl`, `cc`, `vim`, `ping`. The
patches are in `qemu-patches/`, applied in the order of
`qemu-patches/series` (they depend on each other):

| Patch | Purpose |
|-------|---------|
| `qemu-bsd-execve.patch` | `execve()` of FreeBSD programs (and `#!` scripts) runs them through qemu again, so that child processes are emulated too |
| `qemu-bsd-strace.patch` | strace output (`-strace`) shows the thread ID of each call |
| `qemu-bsd-fstatfs.patch` | `fstatfs()` support |
| `qemu-bsd-network.patch` | sockets and network system calls (DNS, TCP/UDP clients, `ping`...) |
| `qemu-bsd-misc.patch` | unsupported ioctls are only logged with strace, `KERN_PROC_UMASK` sysctl, a build fix |
| `qemu-bsd-thread.patch` | threads (`thr_*` system calls) |
| `qemu-bsd-eventfd.patch` | eventfds (FreeBSD `__specialfd()`) with Linux `eventfd2()`, `fcntl()` additions, and `select()` no longer modifies its timeout (FreeBSD semantics) |
| `qemu-bsd-mutex-yield.patch` | umtx mutex wait on a just-released mutex: yield the CPU, breaking a busy loop |
| `qemu-bsd-pipe-buffer.patch` | 1 MB pipe buffers: with the emulation overhead, writers (e.g., git fetching a pack) stalled with the default size |
| `qemu-bsd-write-stats-debug.patch` | debug: with env variable `QEMU_WRITE_STATS=1`, counts reads and writes on fds 0-2 (no effect otherwise) |
| `qemu-bsd-redzone.patch` | signal delivery: respects the x86-64 red zone of the stack, and delivers `SIGALRM` to the thread which armed the timer (fixed random `git clone` failures) |
| `qemu-bsd-shm-open2.patch` | `shm_open2()` (with `memfd_create()` for `SHM_ANON`), used by recent `pkg` |
| `qemu-bsd-cpuset-affinity.patch` | `cpuset_getaffinity()` / `cpuset_setaffinity()` with any level/which values |
| `qemu-bsd-condvar-umtx-fix.patch` | condvar and semaphore umtx operations called the wrong system calls on Linux hosts |
| `qemu-bsd-cpu-pin.patch` | each qemu process pins itself to one CPU core (chosen from its PID and a clock value), working around a race in multi-threaded TCG which randomly crashed or hung multi-threaded programs such as `cc` |
| `qemu-bsd-rlimit.patch` | `getrlimit()` / `setrlimit()`: converts the resource numbers, which differ from Linux from `RLIMIT_NPROC` on (pkg >= 2.9 sets `RLIMIT_NPROC` to 0 in its fetch process, which became `RLIMIT_NOFILE` = 0); FreeBSD-only resources and `setrlimit(RLIMIT_NPROC)` are ignored (on Linux this limit counts all processes and threads of the user, qemu ones included) |

`qemu-patches/unused-debug/` contains other debugging patches written during
this work. They are not applied.

Note: in the container, `pkg` is configured without the `FreeBSD-kmods`
repository, which does not exist for 14.3.


## Dockerfile stages

1. `qemu-builder`: builds the patched qemu bsd-user.
2. `freebsd-builder`: extracts `base.txz`, `kernel.txz` and `ports.txz`
   of the FreeBSD release (from `archive.freebsd.org`, since 14.3 is no
   longer a supported release), and adds the WalT boot and configuration
   files. `/sys` (a symbolic link to `/usr/src/sys` on FreeBSD) is replaced
   with a directory, otherwise podman cannot mount a filesystem there.
3. `pxeboot-builder`: builds `pxeboot.lkrn` (iPXE v2.0.0 in `.lkrn`
   format, embedding `call-pxeboot.ipxe` and FreeBSD's `pxeboot`).
4. Final image (`FROM scratch`): installs packages with `pkg` (vim, bash,
   git, wget, busybox; busybox is used by walt-init) and compiles
   `walt-list-hidden-whiteouts`, all through the emulation of stage 1.


## Limitations and to-do

- FreeBSD 14.3 is no longer supported: update `OS_VERSIONS` in `env.py` (and
  `REPO` in the Dockerfile for a supported release, which is on
  `download.freebsd.org`). The DHCP workaround of the server would then no
  longer be needed (fixed in `pxeboot`).
- Tested mainly with virtual nodes in boot mode `network-volatile`. The other
  boot modes (`network-persistent`, `hybrid-*`) are probably not working
  yet. Physical nodes (legacy BIOS with `pxeboot`, UEFI with `loader.efi`)
  were less tested.
- Since `nullfs` keeps its sources busy, some mounts of the boot process
  cannot be unmounted, which may prevent a clean shutdown.
- Programs run through the qemu bsd-user emulation on the server are slow
  compared to native ones, and less common system calls may still be
  missing (with `QEMU_STRACE=1`, system calls are logged, and unsupported
  ioctls too). Known examples in `walt image shell`: `ps` fails (sysctl
  `kern.pid_max` not implemented), and `tty` prints "not a tty"
  (`ttyname()` uses ioctl `FIODGNAME`, not supported), although `isatty()`
  works. Also, the exit status of each command is logged as
  `[qemu pid=<pid>] exit(<status>)` when it is not zero.
- `/etc/resolv.conf` of the image comes from the build environment.
