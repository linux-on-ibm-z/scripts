#!/bin/bash
# this file has been modified with the assistance of AI Tool [claude 4.6]
# Apply all s390x patches to a clean datadog-agent 7.79.2 tree.
# - Places new source files (008-015) BEFORE diff patches that modify them.
# - Auto-detects -p strip level per patch (001-030, 036, 044, 045 use -p1;
#   031-035 and 037-043 use -p4).
# - Skips patches already present in the shipped source (e.g. obsolete 019, 042).
set -euo pipefail

PATCH_DIR="${1:?Usage: $0 <patch-directory>}"
PATCH_DIR="$(cd "$PATCH_DIR" && pwd)"

if [ ! -f go.mod ] || ! grep -q 'github.com/DataDog/datadog-agent' go.mod 2>/dev/null; then
    echo "ERROR: Run this from the datadog-agent source root." >&2
    exit 1
fi

apply_one() {
    local pf="$1"
    for lvl in 1 2 3 4 5 6 0; do
        if patch --dry-run -p"$lvl" < "$pf" >/dev/null 2>&1; then
            patch -p"$lvl" < "$pf" >/dev/null
            echo "  applied ($(basename "$pf")) -p$lvl"
            return 0
        fi
    done
    # Not applicable at any level: detect "already applied" via forward dry-run
    # message (patch prompts on -R, so parse the forward output instead).
    for lvl in 1 2 3 4 5 6 0; do
        local out
        out="$(patch --dry-run -p"$lvl" < "$pf" 2>&1 || true)"
        if printf '%s' "$out" | grep -q "Reversed (or previously applied)"; then
            echo "  SKIP  ($(basename "$pf")) already applied"
            return 0
        fi
    done
    echo "  FAIL  ($(basename "$pf")) does not apply at any -p level" >&2
    return 1
}

echo "=== Phase 1: Core Agent ==="
apply_one "$PATCH_DIR/datadog-agent.patch"

echo "=== Placing new source files first ==="
declare -A NEW_FILES=(
    [008-ptracer-syscalls-s390x.go]="pkg/security/ptracer/syscalls_s390x.go"
    [009-tests-syscalls-s390x.go]="pkg/security/tests/syscalls_s390x.go"
    [010-kernel-bugs-s390x.go]="pkg/ebpf/kernelbugs/kernel_bugs_s390x.go"
    [011-consts-linux-s390x.go]="pkg/security/secl/model/consts_linux_s390x.go"
    [012-syscalls-linux-s390x.go]="pkg/security/secl/model/syscalls_linux_s390x.go"
    [013-syscalls-string-linux-s390x.go]="pkg/security/secl/model/syscalls_string_linux_s390x.go"
    [014-btfhub-constants-s390x.json]="pkg/security/probe/constantfetch/btfhub/constants_s390x.json"
    [015-btfhub-s390x.go]="pkg/security/probe/constantfetch/btfhub_s390x.go"
)
for src in "${!NEW_FILES[@]}"; do
    dest="${NEW_FILES[$src]}"
    echo "  Placing $src -> $dest"
    mkdir -p "$(dirname "$dest")"
    cp "$PATCH_DIR/$src" "$dest"
done

echo "=== Applying diff patches in order ==="
DIFF_PATCHES=(
    001-syscall-macro-s390x.patch
    002-bpf-metadata-s390x.patch
    003-bpf-tracing-typo.patch
    016-syscalls-unsupported-build-constraint.patch
    017-mount-linux-statfs-type-cast.patch
    019-syscalls-string-dedup.patch
    020-probes-s390x-syscall-prefix.patch
    021-rc-btf-s390x.patch
    022-usm-get-tls-base-s390x.patch
    023-go-tls-location-s390x.patch
    024-bpf-tracing-custom-s390x.patch
    025-cfa-s390x.patch
    026-event-s390x.patch
    027-abi-s390x.patch
    028-irgen-s390x.patch
    029-bininspect-s390x.patch
    030-safeelf-s390x.patch
    031-dyninst-object-big-endian.patch
    032-dyninst-gotype-byteorder.patch
    033-dyninst-gosym-byteorder.patch
    034-dyninst-decode-nativeendian.patch
    035-dyninst-dwarf-loclist-byteorder.patch
    036-dyninst-irgen-loclist-bo.patch
    037-ebpf-probes-test-s390x.patch
    038-bpf-telemetry-bounded-negation.patch
    039-error-telemetry-probe-read-kernel.patch
    040-errors-telemetry-dword-atomic.patch
    041-errors-telemetry-test-s390x.patch
    042-go-tls-location-core-s390x.patch
    043-sample-yaml-s390x-tags.patch
    044-b1-ebpftest-dyninsttest-test-tag.patch
    045-dyninst-decode-typeid-endianness.patch
)
for p in "${DIFF_PATCHES[@]}"; do
    apply_one "$PATCH_DIR/$p"
done

echo "=== All s390x patches applied ==="
