#!/bin/bash
# © Copyright IBM Corporation 2025.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Beats/8.17.1/build_beats.sh
# Execute build script: bash build_beats.sh    (provide -h for help)
#

set -e -o pipefail

PACKAGE_NAME="beats"
PACKAGE_VERSION="8.17.1"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Beats/${PACKAGE_VERSION}/patch"
GO_VERSION="1.22.0"
PYTHON_VERSION="3.11.4"
OPENSSL_VERSION="1.1.1s"
RUST_VERSION="1.76.0"
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
    ./configure --prefix=/usr/local --exec-prefix=/usr/local
    make
    sudo make install
    export PATH=/usr/local/bin:$PATH
    
    if ! [[ "${DISTRO}" == "rhel-8."* ]]; then
        sudo update-alternatives --install /usr/bin/python python /usr/local/bin/python3.11 10
    fi
    if [[ "${DISTRO}" == "rhel-9."* ]]; then
        sudo update-alternatives --install /usr/local/bin/python3 python3 /usr/bin/python3.11 10
    else
        sudo update-alternatives --install /usr/bin/python3 python3 /usr/local/bin/python3.11 10
    fi
    sudo update-alternatives --display python3
    python3 -V
}

function packetbeatSupported() {
    [[ "${DISTRO}" == "ubuntu-20.04" ]] ||
    [[ "${DISTRO}" == "ubuntu-22.04" ]] ||
        [[ "${DISTRO}" =~ ^rhel-8 ]] ||
        [[ "${DISTRO}" =~ ^rhel-9 ]] ||
        [[ "${DISTRO}" =~ ^sles ]]
}

function heartbeatSupported() {
    [[ "${DISTRO}" =~ ^rhel-8 ]] ||
    [[ "${DISTRO}" =~ ^rhel-9 ]] ||
    [[ "${DISTRO}" =~ ^sles ]]
}

function auditbeatSupported() {
    [[ "${DISTRO}" == "ubuntu-20.04" ]] ||
    [[ "${DISTRO}" == "ubuntu-22.04" ]] ||
        [[ "${DISTRO}" =~ ^rhel-8 ]] ||
        [[ "${DISTRO}" =~ ^rhel-9 ]] ||
        [[ "${DISTRO}" =~ ^sles ]]
}

function configureAndInstall() {
    printf -- 'Configuration and Installation started \n'

    cd $CURDIR

    #Installing pip
    wget --no-check-certificate -q https://bootstrap.pypa.io/get-pip.py
    python3 get-pip.py
    rm get-pip.py

    pip3 install wheel -v
    pip3 install "cython<3.0.0" pyyaml==5.4.1 --no-build-isolation -v
    
    printf -- 'Installing Rust \n'
    wget -q -O rustup-init.sh https://sh.rustup.rs
    bash rustup-init.sh -y
    export PATH=$PATH:$HOME/.cargo/bin
    rustup toolchain install ${RUST_VERSION}
    rustup default ${RUST_VERSION}
    rustc --version | grep "${RUST_VERSION}"

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
    cd beats
    curl -sSL ${PATCH_URL}/metricbeat.patch | git apply - || error "Metricbeat patch"
    cd $GOPATH/src/github.com/elastic
    sudo rm -rf ebpfevents
    git clone -b v0.6.0 https://github.com/elastic/ebpfevents.git
    cd ebpfevents
    curl -sSL ${PATCH_URL}/ebpfevents.patch | git apply - || error "ebpfevents patch"
    go install golang.org/x/tools/cmd/stringer@latest
    export PATH=$PATH:$(go env GOPATH)/bin
    go generate ./...


    #Making directory to add .yml files
    if [ ! -d "/etc/beats/" ]; then
        sudo mkdir -p /etc/beats
    fi

    export PATH=$GOPATH/bin:$PATH
    export GRPC_PYTHON_BUILD_SYSTEM_OPENSSL=true
    export PYTHON_EXE=python3
    export PYTHON_ENV=/tmp/venv3

    # Not all OS are supported by each Beat, see support matrix: https://www.elastic.co/support/matrix#matrix_os

    #Building packetbeat and adding to /usr/bin
    if packetbeatSupported; then
        printf -- "Installing packetbeat \n" |& tee -a "$LOG_FILE"
        cd $GOPATH/src/github.com/elastic/beats/packetbeat
        make
        ./packetbeat version
        make update
        make fmt
        sudo cp "./packetbeat" /usr/bin/
        sudo cp "./packetbeat.yml" /etc/beats/
    fi

    #Building filebeat and adding to /usr/bin
    printf -- "Installing filebeat \n" |& tee -a "$LOG_FILE"
    cd $GOPATH/src/github.com/elastic/beats/filebeat
    make
    ./filebeat version
    make update
    make fmt
    sudo cp "./filebeat" /usr/bin/
    sudo cp "./filebeat.yml" /etc/beats/

    #Building metricbeat and adding to /usr/bin
    printf -- "Installing metricbeat \n" |& tee -a "$LOG_FILE"
    cd $GOPATH/src/github.com/elastic/beats/metricbeat
    go install github.com/magefile/mage@latest
    mage build
    ./metricbeat version
    mage update
    mage fmt
    sudo cp "./metricbeat" /usr/bin/
    sudo cp "./metricbeat.yml" /etc/beats/

    #Building heartbeat and adding to /usr/bin
    if heartbeatSupported; then
        # Building heartbeat and adding to usr/bin
        printf -- "Installing heartbeat \n" |& tee -a "$LOG_FILE"
        cd $GOPATH/src/github.com/elastic/beats/heartbeat
        make
        ./heartbeat version
        make update
        make fmt
        sudo cp "./heartbeat" /usr/bin/
        sudo cp "./heartbeat.yml" /etc/beats/
    fi

    #Building auditbeat and adding to /usr/bin
    if auditbeatSupported; then
        printf -- "Installing auditbeat \n" |& tee -a "$LOG_FILE"
        cd $GOPATH/src/github.com/elastic/beats/auditbeat
        go mod edit -replace=github.com/elastic/ebpfevents@v0.6.0=$GOPATH/src/github.com/elastic/ebpfevents
        go mod tidy
        make
        ./auditbeat version
        make update
        make fmt
        sudo cp "./auditbeat" /usr/bin/
        sudo cp "./auditbeat.yml" /etc/beats/
    fi

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
        if packetbeatSupported; then
            printf -- "\nTesting Packetbeat\n"
            cd $GOPATH/src/github.com/elastic/beats/packetbeat
            make unit
            make system-tests
            printf -- "\nTesting Packetbeat completed successfully\n"
        fi

        #METRICBEAT
        printf -- "\nTesting Metricbeat\n"
        cd $GOPATH/src/github.com/elastic/beats/metricbeat
        mage test
        printf -- "\nTesting Metricbeat completed successfully\n"

        if heartbeatSupported; then
            #HEARTBEAT
            printf -- "\nTesting Heartbeat\n"
            cd $GOPATH/src/github.com/elastic/beats/heartbeat
            make unit
            make system-tests
            printf -- "\nTesting Heartbeat completed successfully\n"
        fi

        if auditbeatSupported; then
            #AUDIBEAT
            printf -- "\nTesting Auditbeat\n"
            cd $GOPATH/src/github.com/elastic
            sudo rm -rf tk-btf
            git clone -b v0.1.0 https://github.com/elastic/tk-btf.git
            cd tk-btf
            curl -sSL ${PATCH_URL}/tk-btf.patch | git apply - || error "tk-btf patch"
	          go generate ./...
            cd $GOPATH/src/github.com/elastic/beats/auditbeat
            go mod edit -replace=github.com/elastic/tk-btf@v0.1.0=$GOPATH/src/github.com/elastic/tk-btf
            go mod tidy
            make unit
            make system-tests
            printf -- "\nTesting Auditbeat completed successfully\n"
        fi

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
    printf -- '   sudo <beat_name> -e -c /etc/beats/<beat_name>.yml -d "publish"  \n'
    printf -- '    Example: sudo packetbeat -e -c /etc/beats/packetbeat.yml -d "publish"  \n\n'
    printf -- '\nFor more information visit https://www.elastic.co/guide/en/beats/libbeat/8.17/getting-started.html \n'
    printf -- '*************************************************************************************************\n'
    printf -- '\n'
}

###############################################################################################################

logDetails
prepare #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-20.04" | "ubuntu-22.04" | "ubuntu-24.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git curl make wget tar gcc g++ libcap-dev libpcap0.8-dev openssl libssh-dev acl rsync tzdata patch fdclone libsystemd-dev libjpeg-dev libffi-dev libbz2-dev libdb-dev libgdbm-dev liblzma-dev libncurses-dev libreadline-dev libsqlite3-dev libssl-dev tk-dev uuid-dev xz-utils zlib1g-dev |& tee -a "${LOG_FILE}"
    configureAndInstallPython |& tee -a "${LOG_FILE}"
    configureAndInstall |& tee -a "${LOG_FILE}"
    ;;

"rhel-8.8" | "rhel-8.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y git curl make wget tar gcc gcc-c++ libpcap-devel openssl openssl-devel which acl zlib-devel patch systemd-devel libjpeg-devel python3.11 python3.11-devel bzip2-devel gdbm-devel libdb-devel libffi-devel libuuid-devel ncurses-devel readline-devel sqlite-devel tk-devel xz xz-devel |& tee -a "${LOG_FILE}"
    configureAndInstallPython |& tee -a "${LOG_FILE}"
    configureAndInstall |& tee -a "${LOG_FILE}"
    ;;

"rhel-9.2" | "rhel-9.4" | "rhel-9.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y git curl make wget tar gcc gcc-c++ libpcap-devel openssl openssl-devel which acl zlib-devel patch systemd-devel libjpeg-devel python3.11 python3.11-devel bzip2-devel gdbm-devel libdb-devel libffi-devel libuuid-devel ncurses-devel readline-devel sqlite-devel tk-devel xz xz-devel |& tee -a "${LOG_FILE}"
    configureAndInstallPython |& tee -a "${LOG_FILE}"
    configureAndInstall |& tee -a "${LOG_FILE}"
    ;;

"sles-15.6")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y git curl gawk make wget tar gcc gcc-c++ libpcap libpcap-devel acl patch libsystemd0 systemd-devel libjpeg62-devel openssl libopenssl-devel zlib-devel gzip gdbm-devel libbz2-devel libdb-4_8-devel libffi-devel libnsl-devel libuuid-devel ncurses-devel readline-devel sqlite3-devel tk xz-devel timezone |& tee -a "${LOG_FILE}"
    configureAndInstallPython |& tee -a "${LOG_FILE}"
    python3 -V
    configureAndInstall |& tee -a "${LOG_FILE}"
    ;;

esac

gettingStarted |& tee -a "${LOG_FILE}"
