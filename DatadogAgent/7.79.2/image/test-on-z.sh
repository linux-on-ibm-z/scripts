#!/bin/bash
# this file has been modified with the assistance of AI Tool [claude 4.6]
# Transfer the s390x Agent image to a real IBM Z host and run the acceptance
# suite there -- i.e. on real hardware, not under qemu emulation.
#
# Usage:
#   test-on-z.sh [user@host]
# Defaults to $S390X_SSH_USER@$S390X_SSH_HOST from ../.env
#
# Requires: SSH access to the Z host (IBM VPN if it is a FYRE VM), and podman
# or docker on that host.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
IMAGE_TAG=datadog-agent-s390x:7.79.2
ARCHIVE="$HERE/datadog-agent-s390x-7.79.2.oci.zst"
REMOTE_DIR=/root/dd-s390x-imagetest
API_KEY="${DD_API_KEY:-0000000000000000000000000000000a}"

# --- resolve target --------------------------------------------------------
if [ $# -ge 1 ]; then
    TARGET="$1"
else
    ENVF="${S390X_ENV_FILE:-$HERE/../.env}"
    [ -f "$ENVF" ] || {
        echo "FATAL: no target given."
        echo "       Pass one:        $0 root@<z-host>"
        echo "       or set S390X_ENV_FILE to a file with S390X_SSH_USER/HOST."
        exit 2
    }
    U=$(grep -E '^S390X_SSH_USER=' "$ENVF" | cut -d= -f2-)
    H=$(grep -E '^S390X_SSH_HOST=' "$ENVF" | cut -d= -f2-)
    [ -n "$U" ] && [ -n "$H" ] || { echo "FATAL: S390X_SSH_USER/HOST not set in $ENVF"; exit 2; }
    TARGET="$U@$H"
fi
KEY="${S390X_SSH_KEY_FILE:-$HOME/.ssh/s390x_porting_key}"

# Host-key handling: pin the key in a persistent known_hosts rather than
# disabling verification. `accept-new` enrolls an unseen host on first contact
# but refuses to connect if a known host's key ever changes -- plain `no` would
# accept any key, every time.
#
# This matters here specifically: the image archive and its checksum file both
# travel over this same channel, so an attacker able to MITM the transport
# could substitute both and the integrity check would still pass. Host-key
# verification is what actually prevents that.
KNOWN_HOSTS="${S390X_KNOWN_HOSTS:-$HERE/known_hosts.s390x}"
touch "$KNOWN_HOSTS" 2>/dev/null || { echo "FATAL: cannot write $KNOWN_HOSTS"; exit 2; }
SSH_OPTS=(-o StrictHostKeyChecking=accept-new
          -o UserKnownHostsFile="$KNOWN_HOSTS"
          -o ConnectTimeout=20)
SSH=(ssh "${SSH_OPTS[@]}")
SCP=(scp -q "${SSH_OPTS[@]}")
if [ -f "$KEY" ]; then SSH+=(-i "$KEY"); SCP+=(-i "$KEY"); fi

# Export the local image on demand so the kit works without a pre-made archive.
if [ ! -f "$ARCHIVE" ]; then
    if podman image exists "$IMAGE_TAG" 2>/dev/null; then
        echo "### exporting $IMAGE_TAG (no archive present yet)"
        podman save --format oci-archive -o "$ARCHIVE.tmp" "$IMAGE_TAG" >/dev/null
        zstd -q -19 -T0 -f "$ARCHIVE.tmp" -o "$ARCHIVE" && rm -f "$ARCHIVE.tmp"
    else
        echo "FATAL: neither $ARCHIVE nor a local $IMAGE_TAG image."
        echo "       Run build.sh first."
        exit 2
    fi
fi

echo "### target: $TARGET"
HOSTONLY="${TARGET#*@}"
if ! ssh-keygen -F "$HOSTONLY" -f "$KNOWN_HOSTS" >/dev/null 2>&1; then
  echo "### NOTE: $HOSTONLY is not yet in $KNOWN_HOSTS."
  echo "###       Its key will be enrolled on this connection. Verify the"
  echo "###       fingerprint below against the host's own ssh-keygen -lf"
  echo "###       output if this host is not one you have used before."
fi
PROBE_ERR=$("${SSH[@]}" -o BatchMode=yes "$TARGET" true 2>&1 >/dev/null)
if [ $? -ne 0 ]; then
    # Distinguish a host-key mismatch from plain unreachability -- the former is
    # a security event and must not be reported as "is the VPN up?".
    if echo "$PROBE_ERR" | grep -q "REMOTE HOST IDENTIFICATION HAS CHANGED"; then
        echo "FATAL: host key for $TARGET does not match the pinned key in"
        echo "       $KNOWN_HOSTS"
        echo "       This is either a man-in-the-middle, or the host was rebuilt."
        echo "       If the host was legitimately reprovisioned, remove the stale entry:"
        echo "         ssh-keygen -R '${TARGET#*@}' -f '$KNOWN_HOSTS'"
        echo "$PROBE_ERR" | sed 's/^/       /' | head -12
        exit 7
    fi
    echo "FATAL: cannot reach $TARGET over SSH (IBM VPN connected?)"
    echo "$PROBE_ERR" | sed 's/^/       /' | head -5
    exit 3
fi

# --- 0. the host must actually be Z ---------------------------------------
ARCH=$("${SSH[@]}" "$TARGET" 'uname -m')
echo "### remote arch: $ARCH"
[ "$ARCH" = "s390x" ] || { echo "FATAL: $TARGET is $ARCH, not s390x"; exit 4; }

RT=$("${SSH[@]}" "$TARGET" 'command -v podman || command -v docker' 2>/dev/null)
[ -n "$RT" ] || { echo "FATAL: neither podman nor docker on $TARGET"; exit 5; }
echo "### container runtime: $RT"

# --- 1. transfer -----------------------------------------------------------
echo "### transferring $(du -h "$ARCHIVE" | cut -f1) image archive"
"${SSH[@]}" "$TARGET" "mkdir -p $REMOTE_DIR"
"${SCP[@]}" "$ARCHIVE" "$TARGET:$REMOTE_DIR/"

# --- 2. load ---------------------------------------------------------------
# Digest computed here and passed inline, rather than shipping image.sha256
# alongside the archive -- one less file to keep in sync, and the expected
# value never leaves this script.
ARCHIVE_SHA256=$(sha256sum "$ARCHIVE" | awk '{print $1}')
echo "### archive sha256: $ARCHIVE_SHA256"
"${SSH[@]}" "$TARGET" bash -s <<REMOTE
set -euo pipefail
cd $REMOTE_DIR
echo "### verifying archive integrity"
echo "$ARCHIVE_SHA256  $(basename "$ARCHIVE")" | sha256sum -c -
echo "### loading image"
zstd -d -f datadog-agent-s390x-7.79.2.oci.zst -o dd.oci
$RT load -i dd.oci
$RT tag \$($RT images --format '{{.ID}}' | head -1) $IMAGE_TAG 2>/dev/null || true
rm -f dd.oci
REMOTE
[ $? -eq 0 ] || { echo "FATAL: load failed"; exit 6; }

# --- 3. acceptance suite ---------------------------------------------------
echo
echo "########## ACCEPTANCE SUITE (native s390x) ##########"
"${SCP[@]}" "$HERE/acceptance.sh" "$TARGET:$REMOTE_DIR/"
"${SSH[@]}" "$TARGET" "bash $REMOTE_DIR/acceptance.sh '$RT' '$IMAGE_TAG' '$API_KEY'"
SUITE_RC=$?

echo
echo "########## DONE ##########"
echo "Compare against the emulated baseline in README.md:"
echo "  Agent 7.79.2 / Go 1.26.3 / Build arch: s390x / 16 healthy, 1 unhealthy (forwarder, test API key)"
exit ${SUITE_RC:-0}
