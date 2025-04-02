#!/bin/bash
# © Copyright IBM Corporation 2025.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)

QEMU_BIN_DIR=${QEMU_BIN_DIR:-/usr/bin}

if [ ! -d /proc/sys/fs/binfmt_misc ]; then
    echo "No binfmt support in the kernel."
    echo "  Try: '/sbin/modprobe binfmt_misc' from the host."
    exit 1 
fi

if [ ! -f /proc/sys/fs/binfmt_misc/register ]; then
    mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc || { echo "Could not mount /proc/sys/fs/binfmt_misc. Exiting..."; exit 1; }
fi

if [ $# -gt 1 ]; then
    echo "Too may command line options: Only zero or one of '--force' or '--unregister' allowed."
    exit 1
fi

ALLOW_REGISTER="true"
ALLOW_UNREGISTER="false"
if [ "${1}" = "--force" ]; then
    ALLOW_REGISTER="true"
    ALLOW_UNREGISTER="true"
fi
if [ "${1}" = "--unregister" ]; then
    ALLOW_REGISTER="false"
    ALLOW_UNREGISTER="true"
fi

declare -A binfmt_configs
binfmt_configs["qemu-s390x"]=":qemu-s390x:M:0:\x7fELF\x02\x02\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x16:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff:/usr/bin/qemu-s390x-static:PCF"
binfmt_configs["qemu-x86_64"]=":qemu-x86_64:M:0:\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00:\xff\xff\xff\xff\xff\xfe\xfe\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-x86_64-static:PCF"

for q in "${QEMU_BIN_DIR}"/qemu-*-static; do
    reg=$(basename "${q%-static}")
    [[ -v binfmt_configs[$reg] ]] || continue
    if [ -f "/proc/sys/fs/binfmt_misc/$reg" ]; then
        if [ "true" = "$ALLOW_UNREGISTER" ]; then
            echo -n "Unregistering existing /proc/sys/fs/binfmt_misc/${reg}... "
            echo -n "-1" > "/proc/sys/fs/binfmt_misc/${reg}"
            echo "done"
        else
            echo "Found existing /proc/sys/fs/binfmt_misc/${reg}; Use --force to replace it. Skipping..."
            continue
        fi
    fi

    if [ "true" = "$ALLOW_REGISTER" ]; then
        echo -n "Registering /proc/sys/fs/binfmt_misc/${reg}... "
        echo -n "${binfmt_configs[$reg]}" > /proc/sys/fs/binfmt_misc/register
        echo "done"
    fi
done
