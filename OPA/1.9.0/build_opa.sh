#!/bin/bash
# © Copyright IBM Corporation 2025
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/OPA/1.9.0/build_opa.sh
# Execute build script: bash build_opa.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="opa"
PACKAGE_VERSION="1.9.0"
GO_VERSION="1.25.1" # see https://github.com/open-policy-agent/opa/blob/v1.9.0/.go-version
SOURCE_ROOT="$(pwd)"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/OPA/${PACKAGE_VERSION}/patch"

FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
    mkdir -p "$SOURCE_ROOT/logs/"
fi

source "/etc/os-release"

function prepare() {
    if command -v "sudo" >/dev/null; then
        printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
    else
        printf -- 'Sudo : No \n' >>"$LOG_FILE"
        printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n'
        exit 1
    fi

    if command -v "docker" >/dev/null; then
        printf -- 'Docker : Yes\n' >>"$LOG_FILE"
    else
        printf -- 'Docker : No \n' >>"$LOG_FILE"
        printf -- 'Please install Docker. \n'
        exit 1
    fi

    if [[ "$FORCE" == "true" ]]; then
        printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
    else
        # Ask user for prerequisite installation
        printf -- "\nAs part of the installation , dependencies would be installed/upgraded.\n"
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
    # Remove artifacts
    cd $SOURCE_ROOT
    rm -f go"${GO_VERSION}".linux-s390x.tar.gz
    rm -rf golang-wasmtime
    rm -rf golangci-lint
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

    #Install Go
    cd $SOURCE_ROOT
    wget -q https://storage.googleapis.com/golang/go"${GO_VERSION}".linux-s390x.tar.gz |& tee -a  "$LOG_FILE"
    chmod ugo+r go"${GO_VERSION}".linux-s390x.tar.gz
    sudo tar -C /usr/local -xzf go"${GO_VERSION}".linux-s390x.tar.gz
    export PATH=$PATH:/usr/local/go/bin
    if [[ "${ID}" != "ubuntu" ]]
    then
        sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
        printf -- 'Symlink done for gcc \n'
    fi
    go version

    #Install wasmtime library
    cd $SOURCE_ROOT
    mkdir -p golang-wasmtime && cd golang-wasmtime
    wget -q https://github.com/bytecodealliance/wasmtime/releases/download/v3.0.1/wasmtime-v3.0.1-s390x-linux-c-api.tar.xz
    tar xf wasmtime-v3.0.1-s390x-linux-c-api.tar.xz
    sudo cp wasmtime-v3.0.1-s390x-linux-c-api/lib/libwasmtime.a /usr/lib

    #Install golangci-lint docker image
    cd $SOURCE_ROOT
    export GOLANGCI_VERSION=v1.64.5
    git clone -b $GOLANGCI_VERSION https://github.com/golangci/golangci-lint.git
    cd golangci-lint/
    ./install.sh $GOLANGCI_VERSION
    cd bin
    docker build -t golangci/golangci-lint:v1.64.5 -f ../build/buildx.Dockerfile .
    
    #Setup OPA build
    cd $SOURCE_ROOT
    if [ ! -d "$SOURCE_ROOT/opa/" ]; then
        git clone -b v$PACKAGE_VERSION https://github.com/open-policy-agent/opa.git
    fi
    cd opa
    curl -sSL ${PATCH_URL}/opa.diff | git apply - || echo "Error: patch failed."

    make build
    printf -- "OPA build completed successfully. \n"

  # Run Tests
    runTest

  # Cleanup
    cleanup
}

function runTest() {
    set +e

    if [[ "$TESTS" == "true" ]]; then
        printf -- "TEST Flag is set, continue with running test \n"
        cd $SOURCE_ROOT/opa
        make test
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
    echo "bash build_opa.sh  [-d debug] [-y install-without-confirmation] [-t run tests]"
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
    printf -- "                       Getting Started                \n"
    printf -- " OPA $PACKAGE_VERSION built successfully.       \n"
    printf -- " Binary is available at $SOURCE_ROOT/opa/opa_linux_s390x \n"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"rhel-8.10" | "rhel-9.4" | "rhel-9.6")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y gcc git make python3 python3-pip tar wget xz |& tee -a "$LOG_FILE"

    configureAndInstall |& tee -a "$LOG_FILE"
        ;;
"sles-15.6" | "sles-15.7")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y gcc git make python3 python3-pip hostname tar wget awk |& tee -a "$LOG_FILE"

    configureAndInstall |& tee -a "$LOG_FILE"
        ;;
"ubuntu-22.04" | "ubuntu-24.04" | "ubuntu-25.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y gcc git make python3 python3-pip tar wget |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
