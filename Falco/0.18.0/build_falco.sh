#!/bin/bash
# © Copyright IBM Corporation 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Falco/0.18.0/build_falco.sh
# Execute build script: bash build_falco.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="falco"
PACKAGE_VERSION="0.18.0"

export SOURCE_ROOT="$(pwd)"

PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Falco/0.18.0/patch/"
TEST_USER="$(whoami)"
FORCE="false"
FORCE_LUAJIT="false"
TESTS="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
    mkdir -p "$SOURCE_ROOT/logs/"
fi

# Need handling for RHEL 6.10 as it doesn't have os-release file
if [ -f "/etc/os-release" ]; then
    source "/etc/os-release"
else
    cat /etc/redhat-release >>"$LOG_FILE"
    export ID="rhel"
    export VERSION_ID="6.x"
    export PRETTY_NAME="Red Hat Enterprise Linux 6.x"
fi

function buildOptionLuaOrLuaJIT() {
    if [[ "$FORCE_LUAJIT" == "true" ]]; then
	    buildOption="withLuaJIT"
    else
        printf -- '\n Falco 0.18.0 can be built with LuaJIT and Lua \n'
        printf -- '\n Enter your choice: \n 1 for LuaJIT \n 2 for Lua \n'
	while true; do
            read -p "Your choice: " choice
 
            case $choice in
            1)
                buildOption="withLuaJIT" 
                break
                ;;
            2)
                buildOption="withLua"
                break
                ;;
            *)
                echo "Please provide Correct input to proceed."
                ;;
            esac
        done
    fi
}

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
    #only for rhel
    if [[ "${ID}" == "rhel" ]]; then
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
	
	if [[ "${buildOption}" == "withLua" ]]; then
	  printf -- 'Building lua\n'
          cd $SOURCE_ROOT
          wget http://www.lua.org/ftp/lua-5.1.tar.gz
          tar zxf lua-5.1.tar.gz
          cd lua-5.1
          make linux
          make install
          cp /usr/local/bin/lua* /usr/bin/
          lua -v
          printf -- 'lua installed successfully\n'
	fi
    fi


    cd "${SOURCE_ROOT}"

    # Download and configure sysdig
    printf -- '\nDownloading sysdig. \n'
    cd $SOURCE_ROOT
    #fetch protobuf patch. This is later used in make process
    curl -o protobuf-3.5.0.patch $PATCH_URL/protobuf-3.5.0.patch
    git clone https://github.com/draios/sysdig.git
    cd sysdig
    git checkout falco/0.18.0
    #Apply the patch
    curl -o scap_fds.c.patch $PATCH_URL/scap_fds.c.patch
    patch -l $SOURCE_ROOT/sysdig/userspace/libscap/scap_fds.c scap_fds.c.patch

    printf -- '\nSysdig configuration is complete. \n'

    printf -- '\nDownloading falco. \n'
    cd $SOURCE_ROOT
    git clone https://github.com/falcosecurity/falco.git
    cd falco
    git checkout 0.18.0
    if [[ "${buildOption}" == "withLuaJIT" ]]; then
	    curl -o falco.patch $PATCH_URL/falco.patch
    else
	    curl -o falco.patch $PATCH_URL/falco_for_lua.patch
    fi

    git apply falco.patch
    
    curl -o lauxlib.h.patch $PATCH_URL/lauxlib.h.patch
    
    if [[ "${ID}" == "rhel" ]]; then
        curl -o CMakeLists.txt.patch $PATCH_URL/CMakeLists.txt.patch
        patch -l CMakeLists.txt CMakeLists.txt.patch
    fi
    
    if [[ "${DISTRO}" == "ubuntu-19.10" ]]; then
	    if [[ "${buildOption}" == "withLuaJIT" ]]; then
		    curl -o CMakeLists_txt_grpc.patch $PATCH_URL/CMakeLists_txt_grpc.patch
            else
                    curl -o CMakeLists_txt_grpc.patch $PATCH_URL/CMakeLists_txt_grpc_for_lua.patch
	    fi

      patch -l CMakeLists.txt CMakeLists_txt_grpc.patch
      
      #Download the grpc patch
      curl -o grpc.patch $PATCH_URL/grpc.patch
    fi

    printf -- '\nStarting falco build. \n'
    mkdir -p $SOURCE_ROOT/falco/build/release 
    cd $SOURCE_ROOT/falco/build/release 
    if [[ "${buildOption}" == "withLuaJIT" ]]; then
	    cmake -DFALCO_VERSION=0.18.0 -DCMAKE_VERBOSE_MAKEFILE=On ../../
    else
	    cmake -DUSE_BUNDLED_LUAJIT=false -DFALCO_VERSION=0.18.0 -DCMAKE_VERBOSE_MAKEFILE=On ../../
    fi	    

    make
    make package
    sudo make install
    printf -- '\nFalco build completed successfully. \n'

    printf -- '\nInserting Falco kernel module. \n'
    sudo rmmod falco_probe || true
    cd $SOURCE_ROOT/falco/build/release 
    sudo insmod driver/falco-probe.ko
    printf -- '\nInserted falco kernel module successfully. \n'
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
    echo "  install.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests]"
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

while getopts "h?dbyt" opt; do
    case "$opt" in
    h | \?)
        printHelp
        exit 0
        ;;
    d)
        set -x
        ;;
    b)
        FORCE_LUAJIT="true"
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
    printf -- '\nFor more information on falco please visit https://falco.org/docs/ \n\n'
    printf -- '**********************************************************************************************************\n'
}

logDetails
buildOptionLuaOrLuaJIT
prepare

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04" | "ubuntu-19.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"


    sudo apt-get update
    sudo apt-get install -y autoconf automake build-essential cmake curl elfutils git libelf-dev libssl-dev libtool linux-headers-$(uname -r) lua5.1 lua5.1-dev patch pkg-config rpm sudo wget
    configureAndInstall | tee -a "$LOG_FILE"
    ;;

"rhel-7.5" | "rhel-7.6" | "rhel-7.7" | "rhel-8.0")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
    sudo yum install -y autoconf automake c-ares curl elfutils-libelf elfutils-libelf-devel gcc gcc-c++ git glibc glibc-devel libcurl-devel libstdc++ libstdc++-devel libtool libyaml-devel make patch pkgconfig readline-devel rpm-build sudo vim wget zlib-devel kernel-$(uname -r) kernel-devel-$(uname -r) kernel-headers-$(uname -r)
    configureAndInstall | tee -a "$LOG_FILE"

    ;;

*)
    printf -- "%s not supported \n" "$DISTRO" | tee -a "$LOG_FILE"
    exit 1
    ;;
esac

printSummary | tee -a "$LOG_FILE"
