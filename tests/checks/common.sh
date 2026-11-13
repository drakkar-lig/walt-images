# Generic checks, run on the node by tests/smoke.sh.
# This is a POSIX sh script (it must work on debian, alpine and openwrt).
# Variable SMOKE_NETSETUP is set by tests/smoke.sh (LAN or NAT).
# Image-specific checks (tests/checks/<image>.sh) are appended to this
# script, so they can use the functions below. They must not print
# END-OF-CHECKS, this is done by smoke_end.

smoke_pass() { echo "PASS  $*"; }
smoke_fail() { echo "FAIL  $*"; }
smoke_info() { echo "INFO  $*"; }

# usage: check <description> <shell-command>
# the check passes if the command succeeds; the first line of its output
# is displayed.
check() {
    _desc="$1"
    _out="$(sh -c "$2" 2>&1)" && _ok=1 || _ok=0
    _line="$(echo "$_out" | head -n 1)"
    if [ "$_ok" = 1 ]
    then
        smoke_pass "$_desc${_line:+: $_line}"
    else
        smoke_fail "$_desc${_line:+: $_line}"
    fi
}

smoke_end() {
    echo "END-OF-CHECKS"
}
trap smoke_end EXIT

if [ -f /etc/os-release ]
then
    . /etc/os-release
    smoke_info "os: $PRETTY_NAME"
fi
smoke_info "kernel: $(uname -rm)"

# network root filesystem (nfs or nbfs, possibly below an overlay)
SMOKE_NETFS="$(awk '$3 ~ /^(nfs|nfs4|nbfs|fuse\.nbfs)$/ { print $1 " on " $2 " (" $3 ")"; exit }' \
                  /proc/mounts)"
check "network root filesystem" "[ -n '$SMOKE_NETFS' ] && echo '$SMOKE_NETFS'"

# walt server
SMOKE_SERVER="$(echo "$SMOKE_NETFS" | sed -n 's/^\([0-9.]*\):.*/\1/p')"
if [ -z "$SMOKE_SERVER" ]
then
    SMOKE_SERVER="$(tr ' ' '\n' < /proc/cmdline | \
                    sed -n 's/^walt.server.ip=//p')"
fi
check "walt server ping" "[ -n '$SMOKE_SERVER' ] && \
            ping -c 1 -W 2 '$SMOKE_SERVER' >/dev/null && echo '$SMOKE_SERVER'"

# the clock is synchronized with the server at bootup
check "clock" "[ \$(date +%Y) -ge 2025 ] && date"

# systemd units
if command -v systemctl >/dev/null
then
    check "systemd state" "systemctl is-system-running; true"
    check "no failed systemd unit" \
        "failed=\"\$(systemctl list-units --failed --plain --no-legend | \
                     awk '{ print \$1 }' | tr '\n' ' ')\"; \
         [ -z \"\$failed\" ] || { echo \"\$failed\"; false; }"
fi

# openwrt: the walt-net device must be in the walt firewall zone
if [ -f /etc/openwrt_release ]
then
    check "openwrt firewall zone walt" "uci -q get firewall.walt.device"
fi

# internet access (if the node has netsetup=NAT)
if [ "$SMOKE_NETSETUP" = "NAT" ]
then
    if command -v apt-get >/dev/null
    then
        check "apt-get update" "apt-get update -qq && echo ok"
    elif command -v apk >/dev/null
    then
        check "apk update" "apk update -q && echo ok"
    elif command -v opkg >/dev/null
    then
        check "opkg update" "opkg update >/dev/null && echo ok"
    fi
else
    smoke_info "netsetup is not NAT: internet access not checked"
fi
