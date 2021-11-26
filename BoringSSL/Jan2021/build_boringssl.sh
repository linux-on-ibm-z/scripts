#!/bin/bash
# © Copyright IBM Corporation 2021
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/BoringSSL/Jan2021/build_boringssl.sh
# Execute build script: bash build_boringssl.sh   (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="boringssl"
CURDIR="$(pwd)"
GIT_BRANCH="patch-s390x-Jan2021"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/BoringSSL/Jan2021/patch"
TESTS="false"
FORCE="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${GIT_BRANCH}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
    mkdir -p "$CURDIR/logs/"
fi

source "/etc/os-release"

function cleanup() {
   printf -- 'Cleaning up\n'
   cd "${CURDIR}"
   rm -f gcc-7.4.0.tar.xz
   rm -f cmake-3.7.2.tar.gz
   rm -f go1.15.7.linux-s390x.tar.gz
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

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

	if [ "${VERSION_ID}" == "7.8" ] || [ "${VERSION_ID}" == "7.9" ]; then
		cd "${CURDIR}"
		wget https://cmake.org/files/v3.7/cmake-3.7.2.tar.gz
		tar xzf cmake-3.7.2.tar.gz
		cd cmake-3.7.2
		./configure --prefix=/usr/local
		make && sudo make install
	fi
	# Download and Install Go v1.12.5
	  cd $CURDIR
    wget https://storage.googleapis.com/golang/go1.15.7.linux-s390x.tar.gz
    tar -xzf go1.15.7.linux-s390x.tar.gz
    export PATH=$CURDIR/go/bin:$PATH
    export GOROOT=$CURDIR/go
  	export GOPATH=$CURDIR/go/bin
    go version
	
    # Download Boringssl
    cd $CURDIR
    git clone https://github.com/linux-on-ibm-z/boringssl
    cd boringssl
    git checkout patch-s390x-Jan2021

if [[ "${DISTRO}" == "ubuntu-21.10" ]]  ;then 
	curl -o gcc_patch.diff $PATCH_URL/gcc_patch.diff 
	git apply gcc_patch.diff
fi
	
    # Build Boringssl
    cd $CURDIR/boringssl
    mkdir -p build
    cd build/
    cmake ..
    make
    printf -- "Build for Boringssl is successful\n" 

    # Run Test
    runTest

}

function runTest() {

    if [[ "$TESTS" == "true" ]]; then
        printf -- 'Running tests \n\n' |& tee -a "$LOG_FILE"
        cd $CURDIR/boringssl
        go run util/all_tests.go |& tee $CURDIR/all_tests.log
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
    printf -- "Request details : PACKAGE NAME= %s , GIT_BRANCH= %s \n" "$PACKAGE_NAME" "$GIT_BRANCH" |& tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
    echo
    echo "Usage: "
    echo "bash build_boringssl.sh  [-d debug] [-y install-without-confirmation] [-t install and run tests]"
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

logDetails
prepare # Check Prerequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"ubuntu-18.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$GIT_BRANCH" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y build-essential wget make tar git cmake gcc-7 g++-7 |& tee -a "$LOG_FILE"
      configureAndInstall |& tee -a "$LOG_FILE"
      ;;
"ubuntu-20.04" | "ubuntu-21.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$GIT_BRANCH" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y wget tar make gcc g++ cmake git |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
      ;;
"rhel-7.8" | "rhel-7.9")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$GIT_BRANCH" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo subscription-manager repos --enable=rhel-7-server-for-system-z-devtools-rpms
    sudo yum install -y wget tar make gcc gcc-c++ bzip2 zlib zlib-devel git devtoolset-7|& tee -a "$LOG_FILE"
    source /opt/rh/devtoolset-7/enable
	  configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-8.2")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$GIT_BRANCH" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y wget tar make gcc gcc-c++ bzip2 zlib zlib-devel git xz diffutils cmake |& tee -a "$LOG_FILE"
	  configureAndInstall |& tee -a "$LOG_FILE"
	  ;;
"sles-12.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$GIT_BRANCH" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y wget git tar cmake zlib-devel gcc7 gcc7-c++ |& tee -a "$LOG_FILE"
	  sudo ln -sf /usr/bin/gcc-7 /usr/bin/gcc
    sudo ln -sf /usr/bin/g++-7 /usr/bin/g++
    sudo ln -sf /usr/bin/gcc /usr/bin/cc
    sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-15.2")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$GIT_BRANCH" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y wget git tar gzip cmake zlib-devel gcc gcc-c++ |& tee -a "$LOG_FILE"
	  sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac
