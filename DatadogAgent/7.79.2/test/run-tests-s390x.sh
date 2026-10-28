#!/bin/bash
# this file has been modified with the assistance of AI Tool [claude 4.6]
# s390x validation runner for datadog-agent 7.79.2.
#
#   --targeted   (default) the 34 packages covering the code the port modifies.
#                ~1731 cases. This is what the multi-distro comparison in
#                test-template.csv is built from -- use it when comparing
#                distros or against Intel.
#
#   --full       every package under pkg/, comp/ and cmd/ that compiles for
#                s390x. ~19,268 cases, ~90 min on 4 cores. Use it for coverage.
#
# Usage: run-tests-s390x.sh [--targeted|--full] <source-root> [outdir]
#
# Tally the results with:  python3 -I tally_tests.py <outdir>/*.json
set -uo pipefail

MODE=targeted
case "${1:-}" in
  --targeted) MODE=targeted; shift ;;
  --full)     MODE=full;     shift ;;
  --*) echo "unknown option $1"; exit 2 ;;
esac

usage() {
  echo "usage: run-tests-s390x.sh [--targeted|--full] <source-root> [outdir]"
  echo "  --targeted  34 packages covering the ported code (~1731 cases, default)"
  echo "  --full      every compilable package (~19268 cases, ~90 min)"
  exit 2
}
[ $# -ge 1 ] || usage
SRC="$1"
[ -d "$SRC" ] || { echo "FATAL: $SRC is not a directory"; usage; }
SRC="$(cd "$SRC" && pwd)"
# validate the source root before creating anything
[ -f "$SRC/go.mod" ] || { echo "FATAL: $SRC is not a Go module root (no go.mod)"; exit 3; }
grep -q 'github.com/DataDog/datadog-agent' "$SRC/go.mod" \
  || { echo "FATAL: $SRC is not the datadog-agent source root"; exit 3; }
OUT="${2:-$SRC/../testlogs}"
mkdir -p "$OUT" || { echo "FATAL: cannot create $OUT"; exit 3; }
OUT="$(cd "$OUT" && pwd)"
cd "$SRC" || exit 2

export PATH=/usr/local/go/bin:$PATH
export CGO_LDFLAGS_ALLOW="-Wl,--wrap=.*"
export CGO_CFLAGS="-Werror -Wno-deprecated-declarations"
export GO111MODULE=on

# ---------------------------------------------------------------- preflight
# Every item here cost a false failure during the 2026-10-23 sweep.
warn=0
note() { echo "  WARN: $*"; warn=$((warn+1)); }
echo "=== preflight ==="
command -v go >/dev/null || { echo "FATAL: go not on PATH"; exit 4; }
go version
[ "$(uname -m)" = "s390x" ] || note "host is $(uname -m), not s390x -- results will not be an s390x validation"
command -v xz        >/dev/null || note "xz missing        -> pkg/ebpf TestRemoteConfigBTF* will fail (tar -cvJ)"
[ -f /usr/share/zoneinfo/America/New_York ] \
                                || note "tzdata missing    -> pkg/collector/runner/expvars will fail"
if [ "$MODE" = full ]; then
  command -v ip        >/dev/null || note "iproute2 missing  -> pkg/network/netlink conntrack tests will fail"
  command -v conntrack >/dev/null || note "conntrack missing -> pkg/network/netlink conntrack tests will fail"
fi
ML=$(ulimit -l 2>/dev/null)
[ "$ML" = unlimited ] || note "RLIMIT_MEMLOCK=$ML (not unlimited) -> every eBPF map test will fail with
        'failed to set memlock rlimit: operation not permitted'. Run the
        container with --privileged --ulimit memlock=-1 -v /sys/kernel/debug:/sys/kernel/debug"
[ "$warn" -eq 0 ] && echo "  all clear" || echo "  $warn warning(s) -- see docs/datadog-agent-s390x-verification-guide.md §8"
echo

# The leading `test` tag is patch 044's unified test tag; without it ~12
# packages report [build failed].
TAGS="test bundle_agent cel consul containerd cri datadog.no_waf ec2 etcd fargateprocess grpcnotrace jmx kubeapiserver kubelet linux_bpf ncm netcgo no_dynamic_plugins oracle orchestrator otlp retrynotrace sharedlibrarycheck systemprobechecks zk zlib zstd"

# LDFLAGS are REQUIRED: pkg/version TestCommit and pkg/serializer
# TestAgentPayloadVersion assert these vars are non-empty, and fail without
# them. Omitting them produced two spurious failures in the first full sweep.
LDFLAGS="-X github.com/DataDog/datadog-agent/pkg/version.Commit=$(git rev-parse --short HEAD 2>/dev/null || echo 11e5a46e)"
LDFLAGS="$LDFLAGS -X github.com/DataDog/datadog-agent/pkg/version.AgentVersion=7.79.2"
LDFLAGS="$LDFLAGS -X github.com/DataDog/datadog-agent/pkg/version.AgentPayloadVersion=v5.0.193"
LDFLAGS="$LDFLAGS -X github.com/DataDog/datadog-agent/pkg/version.AgentPackageVersion=7.79.2"

run() {
  local name="$1"; shift
  echo "########## $name"; date -u +"start %FT%TZ"
  go test -tags "$TAGS" -ldflags="$LDFLAGS" -trimpath -count=1 -timeout 2400s -json "$@" \
      > "$OUT/$name.json" 2>&1
  echo "$name go-test-exit=$?"; date -u +"end %FT%TZ"
}

if [ "$MODE" = targeted ]; then
  CORRECTNESS=(
    ./pkg/util/kernel/... ./comp/core/secrets/impl/...
    ./pkg/security/secl/model/... ./pkg/security/secl/compiler/ast/...
    ./pkg/security/secl/containerutils/... ./pkg/security/ptracer/...
    ./pkg/security/utils/... ./pkg/ebpf/maps/... ./pkg/ebpf/cgo/...
    ./pkg/ebpf/bytecode/runtime/... ./pkg/dyninst/exprlang/...
    ./pkg/dyninst/gosymname/... ./pkg/dyninst/dwarf/loclist/...
    ./pkg/dyninst/irprinter/... ./pkg/dyninst/rcjson/...
    ./pkg/dyninst/procsubscribe/procscan/... ./pkg/util/safeelf/...
    ./pkg/network/protocols/tls/... ./pkg/network/config/sysctl/...
    ./pkg/network/filter/...
  )
  B1=( ./pkg/ebpf/telemetry/... ./pkg/ebpf/ ./pkg/dyninst/loader/... ./pkg/dyninst/output/... )
  FIXTURE=( ./pkg/dyninst/gosym/... ./pkg/dyninst/gotype/... ./pkg/dyninst/object/...
            ./pkg/dyninst/decode/... ./pkg/dyninst/htlhash/... ./pkg/dyninst/compiler/... )
  run correctness "${CORRECTNESS[@]}"
  run b1unblocked "${B1[@]}"
  run fixture     "${FIXTURE[@]}"
else
  # Chunk pkg/ by explicit top-level directory. Do NOT try to use a character
  # class with Go's ... wildcard -- `./pkg/[a-c]...` matches no packages and
  # silently produces an empty run.
  mapfile -t DIRS < <(ls -d pkg/*/ | sed 's#/$##' | sort)
  echo "pkg/ top-level directories: ${#DIRS[@]}"
  CHUNK=12; i=0; n=0
  while [ $i -lt ${#DIRS[@]} ]; do
    n=$((n+1)); slice=("${DIRS[@]:$i:$CHUNK}"); pats=()
    for d in "${slice[@]}"; do pats+=("./$d/..."); done
    echo "--- pkg-chunk$n: ${slice[*]}"
    run "pkg-chunk$n" "${pats[@]}"
    i=$((i+CHUNK))
  done
  run comp ./comp/...
  run cmd  ./cmd/...
fi

echo
echo ">>> $MODE run complete -- JSON in $OUT"
TALLY="$(dirname "$(readlink -f "$0")")/tally_tests.py"
if [ ! -f "$TALLY" ]; then
  echo "NOTE: tally_tests.py not found next to this script."
  echo "      Tally with: python3 -I tally_tests.py $OUT/*.json"
elif ! command -v python3 >/dev/null; then
  echo "NOTE: python3 not installed, so results were not tallied here."
  echo "      Tally elsewhere with: python3 -I tally_tests.py $OUT/*.json"
else
  echo "=== tally ==="
  python3 -I "$TALLY" "$OUT"/*.json | tail -1
fi
