#!/bin/bash
# © Copyright IBM Corporation 2021, 2022                                                                                                                                                                                                                                                                                                                                                                                                                                           .
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Falco/0.30.0/build_falco.sh
# Execute build script: bash build_falco.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="falco"
PACKAGE_VERSION="0.30.0"

export SOURCE_ROOT="$(pwd)"

PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Falco/${PACKAGE_VERSION}/patch/"

TEST_USER="$(whoami)"
FORCE="false"
FORCE_LUAJIT="false"
TESTS="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
SLES_KERNEL_VERSION=$(uname -r | sed 's/-default//g')

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

    if [[ "${ID}" == "rhel" ]] || [[ "${ID}" == "sles" ]]; then
        rm -rf "${SOURCE_ROOT}/cmake-3.7.2.tar.gz"
    fi
    if [[ "${DISTRO}" == "sles-12.5" ]]; then
        sudo mv "/usr/src/linux-$SLES_KERNEL_VERSION/Makefile.back" "/usr/src/linux-$SLES_KERNEL_VERSION/Makefile"
    fi

    printf -- '\nCleaned up the artifacts\n'
}

function configureAndInstall() {
    printf -- '\nConfiguration and Installation started \n'

    #Installing dependencies
    printf -- 'User responded with Yes. \n'
    printf -- 'Building dependencies\n'

    cd "${SOURCE_ROOT}"
    if [[ "${ID}" == "rhel" ]] || [[ "${ID}" == "sles" ]]; then
       if [[ "${VERSION_ID}" == "7.8" ]] || [[ "${VERSION_ID}" == "7.9" ]] || [[ "${VERSION_ID}" == "12.5" ]]; then
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
    mkdir -p $SOURCE_ROOT/falco/build
    cd $SOURCE_ROOT/falco/build
    if [[ "${DISTRO}" == "sles-12.5" ]]; then
        sudo cp "/usr/src/linux-$SLES_KERNEL_VERSION/Makefile" "/usr/src/linux-$SLES_KERNEL_VERSION/Makefile.back"
        sudo sed -i 's/-fdump-ipa-clones//g' /usr/src/linux-"$SLES_KERNEL_VERSION"/Makefile
    fi

    CMAKE_FLAGS="-DFALCO_ETC_DIR=/etc/falco -DUSE_BUNDLED_OPENSSL=On -DUSE_BUNDLED_DEPS=On -DCMAKE_BUILD_TYPE=Release"

    cmake $CMAKE_FLAGS ../

    #patch for ub21.10
    if [[ "${DISTRO}" == "ubuntu-21.10" ]]; then
        cd $SOURCE_ROOT/falco/cmake/modules
        sed -i 's/v2.12.1/v2.13.7/g' DownloadCatch.cmake
        sed -i 's/e5635c082282ea518a8dd7ee89796c8026af8ea9068cd7402fb1615deacd91c3/3cdb4138a072e4c0290034fe22d9f0a80d3bcfb8d7a8a5c49ad75d3a5da24fae/g' DownloadCatch.cmake
        cd $SOURCE_ROOT/falco/build/falcosecurity-libs-repo/falcosecurity-libs-prefix/src/falcosecurity-libs/cmake/modules
        sed -i 's/v1.38.1/v1.42.0/g' grpc.cmake
    fi
    
    cd $SOURCE_ROOT/falco/build/falcosecurity-libs-repo/falcosecurity-libs-prefix/src/falcosecurity-libs/cmake/modules
    sed -i 's/v1.2.1/v2.0.0.1/g' b64.cmake
    sed -i 's/d620e7caf3ed5f9c28d727fa799918ad3ef69c80975905646bb549a6019cdcbd/ce8e578a953a591bd4a6f157eec310b9a4c2e6f10ade2fdda6ae6bafaf798b98/g' b64.cmake
    sed -i 's+http://download.sysdig.com/dependencies/protobuf-cpp-3.5.0.tar.gz+https://github.com/protocolbuffers/protobuf/releases/download/v3.13.0/protobuf-cpp-3.13.0.tar.gz+g' protobuf.cmake
    sed -i 's/e4ba8284a407712168593e79e6555eb2/6425d7466db2efe5a80de1e38899f317/g' protobuf.cmake
    sed -i 's/PATCH_COMMAND wget http/#PATCH_COMMAND wget http/g' protobuf.cmake
    cd $SOURCE_ROOT/falco/build/
    make

    if [[ "${ID}" == "rhel" ]] || [[ "${ID}" == "ubuntu" ]]; then
        make package
    fi

    sudo make install
    printf -- '\nFalco build completed successfully. \n'

    printf -- '\nInserting Falco kernel module. \n'
    sudo rmmod falco || true

    cd $SOURCE_ROOT/falco/build
    sudo insmod driver/falco.ko
    printf -- '\nInserted Falco kernel module successfully. \n'

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
    echo "  build_falco.sh  [-d debug] [-y install-without-confirmation] [-t run-tests-after-build] "
    echo
}

function runTest() {
    set +e

    if [[ "$TESTS" == "true" ]]; then
        cd $SOURCE_ROOT/falco/build
        make tests
    fi

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
        if command -v "$PACKAGE_NAME" >/dev/null; then
            printf -- "%s is detected in the system. Skipping build and running tests .\n" "$PACKAGE_NAME" | tee -a "$LOG_FILE"
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
    printf -- '\nRun falco --help to see all available options to run falco'
    printf -- '\nFor more information on Falco please visit https://falco.org/docs/ \n\n'
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare

case "$DISTRO" in
"ubuntu-18.04" | "ubuntu-20.04" | "ubuntu-21.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
    sudo apt-get update
    sudo apt-get install -y git cmake build-essential libncurses-dev pkg-config autoconf libtool libelf-dev curl \
        rpm linux-headers-$(uname -r)

    configureAndInstall | tee -a "$LOG_FILE"
    ;;

"rhel-7.8" | "rhel-7.9")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

    sudo yum install -y git make autoconf automake pkgconfig patch ncurses-devel libtool glibc-static \
        libstdc++-static elfutils-libelf-devel rpm-build createrepo curl libcurl-devel wget devtoolset-7-gcc-c++ devtoolset-7-gcc kernel-devel-$(uname -r)

    source /opt/rh/devtoolset-7/enable

    configureAndInstall | tee -a "$LOG_FILE"
    ;;

"rhel-8.2" | "rhel-8.4" | "rhel-8.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

    sudo yum install -y gcc gcc-c++ git make cmake autoconf automake pkg-config patch ncurses-devel libtool \
        elfutils-libelf-devel diffutils which rpm-build createrepo libarchive kernel-devel-$(uname -r)

    configureAndInstall | tee -a "$LOG_FILE"
    ;;

"sles-12.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

    sudo zypper install -y gcc7 gcc7-c++ git-core cmake ncurses-devel libopenssl-devel \
        libcurl-devel protobuf-devel=2.6.1-7.3.16 patch which automake autoconf libtool libelf-devel \
        "kernel-default-devel=${SLES_KERNEL_VERSION}"
	
    sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-7 40
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-7 40
    sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-7 40
    sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-7 40

    configureAndInstall | tee -a "$LOG_FILE"
    ;;

"sles-15.3")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

    sudo zypper install -y gcc gcc-c++ git-core cmake libjq-devel ncurses-devel yaml-cpp-devel libopenssl-devel \
        libcurl-devel c-ares-devel protobuf-devel patch which automake autoconf libtool libelf-devel \
        "kernel-default-devel=${SLES_KERNEL_VERSION}"

    configureAndInstall | tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" | tee -a "$LOG_FILE"
    exit 1
    ;;
esac

printSummary | tee -a "$LOG_FILE"
