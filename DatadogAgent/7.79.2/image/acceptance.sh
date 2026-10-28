#!/bin/bash
# this file has been modified with the assistance of AI Tool [claude 4.6]
# Acceptance suite for the s390x Agent image. Runs ON the target host.
#
# Kept as a standalone file rather than a heredoc inside test-on-z.sh: nesting
# $(...) and quotes through ssh + heredoc + `sh -c` silently mangles the checks
# (an earlier inline version printed the literal command substitutions instead
# of running them, so the structural tests never actually executed).
#
# Usage (on the Z host): acceptance.sh <runtime> <image> [api-key]
set -uo pipefail

RT="${1:?usage: acceptance.sh <podman|docker> <image> [api-key]}"
IMAGE="${2:?}"
API_KEY="${3:-0000000000000000000000000000000a}"
FAILED=0

pass() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAILED=$((FAILED+1)); }
note() { printf '        %s\n' "$1"; }

echo "=== host ==="
uname -srm
grep PRETTY_NAME /etc/os-release | cut -d= -f2- | tr -d '"'
if [ -e /proc/sys/fs/binfmt_misc/qemu-s390x ]; then
  note "WARNING: qemu-s390x binfmt present -- confirm this is native execution"
else
  note "no qemu binfmt handler: native s390x execution"
fi
[ "$(uname -m)" = "s390x" ] && pass "host is s390x" || fail "host is $(uname -m), not s390x"

echo
echo "=== T1: binary is 64-bit big-endian s390x ==="
HDR=$($RT run --rm "$IMAGE" od -An -tx1 -N20 /opt/datadog-agent/bin/agent/agent | tr -s ' ')
note "$(echo "$HDR" | tr '\n' ' ')"
echo "$HDR" | tr -d ' \n' | grep -q '^7f454c460202' \
  && pass "ELF64 MSB (big-endian)" || fail "not ELF64 MSB"
echo "$HDR" | tr -d ' \n' | grep -q '0016' \
  && pass "e_machine = EM_S390 (22)" || fail "e_machine is not EM_S390"

echo
echo "=== T2: versions ==="
for pair in "agent:agent version" "trace-agent:trace-agent version" "process-agent:process-agent version"; do
  bin=${pair%%:*}; cmd=${pair#*:}
  out=$($RT run --rm "$IMAGE" sh -c "$cmd" 2>&1 | head -1)
  note "$bin -> $out"
  echo "$out" | grep -q "7.79.2" && echo "$out" | grep -q "go1.26.3" \
    && pass "$bin reports 7.79.2 / go1.26.3" || fail "$bin version unexpected"
done

echo
echo "=== T3: image structure ==="
S=$($RT run --rm "$IMAGE" sh -c '
  printf "uid=%s\n"        "$(getent passwd dd-agent | cut -d: -f3)"
  printf "init=%s\n"       "$([ -x /init ] && echo yes || echo no)"
  printf "services=%s\n"   "$(ls /etc/services.d | tr "\n" "," )"
  printf "preload=%s\n"    "$LD_PRELOAD"
  printf "nosys=%s\n"      "$([ -f /opt/lib/nosys.so ] && echo yes || echo no)"
  printf "cacert=%s\n"     "$(wc -l < /opt/datadog-agent/embedded/ssl/certs/cacert.pem)"
  printf "traceloader=%s\n" "$([ -x /opt/datadog-agent/embedded/bin/trace-loader ] && echo yes || echo no)"
  printf "confd=%s\n"      "$(ls /etc/datadog-agent/conf.d | wc -l)"
')
note "$(echo "$S" | tr '\n' ' ')"
get() { echo "$S" | grep "^$1=" | cut -d= -f2-; }
[ "$(get uid)" = "100" ]        && pass "dd-agent uid is 100"        || fail "dd-agent uid is $(get uid)"
[ "$(get init)" = "yes" ]       && pass "s6 /init present"           || fail "s6 /init missing"
[ "$(get nosys)" = "yes" ]      && pass "nosys.so present"           || fail "nosys.so missing"
[ "$(get preload)" = "/opt/lib/nosys.so" ] && pass "LD_PRELOAD set"  || fail "LD_PRELOAD is '$(get preload)'"
[ "$(get traceloader)" = "yes" ] && pass "trace-loader present"      || fail "trace-loader missing"
[ "$(get cacert)" -gt 100 ] 2>/dev/null && pass "CA bundle populated" || fail "CA bundle looks empty"
[ "$(get confd)" -gt 10 ] 2>/dev/null   && pass "conf.d populated"    || fail "conf.d looks empty"

echo
echo "=== T4: s6 multicall dispatch (regression: argv[0] aliasing) ==="
$RT run --rm "$IMAGE" sh -c 's6-test 256 -eq 0' >/tmp/_t 2>&1; rc=$?
if [ $rc -eq 1 ] && ! grep -q "unknown subcommand" /tmp/_t; then
  pass "s6-test 256 -eq 0 -> rc=1, no multicall error"
else
  fail "s6-test misdispatches (rc=$rc): $(cat /tmp/_t)"
fi
rm -f /tmp/_t

echo
echo "=== T5: runs under s6 supervision ==="
$RT rm -f ddztest >/dev/null 2>&1
$RT run -d --name ddztest -e DD_API_KEY="$API_KEY" -e DD_HOSTNAME=z-native-test "$IMAGE" >/dev/null
for _ in $(seq 1 36); do
  sleep 5
  $RT exec ddztest agent status >/dev/null 2>&1 && break
done
ST=$($RT exec ddztest agent status 2>&1)
note "$(echo "$ST" | grep -E 'Build arch|Go Version|Agent flavor' | tr -s ' \n' ' ')"
echo "$ST" | grep -q "Build arch: s390x" && pass "agent reports Build arch: s390x" \
                                         || fail "Build arch not s390x"
SVC=$($RT exec ddztest sh -c 'ls /run/service 2>/dev/null | grep -vE "s6|fdholder" | sort | tr "\n" " "')
note "supervised: $SVC"
for s in agent process trace; do
  echo "$SVC" | grep -qw "$s" && pass "service '$s' supervised" || fail "service '$s' not supervised"
done

HEALTH=$($RT exec ddztest /probe.sh 2>&1)
HN=$(echo "$HEALTH" | grep -oE '=== [0-9]+ healthy' | grep -oE '[0-9]+')
UN=$(echo "$HEALTH" | sed -n '/unhealthy components ===/,$p' | grep -vE '===|^Error' | tr -d ' \n')
note "healthy=$HN unhealthy='$UN'"
[ "${HN:-0}" -ge 15 ] 2>/dev/null && pass "$HN healthy components" || fail "only ${HN:-0} healthy components"
if [ "$UN" = "forwarder" ] || [ -z "$UN" ]; then
  pass "no unexpected unhealthy components (forwarder = invalid test API key)"
else
  fail "unexpected unhealthy components: $UN"
fi

ERR=$($RT logs ddztest 2>&1 | grep -iE 'fatal|unable to spawn|Permission denied' | sort -u)
if [ -z "$ERR" ]; then pass "no fatal/spawn errors in log"
else fail "errors in log:"; echo "$ERR" | sed 's/^/          /'; fi

echo
echo "=== T6: container dies when the agent dies ==="
$RT rm -f ddzdie >/dev/null 2>&1
# no DD_HOSTNAME and an unresolvable host name => agent exits 255
$RT run -d --name ddzdie -e DD_API_KEY="$API_KEY" "$IMAGE" >/dev/null
DIED=no
for _ in $(seq 1 24); do
  sleep 10
  [ "$($RT inspect ddzdie --format '{{.State.Status}}')" != "running" ] && { DIED=yes; break; }
done
[ "$DIED" = yes ] && pass "container exited after agent failure (finish hook works)" \
                  || fail "container still running 240s after agent failure"
$RT rm -f ddztest ddzdie >/dev/null 2>&1

echo
if [ $FAILED -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "$FAILED CHECK(S) FAILED"; fi
exit $FAILED
