#!/bin/bash
# this file has been modified with the assistance of AI Tool [claude 4.6]
# © Copyright IBM Corporation 2026.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Build Datadog Agent 7.79.2 on s390x (IBM Z) with eBPF support.
#
# Usage:
#   bash build_datadog-agent.sh          # interactive
#   bash build_datadog-agent.sh -y       # non-interactive
#   bash build_datadog-agent.sh -y -t    # build + test
#   bash build_datadog-agent.sh -h       # help


set -e -o pipefail

PACKAGE_NAME="datadog-agent"
PACKAGE_VERSION="7.79.2"
GO_VERSION="1.26.3"
SOURCE_ROOT="$(pwd)"
SOURCE_REPO="https://github.com/DataDog/datadog-agent.git"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH_DIR="$SCRIPT_DIR/patch"
LOG_FILE="${SOURCE_ROOT}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
FORCE="false"
TESTS="false"

trap cleanup 0 1 2 ERR

mkdir -p "$SOURCE_ROOT/logs/"
source "/etc/os-release"

function prepare() {
    if ! command -v "sudo" >/dev/null; then
        printf -- 'Install sudo from repository using yum/apt and re-run.\n'
        exit 1
    fi

    if [[ "$FORCE" == "true" ]]; then
        printf -- 'Force flag is enabled.\n\n' |& tee -a "$LOG_FILE"
    else
        printf -- "\nAs part of the installation, dependencies would be installed/upgraded.\n"
        while true; do
            read -r -p "Do you want to continue (y/n)? : " yn
            case $yn in
            [Yy]*) break ;;
            [Nn]*) exit ;;
            *) echo "Please provide confirmation to proceed." ;;
            esac
        done
    fi
}

function cleanup() {
    if [[ -f "$LOG_FILE" ]]; then
        printf -- '\nBuild completed. Logs available at %s\n' "$LOG_FILE"
    fi
}

function installGo() {
    printf -- "Installing Go %s...\n" "$GO_VERSION"
    cd "$SOURCE_ROOT"
    if [[ -f "/usr/local/go/bin/go" ]] && [[ "$(/usr/local/go/bin/go version 2>/dev/null | awk '{print $3}' | sed 's/go//')" == "$GO_VERSION" ]]; then
        printf -- "Go %s already installed.\n" "$GO_VERSION"
    else
        wget -q "https://go.dev/dl/go${GO_VERSION}.linux-s390x.tar.gz"
        sudo rm -rf /usr/local/go
        sudo tar -C /usr/local -xzf "go${GO_VERSION}.linux-s390x.tar.gz"
        rm -f "go${GO_VERSION}.linux-s390x.tar.gz"
    fi
    export PATH=/usr/local/go/bin:$PATH
    export GOPATH=$SOURCE_ROOT/gopath
    mkdir -p "$GOPATH"
    go version |& tee -a "$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started.\n"

    installGo

    # Clone source
    printf -- "Cloning %s %s source...\n" "$PACKAGE_NAME" "$PACKAGE_VERSION"
    cd "$SOURCE_ROOT"
    rm -rf "${PACKAGE_NAME}-${PACKAGE_VERSION}"
    git clone --depth 1 --branch "$PACKAGE_VERSION" "$SOURCE_REPO" "${PACKAGE_NAME}-${PACKAGE_VERSION}" |& tee -a "$LOG_FILE"
    cd "${PACKAGE_NAME}-${PACKAGE_VERSION}"

    # Apply s390x patches
    printf -- "Applying s390x patches...\n"
    bash "$SCRIPT_DIR/apply-patch.sh" "$PATCH_DIR" |& tee -a "$LOG_FILE"

    # Build environment
    export CGO_LDFLAGS_ALLOW="-Wl,--wrap=.*"
    export CGO_CFLAGS="-Werror -Wno-deprecated-declarations"
    export GO111MODULE=on

    COMMIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

    # Build tags — includes linux_bpf for eBPF support
    BUILD_TAGS="bundle_agent cel consul containerd cri datadog.no_waf ec2 etcd"
    BUILD_TAGS="$BUILD_TAGS fargateprocess grpcnotrace jmx kubeapiserver kubelet"
    BUILD_TAGS="$BUILD_TAGS linux_bpf"
    BUILD_TAGS="$BUILD_TAGS ncm netcgo no_dynamic_plugins oracle orchestrator"
    BUILD_TAGS="$BUILD_TAGS otlp retrynotrace sharedlibrarycheck systemprobechecks"
    BUILD_TAGS="$BUILD_TAGS zk zlib zstd"

    # Linker flags for version embedding
    LDFLAGS="-X github.com/DataDog/datadog-agent/pkg/version.Commit=${COMMIT_SHA}"
    LDFLAGS="$LDFLAGS -X github.com/DataDog/datadog-agent/pkg/version.AgentVersion=${PACKAGE_VERSION}"
    LDFLAGS="$LDFLAGS -X github.com/DataDog/datadog-agent/pkg/version.AgentPayloadVersion=v5.0.193"
    LDFLAGS="$LDFLAGS -X github.com/DataDog/datadog-agent/pkg/version.AgentPackageVersion=${PACKAGE_VERSION}"

    printf -- "Building %s %s with eBPF support...\n" "$PACKAGE_NAME" "$PACKAGE_VERSION"
    go build \
        -mod=readonly \
        -tags "$BUILD_TAGS" \
        -o ./bin/agent/agent \
        -ldflags="$LDFLAGS" \
        -trimpath \
        github.com/DataDog/datadog-agent/cmd/agent |& tee -a "$LOG_FILE"

    printf -- "Build completed successfully.\n"

    # Verify binary
    file ./bin/agent/agent |& tee -a "$LOG_FILE"
    ./bin/agent/agent version |& tee -a "$LOG_FILE" || true

    # Install
    sudo cp ./bin/agent/agent /usr/local/bin/datadog-agent
    printf -- "Installed datadog-agent to /usr/local/bin/datadog-agent\n" |& tee -a "$LOG_FILE"
}

function runTest() {
    set +e
    cd "$SOURCE_ROOT/${PACKAGE_NAME}-${PACKAGE_VERSION}"

    export CGO_LDFLAGS_ALLOW="-Wl,--wrap=.*"
    export CGO_CFLAGS="-Werror -Wno-deprecated-declarations"
    export GO111MODULE=on
    export PATH=/usr/local/go/bin:$PATH

    BUILD_TAGS="bundle_agent cel consul containerd cri datadog.no_waf ec2 etcd"
    BUILD_TAGS="$BUILD_TAGS fargateprocess grpcnotrace jmx kubeapiserver kubelet"
    BUILD_TAGS="$BUILD_TAGS linux_bpf"
    BUILD_TAGS="$BUILD_TAGS ncm netcgo no_dynamic_plugins oracle orchestrator"
    BUILD_TAGS="$BUILD_TAGS otlp retrynotrace sharedlibrarycheck systemprobechecks"
    BUILD_TAGS="$BUILD_TAGS zk zlib zstd"

    LDFLAGS="-X github.com/DataDog/datadog-agent/pkg/version.Commit=test"
    LDFLAGS="$LDFLAGS -X github.com/DataDog/datadog-agent/pkg/version.AgentVersion=${PACKAGE_VERSION}"
    LDFLAGS="$LDFLAGS -X github.com/DataDog/datadog-agent/pkg/version.AgentPayloadVersion=v5.0.193"
    LDFLAGS="$LDFLAGS -X github.com/DataDog/datadog-agent/pkg/version.AgentPackageVersion=${PACKAGE_VERSION}"

    printf -- "\n=== Running test suite ===\n" |& tee -a "$LOG_FILE"

    # Core agent tests
    printf -- "\n--- Core Agent Tests ---\n" |& tee -a "$LOG_FILE"

    printf -- "Test: pkg/util/kernel (TestPlatform)\n" |& tee -a "$LOG_FILE"
    go test -tags "$BUILD_TAGS" -ldflags="$LDFLAGS" -count=1 -timeout 120s -v \
        -run TestPlatform ./pkg/util/kernel/... |& tee -a "$LOG_FILE"

    printf -- "Test: comp/core/secrets (TestExecCommandError)\n" |& tee -a "$LOG_FILE"
    go test -tags "test" -count=1 -timeout 120s -v \
        -run TestExecCommandError ./comp/core/secrets/impl/... |& tee -a "$LOG_FILE"

    # eBPF security probe tests
    printf -- "\n--- eBPF Security Probe Tests ---\n" |& tee -a "$LOG_FILE"

    printf -- "Test: pkg/security/secl/model\n" |& tee -a "$LOG_FILE"
    go test -tags "$BUILD_TAGS" -trimpath -count=1 -timeout 300s -v \
        ./pkg/security/secl/model/... |& tee -a "$LOG_FILE"

    printf -- "Test: pkg/security/ptracer\n" |& tee -a "$LOG_FILE"
    go test -tags "$BUILD_TAGS" -trimpath -count=1 -timeout 300s -v \
        ./pkg/security/ptracer/... |& tee -a "$LOG_FILE"

    printf -- "Test: pkg/security/utils\n" |& tee -a "$LOG_FILE"
    go test -tags "$BUILD_TAGS" -trimpath -count=1 -timeout 300s -v \
        ./pkg/security/utils/... |& tee -a "$LOG_FILE"

    printf -- "Test: pkg/ebpf/maps\n" |& tee -a "$LOG_FILE"
    go test -tags "$BUILD_TAGS" -trimpath -count=1 -timeout 300s -v \
        ./pkg/ebpf/maps/... |& tee -a "$LOG_FILE"

    printf -- "Test: pkg/ebpf/cgo\n" |& tee -a "$LOG_FILE"
    go test -tags "$BUILD_TAGS" -trimpath -count=1 -timeout 300s -v \
        ./pkg/ebpf/cgo/... |& tee -a "$LOG_FILE"

    # eBPF dynamic instrumentation tests
    printf -- "\n--- eBPF Dynamic Instrumentation Tests ---\n" |& tee -a "$LOG_FILE"

    printf -- "Test: pkg/dyninst/decode (TestFormatStruct)\n" |& tee -a "$LOG_FILE"
    go test -tags "$BUILD_TAGS" -trimpath -count=1 -timeout 120s -v \
        -run TestFormatStruct ./pkg/dyninst/decode/... |& tee -a "$LOG_FILE"

    printf -- "Test: pkg/util/safeelf\n" |& tee -a "$LOG_FILE"
    go test -tags "$BUILD_TAGS" -trimpath -count=1 -timeout 300s -v \
        ./pkg/util/safeelf/... |& tee -a "$LOG_FILE"

    printf -- "\n=== Test suite completed ===\n" |& tee -a "$LOG_FILE"
    set -e
}

function logDetails() {
    printf -- '\n**************************** SYSTEM DETAILS ****************************\n' >>"$LOG_FILE"
    cat "/etc/os-release" >>"$LOG_FILE"
    cat /proc/version >>"$LOG_FILE"
    printf -- '**************************************************************************\n' >>"$LOG_FILE"
}

function gettingStarted() {
    printf -- '\n******************************* USAGE ***********************************\n'
    printf -- "The Datadog Agent binary is installed at /usr/local/bin/datadog-agent\n"
    printf -- "Run 'datadog-agent version' to verify the installation.\n"
    printf -- '\n**************************************************************************\n'
}

while getopts "h?dyt" opt; do
    case "$opt" in
    h | \?)
        printf -- "Usage: %s [-d] [-y] [-t]\n" "$0"
        printf -- "  -d  Enable debug mode\n"
        printf -- "  -y  Auto-accept prompts (non-interactive)\n"
        printf -- "  -t  Run tests after build\n"
        exit 0
        ;;
    d) set -x ;;
    y) FORCE="true" ;;
    t) TESTS="true" ;;
    esac
done

logDetails
prepare

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"rhel-9"* | "rhel-10"* | "rocky-9"* | "rocky-10"*)
    printf -- "Installing dependencies for %s...\n" "$DISTRO" |& tee -a "$LOG_FILE"
    sudo yum install -y gcc gcc-c++ make wget tar git patch diffutils file |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"ubuntu-24.04" | "debian-12"* | "debian-13"*)
    printf -- "Installing dependencies for %s...\n" "$DISTRO" |& tee -a "$LOG_FILE"
    sudo apt-get update
    sudo apt-get install -y gcc g++ make wget ca-certificates tar git patch file |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-16"*)
    printf -- "Installing dependencies for %s...\n" "$DISTRO" |& tee -a "$LOG_FILE"
    sudo zypper install -y gcc gcc-c++ make wget tar git patch file |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s is not supported.\n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

if [[ "$TESTS" == "true" ]]; then
    runTest |& tee -a "$LOG_FILE"
fi

gettingStarted |& tee -a "$LOG_FILE"
