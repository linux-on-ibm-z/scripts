#!/bin/bash
# ©  Copyright IBM Corporation 2025.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Kong/3.9.1/build_kong.sh
# Execute build script: bash build_kong.sh    (provide -h for help -t for test)
#

set -e -o pipefail

PACKAGE_NAME="kong"
PACKAGE_VERSION="3.9.1"
FORCE=false
CURDIR="$(pwd)"
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
NON_ROOT_USER="$(whoami)"
GO_VERSION=1.24.0
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Kong/${PACKAGE_VERSION}/patch"

trap cleanup 1 2 ERR

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
        mkdir -p "$CURDIR/logs/"
fi

if [ -f "/etc/os-release" ]; then
        source "/etc/os-release"
fi

function prepare() {
        if command -v "sudo" >/dev/null; then
                printf -- 'Sudo : Yes\n'
        else
                printf -- 'Sudo : No \n'
                printf -- 'Install sudo from repository using apt or yum based on your distro. \n'
                exit 1
        fi


        if [[ "$FORCE" == "true" ]]; then
                printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "${LOG_FILE}"
        else
                # Ask user for prerequisite installation
                printf -- "\nAs part of the installation, dependencies would be installed/upgraded. \n"
                while true; do
                        read -r -p "Do you want to continue (y/n) ? :  " yn
                        case $yn in
                        [Yy]*)
                                printf -- 'User responded with Yes. \n' |& tee -a "${LOG_FILE}"
                                break
                                ;;
                        [Nn]*) exit ;;
                        *) echo "Please provide confirmation to proceed." ;;
                        esac
                done
        fi

        true
}

function cleanup() {
        sudo rm -rf "${CURDIR}/bazel"
        sudo rm -rf "${CURDIR}/go1*"
        printf -- 'Cleaned up the artifacts\n' >>"${LOG_FILE}"
}

function configureAndInstall() {

    printf -- 'Configuration and Installation started \n'

    # Install Go
    cd "${CURDIR}"
    wget -q https://storage.googleapis.com/golang/go"${GO_VERSION}".linux-s390x.tar.gz
    chmod ugo+r go"${GO_VERSION}".linux-s390x.tar.gz
    sudo tar -C /usr/local -xzf go"${GO_VERSION}".linux-s390x.tar.gz
    export PATH=$PATH:/usr/local/go/bin
    go version

    # Build Bazel
    printf -- '\nBuilding Bazel..... \n'
    cd "${CURDIR}"
    mkdir bazel && cd bazel
    wget https://github.com/bazelbuild/bazel/releases/download/7.3.1/bazel-7.3.1-dist.zip
    unzip bazel-7.3.1-dist.zip
    chmod -R +w .
    env EXTRA_BAZEL_ARGS="--tool_java_runtime_version=local_jdk" bash ./compile.sh
    sudo cp $CURDIR/bazel/output/bazel /usr/local/bin
    bazel --version

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh /dev/stdin -y
    export PATH="$HOME/.cargo/bin:$PATH"

    # Install rules_rust
    cd "${CURDIR}"
    git clone --depth 1 -b 0.56.0 https://github.com/bazelbuild/rules_rust.git
    cd $CURDIR/rules_rust/crate_universe
    cargo build --bin=cargo-bazel
    export CARGO_BAZEL_GENERATOR_URL=file://$(pwd)/target/debug/cargo-bazel
    export CARGO_BAZEL_REPIN=true

    # gh auth login
    mkdir -p $CURDIR/gh_repo/bin
    cd $CURDIR/gh_repo
    git clone -b v2.45.0 https://github.com/cli/cli.git
    cd cli
    make bin/gh
    cp ./bin/gh $CURDIR/gh_repo/bin/gh
    export PATH=$CURDIR/gh_repo/bin:$PATH
    cd $CURDIR/gh_repo
    tee BUILD.bazel <<EOF
    filegroup(
        name = "gh",
        srcs = ["../gh_repo/gh"],
        visibility = ["//visibility:public"],
    )
EOF

    tee WORKSPACE <<EOF
    filegroup(
        name = "gh",
        srcs = ["../gh_repo/gh"],
        visibility = ["//visibility:public"],
    )
EOF

    # Downloading and installing Kong
    printf -- 'Downloading and installing Kong.\n'
    cd "${CURDIR}"
    git clone -b ${PACKAGE_VERSION} https://github.com/Kong/kong.git
    cd kong
    curl -sSL ${PATCH_URL}/kong.diff | git apply - || echo "Error: patch failed."
    make build-venv
    make build-kong

    #call test
    runTest
    # Cleanup
    cleanup

}

function runTest() {
    set +e
    if [[ "$TESTS" == "true" ]]; then
        printf -- "TEST Flag is set , Continue with running test \n"

        # Building grpcbin image
        printf -- "Building grpcbin \n"
        cd $CURDIR
        git clone -b v1.0.9 https://github.com/kong/grpcbin.git
        cd grpcbin
        docker build -t kong/grpcbin:latest .

        # Building h2client
        printf -- "Building h2client \n"
        cd $CURDIR
        git clone -b v0.4.4 https://github.com/Kong/h2client.git
        cd h2client
        go build -o h2client
        mkdir -p $CURDIR/kong/bin
        mv h2client $CURDIR/kong/bin/
        chmod +x $CURDIR/kong/bin/h2client

        if [[ "${ID}" == "ubuntu" ]]; then
            sudo apt install -y libssl-dev
        elif [[ "${ID}" == "rhel" ]]; then
            sudo yum install -y openssl-devel
        fi

        cd $CURDIR/kong
        . bazel-bin/build/kong-dev-venv.sh
        start_services
        sleep 150
        kong migrations bootstrap
        sleep 60
        make dev
        make test
        deactivate
        printf -- "Tests completed. \n"
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
        echo "  bash build_kong.sh  [-d debug] [-y install-without-confirmation] [-t for executing build with tests]"
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
		# Early Docker check if -t is passed
                if command -v "docker" >/dev/null; then
                        printf -- 'Docker : Yes\n' |& tee -a "${LOG_FILE}"
                else
                        printf -- 'Docker : No \n' |& tee -a "${LOG_FILE}"
                        printf -- 'Please install Docker before running with -t flag.\n'
                        exit 1
                fi
                ;;	
        esac
done

function gettingStarted() {
        printf -- '\n********************************************************************************************************\n'
        printf -- "\n* Getting Started * \n"
        printf -- "Note: To activate the venv needed for Kong, please run: \n"
	printf -- "    cd $CURDIR \n"
	printf -- "    . bazel-bin/build/kong-dev-venv.sh \n"
        printf -- "Run Kong: \n"
        printf -- "    kong version \n\n"
        printf -- '********************************************************************************************************\n'
}

###############################################################################################################

logDetails
prepare

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"rhel-8.10" | "rhel-9.4" | "rhel-9.6")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo yum install -y automake gcc gcc-c++ git libyaml-devel cmake make patch perl perl-IPC-Cmd protobuf-devel unzip java-21-openjdk-devel valgrind valgrind-devel zlib-devel zip |& tee -a "${LOG_FILE}"
        export JAVA_HOME=/usr/lib/jvm/java-21-openjdk/
        export PATH=$JAVA_HOME/bin:/usr/local/lib:$PATH
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"ubuntu-22.04" | "ubuntu-24.04" | "ubuntu-25.04")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo apt-get update
        sudo apt-get install -y automake build-essential curl wget openjdk-21-jdk file git libyaml-dev libprotobuf-dev m4 perl pkg-config procps unzip valgrind zlib1g-dev libyaml-dev cmake zip |& tee -a "${LOG_FILE}"
        export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-s390x/
        export PATH=$JAVA_HOME/bin:/usr/local/lib:$PATH
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

*)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "${LOG_FILE}"
        exit 1

        ;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
