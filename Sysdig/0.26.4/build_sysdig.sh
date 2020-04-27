#!/bin/bash
# © Copyright IBM Corporation 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Sysdig/0.26.4/build_sysdig.sh
# Execute build script: bash build_sysdig.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="sysdig"
PACKAGE_VERSION="0.26.4"

export SOURCE_ROOT="$(pwd)"

PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Sysdig/0.26.4/patch"

TEST_USER="$(whoami)"
FORCE="false"
TESTS="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
    mkdir -p "$SOURCE_ROOT/logs/"
fi

source "/etc/os-release"

function prepare() {

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
            *) echo "Please provide Correct input to proceed." ;;
            esac
        done
    fi
}

function cleanup() {

    rm -rfv "$SOURCE_ROOT"/*.patch
    printf -- '\nCleaned up the artifacts\n'
}

function configureAndInstall() {
    printf -- '\nConfiguration and Installation started \n'

    #Installing dependencies
    printf -- 'User responded with Yes. \n'

    cd "${SOURCE_ROOT}"
    curl -o protobuf-3.5.0.patch $PATCH_URL/protobuf-3.5.0.patch
    curl -SLO $PATCH_URL/cmake.patch
    curl -SLO $PATCH_URL/grpc.patch
    git clone https://github.com/draios/sysdig.git
    cd sysdig
    git checkout "$PACKAGE_VERSION"
    
    if [[ $ID == *"ubuntu"* ]]; then
        if [[ $VERSION_ID == *"16.04"* ]]; then
                sudo mkdir -p /lib/modules/$(uname -r)
                version=4.4.0-142
                echo linux-headers-$version-generic
                sudo ln -s /usr/src/linux-headers-$version-generic /lib/modules/$(uname -r)/build
        elif [[ $VERSION_ID == *"18.04"* ]]; then
                sudo mkdir -p /lib/modules/$(uname -r)
                version=4.15.0-52
                echo linux-headers-$version-generic
                sudo ln -s /usr/src/linux-headers-$version-generic /lib/modules/$(uname -r)/build
        else
                sudo mkdir -p /lib/modules/$(uname -r)
                version=5.3.0-29
                echo linux-headers-$version-generic
                sudo ln -s /usr/src/linux-headers-$version-generic /lib/modules/$(uname -r)/build
        fi
    fi
    
    if [[ $ID == *"sles"* ]]; then
            sudo mkdir -p /lib/modules/$(uname -r)
            trim=$(sudo zypper info kernel-default-devel | grep Version | cut -d ':' -f 2-)
            version=$(echo $trim | sed 's/..$//')
            echo linux-$version-obj
            sudo ln -s /usr/src/linux-$version-obj/s390x/default /lib/modules/$(uname -r)/build
    fi
    
    patch -p1 < $SOURCE_ROOT/cmake.patch
    mkdir build
    cd build
    if [[ $ID == *"rhel"* ]]; then
            sudo mkdir -p /lib/modules/$(uname -r)
            version=$(sudo yum info kernel-devel | grep Version | awk '{print $3}')
            release=$(sudo yum info kernel-devel | grep Release | awk '{print $3}')
            echo $version-$release.s390x
            sudo ln -s /usr/src/kernels/$version-$release.s390x /lib/modules/$(uname -r)/build
    fi
    
    
    cmake -DUSE_BUNDLED_LUAJIT=OFF ..
    make
    sudo make install
    
    cd driver
    sudo insmod sysdig-probe.ko
    
    
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
    echo "  install.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests]"
    echo
}

function runTest() {
    set +e

    #if [[ "$TESTS" == "true" ]]; then
        # Place holder for future tests
    #fi

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
            printf -- "%s is detected with version %s .\n" "$PACKAGE_NAME" "$PACKAGE_VERSION" | tee -a "$LOG_FILE"
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
    printf -- '\nRun sysdig --help to see all available options to run sysdig'
    printf -- '\nFor more information on sysdig, please visit https://docs.sysdig.com/?lang=en \n\n'
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04" | "ubuntu-19.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
    sudo apt-get update
    sudo apt-get install -y wget tar gcc git cmake g++ lua5.1 lua5.1-dev linux-headers-$(uname -r) patch libelf-dev
    configureAndInstall | tee -a "$LOG_FILE"
    ;;

"rhel-7.5" | "rhel-7.6" | "rhel-7.7")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
    sudo yum install -y wget git tar curl gcc cmake gcc-c++ make lua-devel.s390x kernel-devel patch elfutils-libelf-devel.s390x elfutils-libelf-devel-static.s390x glibc-static libstdc++-static patch
    configureAndInstall | tee -a "$LOG_FILE"
    ;;

"sles-12.4" | "sles-15.1")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
    sudo zypper install -y gawk wget tar git-core gcc which cmake make gcc-c++ lua51 lua51-devel kernel-default-devel patch libelf-devel glibc-devel-static
    configureAndInstall | tee -a "$LOG_FILE"
    ;;

*)
    printf -- "%s not supported \n" "$DISTRO" | tee -a "$LOG_FILE"
    exit 1
    ;;
esac

printSummary | tee -a "$LOG_FILE"
