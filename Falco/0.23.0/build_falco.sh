#!/bin/bash
# © Copyright IBM Corporation 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Falco/0.23.0/build_falco.sh
# Execute build script: bash build_falco.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="falco"
PACKAGE_VERSION="0.23.0"

export SOURCE_ROOT="$(pwd)"

PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Falco/${PACKAGE_VERSION}/patch/"

TEST_USER="$(whoami)"
FORCE="false"
FORCE_LUAJIT="false"
TESTS="false"
BUILD_KERNEL_DRIVER="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
    mkdir -p "$SOURCE_ROOT/logs/"
fi

if [ -f "/etc/os-release" ]; then
    source "/etc/os-release"
fi

DISTRO="$ID-$VERSION_ID"

function prepare()
{

    if [[ "$FORCE" == "true" ]]; then
        printf -- 'Force attribute provided hence continuing with install without confirmation message\n' | tee -a "$LOG_FILE"
    else
        printf -- 'As part of the installation, dependencies would be installed/upgraded.\n'
        while true; do
            read -r -p "Do you want to continue (y/n) ? :  " yn
            case $yn in
            [Yy]*)

                break
                ;;
            [Nn]*) exit ;;
            *) echo "Please provide correct input to proceed." ;;
            esac
        done
    fi
}

function cleanup() {

    rm -rf "${SOURCE_ROOT}/protobuf-3.5.0.patch"
    if [[ "${ID}" == "rhel" ]]; then
        rm -rf "${SOURCE_ROOT}/cmake-3.7.2.tar.gz"
    fi
    printf -- '\nCleaned up the artifacts\n'
}

function configureAndInstall() {
    printf -- '\nConfiguration and Installation started \n'

    #Installing dependencies
    printf -- 'User responded with Yes. \n'
    printf -- 'Building dependencies\n'

    cd "${SOURCE_ROOT}"
    if [[ "${ID}" == "rhel" ]]; then
       if [[ "${VERSION_ID}" == "8.1" ]] || [[ "${VERSION_ID}" == "8.2" ]]; then
           printf -- 'Installing cmake for RHEL 8\n'
           sudo yum install -y cmake
       else
           printf -- 'Building cmake\n'
           cd $SOURCE_ROOT
           wget https://cmake.org/files/v3.7/cmake-3.7.2.tar.gz
           tar xzf cmake-3.7.2.tar.gz
           cd cmake-3.7.2
           ./configure --prefix=/usr/
           ./bootstrap --system-curl --parallel=16
           make -j16
           sudo make install
           export PATH=/usr/local/bin:$PATH
           cmake --version
           printf -- 'cmake installed successfully\n'
       fi
    fi

    printf -- '\nDownloading Falco source. \n'
    cd $SOURCE_ROOT
    git clone https://github.com/falcosecurity/falco.git
    cd falco
    git checkout ${PACKAGE_VERSION}

    curl -SL -o falco.patch $PATCH_URL/falco.patch
    git apply falco.patch

    curl -SL -o lauxlib.h.patch $PATCH_URL/lauxlib.h.patch

    printf -- '\nStarting Falco build. \n'
    mkdir -p $SOURCE_ROOT/falco/build/release
    cd $SOURCE_ROOT/falco/build/release

    CMAKE_FLAGS=""

    # RHEL does not ship all the bundled dependencies
    if [[ "${ID}" == "rhel" ]] || [[ "${DISTRO}" == "ubuntu-16.04" ]]; then
        CMAKE_FLAGS+=" -DFALCO_ETC_DIR=/etc/falco -DUSE_BUNDLED_OPENSSL=On -DUSE_BUNDLED_DEPS=On "
    fi

    # Kernel driver is not built by default
    if [[ "$BUILD_KERNEL_DRIVER" == "false" ]]; then
        CMAKE_FLAGS+=" -DBUILD_DRIVER=OFF "
    fi

    cmake $CMAKE_FLAGS ../..
    make
    make package
    sudo make install
    printf -- '\nFalco build completed successfully. \n'

    if [[ "$BUILD_KERNEL_DRIVER" == "true" ]]; then
        printf -- '\nInserting Falco kernel module. \n'
        sudo rmmod falco || true

        cd $SOURCE_ROOT/falco/build/release
        sudo insmod driver/falco.ko
        printf -- '\nInserted Falco kernel module successfully. \n'
    fi

    # Run Tests
    runTest
}

function logDetails() {
    printf -- 'SYSTEM DETAILS\n' >"$LOG_FILE"
    if [ -f "/etc/os-release" ]; then
        cat "/etc/os-release" >>"$LOG_FILE"
    fi

    cat /proc/version >>"$LOG_FILE"
    printf -- "\nDetected %s \n" "$PRETTY_NAME"
    printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" | tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
    echo
    echo "Usage: "
    echo "  build_falco.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests] [-k build-kernel-driver] "
    echo
}

function runTest() {
    set +e

    if [[ "$TESTS" == "true" ]]; then
        cd $SOURCE_ROOT/falco/build/release
        make tests
    fi

    set -e
}

while getopts "h?dkyt" opt; do
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
    k)
        BUILD_KERNEL_DRIVER="true"
        ;;
    t)
        if command -v "$PACKAGE_NAME" >/dev/null; then
            printf -- "%s is detected in the system. Skipping build and running tests .\n" "$PACKAGE_NAME" | tee -a "$LOG_FILE"
            TESTS="true"
            exit 0
        else
            TESTS="true"
        fi

        ;;
    esac
done

function printSummary() {

    printf -- '\n********************************************************************************************************\n'
    printf -- "\n* Getting Started * \n"
    printf -- '\nRun falco --help to see all available options to run falco'
    printf -- '\nFor more information on Falco please visit https://falco.org/docs/ \n\n'
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare

case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04" | "ubuntu-20.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
    sudo apt-get update
    sudo apt-get install -y git cmake autoconf automake build-essential curl wget rpm pkg-config patch sudo kmod

    if [[ "${DISTRO}" != "ubuntu-16.04" ]]; then
        sudo apt-get install -y libssl-dev libyaml-dev libncurses-dev libc-ares-dev libprotobuf-dev \
            protobuf-compiler libjq-dev libyaml-cpp-dev libgrpc++-dev protobuf-compiler-grpc        \
            libcurl4-openssl-dev libelf-dev
    else
        sudo apt-get install -y libssl-dev libyaml-dev libncurses-dev libc-ares-dev libcurl4-openssl-dev libelf-dev \
            elfutils libtool
    fi

    if [[ "$BUILD_KERNEL_DRIVER" == "true" ]]; then
        sudo apt-get install -y linux-headers-$(uname -r) | tee -a "$LOG_FILE"
    fi

    configureAndInstall | tee -a "$LOG_FILE"
    ;;

"rhel-7.6" | "rhel-7.7" | "rhel-7.8" | "rhel-8.1" | "rhel-8.2")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

    if [[ "$DISTRO" == "rhel-8."* ]]; then
        sudo subscription-manager repos --enable codeready-builder-for-rhel-8-s390x-rpms
    fi

    sudo yum install -y gcc gcc-c++ git make autoconf automake pkg-config patch curl wget rpm-build \
            libcurl-devel zlib-devel libyaml-devel c-ares-devel ncurses-devel libtool glibc-static \
            libstdc++-static elfutils-libelf-devel

    if [[ "$BUILD_KERNEL_DRIVER" == "true" ]]; then
        sudo yum install -y kernel-devel-$(uname -r) | tee -a "$LOG_FILE"
    fi

    configureAndInstall | tee -a "$LOG_FILE"
    ;;

*)
    printf -- "%s not supported \n" "$DISTRO" | tee -a "$LOG_FILE"
    exit 1
    ;;
esac

printSummary | tee -a "$LOG_FILE"
