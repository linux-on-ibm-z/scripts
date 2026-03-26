#!/bin/bash
# © Copyright IBM Corporation 2026.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Beats/9.3.1/build_beats.sh
# Execute build script: bash build_beats.sh    (provide -h for help)
#

set -e -o pipefail

PACKAGE_NAME="beats"
PACKAGE_VERSION="9.3.1"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Beats/${PACKAGE_VERSION}/patch"
GO_VERSION="1.24.11"
PYTHON_VERSION="3.11.4"
CURDIR="$(pwd)"
USER="$(whoami)"

FORCE="false"
TESTS="false"
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
BUILD_ENV="${CURDIR}/setenv.sh"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
    mkdir -p "$CURDIR/logs/"
fi

if [ -f "/etc/os-release" ]; then
    source "/etc/os-release"
fi

function error() {
    echo "Error: ${*}"
    exit 1
}

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
        printf -- "\nAs part of the installation, dependencies would be installed/upgraded. \n"
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
    sudo rm -rf Python-3.11.4* data go1* rustup-init.sh
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"

}
function configureAndInstallPython() {
    printf -- 'Configuration and Installation of Python started\n'

    cd $CURDIR

    #Install Python 3.x
    sudo rm -rf Python*
    wget -q https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz
    tar -xzf Python-${PYTHON_VERSION}.tgz
    cd Python-${PYTHON_VERSION}
    ./configure --prefix=/opt/python3.11 --enable-optimizations --with-lto
    make -j$(nproc)
    sudo make install
    /opt/python3.11/bin/python3.11 -V
}

function configureAndInstall() {
    printf -- 'Configuration and Installation started \n'

    configureAndInstallPython |& tee -a "${LOG_FILE}"

    cd $CURDIR
    
    printf -- 'Installing Rust \n'
    wget -q -O rustup-init.sh https://sh.rustup.rs
    bash rustup-init.sh -y
    export PATH=$PATH:$HOME/.cargo/bin

    cd $CURDIR

    # Install go
    printf -- "Installing Go... \n"
    wget -q https://go.dev/dl/go${GO_VERSION}.linux-s390x.tar.gz
    chmod ugo+r go${GO_VERSION}.linux-s390x.tar.gz
    sudo tar -C /usr/local -xzf go${GO_VERSION}.linux-s390x.tar.gz
    export PATH=$PATH:/usr/local/go/bin

    if [[ "${ID}" != "ubuntu" ]]; then
        sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
        printf -- 'Symlink done for gcc \n'
    fi
    go version

    # Set GOPATH if not already set
    if [[ -z "${GOPATH}" ]]; then
        printf -- "Setting default value for GOPATH \n"

        export GOPATH=$(go env GOPATH)
        printf 'export GOPATH=%q\n' "$GOPATH" > "${BUILD_ENV}"
        mkdir -p $GOPATH
    else
        printf -- "GOPATH already set : Value : %s \n" "$GOPATH"
    fi

    # Checking permissions
    sudo setfacl -dm u::rwx,g::r,o::r $GOPATH
    cd $GOPATH
    touch test && ls -la test && rm test

    # Install beats
    printf -- "\nInstalling Beats..... \n"

    # Download Beats Source
    if [ ! -d "$GOPATH/src/github.com/elastic" ]; then
        mkdir -p $GOPATH/src/github.com/elastic
    fi
    cd $GOPATH/src/github.com/elastic
    sudo rm -rf beats
    git clone -b v$PACKAGE_VERSION https://github.com/elastic/beats.git

    export PATH=$GOPATH/bin:$PATH
    export GRPC_PYTHON_BUILD_SYSTEM_OPENSSL=true
    export PATH=/opt/python3.11/bin:$PATH
    export PYTHON_EXE=python3.11

    #Building packetbeat and adding to /usr/bin
    printf -- "Installing packetbeat \n" |& tee -a "$LOG_FILE"
    cd $GOPATH/src/github.com/elastic/beats/packetbeat
    make
    ./packetbeat version
    make update
    make fmt
    cp -r build/kibana .

    #Building filebeat and adding to /usr/bin
    printf -- "Installing filebeat \n" |& tee -a "$LOG_FILE"
    cd $GOPATH/src/github.com/elastic/beats/filebeat
    make
    ./filebeat version
    make update
    make fmt
    cp -r build/kibana .

    #Building metricbeat and adding to /usr/bin
    printf -- "Installing metricbeat \n" |& tee -a "$LOG_FILE"
    cd $GOPATH/src/github.com/elastic/beats/metricbeat
    go install github.com/magefile/mage@latest
    mage build
    ./metricbeat version
    mage update
    mage fmt
    cp -r build/kibana .

    #Building heartbeat and adding to /usr/bin
    printf -- "Installing heartbeat \n" |& tee -a "$LOG_FILE"
    cd $GOPATH/src/github.com/elastic/beats/heartbeat
    make
    ./heartbeat version
    make update
    make fmt

    #Building auditbeat and adding to /usr/bin
    printf -- "Installing auditbeat \n" |& tee -a "$LOG_FILE"
    cd $GOPATH/src/github.com/elastic/beats/auditbeat
    make
    ./auditbeat version
    make update
    make fmt
    cp -r build/kibana .

    # Run Tests
    runTest

    printf -- "\n Installation of %s %s was successful \n\n" $PACKAGE_NAME $PACKAGE_VERSION
}

function runTest() {
    set +e

    if [[ "$TESTS" == "true" ]]; then
        printf -- "TEST Flag is set , Continue with running test \n"

        #FILEBEAT
        printf -- "\nTesting Filebeat\n"
        cd $GOPATH/src/github.com/elastic/beats/filebeat
        make unit
        make system-tests
        printf -- "\nTesting Filebeat completed successfully\n"

        #PACKETBEAT
        printf -- "\nTesting Packetbeat\n"
        cd $GOPATH/src/github.com/elastic/beats/packetbeat
        make unit
        make system-tests
        printf -- "\nTesting Packetbeat completed successfully\n"

        #METRICBEAT
        printf -- "\nTesting Metricbeat\n"
        cd $GOPATH/src/github.com/elastic/beats/metricbeat
        mage unitTest
        printf -- "\nTesting Metricbeat completed successfully\n"

        #HEARTBEAT
        printf -- "\nTesting Heartbeat\n"
        cd $GOPATH/src/github.com/elastic/beats/heartbeat
        make unit
        make system-tests
        printf -- "\nTesting Heartbeat completed successfully\n"

        #AUDIBEAT
        printf -- "\nTesting Auditbeat\n"
        cd $GOPATH/src/github.com/elastic
        sudo rm -rf tk-btf
        git clone -b v0.2.0 https://github.com/elastic/tk-btf.git
        cd tk-btf
        curl -sSL ${PATCH_URL}/tk-btf.patch | git apply - || error "tk-btf patch"
        go generate ./...
        cd $GOPATH/src/github.com/elastic/beats/auditbeat
        go mod edit -replace=github.com/elastic/tk-btf@v0.2.0=$GOPATH/src/github.com/elastic/tk-btf
        go mod tidy
        make unit
        make test
        printf -- "\nTesting Auditbeat completed successfully\n"

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
    echo "  bash build_beats.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests]"
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
    printf -- '\n***********************************************************************************************\n'
    printf -- "Getting Started: \n"
    printf -- "To run a particular beat , run the following command : \n"
    printf -- " source setenv.sh \n"
    printf -- " cd $GOPATH/src/github.com/elastic/beats/<beat_name> \n"
    printf -- " sudo ./<beat_name> setup -e \n"
    printf -- ' sudo ./<beat_name> -e -d "publish"  \n'
    printf -- " Example:  \n\n"
    printf -- " source setenv.sh \n"
    printf -- " cd $GOPATH/src/github.com/elastic/beats/packetbeat \n"
    printf -- " sudo ./packetbeat setup -e \n"
    printf -- ' sudo ./packetbeat -e -d "publish"  \n'
    printf -- '\nFor more information visit https://www.elastic.co/docs/reference/beats \n'
    printf -- '*************************************************************************************************\n'
    printf -- '\n'
}

###############################################################################################################

logDetails
prepare #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"rhel-8.10" | "rhel-9.4" | "rhel-9.6" | "rhel-9.7")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y git curl make wget tar gcc gcc-c++ libpcap-devel openssl openssl-devel which acl zlib-devel patch systemd-devel libjpeg-devel python3.11 python3.11-devel bzip2-devel gdbm-devel libdb-devel libffi-devel libuuid-devel ncurses-devel readline-devel sqlite-devel tk-devel xz xz-devel  |& tee -a "${LOG_FILE}"
    configureAndInstall > >(tee -a "${LOG_FILE}") 2>&1
    ;;

 "sles-15.7")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y git curl gawk make wget tar gcc gcc-c++ libpcap libpcap-devel acl patch libsystemd0 systemd-devel libjpeg62-devel openssl libopenssl-devel zlib-devel gzip gdbm-devel libbz2-devel libdb-4_8-devel libffi-devel libnsl-devel libuuid-devel ncurses-devel readline-devel sqlite3-devel tk xz-devel timezone |& tee -a "${LOG_FILE}"

    configureAndInstall > >(tee -a "${LOG_FILE}") 2>&1
    ;;

"ubuntu-22.04" | "ubuntu-24.04" )
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git curl make wget tar gcc g++ libcap-dev libpcap0.8-dev openssl libssh-dev acl rsync tzdata patch fdclone libsystemd-dev libjpeg-dev libffi-dev libbz2-dev libdb-dev libgdbm-dev liblzma-dev libncurses-dev libreadline-dev libsqlite3-dev libssl-dev tk-dev uuid-dev xz-utils zlib1g-dev |& tee -a "${LOG_FILE}"
    configureAndInstall > >(tee -a "${LOG_FILE}") 2>&1
    ;;

esac

gettingStarted |& tee -a "${LOG_FILE}"
