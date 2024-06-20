#!/bin/bash
# © Copyright IBM Corporation 2024
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/BoringSSL/Aug2023/build_boringssl.sh
# Execute build script: bash build_boringssl.sh   (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="boringssl"
CURDIR="$(pwd)"
BORINGSSL_REPO="https://github.com/linux-on-ibm-z/boringssl"
BORINGSSL_BRANCH="patch-s390x-Aug2023"
GO_VERSION="1.22.4"
CMAKE_VERSION="3.29.5"
TESTS="false"
FORCE="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${BORINGSSL_BRANCH}-$(date +"%F-%T").log"
ENV_VARS=$CURDIR/setenv.sh

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
    mkdir -p "$CURDIR/logs/"
fi

source "/etc/os-release"

function cleanup() {
   printf -- 'Cleaning up\n'
   cd "${CURDIR}"
   rm -f go${GO_VERSION}.linux-s390x.tar.gz
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

function buildCmake() {
    cd "${CURDIR}"
    local cmake_short_version=${CMAKE_VERSION%.*}
	wget https://cmake.org/files/v${cmake_short_version}/cmake-${CMAKE_VERSION}.tar.gz
	tar xzf cmake-${CMAKE_VERSION}.tar.gz
	cd cmake-${CMAKE_VERSION}
	./configure --prefix=/usr/local
	make && sudo make install
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

	# Download and Install Go
	cd $CURDIR
    wget https://storage.googleapis.com/golang/go${GO_VERSION}.linux-s390x.tar.gz
    tar -xzf go${GO_VERSION}.linux-s390x.tar.gz
    export PATH=$CURDIR/go/bin:$PATH
    export GOROOT=$CURDIR/go
  	export GOPATH=$CURDIR/go/bin
    echo "export PATH=$PATH" >>$ENV_VARS
    echo "export GOROOT=$GOROOT" >>$ENV_VARS
    echo "export GOPATH=$GOPATH" >>$ENV_VARS
    go version
	
    # Download Boringssl
    cd $CURDIR
    git clone "$BORINGSSL_REPO"
    cd boringssl
    git checkout "$BORINGSSL_BRANCH"
	
    # Build Boringssl
    cd $CURDIR/boringssl
    if [[ $DISTRO == "ubuntu-23.10" || $DISTRO == "ubuntu-24.04" ]]; then
        # This is needed to fix a build error with newer g++ versions
        curl -sSL https://github.com/google/boringssl/commit/e3d9b69e8c6f6b78120006282c020c71803a8075.patch | git apply -
    fi
    mkdir -p build
    cd build/
    cmake -G Ninja ..
    cd $CURDIR/boringssl
    ninja -C build
    printf -- "Build for Boringssl is successful\n" 

    # Run Test
    runTest
}

function runTest() {
    if [[ "$TESTS" == "true" ]]; then
        printf -- 'Running tests \n\n'
        cd $CURDIR/boringssl
        ninja -C build run_tests |& tee $CURDIR/all_tests.log
    fi
}

function logDetails() {
    printf -- '**************************** SYSTEM DETAILS *************************************************************\n' >"$LOG_FILE"
    if [ -f "/etc/os-release" ]; then
        cat "/etc/os-release" >>"$LOG_FILE"
    fi

    cat /proc/version >>"$LOG_FILE"
    printf -- '*********************************************************************************************************\n' >>"$LOG_FILE"
    printf -- "Detected %s \n" "$PRETTY_NAME"
    printf -- "Request details : PACKAGE NAME= %s , BORINGSSL_BRANCH= %s \n" "$PACKAGE_NAME" "$BORINGSSL_BRANCH" |& tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
    echo
    echo "Usage: "
    echo "bash build_boringssl.sh  [-d debug] [-y install-without-confirmation] [-t install and run tests]"
    echo
}

gettingStarted() {
        printf -- '\n*********************************************************************************************\n'
        printf -- "Getting Started:\n\n"
        printf -- "BoringSSL Build Successful \n"
        printf -- "BoringSSL libraries can be found here:\n  $CURDIR/boringssl/build/ssl/libssl.a\n  $CURDIR/boringssl/build/crypto/libcrypto.a\n\n"
        printf -- "For more information, see: https://github.com/google/boringssl\n"
        printf -- '*********************************************************************************************\n'
        printf -- '\n'

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

logDetails
prepare # Check Prerequisites
DISTRO="$ID-$VERSION_ID"
rm -f "$ENV_VARS"

case "$DISTRO" in
"ubuntu-20.04" | "ubuntu-22.04" | "ubuntu-23.10" | "ubuntu-24.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$BORINGSSL_BRANCH" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y wget tar make gcc g++ cmake ninja-build git curl |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-8.8" | "rhel-8.9" | "rhel-8.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$BORINGSSL_BRANCH" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y wget tar make gcc-toolset-12-gcc-c++ gcc-toolset-12-libstdc++-devel bzip2 zlib zlib-devel git xz diffutils cmake ninja-build libarchive-devel.s390x curl |& tee -a "$LOG_FILE"
    source /opt/rh/gcc-toolset-12/enable
    echo "source /opt/rh/gcc-toolset-12/enable" >>$ENV_VARS
	configureAndInstall |& tee -a "$LOG_FILE"
	;;
"rhel-9.2" | "rhel-9.3" | "rhel-9.4")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$BORINGSSL_BRANCH" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y wget tar make gcc gcc-c++ bzip2 zlib zlib-devel git xz diffutils cmake ninja-build libarchive-devel.s390x |& tee -a "$LOG_FILE"
    sudo yum install -y --allowerasing curl |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;
"sles-12.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$BORINGSSL_BRANCH" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y wget git tar gzip ninja zlib-devel gcc12 gcc12-c++ make openssl-devel curl |& tee -a "$LOG_FILE"
    export CC=/usr/bin/gcc-12
    export CXX=/usr/bin/g++-12
    echo "export CC=$CC" >>$ENV_VARS
    echo "export CXX=$CXX" >>$ENV_VARS
    buildCmake |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-15.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$BORINGSSL_BRANCH" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y wget git tar gzip cmake ninja zlib-devel gcc12 gcc12-c++ curl |& tee -a "$LOG_FILE"
    export CC=/usr/bin/gcc-12
    export CXX=/usr/bin/g++-12
    echo "export CC=$CC" >>$ENV_VARS
    echo "export CXX=$CXX" >>$ENV_VARS
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
