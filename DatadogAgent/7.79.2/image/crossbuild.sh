#!/bin/bash
# this file has been modified with the assistance of AI Tool [claude 4.6]
# Cross-compile datadog-agent 7.79.2 binaries for s390x from an amd64 host.
# Runs inside ubuntu:24.04 (amd64) so the s390x cross-glibc (2.39) matches the
# ubuntu:24.04 s390x runtime image exactly.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq crossbuild-essential-s390x >/dev/null
s390x-linux-gnu-gcc --version | head -1

export PATH=/work/go-1.26.3/bin:$PATH
export GOCACHE=/work/gocache-cross GOMODCACHE=/work/gomodcache
export GOOS=linux GOARCH=s390x CGO_ENABLED=1 CC=s390x-linux-gnu-gcc GO111MODULE=on
export CGO_LDFLAGS_ALLOW="-Wl,--wrap=.*"
export CGO_CFLAGS="-Wno-deprecated-declarations"
go version

cd /work/src
TAGS="bundle_agent cel consul containerd cri datadog.no_waf ec2 etcd fargateprocess grpcnotrace jmx kubeapiserver kubelet ncm no_dynamic_plugins orchestrator otlp retrynotrace zk zlib zstd"
LDFLAGS="-X github.com/DataDog/datadog-agent/pkg/version.Commit=11e5a46e"
LDFLAGS="$LDFLAGS -X github.com/DataDog/datadog-agent/pkg/version.AgentVersion=7.79.2"
LDFLAGS="$LDFLAGS -X github.com/DataDog/datadog-agent/pkg/version.AgentPayloadVersion=v5.0.193"
LDFLAGS="$LDFLAGS -X github.com/DataDog/datadog-agent/pkg/version.AgentPackageVersion=7.79.2"
echo "$TAGS" > /work/out/BUILD_TAGS.txt

build() {
  local name="$1" pkg="$2"
  echo "### building $name"
  go build -mod=readonly -tags "$TAGS" -ldflags="$LDFLAGS" -trimpath -o "/work/out/$name" "$pkg" \
    && echo "OK  $name" || echo "FAIL $name"
}
build agent         ./cmd/agent
build trace-agent   ./cmd/trace-agent
build process-agent ./cmd/process-agent
ls -la /work/out/
