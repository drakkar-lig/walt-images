#!/bin/bash
# Smoke test of an image of this repository on a WalT node.
#
# usage: tests/smoke.sh [-r] [-f] [-n <walt-image-name>] [-t <timeout>] <image> <node>
#
# <image> is the name of a locally built image, without the 'waltplatform/'
# prefix and ':latest' suffix (e.g., 'rpi32-debian', 'pc-x86-64-k3s-server').
#
# The image is cloned into the WalT image <walt-image-name> (default:
# 'smoke-<image>'), the node boots it, and a set of checks are run on the
# node. Since cloning an image reboots the nodes using it, use a WalT image
# name dedicated to this test: the script stops if other nodes use this
# WalT image, unless option -f is given.
#
# Generic checks are defined in tests/checks/common.sh. If the file
# tests/checks/<image>.sh exists, its checks are run too.
#
# options:
#   -r   boot the node back on its previous image at the end
#   -f   proceed even if other nodes use the WalT image (they will reboot)
#   -n   WalT image name to use (default: smoke-<image>)
#   -t   timeout in seconds for the node bootup (default: 600)
#
# The exit code is 0 if all checks passed, 1 otherwise.

set -e -o pipefail

usage() {
    sed -n '4p' "$0" | sed 's/^# //' >&2
    exit 2
}

restore=0
force=0
walt_image=""
timeout=600
while getopts "rfn:t:" opt
do
    case "$opt" in
        r) restore=1 ;;
        f) force=1 ;;
        n) walt_image="$OPTARG" ;;
        t) timeout="$OPTARG" ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))
[ $# -eq 2 ] || usage
image="$1"
node="$2"
[ -n "$walt_image" ] || walt_image="smoke-$image"

tests_dir="$(cd "$(dirname "$0")" && pwd)"

info() {
    echo "--- $*"
}

walt_node_show() {
    # columns: name type model image ip netsetup booted
    walt node show --all | sed 's/\x1b\[[0-9;]*m//g'
}

get_node_image() {
    walt_node_show | awk -v node="$1" '$1 == node { print $4; exit }'
}

# nodes (other than $2) using image $1
# (note: "walt node show --all" also lists the nodes of other users, so
# their image names may be the same as ours.)
get_other_nodes_of_image() {
    walt_node_show | awk -v image="$1" -v node="$2" \
        '$4 == image && $1 != node { printf "%s ", $1 }'
}

prev_image="$(get_node_image "$node")"
if [ -z "$prev_image" ]
then
    echo "Node '$node' not found in your nodes (see 'walt node show')." >&2
    exit 2
fi
if [ "$prev_image" = "$walt_image" ]
then
    # the node already uses this image name, nothing to restore
    restore=0
fi
netsetup="$(walt node config "$node" | sed -n 's/^netsetup=//p')"
other_nodes="$(get_other_nodes_of_image "$walt_image" "$node")"
if [ -n "$other_nodes" -a "$force" = 0 ]
then
    echo "WalT image '$walt_image' is also used by: $other_nodes" >&2
    echo "Cloning would reboot them. Use option -n to select another" \
         "WalT image name, or -f to proceed anyway." >&2
    exit 2
fi

info "image $image (WalT image '$walt_image'), node $node" \
     "(previous image: $prev_image, netsetup: $netsetup)"

info "cloning waltplatform/$image:latest"
walt image clone --force "docker:waltplatform/$image:latest" "$walt_image"

if [ "$prev_image" != "$walt_image" ]
then
    # (otherwise, cloning already rebooted the node)
    info "booting $node on $walt_image"
    walt node boot "$node" "$walt_image"
fi

info "waiting for $node (timeout: ${timeout}s)"
start=$(date +%s)
if ! walt node wait --timeout "$timeout" "$node"
then
    echo "FAIL  node bootup (timeout after ${timeout}s)"
    echo "Check the logs with: walt log show --issuers $node --history -5m:"
    exit 1
fi
echo "PASS  node bootup ($(( $(date +%s) - start ))s)"

info "running checks on $node"
results="$(mktemp)"
trap 'rm -f "$results"' EXIT
{
    echo "SMOKE_NETSETUP='$netsetup'"
    cat "$tests_dir/checks/common.sh"
    if [ -f "$tests_dir/checks/$image.sh" ]
    then
        cat "$tests_dir/checks/$image.sh"
    fi
} | walt node run "$node" -- sh 2>&1 | tee "$results" || true

failures=$(grep -c "^FAIL" "$results" || true)
passes=$(( $(grep -c "^PASS" "$results" || true) + 1 ))  # +1: node bootup
if ! grep -q "^END-OF-CHECKS" "$results"
then
    echo "FAIL  checks did not complete"
    failures=$((failures + 1))
fi

if [ "$restore" = 1 ]
then
    info "booting $node back on $prev_image"
    walt node boot "$node" "$prev_image"
else
    info "to boot $node back on its previous image:" \
         "walt node boot $node $prev_image"
fi

info "$passes passed, $failures failed"
[ "$failures" -eq 0 ]
