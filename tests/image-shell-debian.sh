#!/bin/bash
# Test "walt image shell" on a Debian image of this repository.
#
# usage: tests/image-shell-debian.sh [-k] <image>
#
# <image> is the name of a locally built image, without the 'waltplatform/'
# prefix and ':latest' suffix (e.g., 'rpi32-debian', 'pc-x86-64-debian').
# It must be a Debian-based image: the test installs a package with apt,
# and relies on the "advanced mode" of "walt image shell", where the
# server starts the init system of the image (systemd) in the container,
# using /bin/walt-image-shell-start (see "walt help show shells").
# More minimalist images (e.g., alpine, openwrt) only provide a shell
# process in this virtual environment, so this test does not apply to them.
#
# The image is cloned into the WalT image 'imgshell-<image>', and a
# derived WalT image 'imgshell-<image>-pg' is built with "walt image build",
# with postgresql installed. Then, in a "walt image shell" session on this
# derived image, we check that:
# - systemd reaches the "running" state (no failed units)
# - the postgresql service is running and answers a query
#
# options:
#   -k   keep the WalT images at the end (they are removed otherwise)
#
# The exit code is 0 if all checks passed, 1 otherwise.

set -e -o pipefail

usage() {
    sed -n '4p' "$0" | sed 's/^# //' >&2
    exit 2
}

keep=0
while getopts "k" opt
do
    case "$opt" in
        k) keep=1 ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))
[ $# -eq 1 ] || usage
image="$1"
walt_image="imgshell-$image"
walt_image_pg="$walt_image-pg"

info() {
    echo "--- $*"
}

work_dir="$(mktemp -d)"
output="$work_dir/output"
cleanup() {
    rm -rf "$work_dir"
    if [ "$keep" = 0 ]
    then
        walt image remove "$walt_image_pg" >/dev/null 2>&1 || true
        walt image remove "$walt_image" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

info "cloning waltplatform/$image:latest as $walt_image"
# note: "walt image clone" may return 0 even when the clone failed
clone_output="$(walt image clone --force \
                "docker:waltplatform/$image:latest" "$walt_image" 2>&1)" || true
echo "$clone_output"
if ! echo "$clone_output" | grep -q "was cloned successfully"
then
    echo "FAIL  cloning waltplatform/$image:latest"
    exit 1
fi

info "building $walt_image_pg (with postgresql)"
cat > "$work_dir/Dockerfile" << EOF
FROM $walt_image
RUN apt-get update && \\
    apt-get install -y --no-install-recommends postgresql && \\
    apt-get clean && rm -rf /var/lib/apt/lists/*
EOF
# (the build would ask for confirmation if the image already existed)
walt image remove "$walt_image_pg" >/dev/null 2>&1 || true
if ! walt image build --from-dir "$work_dir" "$walt_image_pg" < /dev/null
then
    echo "FAIL  building $walt_image_pg"
    exit 1
fi

info "running checks in 'walt image shell $walt_image_pg'"
# "walt image shell" needs a terminal: we run it with "script", and type
# the commands once the shell is started. When the shell exits, the client
# asks for an image name to save the changes, and we press ctrl-C to abort.
checks='
export SYSTEMD_PAGER= SYSTEMD_COLORS=0
st=$(systemctl is-system-running --wait)
if [ "$st" = running ]; then echo "PASS  systemd state"
else echo "FAIL  systemd state: $st"; systemctl --failed --no-legend --plain --no-pager; fi
if systemctl is-active -q postgresql && \
   [ "$(su postgres -c "psql -tAc \"select 40 + 2\"")" = 42 ]
then echo "PASS  postgresql service"
else echo "FAIL  postgresql service"; systemctl status --no-pager "postgresql*"
fi
echo END-OF-CHECKS
'
{
    # wait for the shell prompt
    for i in $(seq 300)
    do
        grep -q "virtual environment" "$output" 2>/dev/null && break
        sleep 1
    done
    sleep 3
    # (the script is sent base64-encoded, on a single line)
    echo "echo $(echo "$checks" | base64 -w0) | base64 -d | sh; exit"
    # wait for the end of the checks, then for the prompt
    for pattern in "^END-OF-CHECKS" "New image name"
    do
        for i in $(seq 300)
        do
            tr -d '\r' < "$output" | grep -q "$pattern" && break
            sleep 1
        done
    done
    printf '\003'
    sleep 3
} | timeout 600 script -qfec "walt image shell $walt_image_pg" /dev/null \
    > "$output" 2>&1 || true
clean_output="$work_dir/clean-output"
sed -e 's/\x1b\[[0-9;:?]*[a-zA-Z]//g' -e 's/\x1b\][^\x07]*\x07//g' "$output" | tr -d '\r' > "$clean_output"
grep -E "^(PASS|FAIL)|loaded failed|Active:|Process:" "$clean_output" || true

failures=$(grep -c "^FAIL" "$clean_output" || true)
passes=$(grep -c "^PASS" "$clean_output" || true)
if ! grep -q "^END-OF-CHECKS" "$clean_output"
then
    echo "FAIL  checks did not complete"
    failures=$((failures + 1))
fi
info "$passes passed, $failures failed"
[ "$failures" -eq 0 ]
