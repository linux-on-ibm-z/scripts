#!/bin/bash
# © Copyright IBM Corporation 2025
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/refs/heads/master/Minio/2025-07-18T21-56-31Z/build_minio.sh
# Execute build script: bash build_minio.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="minio"
PACKAGE_VERSION="RELEASE.2025-09-07T16-13-09Z"
MC_PACKAGE_VERSION="RELEASE.2025-08-13T08-35-41Z"
CURDIR="$(pwd)"
SOURCE_ROOT="$(pwd)"
FORCE="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
TESTS='false'


#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
    mkdir -p "$CURDIR/logs/"
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

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"
    #Install Go
    export GOPATH=$SOURCE_ROOT
    cd $GOPATH
    GO_VERSION=1.24.2
    wget -q https://go.dev/dl/go"${GO_VERSION}".linux-s390x.tar.gz
    chmod ugo+r go"${GO_VERSION}".linux-s390x.tar.gz
    sudo rm -rf /usr/local/go /usr/bin/go
    sudo tar -C /usr/local -xzf go"${GO_VERSION}".linux-s390x.tar.gz
    sudo ln -sf /usr/local/go/bin/go /usr/bin/ 
    sudo ln -sf /usr/local/go/bin/gofmt /usr/bin/
    go version  
    export PATH=$PATH:$GOPATH/bin

    #Download Minio source code

    cd "$CURDIR"
    mkdir -p $GOPATH/src/github.com/minio
    cd $GOPATH/src/github.com/minio
    git clone -b ${PACKAGE_VERSION} https://github.com/minio/minio.git
    cd minio 
    make
    make install
    printf -- "Build Minio success\n"

    #Download MC source code
    cd "$CURDIR"
    mkdir -p $GOPATH/src/github.com/minio
    cd $GOPATH/src/github.com/minio
    git clone -b ${MC_PACKAGE_VERSION} https://github.com/minio/mc.git
    cd mc/
    make
    make install
    printf -- "Installation MC success\n"

    #verify minio and mc
    export PATH=$CURDIR/bin:$PATH
    minio --version 
    minio --help
    mc --version
    mc --help
    if [[ "$TESTS" == "true" ]]; then
        runTests
    fi

}

function logDetails() {
    printf -- '**************************** SYSTEM DETAILS *************************************************************\n' >"$LOG_FILE"
    if [ -f "/etc/os-release" ]; then
        cat "/etc/os-release" >>"$LOG_FILE"
    else
        cat /etc/redhat-release >>"${LOG_FILE}"
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
    echo "bash minio.sh  [-d debug] [-y install-without-confirmation] [-t run-tests]"
    echo
}
function runTests() {
    set +e
    printf -- 'Running tests \n\n'
    
    cd "$SOURCE_ROOT"
    cd "$GOPATH/src/github.com/minio/minio"
    go install mvdan.cc/gofumpt@latest
    gofumpt -w .&&go generate ./...
    make test
    
    printf -- "Starting MinIO...\n"
    minio server data/ > minio.log 2>&1 &
    MINIO_PID=$!
    echo "MinIO started with PID $MINIO_PID"
    sleep 5
    
    cd "$GOPATH/src/github.com/minio/mc"
    gofumpt -w .&&go generate ./...s
    make test
    
    printf -- "Stopping MinIO...\n"
    kill "$MINIO_PID"
    # waiting for process to exit
    while kill -0 "$MINIO_PID" 2> /dev/null; do
        sleep 1
    done
    
    printf -- "MinIO stopped.\n"
    set -e
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
    printf -- "Note: for suse, run command .\n"
    printf -- 'export PATH=$CURDIR/bin:$PATH \n'
    printf -- "Start Minio Server : \n"
    printf -- " minio server $SOURCE_ROOT/data \n\n"
    printf -- "Access Minio on browser http://<ip_address>:9000.\n"
    printf -- "You have successfully started Minio.\n"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"rhel-8.10" | "rhel-9.4" | "rhel-9.6" | "rhel-10.0")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y git make wget tar gcc curl which diffutils jq |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-15.6" | "sles-15.7")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y git make wget tar gcc which curl gawk m4 jq |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"ubuntu-22.04" | "ubuntu-24.04" | "ubuntu-25.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y git make wget tar gcc curl jq |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
