#!/bin/bash
# © Copyright IBM Corporation 2022
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: curl -sSLO https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Consul/1.12.2/build_consul.sh
# Execute build script: bash build_consul.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="consul"
PACKAGE_VERSION="1.12.2"
SOURCE_ROOT="$(pwd)"
export GOPATH=$SOURCE_ROOT
GO_PACKAGE_VERSION="1.17.7"
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

    if command -v "consul" > /dev/null; then
      if consul version | grep "Consul v$PACKAGE_VERSION"
      then
        printf -- "Version : %s (Satisfied) \n" "v${PACKAGE_VERSION}" >>  "$LOG_FILE"
        printf -- "No update required for consul \n" |& tee -a  "$LOG_FILE"
        exit 0;
      fi
    fi

    if [[ "$FORCE" == "true" ]]; then
        printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
    else
        # Ask user for prerequisite installation
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
    # Remove artifacts
    rm -rf "$SOURCE_ROOT/go1.17.7.linux-s390x.tar.gz"
    rm -rf "$SOURCE_ROOT/build_go.sh"
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

    # Install Go
    printf -- 'Installing go\n'
    cd ${GOPATH}
    wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Go/1.18.4/build_go.sh
    bash build_go.sh -y -v ${GO_PACKAGE_VERSION}
    go version
    printf -- "Install Go success\n"

    # Build and install consul
    mkdir -p "$GOPATH/bin"
    export PATH=$GOPATH/bin:$PATH
	printenv

    mkdir -p $GOPATH/src/github.com/hashicorp
    cd $GOPATH/src/github.com/hashicorp
    rm -rf consul

    printf -- "Building and installing consul\n"
    git clone https://github.com/hashicorp/consul.git
    cd consul
    git checkout v${PACKAGE_VERSION}
    make tools
    make dev

    # Create a symlink
    sudo ln -sf $GOPATH/bin/consul /usr/bin/consul
    printf -- "Build and install consul success\n"

    # Run Test
    runTest

    cd "$SOURCE_ROOT"

    # Verify consul installation
    if command -v "consul" >/dev/null; then
        printf -- " %s Installation verified.\n" "$PACKAGE_NAME"
    else
        printf -- "Error while installing %s, exiting with 127 \n" "$PACKAGE_NAME"
        exit 127
    fi
}

function runTest() {
    set +e
    if [[ "$TESTS" == "true" ]]; then
        printf -- 'Running consul tests \n\n'
        cd $GOPATH/src/github.com/hashicorp/consul/
        make test 2>&1 | tee -a maketestlog
        grep "FAIL" maketestlog | grep github.com | awk '{print $2}' >>test.txt

        if [ -s $GOPATH/src/github.com/hashicorp/consul/test.txt ]; then
            printf -- '*****************************************************************************************************************************\n'
            printf -- '\nUnexpected test failures detected. Tip : Try running them individually as go test -v <package_name> -run <failed_test_name>
                                         or increasing the timeout using -timeout option to go test command.\n'
            printf -- '*****************************************************************************************************************************\n'
        fi
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
    echo " bash build_consul.sh  [-d debug] [-y install-without-confirmation] [-t install and run tests]"
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
    printf -- "\n*Getting Started * \n"
    printf -- "Running consul: \n"
    printf -- "nohup consul agent -dev & \n\n"
    printf -- "You have successfully started consul.\n"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare # Check Prequisites

case "$DISTRO" in
"ubuntu-18.04" | "ubuntu-20.04" | "ubuntu-22.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y curl gcc git make wget unzip |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-7.8" | "rhel-7.9" | "rhel-8.4" | "rhel-8.6" | "rhel-9.0")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y  curl gcc git make wget diffutils procps-ng unzip|& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-12.5" | "sles-15.3" | "sles-15.4")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y curl gcc git-core make wget awk unzip|& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
