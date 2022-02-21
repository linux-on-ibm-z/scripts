#!/bin/bash
# © Copyright IBM Corporation 2022.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Sysdig/0.28.0/build_sysdig.sh
# Execute build script: bash build_sysdig.sh    (provide -h for help)
set -e -o pipefail
PACKAGE_NAME="sysdig"
PACKAGE_VERSION="0.28.0"
export SOURCE_ROOT="$(pwd)"
TEST_USER="$(whoami)"
FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
SLES_KERNEL_VERSION=$(uname -r | sed 's/-default//g')
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
    printf -- '\nCleaned up the artifacts\n'
}
function configureAndInstall() {
    printf -- '\nConfiguration and Installation started \n'
    
    
#Installing dependencies
    printf -- 'User responded with Yes. \n'
    printf -- 'Building dependencies\n'
    cd "${SOURCE_ROOT}"
    if [[ "${ID}" == "rhel" ]]; then
       if [[ "${VERSION_ID}" == "7.8" ]] || [[ "${VERSION_ID}" == "7.9" ]]; then
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
	
	if [[ "$DISTRO" = "sles-12.5"  ]]; then
        printf -- 'Building Protobuf\n'
        cd $SOURCE_ROOT
        sudo zypper install -y autoconf automake bzip2 gawk git gzip libtool make tar wget zlib-devel
		cd $SOURCE_ROOT
		git clone https://github.com/protocolbuffers/protobuf.git
		cd protobuf
		git checkout v3.13.0
		git submodule update --init --recursive
		./autogen.sh
		./configure
		make
		sudo make install
		sudo ldconfig
        protoc --version
        printf -- 'cmake installed successfully\n'
       fi
	
    printf -- '\nDownloading Sysdig source. \n'
    cd "${SOURCE_ROOT}"
    git clone https://github.com/draios/sysdig.git
    cd sysdig
    git checkout "$PACKAGE_VERSION"
    mkdir build
    cd $SOURCE_ROOT/sysdig/build
    printf -- '\nStarting Sysdig build. \n'
    if  [[  "$DISTRO"  =  "ubuntu-20.04"  ]] || [[  "$DISTRO"  =  "ubuntu-21.10"  ]]; then
      cmake -DUSE_BUNDLED_PROTOBUF=Off -DPROTOBUF_PREFIX=/usr/lib/s390x-linux-gnu  \
        -DUSE_BUNDLED_GRPC=Off -DGRPC_PREFIX=/usr/lib/s390x-linux-gnu \
        .. -DSYSDIG_VERSION=$PACKAGE_VERSION
    else
      cmake .. -DSYSDIG_VERSION=$PACKAGE_VERSION
    fi
    cd $SOURCE_ROOT/sysdig/build/falcosecurity-libs-repo/falcosecurity-libs-prefix/src/falcosecurity-libs/cmake/modules
    sed -i 's+http://download.sysdig.com/dependencies/protobuf-cpp-3.5.0.tar.gz+https://github.com/protocolbuffers/protobuf/releases/download/v3.13.0/protobuf-cpp-3.13.0.tar.gz+g' protobuf.cmake
    sed -i 's/e4ba8284a407712168593e79e6555eb2/6425d7466db2efe5a80de1e38899f317/g' protobuf.cmake
    sed -i 's/PATCH_COMMAND wget http/#PATCH_COMMAND wget http/g' protobuf.cmake
    make
    sudo make install
    printf -- '\nSysdig build completed successfully. \n'
    
    printf -- '\nInserting Sysdig kernel module. \n'
    sudo rmmod scap || true
    cd $SOURCE_ROOT/sysdig/build/driver
	sudo insmod scap.ko
    printf -- '\nInserted Sysdig kernel module successfully. \n'
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
    echo "  bash build_sysdig.sh  [-d debug] [-y install-without-confirmation]"
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
    esac
done
function printSummary() {
    printf -- '\n********************************************************************************************************\n'
    printf -- "\n* Getting Started * \n"
    printf -- '\nRun sysdig --help to see all available options to run sysdig\n'
    printf -- "\nRun sysdig: \n"
    printf -- "    sysdig --version \n\n"
    printf -- "    sudo /usr/local/bin/sysdig \n\n"
    printf -- '\nFor more information on sysdig, please visit https://docs.sysdig.com/?lang=en \n\n'
    printf -- '**********************************************************************************************************\n'
}
logDetails
prepare
DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-18.04" | "ubuntu-20.04" | "ubuntu-21.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
    sudo apt-get update
    sudo apt-get install -y git cmake build-essential pkg-config autoconf \
       wget curl patch libtool libelf-dev linux-headers-$(uname -r) kmod
    
    if  [[  "$DISTRO"  =  "ubuntu-20.04"  ]] || [[  "$DISTRO"  =  "ubuntu-21.10"  ]]; then
      sudo apt install -y libgrpc++-dev protobuf-compiler-grpc
    fi
    configureAndInstall | tee -a "$LOG_FILE"
    ;;
"rhel-7.8" | "rhel-7.9")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
    sudo yum install -y devtoolset-7 devtoolset-7-elfutils-libelf-devel cmake automake curl \
       glibc-static libcurl-devel git pkgconfig wget patch kernel-devel-$(uname -r) kmod
    source /opt/rh/devtoolset-7/enable
    configureAndInstall | tee -a "$LOG_FILE"
    ;;
    
"rhel-8.2" | "rhel-8.4" | "rhel-8.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
    sudo yum install -y gcc gcc-c++ git make cmake autoconf automake pkg-config libtool wget patch \
        curl elfutils-libelf-devel kernel-devel-$(uname -r) glibc-static libstdc++-static kmod libarchive
    configureAndInstall | tee -a "$LOG_FILE"
    ;;
"sles-12.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
    sudo zypper install -y gcc7 gcc7-c++ git cmake automake autoconf libtool zlib-devel wget pkg-config \
        curl patch glibc-devel-static libelf-devel "kernel-default-devel=${SLES_KERNEL_VERSION}" kmod
    
    sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-7 40
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-7 40
    sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-7 40
    sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-7 40
    configureAndInstall | tee -a "$LOG_FILE"
    ;;
    
 "sles-15.3")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
    sudo zypper install -y gcc gcc-c++ git cmake patch automake autoconf libtool wget pkg-config \
       curl glibc-devel-static libelf-devel "kernel-default-devel=${SLES_KERNEL_VERSION}" kmod
    configureAndInstall | tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" | tee -a "$LOG_FILE"
    exit 1
    ;;
esac
printSummary | tee -a "$LOG_FILE"
