
# Running OpenWRT on an NFS root

In its default configuration, openwrt does not work properly on
a network filesystem root. Initial work on this was done by
Rémy Grunblatt and his conclusions are described at:
https://forum.openwrt.org/t/preventing-the-init-to-mess-with-my-nfs-root-and-network/50357/8

Successfully running OpenWRT on a read-only NFS mount implies
the following:
* Prepare an appropriate `/etc/config/network` file so that
  the OS does not reset the network interface used by NFS
  will booting.
* Prevent the firewalling service from disconnecting the
  related network connections.
* Have a handful of device files ready in /dev because
  the NFS mount is read-only so it's not possible to create
  them on-the-fly at bootup.

Those tree points are detailed below.


## The `/etc/config/network` file

As of this writing (january 2026), and as long as the NFS root
is handled by the kernel itself (not by an initramfs), there is
only one remaining cause of network interface reset: the "network"
service.
The network service is based on the configuration file at
/etc/config/network. If this file contains a section referring
to the network interface used for network booting (eth0), then
this interface will be reset when the service starts, which
disconnects the NFS mount.
So we must ensure this is not the case.
If this file is empty or missing, a default configuration will
be installed at /etc/config/network when the OS boots, and
this default configuration has a reference to "eth0".
Considering all this, we install a basic configuration just
containing the definition of the loopback.


## Dealing with the firewall

Another cause of disconnection is the firewalling service.
For proper behavior as a WalT node, it should allow at least
the following TCP connections:
- NFS connections to the server. This includes various ports,
  some of which are dynamic by default.
  Check-out https://wiki.debian.org/SecuringNFS.
- SSH connections from the server to the node (port 22)
- Pings from the server (already allowed by default)
- Connections from the server to the node on TCP port 12346
  (for WalT server requests to the node, e.g. reboot requests)
- Connections from the node to the server on its TCP port 12345
  (for things such as clock sync or bootup notification)
- Connections from the node to the server on its TCP port 12347
  (for sending WalT logs)
- Connections to WalT server on its TCP port 12342
  (for the node's "netconsole", if enabled)
  
Since we are just on a testbed, we just disabled the service
on this image.


## Device files in /dev

In order to boot properly, `/dev` must contain at least a minimal
set of special files such as `/dev/null`, `/dev/console`, etc.
Those files cannot be created on the fly since the NFS mount is
read-only.
