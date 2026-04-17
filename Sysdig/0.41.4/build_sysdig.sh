#!/bin/bash
# © Copyright IBM Corporation 2026.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Sysdig/0.41.4/build_sysdig.sh
# Execute build script: bash build_sysdig.sh    (provide -h for help)
set -e -o pipefail
PACKAGE_NAME="sysdig"
PACKAGE_VERSION="0.41.4"
PLUGINS_VERSION="0.6.0" #http://github.com/draios/sysdig/blob/0.41.4/cmake/modules/container_plugin.cmake#L20
export SOURCE_ROOT="$(pwd)"
TEST_USER="$(whoami)"
FORCE="false"
TESTS="false"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Sysdig/$PACKAGE_VERSION/patch"

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
    sudo rm -rf $SOURCE_ROOT/go"$GO_VERSION".linux-s390x.tar.gz  $SOURCE_ROOT/container_plugin_cmake.patch
}

function configureAndInstall() {
    printf -- '\nConfiguration and Installation started \n'
    printf -- 'User responded with Yes. \n'
    printf -- 'Building dependencies\n'
    
    # Build container plugin
    buildContainerPlugin

    printf -- '\nDownloading Sysdig source. \n'
    cd "${SOURCE_ROOT}"
    git clone -b $PACKAGE_VERSION https://github.com/draios/sysdig.git
    cd sysdig

    wget -O $SOURCE_ROOT/container_plugin_cmake.patch $PATCH_URL/container_plugin_cmake.patch
    sed -i "s#SOURCE_ROOT_PATH#$SOURCE_ROOT#g" $SOURCE_ROOT/container_plugin_cmake.patch
    git apply $SOURCE_ROOT/container_plugin_cmake.patch

    mkdir build && cd build
    printf -- '\nStarting Sysdig build. \n'

    if [[ "$DISTRO" == "rhel-8.10" ]]; then
        cmake -DCREATE_TEST_TARGETS=ON -DUSE_BUNDLED_DEPS=ON -DBUILD_SYSDIG_MODERN_BPF=OFF -DSYSDIG_VERSION=$PACKAGE_VERSION ..
    elif [[ "$DISTRO" == "rhel-9.4" ]] || [[ "$DISTRO" == "rhel-9.6" ]] || [[ "$DISTRO" == "rhel-9.7" ]] || [[ "$DISTRO" == "rhel-10.0" ]]; then
        cmake -DCREATE_TEST_TARGETS=ON -DUSE_BUNDLED_DEPS=ON -DSYSDIG_VERSION=$PACKAGE_VERSION ..
    elif [[ "$DISTRO" == "sles-15.7" ]]; then
        cmake -DCMAKE_C_COMPILER=/usr/bin/gcc-14 -DCMAKE_CXX_COMPILER=/usr/bin/g++-14 -DCREATE_TEST_TARGETS=ON -DUSE_BUNDLED_DEPS=ON -DSYSDIG_VERSION=$PACKAGE_VERSION ..
    elif [[ "$DISTRO" == "ubuntu-22.04" ]] || [[ "$DISTRO" == "ubuntu-24.04" ]]; then
        cmake -DCREATE_TEST_TARGETS=ON -DUSE_BUNDLED_DEPS=ON -DSYSDIG_VERSION=$PACKAGE_VERSION ..
    else
        printf -- "%s not supported \n" "$DISTRO" | tee -a "$LOG_FILE"
        exit 1
    fi

    cd $SOURCE_ROOT/sysdig/build
    make
    sudo make install
    printf -- '\nSysdig build completed successfully. \n'

    # Run Tests
    runTest

    printf -- '\nInserting Sysdig kernel module. \n'
    sudo rmmod scap || true
    cd $SOURCE_ROOT/sysdig/build/driver
    sudo insmod scap.ko
    printf -- '\nInserted Sysdig kernel module successfully. \n'
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
function bpftoolInstall() {
    printf -- 'Installing bpftool\n' >"$LOG_FILE"
    cd "${SOURCE_ROOT}"
    git clone --recurse-submodules https://github.com/libbpf/bpftool.git
    cd bpftool && cd src
    make
    sudo make install
}

function buildContainerPlugin() {
    GO_VERSION="1.25.0"
    if [[ $(go version | awk '{print $3}' | sed 's/^go//') < "$GO_VERSION" ]]; then
        printf -- 'Installing Go\n'
        cd $SOURCE_ROOT
        wget -q https://go.dev/dl/go"${GO_VERSION}".linux-s390x.tar.gz
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
    fi
    printf -- '\nBuilding container plugin... \n'
    # Build container plugin
    cd $SOURCE_ROOT
    git clone --depth 1 -b plugins/container/v${PLUGINS_VERSION} https://github.com/falcosecurity/plugins.git
    cd plugins/plugins/container
    if [[ "${DISTRO}" == "sles-15.7" ]]; then
        make CC=/usr/bin/gcc-14 CXX=/usr/bin/g++-14 libcontainer.so
    else
        make libcontainer.so
    fi
    tar zcf $SOURCE_ROOT/container-${PLUGINS_VERSION}-linux-s390x.tar.gz libcontainer.so
}

function installCMakeFromSource() {
    if [[ $(cmake --version | head -n 1 | awk '{print $3}') < "3.28.0" ]]; then
        sudo apt-get remove --purge -y cmake || true
        sudo yum remove -y cmake || true

        printf -- '\nInstalling CMake (3.28.3) from source...\n'
        cd $SOURCE_ROOT
        wget -q https://cmake.org/files/v3.28/cmake-3.28.3.tar.gz
        tar -xf cmake-3.28.3.tar.gz
        cd cmake-3.28.3
        ./bootstrap
        make -j"$(nproc)"
        sudo make install
        hash -r
        cmake --version
        rm $SOURCE_ROOT/cmake-3.28.3.tar.gz
        printf -- '\nCMake 3.28.3 installed successfully.\n'
    fi
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
"rhel-8.10" | "rhel-9.4" | "rhel-9.6" | "rhel-9.7")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
    sudo mkdir -p /lib/modules/$(uname -r)
    version=$(sudo yum info kernel-devel | grep Version | awk 'NR==1{print $3}')
    release=$(sudo yum info kernel-devel | grep Release | awk 'NR==1{print $3}')
    echo $version-$release.s390x
    # Check if the symbolic link already exists
    if [ ! -L "/lib/modules/$(uname -r)/build" ]; then
        # If the symbolic link does not exist, create it
        sudo ln -s "/usr/src/kernels/$version-$release.s390x" "/lib/modules/$(uname -r)/build"
    else
        echo "Symbolic link already exists."
    fi
    sudo yum install -y wget tar patch gcc gcc-c++ git bpftool clang pkg-config elfutils-libelf-devel kernel-devel kmod llvm perl libstdc++-static |& tee -a "$LOG_FILE"
    installCMakeFromSource |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-10.0")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
    sudo mkdir -p /lib/modules/$(uname -r)
    version=$(sudo yum info kernel-devel | grep Version | awk 'NR==1{print $3}')
    release=$(sudo yum info kernel-devel | grep Release | awk 'NR==1{print $3}')
    echo $version-$release.s390x
     Check if the symbolic link already exists
    if [ ! -L "/lib/modules/$(uname -r)/build" ]; then
        # If the symbolic link does not exist, create it
        sudo ln -s "/usr/src/kernels/$version-$release.s390x" "/lib/modules/$(uname -r)/build"
    else
        echo "Symbolic link already exists."
    fi
    sudo yum install -y wget tar patch gcc gcc-c++ git bpftool clang cmake pkg-config elfutils-libelf-devel kernel-devel kmod llvm perl libstdc++-static |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-15.7")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

    # Install required dependencies
    sudo zypper install -y \
        curl wget tar patch git \
        gcc gcc-c++ gcc14 gcc14-c++ \
        zlib-devel libelf-devel pkg-config kmod \
        openssl-devel kernel-default-devel \
        cmake llvm clang bpftool |& tee -a "$LOG_FILE"

    # Configure GCC alternatives
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-7 70
    sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-7 70
    sudo update-alternatives --set gcc /usr/bin/gcc-7
    sudo update-alternatives --set g++ /usr/bin/g++-7

    # Verify compiler version
    gcc -v |& tee -a "$LOG_FILE"

    configureAndInstall | tee -a "$LOG_FILE"
    ;;
"ubuntu-22.04" | "ubuntu-24.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
    sudo apt-get update >/dev/null
    export DEBIAN_FRONTEND=noninteractive
    sudo apt update && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget tar patch git g++ gcc zlib1g clang llvm linux-headers-generic cmake libelf-dev pkg-config kmod libssl-dev |& tee -a "$LOG_FILE"

    sudo mkdir -p /lib/modules/$(uname -r)
    version=$(ls /usr/src/ | grep generic | tail -1)
    # Check if the symbolic link already exists
    if [ ! -L "/lib/modules/$(uname -r)/build" ]; then
        # If the symbolic link does not exist, create it
        sudo ln -s /usr/src/$version /lib/modules/$(uname -r)/build
    else
        echo "Symbolic link already exists."
    fi
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y  g++-11
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-11 11
    sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-11 11
    gcc -v

    if [[ "${DISTRO}" == "ubuntu-22.04" ]]; then
        installCMakeFromSource |& tee -a "$LOG_FILE"
    fi
    bpftoolInstall |& tee -a "$LOG_FILE" 
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" | tee -a "$LOG_FILE"
    exit 1
    ;;
esac
printSummary | tee -a "$LOG_FILE"

