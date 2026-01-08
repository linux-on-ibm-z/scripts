#!/bin/bash
# © Copyright IBM Corporation 2026.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)

if [[ $# -ne 1 ]]; then
    echo "missing argument one: <qemu src dir>"
    echo "$0 <qemu src dir>"
    exit 2
fi

QD=$1

if [[ ! -x "${QD}/configure" ]]; then
    echo "Can not execute ${QD}/configure. Exiting..."
    exit 1;
fi

SUPPORTED_ARCHS=("s390x" "x86_64")

function supported() {
    local a="$1"
    for value in "${SUPPORTED_ARCHS[@]}"
    do
        [[ "$a" = "$value" ]] && return 0
    done
    return 1
}

function target_list() {
    local a="$1"
    local tl=""
    for value in "${SUPPORTED_ARCHS[@]}"
    do
        [[ "$a" = "$value" ]] && continue
        tl="${tl},${value}-linux-user"
    done
    echo "${tl:1}"
}

ARCH="$(uname -m)"
if ! supported "$ARCH"; then
    echo "${ARCH} is not supported. Exiting..."
    exit 1;
fi

"${QD}/configure" \
  --enable-linux-user \
  --disable-system \
  --static \
  --disable-blobs \
  --disable-brlapi \
  --disable-cap-ng \
  --disable-capstone \
  --disable-curl \
  --disable-curses \
  --disable-docs \
  --disable-gcrypt \
  --disable-gnutls \
  --disable-gtk \
  --disable-guest-agent \
  --disable-guest-agent-msi \
  --disable-libiscsi \
  --disable-libnfs \
  --disable-mpath \
  --disable-nettle \
  --disable-opengl \
  --disable-pie \
  --disable-sdl \
  --disable-spice \
  --disable-tools \
  --disable-vte \
  --target-list="$(target_list "$ARCH")"
