#!/bin/bash
# © Copyright IBM Corporation 2025.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Falco/0.42.1/build_falco.sh
# Execute build script: bash build_falco.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="falco"
PACKAGE_VERSION="0.42.1"
GO_VERSION="1.25.0"
PLUGINS_VERSION="0.4.1" # https://github.com/falcosecurity/falco/blob/0.42.1/CMakeLists.txt#L270
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Falco/0.42.1/patch"

export SOURCE_ROOT="$(pwd)"
TEST_USER="$(whoami)"
FORCE="false"
TESTS="false"
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

function error() { echo "Error: ${*}"; exit 1; }

function prepare()
{
    if [[ "$FORCE" == "true" ]]; then
        printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
    else
        printf -- 'As part of the installation, dependencies would be installed/upgraded.\n'
        while true; do
            read -r -p "Do you want to continue (y/n) ? :  " yn
            case $yn in
            [Yy]*) break ;;
            [Nn]*) exit ;;
            *) echo "Please provide correct input to proceed." ;;
            esac
        done
    fi
}

function cleanup() {
    rm -rf go"${GO_VERSION}".linux-s390x.tar.gz* /tmp/cmake-3.28.3*
    printf -- '\nCleaned up the artifacts\n'
}

# --- New function: build and install modern CMake from source ---
function installCMakeFromSource() {
    printf -- '\nInstalling latest CMake (3.28.3) from source...\n'
    sudo apt-get remove --purge -y cmake || true
    sudo yum remove -y cmake || true
    sudo zypper remove -y cmake || true

    cd $SOURCE_ROOT
    wget -q https://cmake.org/files/v3.28/cmake-3.28.3.tar.gz
    tar -xf cmake-3.28.3.tar.gz
    cd cmake-3.28.3
    ./bootstrap
    make -j"$(nproc)"
    sudo make install
    cmake --version
    printf -- '\nCMake 3.28.3 installed successfully.\n'
}

function configureAndInstall() {
    printf -- '\nConfiguration and Installation started \n'

    #Installing dependencies
    printf -- 'User responded with Yes. \n'
    printf -- 'Building dependencies\n'

    cd "${SOURCE_ROOT}"
    
    printf -- 'Installing Go\n'
    cd $SOURCE_ROOT
    wget -q https://storage.googleapis.com/golang/go"$GO_VERSION".linux-s390x.tar.gz
    chmod ugo+r go"$GO_VERSION".linux-s390x.tar.gz
    sudo tar -C /usr/local -xzf go"$GO_VERSION".linux-s390x.tar.gz
    sudo ln -sf /usr/local/go/bin/go /usr/bin/
    sudo ln -sf /usr/local/go/bin/gofmt /usr/bin/
    export GOPATH=$SOURCE_ROOT
    export PATH=$GOPATH/bin:$PATH
    export CC=$(which gcc)
    export CXX=$(which g++)
    go version
    printf -- 'Go installed successfully\n'
    
    if [[ "${DISTRO}" == "ubuntu-22.04" ]]; then
        printf -- 'Building bpftool\n'
        cd "${SOURCE_ROOT}"
        git clone --depth 1 --recurse-submodules https://github.com/libbpf/bpftool.git
        cd bpftool && cd src
        CLANG=Nope make -j8
        sudo make install
        printf -- 'bpftool installed successfully\n'
    fi

    printf -- '\nBuilding container plugin \n'
    # Build container plugin
    cd $SOURCE_ROOT
    git clone --depth 1 -b plugins/container/v${PLUGINS_VERSION} https://github.com/falcosecurity/plugins.git
    cd plugins/plugins/container
    make libcontainer.so
    tar zcf $SOURCE_ROOT/container-0.4.1-linux-s390x.tar.gz libcontainer.so

    printf -- '\nDownloading Falco source. \n'
    cd $SOURCE_ROOT
    git clone --depth 1 -b ${PACKAGE_VERSION} https://github.com/falcosecurity/falco.git
    cd falco

    printf -- '\nApplying patch \n'
    wget -O $SOURCE_ROOT/falco/cmake/modules/falcosecurity-libs-repo/libs_container_plugin_cmake.patch $PATCH_URL/libs_container_plugin_cmake.patch
    sed -i "s#SOURCE_ROOT_PATH#$SOURCE_ROOT#g" $SOURCE_ROOT/falco/cmake/modules/falcosecurity-libs-repo/libs_container_plugin_cmake.patch
    curl -sSL ${PATCH_URL}/falco.patch | git apply -

    if [[ "${DISTRO}" =~ ^rhel-8 ]]; then 
        printf -- '\nApplying patch for RHEL 8 \n'
        curl -sSL ${PATCH_URL}/modern_bpf.patch | patch -p1 --forward || echo "Error: modern_bpf patch failed."
    fi

    printf -- '\nStarting Falco cmake setup. \n'
    mkdir -p $SOURCE_ROOT/falco/build
    cd $SOURCE_ROOT/falco/build
    if [[ "$TESTS" == "true" ]]; then
        CMAKE_TEST_FLAG="-DBUILD_FALCO_UNIT_TESTS=ON"
    else
        CMAKE_TEST_FLAG=""
    fi
    if [[ "${DISTRO}" =~ ^rhel-8 ]]; then
        CMAKE_FLAGS="-DFALCO_ETC_DIR=/etc/falco -DUSE_BUNDLED_DEPS=ON -DCMAKE_BUILD_TYPE=Release -DBUILD_DRIVER=ON -DBUILD_BPF=OFF ${CMAKE_TEST_FLAG}"
    else
        CMAKE_FLAGS="-DFALCO_ETC_DIR=/etc/falco -DUSE_BUNDLED_DEPS=ON -DCMAKE_BUILD_TYPE=Release -DBUILD_DRIVER=ON -DBUILD_BPF=ON -DBUILD_FALCO_MODERN_BPF=ON ${CMAKE_TEST_FLAG}"
    fi
    cmake $CMAKE_FLAGS ../
    
    printf -- '\nStarting Falco build. \n'
    cd $SOURCE_ROOT/falco/build/

    if [[ "${ID}" == "ubuntu" ]]; then
        sed -i 's/!found/found/g' falcosecurity-libs-repo/falcosecurity-libs-prefix/src/falcosecurity-libs/userspace/libscap/engine/modern_bpf/scap_modern_bpf.c
    fi

    make -j$(nproc)

    printf -- '\nStarting Falco install. \n'
    sudo make install
    printf -- '\nFalco build completed successfully. \n'

    printf -- '\nInserting Falco kernel module. \n'
    sudo rmmod falco || true

    cd $SOURCE_ROOT/falco/build
    sudo insmod driver/falco.ko
    printf -- '\nInserted Falco kernel module successfully. \n'

    if [[ "${DISTRO}" =~ ^rhel-9 ]] || [[ "${ID}" == "ubuntu" ]] || [[ "${DISTRO}" = "sles-15" ]]; then
        sudo mkdir /root/.falco || true
        sudo cp -f $SOURCE_ROOT/falco/build/driver/bpf/probe.o /root/.falco/falco-bpf.o
    fi

    runTest
}

function logDetails() {
    printf -- 'SYSTEM DETAILS\n' >"$LOG_FILE"
    if [ -f "/etc/os-release" ]; then
       cat "/etc/os-release" >>"$LOG_FILE"
    fi
    cat /proc/version >>"$LOG_FILE"
    printf -- "\nDetected %s \n" "$PRETTY_NAME"
    printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" |& tee -a "$LOG_FILE"
}

function printHelp() {
    echo
    echo "Usage: "
    echo "  bash build_falco.sh  [-d debug] [-y install-without-confirmation] [-t run-tests-after-build] "
    echo
}

function runTest() {
    set +e
    if [[ "$TESTS" == "true" ]]; then
        cd $SOURCE_ROOT/falco/build
        sudo ./unit_tests/falco_unit_tests 
    fi
    set -e
}

while getopts "h?dyt" opt; do
    case "$opt" in
    h | \?) printHelp; exit 0 ;;
    d) set -x ;;
    y) FORCE="true" ;;
    t)
        if command -v "$PACKAGE_NAME" >/dev/null; then
            printf -- "%s is detected in the system. Skipping build and running tests .\n" "$PACKAGE_NAME" |& tee -a "$LOG_FILE"
            TESTS="true"
            runTest
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
    printf -- "\n# Kernel module"
    printf -- "\nRun sudo falco -o engine.kind=kmod"
    if [[ "${DISTRO}" =~ ^rhel-9 ]] || [[ "${DISTRO}" == "ubuntu-22.04" ]] || [[ "${DISTRO}" == "ubuntu-24.04" ]] || [[ "${DISTRO}" == "ubuntu-25.04" ]] || [[ "${DISTRO}" == "sles-15" ]]; then
        printf -- "\n# Legacy eBPF probe"
        printf -- "\nRun sudo falco -o engine.kind=ebpf"
        printf -- "\n# Modern eBPF probe"
        printf -- "\nRun sudo falco -o engine.kind=modern_ebpf"
    fi
    printf -- '\nRun falco --help to see all available options to run falco.'
    printf -- '\nSee https://github.com/falcosecurity/event-generator for information on testing falco.'
    printf -- '\nFor more information on Falco please visit https://falco.org/docs/ \n\n'
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare

case "$DISTRO" in

"rhel-8.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
    sudo yum install -y gcc-toolset-13-gcc gcc-toolset-13-gcc-c++ git make cmake autoconf automake pkg-config patch libtool elfutils-libelf-devel diffutils which createrepo libarchive wget curl rpm-build kmod kernel-devel-$(uname -r) perl-IPC-Cmd perl-bignum perl-core clang llvm bpftool |& tee -a "${LOG_FILE}"
    source /opt/rh/gcc-toolset-13/enable
    installCMakeFromSource |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"rhel-9.4" | "rhel-9.6")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
    sudo yum install --allowerasing -y openssl-devel libstdc++-static libstdc++-devel c-ares-devel gcc gcc-c++ git make cmake autoconf automake pkg-config patch perl-IPC-Cmd perl-bignum perl-core perl-FindBin libtool elfutils-libelf-devel diffutils which createrepo libarchive wget curl rpm-build kmod kernel-devel-$(uname -r) clang llvm bpftool |& tee -a "${LOG_FILE}"
    installCMakeFromSource |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
    
"sles-15.6")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
    SLES_KERNEL_VERSION=$(uname -r | sed 's/-default//')
    SLES_KERNEL_PKG_VERSION=$(sudo zypper se -s 'kernel-default-devel' | grep ${SLES_KERNEL_VERSION} | head -n 1 | cut -d "|" -f 4 - | tr -d '[:space:]')
    sudo zypper install -y gcc gcc-c++ gcc13 gcc13-c++ git-core cmake patch which automake autoconf libtool libelf-devel gawk tar curl vim wget pkg-config glibc-devel-static "kernel-default-devel=${SLES_KERNEL_PKG_VERSION}" kmod clang17 llvm17 bpftool |& tee -a "${LOG_FILE}"
    sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-13 50 |& tee -a "${LOG_FILE}"
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-13 50 |& tee -a "${LOG_FILE}"
    export CC=$(which gcc)
    export CXX=$(which g++)
    installCMakeFromSource |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"ubuntu-22.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
    sudo apt-get update
    sudo apt-get install -y git cmake libssl-dev build-essential pkg-config autoconf wget curl patch libssl-dev libelf-dev gcc rpm linux-headers-$(uname -r) linux-tools-$(uname -r) kmod clang llvm |& tee -a "${LOG_FILE}"
    installCMakeFromSource |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"ubuntu-24.04" | "ubuntu-25.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
    sudo apt-get update
    sudo apt-get install -y git cmake build-essential pkg-config autoconf wget curl patch libtool libelf-dev gcc gcc-13 g++-13 rpm linux-headers-$(uname -r) linux-tools-$(uname -r) kmod clang llvm |& tee -a "${LOG_FILE}"
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-13 100 --slave /usr/bin/g++ g++ /usr/bin/g++-13
    export CC=$(which gcc)
    export CXX=$(which g++)
    installCMakeFromSource |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
    
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

printSummary |& tee -a "$LOG_FILE"
