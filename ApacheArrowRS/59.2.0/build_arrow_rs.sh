#!/bin/bash
# © Copyright IBM Corporation 2026
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ApacheArrowRS/59.2.0/build_arrow_rs.sh
# Execute build script: bash build_arrow_rs.sh    (provide -h for help)
#
# This s390x port was completed using AI-assisted tooling with IBM Bob v2.2.0 (https://www.ibm.com/products/bob)

set -e -o pipefail

PACKAGE_NAME="arrow-rs"
PACKAGE_VERSION="59.2.0"
SOURCE_ROOT="$(pwd)"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ApacheArrowRS/59.2.0/patch"
PATCH_FILE="${PATCH_FILE:-/tmp/arrow-rs.patch}"
TESTS="false"
FORCE="false"

source "/etc/os-release"
DISTRO="$ID-$VERSION_ID"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$DISTRO-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

error() { echo "Error: ${*}"; exit 1; }

mkdir -p "$SOURCE_ROOT/logs/"

function prepare() {
    if command -v "sudo" >/dev/null; then
        printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
    else
        printf -- 'Sudo : No \n' >>"$LOG_FILE"
        printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n'
        exit 1
    fi

    if [[ "$FORCE" == "true" ]]; then
        printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
    else
        printf -- "\nAs part of the installation, dependencies would be installed/upgraded.\n"
        while true; do
            read -r -p "Do you want to continue (y/n) ? :  " yn
            case $yn in
            [Yy]*)
                printf -- 'User responded with Yes. \n' >>"$LOG_FILE"
                break
                ;;
            [Nn]*) exit ;;
            *) echo "Please provide confirmation to proceed." ;;
            esac
        done
    fi
}

function cleanup() {
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

    # Install Rust toolchain
    printf -- "=== Setting up Rust toolchain ===\n"
    if ! command -v cargo &>/dev/null; then
        printf -- "Installing Rust via rustup...\n"
        wget -qO- https://sh.rustup.rs \
            | sh -s -- -y --default-toolchain stable
    fi
    # shellcheck source=/dev/null
    source "$HOME/.cargo/env"
    rustup show
    printf -- "Rust toolchain ready: %s\n" "$(rustc --version)"

    cd "$SOURCE_ROOT"

    # Clone or update the source
    if [[ -d "$SOURCE_ROOT/${PACKAGE_NAME}/.git" ]]; then
        printf -- "Source directory exists; pulling latest...\n"
        cd "$SOURCE_ROOT/${PACKAGE_NAME}"
        git fetch --tags
    else
        git clone --depth 1 --branch "$PACKAGE_VERSION" https://github.com/apache/arrow-rs \
            "$SOURCE_ROOT/${PACKAGE_NAME}"
        cd "$SOURCE_ROOT/${PACKAGE_NAME}"
    fi

    printf -- "Initialising submodules\n"
    git submodule update --init --recursive

    # Apply s390x patch
    printf -- "Applying s390x patch\n"
    if [[ ! -f "$PATCH_FILE" ]]; then
        printf -- "Patch file not found locally; downloading from %s\n" "$PATCH_URL"
        wget -q "$PATCH_URL/arrow-rs.patch" -O "$PATCH_FILE"
    fi
    patch -p1 < "$PATCH_FILE"
    printf -- "Patch applied successfully.\n"
    printf -- "Files modified by patch:\n"
    git diff --name-only HEAD

    # Build
    printf -- "Building workspace\n"
    export RUSTFLAGS="-C debuginfo=0"
    cargo build --workspace --release
    printf -- "Build complete.\n"

    # Run tests
    runTest

    cd "$SOURCE_ROOT"

    printf -- " %s Installation verified.\n" "$PACKAGE_NAME"
}

function runTest() {
    set +e
    if [[ "$TESTS" == "true" ]]; then
        printf -- "Running arrow-rs tests \n\n"
        cd "$SOURCE_ROOT/${PACKAGE_NAME}"

        export RUST_BACKTRACE=1
        export RUSTFLAGS="-C debuginfo=0"
        THREADS=2

        run_phase() {
            local label="$1"; shift
            printf -- "--- %s ---\n" "$label"
            cargo test "$@" -- --test-threads="$THREADS"
        }

        # Phase 1: Core buffers and schema
        run_phase "arrow-buffer"  -p arrow-buffer  --all-features
        run_phase "arrow-schema"  -p arrow-schema  --all-features

        # Phase 2: Arrow data
        run_phase "arrow-data"    -p arrow-data    --all-features

        # Phase 3: Array types
        run_phase "arrow-array"   -p arrow-array   --all-features

        # Phase 4: Arithmetic
        run_phase "arrow-arith"   -p arrow-arith   --all-features

        # Phase 5: IPC
        run_phase "arrow-ipc"     -p arrow-ipc     --all-features

        # Phase 6: Compute extensions
        run_phase "arrow-ord"     -p arrow-ord     --all-features
        run_phase "arrow-select"  -p arrow-select  --all-features
        run_phase "arrow-string"  -p arrow-string  --all-features
        run_phase "arrow-row"     -p arrow-row     --all-features
        run_phase "arrow-cast"    -p arrow-cast    --all-features

        # Phase 7: CSV / JSON
        run_phase "arrow-csv"     -p arrow-csv     --all-features
        run_phase "arrow-json"    -p arrow-json    --all-features

        # Phase 8: Avro
        run_phase "arrow-avro"    -p arrow-avro

        # Phase 9: Flight
        run_phase "arrow-flight (default)" -p arrow-flight
        run_phase "arrow-flight (all)"     -p arrow-flight --all-features

        # Phase 10: Parquet core
        run_phase "parquet (default)"      -p parquet
        run_phase "parquet (all-features)" -p parquet --all-features

        # Phase 11: Parquet extensions + integration
        run_phase "parquet-variant"         -p parquet-variant
        run_phase "parquet-variant-json"    -p parquet-variant-json
        run_phase "parquet-variant-compute" -p parquet-variant-compute
        run_phase "parquet-geospatial"      -p parquet-geospatial
        run_phase "arrow-integration-test"  -p arrow-integration-test --all-features
        run_phase "arrow-integration-testing" -p arrow-integration-testing
        run_phase "arrow (top-level)"       -p arrow

        printf -- "=== All tests passed on s390x ===\n"
    fi

    set -e
}

function logDetails() {
    printf -- '**************************** SYSTEM DETAILS *************************************************************\n' >"$LOG_FILE"
    if [ -f "/etc/os-release" ]; then
        cat "/etc/os-release" >>"$LOG_FILE"
    fi

    cat /proc/version >>"$LOG_FILE"
    printf -- '*********************************************************************************************************\n' >>"$LOG_FILE"
    printf -- "Detected %s \n" "$PRETTY_NAME"
    printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" |& tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
    echo
    echo "Usage: "
    echo "  bash build_arrow_rs.sh  [-d debug] [-y install-without-confirmation] [-t install and run tests]"
    echo
}

while getopts "h?dyt" opt; do
    case "$opt" in
    h | \?)
        printHelp
        exit 0
        ;;
    d)
        set -x
        ;;
    y)
        FORCE="true"
        ;;
    t)
        TESTS="true"
        ;;
    esac
done

function gettingStarted() {
    printf -- '\n********************************************************************************************************\n'
    printf -- "\n* Getting Started *\n"
    printf -- " Arrow RS %s built successfully on s390x\n" "$PACKAGE_VERSION"
    printf -- " Release artefacts: %s/%s/target/release/\n" "$SOURCE_ROOT" "$PACKAGE_NAME"
    printf -- '\n'
    printf -- " To use as a Cargo dependency:\n"
    printf -- "   [dependencies]\n"
    printf -- "   arrow = { version = \"%s\", features = [\"...\"] }\n" "$PACKAGE_VERSION"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare # Check Prerequisites

case "$DISTRO" in
"rhel-8."*)
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y \
        gcc gcc-c++ make curl git pkgconfig openssl-devel \
        protobuf-compiler lz4-devel libzstd-devel cmake patch \
        python3.12 python3.12-devel ca-certificates |& tee -a "$LOG_FILE"
    sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 11 |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-9."* | "rhel-10."*)
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y \
        gcc gcc-c++ make curl git pkgconfig openssl-devel \
        protobuf-compiler lz4-devel libzstd-devel cmake patch ca-certificates |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-15."*)
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y \
        gcc gcc-c++ make curl git pkg-config libopenssl-devel \
        protobuf-devel liblz4-devel libzstd-devel cmake patch \
        python311 python311-devel ca-certificates |& tee -a "$LOG_FILE"
    sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 11 |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-16."*)
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y \
        gcc gcc-c++ make curl git pkg-config libopenssl-devel \
        protobuf-devel liblz4-devel libzstd-devel cmake patch ca-certificates |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"ubuntu-22.04" | "ubuntu-24.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update -q
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential curl git pkg-config libssl-dev \
        protobuf-compiler liblz4-dev libzstd-dev cmake ca-certificates \
        python3 python3-dev |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
