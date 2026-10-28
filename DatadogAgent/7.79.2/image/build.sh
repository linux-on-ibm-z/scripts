#!/bin/bash
# this file has been modified with the assistance of AI Tool [claude 4.6]
# One-shot driver: build the Datadog Agent 7.79.2 s390x container image
# without omnibus (Option 1 of
# docs/datadog-agent-s390x-container-image-gap-analysis.md).
#
#   1. cross-compile the Go binaries for s390x  (crossbuild.sh)
#   2. assemble an omnibus-shaped artifact tarball (make-artifact.sh)
#   3. build the image from ../../../dockerfiles/DatadogAgent.dockerfile
#
# Works from an x86_64 host with qemu-s390x binfmt registered, or natively on
# s390x (in which case step 1 degrades to a normal build -- see NATIVE below).
#
# Usage: build.sh <path-to-patched-datadog-agent-7.79.2> [workdir]
set -euo pipefail

SRC="${1:?usage: build.sh <path-to-patched-datadog-agent-7.79.2> [workdir]}"
SRC="$(cd "$SRC" && pwd)"
W="${2:-$PWD/.build}"
HERE="$(cd "$(dirname "$0")" && pwd)"
# Dockerfile lives at the top of the component tree ("Datadog Agent/dockerfiles"),
# not next to these scripts.
DOCKERFILE="$(cd "$HERE/../../.." && pwd)/dockerfiles/DatadogAgent.dockerfile"
GO_VERSION=1.26.3
IMAGE=datadog-agent-s390x:7.79.2

# Go toolchain checksums, committed here rather than fetched at build time so a
# compromised or MITM'd go.dev cannot supply both the tarball and its digest.
# Source: https://go.dev/dl/?mode=json&include=all  (go1.26.3)
GO_SHA256_amd64=2b2cfc7148493da5e73981bffbf3353af381d5f93e789c82c79aff64962eb556
GO_SHA256_s390x=5c0605b7175449f1c8e8cb02efaba2695caab914fad4dcedc764c2f4c6dfe6ca

command -v podman >/dev/null || { echo "FATAL: podman required"; exit 1; }
[ -f "$SRC/go.mod" ] || { echo "FATAL: $SRC is not the agent source root"; exit 2; }
[ -f "$DOCKERFILE" ] || { echo "FATAL: Dockerfile not found at $DOCKERFILE"; exit 6; }

mkdir -p "$W"/{out,artifacts}

# --- 0. preflight ----------------------------------------------------------
if [ "$(uname -m)" != "s390x" ]; then
  if [ ! -e /proc/sys/fs/binfmt_misc/qemu-s390x ]; then
    echo "FATAL: no qemu-s390x binfmt handler. Install qemu-user-static(-s390x)"
    echo "       or run:  podman run --rm --privileged docker.io/tonistiigi/binfmt --install s390x"
    exit 3
  fi
  echo "### cross-building from $(uname -m) with qemu-s390x binfmt"
fi

# --- 1. Go toolchain -------------------------------------------------------
if [ ! -x "$W/go-$GO_VERSION/bin/go" ]; then
  echo "### fetching Go $GO_VERSION"
  HOSTARCH=$([ "$(uname -m)" = "x86_64" ] && echo amd64 || echo s390x)
  eval "GO_EXPECTED=\$GO_SHA256_${HOSTARCH}"
  [ -n "${GO_EXPECTED:-}" ] || { echo "FATAL: no pinned Go checksum for $HOSTARCH"; exit 5; }
  curl -fsSL -o "$W/go.tgz" "https://go.dev/dl/go${GO_VERSION}.linux-${HOSTARCH}.tar.gz"
  echo "${GO_EXPECTED}  $W/go.tgz" | sha256sum -c - \
    || { echo "FATAL: Go toolchain checksum mismatch"; rm -f "$W/go.tgz"; exit 5; }
  tar -C "$W" -xzf "$W/go.tgz" && mv "$W/go" "$W/go-$GO_VERSION" && rm -f "$W/go.tgz"
fi

# --- 2. cross-compile ------------------------------------------------------
# The build runs in an ubuntu:24.04 container so the s390x cross-glibc (2.39)
# matches the ubuntu:24.04 s390x runtime image exactly. cgo is required:
# github.com/DataDog/zstd is imported unconditionally.
echo "### cross-compiling s390x binaries"
cp "$HERE/crossbuild.sh" "$W/crossbuild.sh"
[ -e "$W/src" ] || cp -a "$SRC" "$W/src"

# Optional: seed the module cache from an existing one to avoid re-downloading
# the whole dependency set. Hardlinked, so it costs no extra disk; module files
# are read-only by design and Go only ever adds to the cache.
#   GOMODCACHE_SEED=~/go/pkg/mod ./build.sh …
if [ -n "${GOMODCACHE_SEED:-}" ] && [ ! -e "$W/gomodcache" ]; then
  # Hardlinks cannot cross filesystems, so this only works when the workdir and
  # the seed are on the same device. Warn and carry on rather than failing the
  # build -- Go will just download the modules instead.
  if [ "$(stat -c %d "$GOMODCACHE_SEED" 2>/dev/null)" = "$(stat -c %d "$W" 2>/dev/null)" ]; then
    echo "### seeding module cache from $GOMODCACHE_SEED"
    cp -al "$GOMODCACHE_SEED" "$W/gomodcache" \
      || { echo "### seed failed; continuing without it"; rm -rf "$W/gomodcache"; }
  else
    echo "### NOTE: $GOMODCACHE_SEED is on a different filesystem from $W;"
    echo "###       cannot hardlink-seed. Go will download modules instead."
    echo "###       Put the workdir on the same filesystem to use the seed."
  fi
fi
podman run --rm --security-opt label=disable -v "$W:/work" \
  mirror.gcr.io/library/ubuntu:24.04 bash /work/crossbuild.sh

for b in agent trace-agent process-agent; do
  file "$W/out/$b" | grep -q "IBM S/390" || { echo "FATAL: $b is not s390x"; exit 4; }
done
echo "### binaries OK (ELF64 MSB, IBM S/390)"

# --- 3. artifact tarball ---------------------------------------------------
echo "### assembling artifact"
bash "$HERE/make-artifact.sh" "$W/out" "$W/src" "$W/artifacts" | tail -3
TARBALL=$(ls "$W"/artifacts/datadog-agent-*-s390x.tar.xz)
SHA=$(sha256sum "$TARBALL" | awk '{print $1}')

# --- 4. image --------------------------------------------------------------
echo "### building image $IMAGE"
cp "$HERE/s6.s390x.sha256" "$W/src/Dockerfiles/agent/"
podman build --platform linux/s390x --format docker --security-opt label=disable \
  --build-arg ARTIFACT_SHA256="$SHA" \
  -f "$DOCKERFILE" \
  --build-context artifacts="$W/artifacts" \
  -t "$IMAGE" \
  "$W/src/Dockerfiles/agent"

# --- 5. verify -------------------------------------------------------------
echo "### verifying"
podman run --rm --platform linux/s390x "$IMAGE" agent version
podman run --rm --platform linux/s390x "$IMAGE" \
  sh -c 'agent status 2>/dev/null | grep -E "Build arch|Go Version"' || true
echo
echo "built $IMAGE   (artifact sha256 $SHA)"
