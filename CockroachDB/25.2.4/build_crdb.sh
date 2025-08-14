#!/usr/bin/env bash
# © Copyright IBM Corporation 2025.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/CockroachDB/25.2.4/build_crdb.sh
# Execute build script: bash build_crdb.sh    (provide -h for help)

set -e  -o pipefail

SOURCE_ROOT="$(pwd)"
PACKAGE_NAME="CockroachDB"
PACKAGE_VERSION="25.2.4"
GO_VERSION="1.22.8"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/CockroachDB/25.2.4/patch"
FORCE="false"
TEST="false"
LOG_FILE="$SOURCE_ROOT/logs/$PACKAGE_NAME-$PACKAGE_VERSION-$(date +"%F-%T").log"
BUILD_ENV="$HOME/setenv.sh"
trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs" ]; then
    mkdir -p "$SOURCE_ROOT/logs"
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
    if [[ -f $SOURCE_ROOT/resolv_wrapper-1.1.8.tar.gz ]]; then
        rm $SOURCE_ROOT/resolv_wrapper-1.1.8.tar.gz
        sudo rm -r $SOURCE_ROOT/resolv_wrapper-1.1.8
    fi
}

function configureAndInstall() {
    printf -- 'Configuration and Installation started \n'
    # Install bazel
    cd $SOURCE_ROOT
    if [[ ! -f $SOURCE_ROOT/bazel/output/bazel ]]; then
        cd $SOURCE_ROOT
        git clone -b 7.6.1 https://github.com/bazelbuild/rules_java.git
        cd rules_java
        curl -sSL https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Bazel/7.2.1/patch/rules_java_7.6.1.patch | git apply || error "Patch rules_java v7.6.1"
        cd $SOURCE_ROOT
        git clone -b v0.11.1 https://github.com/sgammon/rules_graalvm
        cd rules_graalvm
        curl -sSL https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Bazel/7.2.1/patch/rules_graalvm_0.11.1.patch | git apply || error "Patch graalvm v0.11.1"
        mkdir -p $SOURCE_ROOT/bazel
        cd $SOURCE_ROOT/bazel
        wget -q https://github.com/bazelbuild/bazel/releases/download/7.2.1/bazel-7.2.1-dist.zip
        unzip -q bazel-7.2.1-dist.zip
        chmod -R +w .
        curl -sSLO https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Bazel/7.2.1/patch/bazel.patch
        sed -i '368,$d' bazel.patch
        sed -i "s#RULES_JAVA_ROOT_PATH#$SOURCE_ROOT#g" bazel.patch
        patch -p1 < bazel.patch || error "Patch bazel"
		if [[ "$DISTRO" == "rhel-10.0" || "$DISTRO" == "rhel-9.6" ]]; then
	        export JAVA_HOME=/usr/lib/jvm/java-21-openjdk && export PATH=$JAVA_HOME/bin:$PATH
            printf -- "export JAVA_HOME=$JAVA_HOME\n" >> "$BUILD_ENV"
        fi
        if [[ "$DISTRO" == "ubuntu-25.04" ]]; then
	        export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-s390x && export PATH=$JAVA_HOME/bin:$PATH
            printf -- "export JAVA_HOME=$JAVA_HOME\n" >> "$BUILD_ENV"
        fi
        env EXTRA_BAZEL_ARGS="--tool_java_runtime_version=local_jdk" bash ./compile.sh
    fi
    export PATH=$PATH:$SOURCE_ROOT/bazel/output/
    printf -- "export PATH=$PATH\n" >> "$BUILD_ENV"
    bazel --version

    # Build and install resolv-wrapper lib (RHEL)
    if [[ "$ID" == "rhel" ]]; then
        if [ ! -d  $SOURCE_ROOT/resolv_wrapper-1.1.8 ]; then
            cd $SOURCE_ROOT
            wget https://ftp.samba.org/pub/cwrap/resolv_wrapper-1.1.8.tar.gz
            tar zxf resolv_wrapper-1.1.8.tar.gz
            cd resolv_wrapper-1.1.8
            mkdir obj && cd obj
            cmake -DCMAKE_INSTALL_PREFIX=/usr ..
            make
            sudo make install
            ls -la /usr/lib64/libresolv*
        fi
    fi

    # Build and install bazel-lib
    if [ ! -d  $SOURCE_ROOT/bazel-lib ]; then
        cd $SOURCE_ROOT
        git clone -b v1.42.3 https://github.com/aspect-build/bazel-lib.git
        cd bazel-lib/
        value=($(sha256sum /usr/bin/bsdtar))
        wget -O $SOURCE_ROOT/bazel-lib.patch $PATCH_URL/bazel-lib.patch
        sed -i "s#BSDTAR_SHA256SUM#$value#g" $SOURCE_ROOT/bazel-lib.patch
        git apply --reject --whitespace=fix $SOURCE_ROOT/bazel-lib.patch
        bazel build @aspect_bazel_lib//tools/copy_directory
        bazel build @aspect_bazel_lib//tools/copy_to_directory
    fi

    # Download and configure CockroachDB
    printf -- 'Downloading CockroachDB source code. Please wait.\n'
    cd $SOURCE_ROOT
    git clone -b v$PACKAGE_VERSION --depth 1 https://github.com/cockroachdb/cockroach.git
    # Applying patches
    printf -- 'Apply patches....\n'
    cd $SOURCE_ROOT/cockroach
    mkdir patch && cd patch
    cp $SOURCE_ROOT/bazel-lib.patch .
    cat <<EOF >BUILD
filegroup(
    name = "bazel-lib.patch",
    srcs = ["bazel-lib.patch"],
)
EOF
    cd $SOURCE_ROOT/cockroach
    wget -O $SOURCE_ROOT/crdb.patch $PATCH_URL/crdb.patch
    git apply --reject --whitespace=fix $SOURCE_ROOT/crdb.patch
    # Build CockroachDB
    printf -- 'Building CockroachDB.... \n'
    printf -- 'Build might take some time. Sit back and relax\n'
    cd $SOURCE_ROOT/cockroach
    echo 'build --remote_cache=http://127.0.0.1:9867' >> .bazelrc.user
    echo 'build --config=dev' >> .bazelrc.user
    echo 'build --config=nolintonbuild' >> .bazelrc.user
    echo "test --test_tmpdir=$SOURCE_ROOT/cockroach/tmp" >> .bazelrc.user
    ./dev doctor
    ./dev build
	if [[ "$DISTRO" == "rhel-10.0" || "$DISTRO" == "ubuntu-24.04" || "$DISTRO" == "ubuntu-25.04" ]]; then
	    sed -i '/#include/ a #include <cstdint>' $SOURCE_ROOT/cockroach/c-deps/geos/include/geos/shape/fractal/HilbertEncoder.h
    fi
    bazel build c-deps:libgeos --config force_build_cdeps
    sudo cp cockroach /usr/local/bin
    sudo mkdir -p /usr/local/lib/cockroach
    sudo cp _bazel/bin/c-deps/libgeos_foreign/lib/libgeos.so /usr/local/lib/cockroach/
    sudo cp _bazel/bin/c-deps/libgeos_foreign/lib/libgeos_c.so /usr/local/lib/cockroach/
    export PATH=$SOURCE_ROOT/cockroach:$PATH
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
        cd $SOURCE_ROOT/cockroach
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
"rhel-8.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
    sudo yum install -y gcc-c++ git ncurses-devel make cmake automake bison patch wget tar xz zip unzip java-21-openjdk-devel python3 zlib-devel diffutils libtool libarchive openssl-devel keyutils-libs-devel bsdtar |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-9.4" | "rhel-9.6" | "rhel-10.0")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
    sudo yum install -y gcc-c++ git ncurses-devel make cmake automake bison patch wget tar xz zip unzip java-21-openjdk-devel python3 zlib-devel diffutils libtool libarchive keyutils-libs-devel bsdtar |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"ubuntu-22.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
    sudo apt-get update >/dev/null
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y zip unzip autoconf automake wget make libssl-dev libncurses5-dev bison xz-utils patch g++ curl git python3 cmake netbase libresolv-wrapper libkeyutils-dev openjdk-21-jdk libarchive-tools |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"ubuntu-24.04" | "ubuntu-25.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
    sudo apt-get update >/dev/null
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y zip unzip autoconf automake wget make libssl-dev libncurses5-dev bison xz-utils patch g++ curl git python3 cmake netbase libresolv-wrapper libkeyutils-dev openjdk-21-jdk bzip2 libarchive-tools |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac
gettingStarted |& tee -a "$LOG_FILE"


