#!/usr/bin/env bash
# © Copyright IBM Corporation 2023.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/CockroachDB/23.1.2/build_crdb.sh
# Execute build script: bash build_crdb.sh    (provide -h for help)
set -e  -o pipefail
CURDIR="$(pwd)"
PACKAGE_NAME="CockroachDB"
PACKAGE_VERSION="23.1.2"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/CockroachDB/23.1.2/patch/crdb.patch"
FORCE="false"
TEST="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
trap cleanup 0 1 2 ERR
#Check if directory exsists
if [ ! -d "$CURDIR/logs" ]; then
        mkdir -p "$CURDIR/logs"
fi
source "/etc/os-release"
function checkPrequisites() {
    printf -- "Checking Prequisites\n"
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
function cleanup() {
    printf -- 'Cleaned up the artifacts\n' >>"$LOG_FILE"
    if [[ -f ${CURDIR}/v2.27.1.tar.gz ]]; then
        rm ${CURDIR}/v2.27.1.tar.gz
        sudo rm -r ${CURDIR}/git-2.27.1
    fi
    if [[ -f ${CURDIR}/cmake-3.23.3.tar.gz ]]; then
        rm ${CURDIR}/cmake-3.23.3.tar.gz
        sudo rm -r ${CURDIR}/cmake-3.23.3
    fi
    if [[ -f ${CURDIR}/resolv_wrapper-1.1.7.tar.gz ]]; then
        rm ${CURDIR}/resolv_wrapper-1.1.7.tar.gz
        sudo rm -r ${CURDIR}/resolv_wrapper-1.1.7
    fi
    if [[ -f ${CURDIR}/gcc-10.2.0.tar.gz ]]; then
        rm ${CURDIR}/gcc-10.2.0.tar.gz
    fi
}
function configureAndInstall() {
    printf -- 'Configuration and Installation started \n'
# Install GCC
    if [[ ${DISTRO} =~ rhel-7\.* ]] || [[ "${DISTRO}" == "ubuntu-23.10" ]] ; then
        printf -- 'Installing gcc...\n'
        cd ${CURDIR}
        ver=10.2.0
        wget https://ftp.gnu.org/gnu/gcc/gcc-${ver}/gcc-${ver}.tar.gz
        tar xzf gcc-${ver}.tar.gz
        cd gcc-${ver}
        ./contrib/download_prerequisites
        mkdir build-gcc
        cd build-gcc
        ../configure --enable-languages=c,c++ --disable-multilib
        make -j$(nproc)
        sudo make install
    fi
    if [[ ${DISTRO} =~ rhel-7\.* ]] ; then
        sudo ldconfig /usr/local/lib64 /usr/local/lib
        sudo mv /usr/bin/gcc /usr/bin/gcc-4.8.5
        sudo mv /usr/bin/g++ /usr/bin/g++-4.8.5
        sudo mv /usr/bin/c++ /usr/bin/c++-4.8.5
        sudo update-alternatives --install /usr/bin/cc cc /usr/local/bin/gcc 40
        sudo update-alternatives --install /usr/bin/gcc gcc /usr/local/bin/gcc 40
        sudo update-alternatives --install /usr/bin/g++ g++ /usr/local/bin/g++ 40
        sudo update-alternatives --install /usr/bin/c++ c++ /usr/local/bin/c++ 40
        export CC=/usr/local/bin/gcc
        export CXX=/usr/local/bin/g++
    fi

    # Install Git - v2.20+
    if [[ ${DISTRO} =~ rhel-7\.* ]]; then
        printf -- 'Installing git...\n'
        cd ${CURDIR}
        wget https://github.com/git/git/archive/refs/tags/v2.27.1.tar.gz
        tar -xzf v2.27.1.tar.gz
        cd git-2.27.1
        make configure
        ./configure --prefix=/usr
        make
        sudo make install
        fi
    git --version
# Install CMake - 3.23.3
    if [[ ${DISTRO} =~ rhel-7\.* || ${DISTRO} =~ ubuntu-20\.* ]]; then
        printf -- 'Installing CMake...\n'
        cd ${CURDIR}
        wget https://github.com/Kitware/CMake/releases/download/v3.23.3/cmake-3.23.3.tar.gz
        tar -xzf cmake-3.23.3.tar.gz
        cd cmake-3.23.3
        ./bootstrap
        make
        sudo make install
    fi
    cmake --version
# Install bazel
    cd ${CURDIR}
    if [[ ! -f ${CURDIR}/bazel/output/bazel ]]; then
            mkdir -p ${CURDIR}/bazel
            cd ${CURDIR}/bazel
            wget https://github.com/bazelbuild/bazel/releases/download/5.1.1/bazel-5.1.1-dist.zip
            unzip -q bazel-5.1.1-dist.zip
            chmod -R +w .
            curl -sSL https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Bazel/5.1.1/patch/bazel.patch | patch -p1
            bash ./compile.sh
    fi
    export PATH=$PATH:${CURDIR}/bazel/output/
    bazel --version
# Build and install resolv-wrapper lib (RHEL)
    if [[ "${ID}" == "rhel" ]]; then
        cd ${CURDIR}
        wget https://ftp.samba.org/pub/cwrap/resolv_wrapper-1.1.7.tar.gz
        tar zxf resolv_wrapper-1.1.7.tar.gz
        cd resolv_wrapper-1.1.7
        mkdir obj && cd obj
        cmake -DCMAKE_INSTALL_PREFIX=/usr ..
        make
        sudo make install
        ls -la /usr/lib64/libresolv*
    fi
# Download and configure CockroachDB
    printf -- 'Downloading CockroachDB source code. Please wait.\n'
    cd ${CURDIR}
    git clone https://github.com/cockroachdb/cockroach
    cd cockroach
    git checkout v$PACKAGE_VERSION
    git submodule update --init --recursive
# Applying patches
    printf -- 'Apply patches....\n'
    cd ${CURDIR}/cockroach
    wget -O ${CURDIR}/cockroachdb.patch $PATCH_URL
    git apply --reject --whitespace=fix ${CURDIR}/cockroachdb.patch
# Build CockroachDB
    printf -- 'Building CockroachDB.... \n'
    printf -- 'Build might take some time. Sit back and relax\n'
    cd ${CURDIR}/cockroach
    echo 'build --remote_cache=http://127.0.0.1:9867' > ~/.bazelrc
    echo 'build --config=dev
    build --config nolintonbuild' > .bazelrc.user
    echo "test --test_tmpdir=$CURDIR/cockroach/tmp" >> .bazelrc.user
    ./dev doctor
    ./dev build
    bazel build c-deps:libgeos --config force_build_cdeps
    sudo cp cockroach /usr/local/bin
    sudo mkdir -p /usr/local/lib/cockroach
    sudo cp _bazel/bin/c-deps/libgeos_foreign/lib/libgeos.so /usr/local/lib/cockroach/
    sudo cp _bazel/bin/c-deps/libgeos_foreign/lib/libgeos_c.so /usr/local/lib/cockroach/
    export PATH=${CURDIR}/cockroach:$PATH
    cockroach version
printf -- 'Successfully installed CockroachDB. \n'
#Run Test
        runTests
cleanup
}
function runTests() {
        set +e
        if [[ "$TESTS" == "true" ]]; then
                printf -- "TEST Flag is set, continue with running test \n"
                cd ${CURDIR}/cockroach
                #run all_tests target in pkg/BUILD.bazel
                ./dev test -v -- --test_timeout=3600
        fi
        set -e
}
function logDetails() {
    printf -- '**************************** SYSTEM DETAILS *************************************************************\n' >"$LOG_FILE"
if [ -f "/etc/os-release" ]; then
            cat "/etc/os-release" >>"$LOG_FILE"
    fi
cat /proc/version >>"$LOG_FILE"
    printf -- '*********************************************************************************************************\n' >>"$LOG_FILE"
printf -- "Detected %s \n" "$PRETTY_NAME"
    printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" |& tee -a "$LOG_FILE"
}
# Print the usage message
function printHelp() {
        echo
        echo "Usage: "
        echo "  bash build_crdb.sh [-y install-without-confirmation -t run-test-cases]"
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
function gettingStarted() {
        printf -- '\n********************************************************************************************************\n'
        printf -- "\n* Getting Started * \n"
        printf -- "\nAll relevant binaries are installed in /usr/local/bin. \n"
        printf -- "\nTo verify: \n"
        printf -- "  $ cockroach version\n"
        printf -- '\n\n**********************************************************************************************************\n'
}
###############################################################################################################
logDetails
DISTRO="$ID-$VERSION_ID"
checkPrequisites #Check Prequisites
case "$DISTRO" in
"ubuntu-20.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
    sudo apt-get update >/dev/null
    sudo apt-get install -y zip unzip autoconf automake wget make libssl-dev libncurses5-dev bison xz-utils patch g++ curl git python3 libresolv-wrapper libkeyutils-dev openjdk-11-jdk |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"ubuntu-22.04" | "ubuntu-23.04" | "ubuntu-23.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
    sudo apt-get update >/dev/null
    sudo apt-get install -y zip unzip autoconf automake wget make libssl-dev libncurses5-dev bison xz-utils patch g++ curl git python3 cmake netbase libresolv-wrapper libkeyutils-dev openjdk-11-jdk |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-7.8" | "rhel-7.9")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
        sudo yum install -y gcc gcc-c++ bzip2 git ncurses-devel make automake bison patch wget tar xz zip unzip java-11-openjdk-devel python3 zlib-devel openssl-devel gettext-devel diffutils keyutils-libs-devel |& tee -a "$LOG_FILE"
        export LD_LIBRARY_PATH=/usr/local/lib64:/usr/local/lib/:/usr/lib64:/usr/lib/:$LD_LIBRARY_PATH
        configureAndInstall |& tee -a "$LOG_FILE"
  ;;
"rhel-8.6" | "rhel-8.8")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
    sudo yum install -y gcc-c++ git ncurses-devel make cmake automake bison patch wget tar xz zip unzip java-11-openjdk-devel python3 zlib-devel diffutils libtool libarchive openssl-devel keyutils-libs-devel |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-9.0" | "rhel-9.2")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
    sudo yum install -y gcc-c++ git ncurses-devel make cmake automake bison patch wget tar xz zip unzip java-11-openjdk-devel python3 ghc-resolv zlib-devel diffutils libtool libarchive keyutils-libs-devel |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac
gettingStarted |& tee -a "$LOG_FILE"
