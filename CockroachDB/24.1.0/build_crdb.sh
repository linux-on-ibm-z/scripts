#!/usr/bin/env bash
# © Copyright IBM Corporation 2024.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/CockroachDB/24.1.0/build_crdb.sh
# Execute build script: bash build_crdb.sh    (provide -h for help)
set -e  -o pipefail
CURDIR="$(pwd)"
PACKAGE_NAME="CockroachDB"
PACKAGE_VERSION="24.1.0"
GO_VERSION="1.22.2"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/CockroachDB/24.1.0/patch"
FORCE="false"
TEST="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
trap cleanup 0 1 2 ERR
#Check if directory exists
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
    if [[ -f ${CURDIR}/cmake-3.29.0.tar.gz ]]; then
        rm ${CURDIR}/cmake-3.29.0.tar.gz
        sudo rm -r ${CURDIR}/cmake-3.29.0
    fi
    if [[ -f ${CURDIR}/resolv_wrapper-1.1.8.tar.gz ]]; then
        rm ${CURDIR}/resolv_wrapper-1.1.8.tar.gz
        sudo rm -r ${CURDIR}/resolv_wrapper-1.1.7
    fi
    if [[ -f ${CURDIR}/gcc-10.5.0.tar.gz ]]; then
        rm ${CURDIR}/gcc-10.5.0.tar.gz
    fi
}
function configureAndInstall() {
    printf -- 'Configuration and Installation started \n'
# Install GCC
    if [[ "${DISTRO}" == "ubuntu-23.10" ]] || [[ "${DISTRO}" == "ubuntu-24.04" ]]; then
        printf -- 'Installing gcc...\n'
        cd ${CURDIR}
        ver=10.5.0
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

# Install CMake - 3.23.3
    if [[ ${DISTRO} =~ ubuntu-20\.* ]]; then
        printf -- 'Installing CMake...\n'
        cd ${CURDIR}
        wget https://github.com/Kitware/CMake/releases/download/v3.29.0/cmake-3.29.0.tar.gz
        tar -xzf cmake-3.29.0.tar.gz
        cd cmake-3.29.0
        ./bootstrap
        make
        sudo make install
    fi
    cmake --version

# Install patched go runtime
    printf -- 'Installing Go...\n'
    cd ${CURDIR}
    mkdir go_bootstrap
    cd go_bootstrap
    wget https://go.dev/dl/go${GO_VERSION}.linux-s390x.tar.gz
    tar -xzf go${GO_VERSION}.linux-s390x.tar.gz
    export GOROOT_BOOTSTRAP=${CURDIR}/go_bootstrap/go

    cd ${CURDIR}
    git clone -b go${GO_VERSION} https://go.googlesource.com/go goroot
    cd goroot
    wget -O ${CURDIR}/go.patch $PATCH_URL/go.patch
    git apply --reject --whitespace=fix $CURDIR/go.patch
    cd src
    ./make.bash
    export PATH="${CURDIR}/goroot/bin:${PATH}"

    go version

# Install bazel
    cd ${CURDIR}
    if [[ ! -f ${CURDIR}/bazel/output/bazel ]]; then
            cd ${CURDIR}
            git clone -b 5.5.1 https://github.com/bazelbuild/rules_java.git
            cd rules_java
            curl -sSL https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Bazel/6.4.0/patch/rules_java_5.5.1.patch | git apply || error "Patch rules_java v5.5.1"
            mkdir -p ${CURDIR}/bazel
            cd ${CURDIR}/bazel
            wget https://github.com/bazelbuild/bazel/releases/download/6.4.0/bazel-6.4.0-dist.zip
            unzip -q bazel-6.4.0-dist.zip
            chmod -R +w .
            curl -sSLO https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Bazel/6.4.0/patch/bazel.patch
            sed -i "s#RULES_JAVA_ROOT_PATH#${CURDIR}#g" bazel.patch
            patch -p1 < bazel.patch || error "Patch bazel"
            bash ./compile.sh
    fi
    export PATH=$PATH:${CURDIR}/bazel/output/
    bazel --version
# Build and install resolv-wrapper lib (RHEL)
    if [[ "${ID}" == "rhel" ]]; then
        cd ${CURDIR}
        wget https://ftp.samba.org/pub/cwrap/resolv_wrapper-1.1.8.tar.gz
        tar zxf resolv_wrapper-1.1.8.tar.gz
        cd resolv_wrapper-1.1.8
        mkdir obj && cd obj
        cmake -DCMAKE_INSTALL_PREFIX=/usr ..
        make
        sudo make install
        ls -la /usr/lib64/libresolv*
    fi
# Build and install bazel-lib
    cd ${CURDIR}
    git clone https://github.com/aspect-build/bazel-lib.git
    cd bazel-lib/
    git checkout v1.32.1
    wget -O ${CURDIR}/bazel-lib.patch $PATCH_URL/bazel-lib.patch
    git apply --reject --whitespace=fix $CURDIR/bazel-lib.patch
    bazel build @aspect_bazel_lib//tools/copy_directory
    bazel build @aspect_bazel_lib//tools/copy_to_directory
# Download and configure CockroachDB
    printf -- 'Downloading CockroachDB source code. Please wait.\n'
    cd ${CURDIR}
    git clone https://github.com/cockroachdb/cockroach
    cd cockroach
    git checkout v$PACKAGE_VERSION
# Applying patches
    printf -- 'Apply patches....\n'
    cd ${CURDIR}/cockroach
    wget -O ${CURDIR}/cockroachdb.patch $PATCH_URL/crdb.patch
    sed -i "s#SOURCE_ROOT_PATH#${CURDIR}#g" ${CURDIR}/cockroachdb.patch
    git apply --reject --whitespace=fix ${CURDIR}/cockroachdb.patch
    sudo cp ${CURDIR}/bazel-lib/lib/private/copy_to_directory_toolchain.bzl .
    sudo cp ${CURDIR}/bazel-lib/lib/private/copy_directory_toolchain.bzl .
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
    sudo cp cockroach /usr/local/bin
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
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y zip unzip autoconf automake wget make libssl-dev libncurses5-dev bison xz-utils patch g++ curl git python3 libresolv-wrapper libkeyutils-dev openjdk-11-jdk |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"ubuntu-22.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
    sudo apt-get update >/dev/null
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y zip unzip autoconf automake wget make libssl-dev libncurses5-dev bison xz-utils patch g++ curl git python3 cmake netbase libresolv-wrapper libkeyutils-dev openjdk-11-jdk |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"ubuntu-23.10" | "ubuntu-24.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
    sudo apt-get update >/dev/null
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y zip unzip autoconf automake wget make libssl-dev libncurses5-dev bison xz-utils patch g++ curl git python3 cmake netbase libresolv-wrapper libkeyutils-dev openjdk-11-jdk bzip2 |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-8.8" | "rhel-8.9" | "rhel-8.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
    sudo yum install -y gcc-c++ git ncurses-devel make cmake automake bison patch wget tar xz zip unzip java-11-openjdk-devel python3 zlib-devel diffutils libtool libarchive openssl-devel keyutils-libs-devel |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-9.2")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
    sudo yum install -y gcc-c++ git ncurses-devel make cmake automake bison patch wget tar xz zip unzip java-11-openjdk-devel python3 ghc-resolv zlib-devel diffutils libtool libarchive keyutils-libs-devel |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-9.3" | "rhel-9.4")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
    sudo yum install -y gcc-c++ git ncurses-devel make cmake automake bison patch wget tar xz zip unzip java-11-openjdk-devel python3 zlib-devel diffutils libtool libarchive keyutils-libs-devel |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac
gettingStarted |& tee -a "$LOG_FILE"
