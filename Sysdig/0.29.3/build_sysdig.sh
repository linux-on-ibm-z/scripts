#!/bin/bash
# © Copyright IBM Corporation 2022.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Sysdig/0.29.3/build_sysdig.sh
# Execute build script: bash build_sysdig.sh    (provide -h for help)
set -e -o pipefail
PACKAGE_NAME="sysdig"
PACKAGE_VERSION="0.29.3"
export SOURCE_ROOT="$(pwd)"
TEST_USER="$(whoami)"
FORCE="false"
TESTS="false"
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
    sudo rm -rf $SOURCE_ROOT/cmake-3.20.3  $SOURCE_ROOT/cmake-3.20.3.tar.gz  $SOURCE_ROOT/grpc $SOURCE_ROOT/openssl-1.1.1l  $SOURCE_ROOT/openssl-1.1.1l.tar.gz  $SOURCE_ROOT/protobuf
}
function configureAndInstall() {
    printf -- '\nConfiguration and Installation started \n'
    printf -- 'User responded with Yes. \n'
    printf -- 'Building dependencies\n'

    if [[ ${DISTRO} =~ rhel-7\.[8-9] ]] || [[ "$DISTRO" = "sles-12.5" ]]; then
        printf -- 'Building openssl v1.1.1l\n'
        cd $SOURCE_ROOT
        wget https://www.openssl.org/source/openssl-1.1.1l.tar.gz --no-check-certificate
        tar -xzf openssl-1.1.1l.tar.gz
        cd openssl-1.1.1l
        ./config --prefix=/usr/local --openssldir=/usr/local
        make
        sudo make install

        sudo mkdir -p /usr/local/etc/openssl
        sudo wget https://curl.se/ca/cacert.pem --no-check-certificate -P /usr/local/etc/openssl

        LD_LIBRARY_PATH=/usr/local/lib/:/usr/local/lib64/${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
        export LD_LIBRARY_PATH
        export SSL_CERT_FILE=/usr/local/etc/openssl/cacert.pem
        printf -- 'openssl installed successfully\n'

        printf -- 'Building cmake v3.20.3\n'
        cd $SOURCE_ROOT
        wget https://github.com/Kitware/CMake/releases/download/v3.20.3/cmake-3.20.3.tar.gz --no-check-certificate
        tar -xvzf cmake-3.20.3.tar.gz
        cd cmake-3.20.3
        ./bootstrap
        make
        sudo make install
        if [[ "$DISTRO" = "sles-12.5"  ]]; then
            sudo ln -s /usr/local/bin/cmake /usr/bin/cmake
        fi
        cmake --version
        printf -- 'cmake installed successfully\n'
    fi
	
	if [[ "${ID}" == "rhel" ]] || [[ "${ID}" == "sles" ]]; then
        printf -- 'Building Protobuf v3.17.3\n'
        cd $SOURCE_ROOT
        git clone https://github.com/protocolbuffers/protobuf.git
        cd protobuf
        git checkout v3.17.3
        git submodule update --init --recursive
        ./autogen.sh
        ./configure
        make -j$(nproc)
        sudo make install
        if [[ "${ID}" == "sles" ]]; then
            sudo ldconfig
        fi
        if [[ ${DISTRO} =~ rhel-8\.[4-6] ]]; then
            LD_LIBRARY_PATH=/usr/local/lib/:/usr/local/lib64/${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
            export LD_LIBRARY_PATH
        fi
        if [[ "${ID}" == "rhel" ]]; then
            sudo ln -s /usr/local/lib/libprotobuf.so.28 /usr/lib64/libprotobuf.so.28
        fi
        protoc --version
        printf -- 'Protobuf installed successfully\n'

        printf -- 'Building gRPC v1.44.0\n'
        cd $SOURCE_ROOT
        git clone --recurse-submodules -b v1.44.0 --depth 1 --shallow-submodules https://github.com/grpc/grpc
        cd grpc 
        mkdir build && cd build
        cmake -DgRPC_INSTALL=true -DgRPC_BUILD_TESTS=OFF \
	          -DgRPC_SSL_PROVIDER=OpenSSL -DgRPC_PROTOBUF_PROVIDER=package \
              -DCMAKE_INSTALL_PREFIX=/usr/local ..
        make -j$(nproc)
        sudo make install
        printf -- 'gRPC installed successfully\n'
    fi

    printf -- '\nDownloading Sysdig source. \n'
    cd "${SOURCE_ROOT}"
    git clone https://github.com/draios/sysdig.git
    cd sysdig
    git checkout "$PACKAGE_VERSION"
    mkdir build && cd build
    printf -- '\nStarting Sysdig build. \n'
    cmake -DUSE_BUNDLED_PROTOBUF=Off -DUSE_BUNDLED_GRPC=Off \
        -DCREATE_TEST_TARGETS=ON -DSYSDIG_VERSION=$PACKAGE_VERSION ..
    if [[ "$DISTRO" != "ubuntu-18.04"  ]]; then
    mv googletest-src googletest-src_old
    git clone https://github.com/google/googletest.git
    cd googletest
    git checkout release-1.12.0
    cd ..
    mv googletest googletest-src
    fi

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
function runTest() {
    set +e
    if [[ "$TESTS" == "true" ]]; then
    # Run tests
    #Check if directory exists
        if [ -d "$SOURCE_ROOT/sysdig" ]; then
            cd $SOURCE_ROOT/sysdig/build/
            make run-unit-test-libsinsp
        fi
    fi
    set -e
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
    echo "  bash build_sysdig.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests]"
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
    printf -- '\nRun sysdig --help to see all available options to run sysdig\n'
    printf -- "\nRun sysdig: \n"
    printf -- "    sysdig --version \n\n"
    printf -- "    sudo /usr/local/bin/sysdig \n\n"
    printf -- "    sudo /usr/local/bin/csysdig \n\n"
    printf -- '\nFor more information on sysdig, please visit https://docs.sysdig.com/?lang=en \n\n'
    printf -- '**********************************************************************************************************\n'
}
logDetails
prepare
DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-18.04" | "ubuntu-20.04" | "ubuntu-21.10" | "ubuntu-22.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
    sudo apt-get update >/dev/null
    sudo apt-get install -y git cmake build-essential pkg-config autoconf wget curl patch libtool libelf-dev linux-headers-$(uname -r) kmod libz-dev libssl-dev libcurl4-gnutls-dev libexpat1-dev gettext gcc libgrpc++-dev protobuf-compiler-grpc libprotobuf-dev |& tee -a "$LOG_FILE"
    configureAndInstall | tee -a "$LOG_FILE"
    ;;

"rhel-7.8" | "rhel-7.9")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
    sudo yum install -y devtoolset-7 devtoolset-7-elfutils-libelf-devel libtool automake curl glibc-static libcurl-devel rh-git227-git.s390x pkgconfig wget patch kernel-devel-$(uname -r) kmod |& tee -a "$LOG_FILE"
    #switch to GCC 7
    source /opt/rh/devtoolset-7/enable
    #Enable git 2.27
    source /opt/rh/rh-git227/enable
    configureAndInstall | tee -a "$LOG_FILE"
    ;;
    
"rhel-8.4" | "rhel-8.5" | "rhel-8.6")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
    sudo yum install -y gcc gcc-c++ git make cmake autoconf automake pkg-config libtool wget patch curl elfutils-libelf-devel kernel-devel-$(uname -r) glibc-static libstdc++-static kmod libarchive openssl-devel |& tee -a "$LOG_FILE"
    configureAndInstall | tee -a "$LOG_FILE"
    ;;

"sles-12.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
    sudo zypper install -y gcc7 gcc7-c++ git make automake autoconf libtool zlib-devel wget pkg-config curl patch glibc-devel-static libelf-devel "kernel-default-devel=${SLES_KERNEL_VERSION}" kmod libexpat-devel tcl gettext-tools libcurl-devel tar |& tee -a "$LOG_FILE"
    sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-7 40
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-7 40
    sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-7 40
    sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-7 40
    configureAndInstall | tee -a "$LOG_FILE"
    ;;
    
 "sles-15.3")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
    sudo zypper install -y gcc gcc-c++ git cmake patch automake autoconf libtool wget pkg-config curl glibc-devel-static libelf-devel "kernel-default-devel=${SLES_KERNEL_VERSION}" kmod libexpat-devel tcl-devel gettext-tools tar libopenssl-devel libcurl-devel |& tee -a "$LOG_FILE"
    configureAndInstall | tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" | tee -a "$LOG_FILE"
    exit 1
    ;;
esac
printSummary | tee -a "$LOG_FILE"
