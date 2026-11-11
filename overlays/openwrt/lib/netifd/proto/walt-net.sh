#!/bin/sh
#
# netifd protocol handler for the interface connected to walt-net.
#
# The WalT network interface is configured very early at bootup
# (by the initramfs) because the root filesystem is mounted over NFS
# through it. netifd must not reconfigure it: when netifd claims a
# network device it normally brings it down and flushes its addresses
# and routes, which breaks the NFS root (and the node then hangs,
# since the netifd helper programs are themselves read from NFS).
#
# This handler declares the interface and its current IPv4 address(es)
# as "external" (option "address-external" of proto_init_update()):
# netifd then registers them (e.g. for firewall zones or "ubus call
# network.interface.walt status") without modifying the device.
#
# Usage in /etc/config/network:
#
# config interface 'walt'
#	option proto 'walt-net'
#
# Note: no other section of /etc/config/network should reference
# the network device used by WalT (usually eth0), otherwise netifd
# would reset it.

. /lib/functions.sh
. ../netifd-proto.sh
init_proto "$@"

proto_walt-net_init_config() {
	no_device=1
	available=1
}

get_walt_server_ip() {
	local opt
	for opt in $(cat /proc/cmdline)
	do
		case "$opt" in
			walt.server.ip=*)
				echo "${opt#*=}"
				return
				;;
		esac
	done
}

proto_walt-net_setup() {
	local config="$1"
	local server_ip ifname addr

	server_ip="$(get_walt_server_ip)"
	if [ -n "$server_ip" ]
	then
		ifname="$(ip -4 route get "$server_ip" | \
			sed -n 's/.* dev \([^ ]*\).*/\1/p' | head -n 1)"
	fi
	if [ -z "$ifname" ]
	then
		echo "walt-net: could not detect the WalT network interface" >&2
		proto_notify_error "$config" "NO_WALT_INTERFACE"
		proto_block_restart "$config"
		return 1
	fi

	# link up, address-external
	proto_init_update "$ifname" 1 1
	for addr in $(ip -4 -o addr show dev "$ifname" | \
			sed -n 's/.* inet \([^ ]*\) .*/\1/p')
	do
		proto_add_ipv4_address "${addr%/*}" "${addr#*/}"
	done
	proto_send_update "$config"
}

proto_walt-net_teardown() {
	# nothing to do: the interface and its addresses are external,
	# so netifd does not remove them.
	return 0
}

add_protocol walt-net
