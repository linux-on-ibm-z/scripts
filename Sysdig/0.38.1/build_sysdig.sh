#!/bin/bash
# © Copyright IBM Corporation 2024.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Sysdig/0.38.1/build_sysdig.sh
# Execute build script: bash build_sysdig.sh    (provide -h for help)
set -e -o pipefail
PACKAGE_NAME="sysdig"
PACKAGE_VERSION="0.38.1"
export SOURCE_ROOT="$(pwd)"
TEST_USER="$(whoami)"
FORCE="false"
TESTS="false"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Sysdig/${PACKAGE_NAME}/patch/sysdig.patch"

source "/etc/os-release"
DISTRO="$ID-$VERSION_ID"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-${DISTRO}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR
#Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
    mkdir -p "$SOURCE_ROOT/logs/"
fi

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
    sudo rm -rf $SOURCE_ROOT/cmake-3.20.3  $SOURCE_ROOT/cmake-3.20.3.tar.gz  $SOURCE_ROOT/openssl-1.1.1l  $SOURCE_ROOT/openssl-1.1.1l.tar.gz
}

function configureAndInstall() {
    printf -- '\nConfiguration and Installation started \n'
    printf -- 'User responded with Yes. \n'
    printf -- 'Building dependencies\n'
    printf -- '\nDownloading Sysdig source. \n'
    cd "${SOURCE_ROOT}"
    git clone https://github.com/draios/sysdig.git
    cd sysdig
    git checkout "$PACKAGE_VERSION"
    mkdir build && cd build
    printf -- '\nStarting Sysdig build. \n'
    cmake -DCREATE_TEST_TARGETS=ON -DUSE_BUNDLED_DEPS=ON -DSYSDIG_VERSION=$PACKAGE_VERSION ..
    cd $SOURCE_ROOT/sysdig/build
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
            cd $SOURCE_ROOT/sysdig/build/falcosecurity-libs-repo/falcosecurity-libs-prefix/src/falcosecurity-libs
            printf -- "\nApplying patch for Failing Test cases\n"
            wget -O sysdig.patch $PATCH_URL
            patch -p1 < sysdig.patch
            cd $SOURCE_ROOT/sysdig/build/
            make run-unit-test-libsinsp
        fi
    fi
    set -e
}
function bpftoolInstall() {
    printf -- 'Installing bpftool\n' >"$LOG_FILE"
    cd "${SOURCE_ROOT}"
    if [[ $DISTRO == "ubuntu-20.04" ]]; then
        cd $SOURCE_ROOT
        sudo apt-get update 
        sudo apt install -y lsb-release wget software-properties-common gnupg
        wget https://apt.llvm.org/llvm.sh
        sed -i 's,add-apt-repository "${REPO_NAME}",add-apt-repository "${REPO_NAME}" -y,g' llvm.sh
        chmod +x llvm.sh
        sudo ./llvm.sh 14
        rm ./llvm.sh

        export CC=clang-14
        export CXX=clang++-14
        sudo ln -sf /usr/bin/clang-14 /usr/bin/clang
        sudo ln -sf /usr/bin/clang++-14 /usr/bin/clang++
        sudo update-alternatives --install /usr/bin/llvm-config llvm-config /usr/bin/llvm-config-14 200
        sudo update-alternatives --install /usr/bin/llvm-strip  llvm-strip  /usr/bin/llvm-strip-14 200 
    fi
    git clone --recurse-submodules https://github.com/libbpf/bpftool.git
    cd bpftool && cd src
    #Due to some features requiring the use of "skeletons" (feature-clang-bpf-co-re compilation option) require kernel 5.15 or more recent.
    if [[ $DISTRO == "ubuntu-20.04" ]]; then
        CLANG=Nope make
    else
        make
    fi
    sudo make install
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

case "$DISTRO" in
"rhel-8.8" | "rhel-8.10" | "rhel-9.2" | "rhel-9.4")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
    sudo mkdir -p /lib/modules/$(uname -r)
    version=$(sudo yum info kernel-devel | grep Version | awk 'NR==1{print $3}')
    release=$(sudo yum info kernel-devel | grep Release | awk 'NR==1{print $3}')
    echo $version-$release.s390x
    # Check if the symbolic link already exists
    if [ ! -e "/lib/modules/$(uname -r)/build" ]; then
        # If the symbolic link does not exist, create it
        sudo ln -s "/usr/src/kernels/$version-$release.s390x" "/lib/modules/$(uname -r)/build"
    else
        echo "Symbolic link already exists."
    fi
    sudo yum install -y wget tar patch gcc gcc-c++ git bpftool clang cmake pkg-config elfutils-libelf-devel kernel-devel kmod llvm perl |& tee -a "$LOG_FILE"
    configureAndInstall | tee -a "$LOG_FILE"
    ;;    
"ubuntu-20.04" | "ubuntu-22.04" | "ubuntu-24.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
    sudo apt-get update >/dev/null
    export DEBIAN_FRONTEND=noninteractive
    sudo apt update && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget tar patch git g++ gcc zlib1g  libelf-dev clang llvm linux-headers-generic cmake libelf-dev pkg-config kmod |& tee -a "$LOG_FILE"
    sudo mkdir -p /lib/modules/$(uname -r)
    version=$(ls /usr/src/ | grep generic | tail -1)
    sudo ln -s /usr/src/$version /lib/modules/$(uname -r)/build
    if [[ ${DISTRO} == ubuntu-24.04 ]]; then
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y  g++-11
        sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-11 11
        sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-11 11
        gcc -v
    fi
    bpftoolInstall | tee -a "$LOG_FILE"
    configureAndInstall | tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" | tee -a "$LOG_FILE"
    exit 1
    ;;
esac
printSummary | tee -a "$LOG_FILE"
