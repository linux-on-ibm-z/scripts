#!/usr/bin/env bash
# © Copyright IBM Corporation 2022.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/CockroachDB/22.1.7/build_crdb.sh
# Execute build script: bash build_crdb.sh    (provide -h for help)
set -e  -o pipefail

CURDIR="$(pwd)"
PACKAGE_NAME="CockroachDB"
PACKAGE_VERSION="22.1.7"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/CockroachDB/22.1.7/patch/crdb.patch"
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
}

function configureAndInstall() {
    printf -- 'Configuration and Installation started \n'

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

    # Install CMake - 3.20.*+
    if [[ ${DISTRO} =~ rhel-7\.* || ${DISTRO} =~ rhel-8\.* || ${DISTRO} =~ ubuntu-18\.* || ${DISTRO} =~ ubuntu-20\.* ]]; then
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
    if [[ "${ID}" == "ubuntu" ]]; then
        wget -q https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Bazel/5.1.1/build_bazel.sh
        bash build_bazel.sh -y
        export PATH=$PATH:${CURDIR}/dist/bazel/output/
    else
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
    fi
    bazel --version


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

    ./dev doctor
    ./dev build
    bazel build c-deps:libgeos
    sudo cp cockroach /usr/local/bin
    sudo mkdir -p /usr/local/lib/cockroach
    sudo cp _bazel/bin/c-deps/libgeos/lib/libgeos.so /usr/local/lib/cockroach/
    sudo cp _bazel/bin/c-deps/libgeos/lib/libgeos_c.so /usr/local/lib/cockroach/
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
        for PKG in acceptance base bench blobs cli clusterversion compose config geo gossip jobs keys kv roachpb rpc security server settings spanconfig sql startupmigrations storage testutils ts ui util workload 
        do
            printf -- "Testing pkg/$PKG ... \n"
            ./dev test pkg/$PKG
        done
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
"ubuntu-18.04" | "ubuntu-20.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
    sudo apt-get update >/dev/null
    sudo apt-get install -y autoconf automake wget make libssl-dev libncurses5-dev bison xz-utils patch g++ curl git python libresolv-wrapper |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"ubuntu-22.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
    sudo apt-get update >/dev/null
    sudo apt-get install -y autoconf automake wget make libssl-dev libncurses5-dev bison xz-utils patch g++ curl git python3 cmake libresolv-wrapper |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"rhel-7.8" | "rhel-7.9")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
	sudo subscription-manager repos --enable=rhel-7-server-for-system-z-rhscl-rpms || true
	sudo yum install -y devtoolset-7-gcc-c++ devtoolset-7-gcc git ncurses-devel make cmake automake bison patch wget tar xz zip unzip java-11-openjdk-devel python3 zlib-devel openssl-devel gettext-devel diffutils |& tee -a "$LOG_FILE"
	source /opt/rh/devtoolset-7/enable
	configureAndInstall |& tee -a "$LOG_FILE"
  ;;

"rhel-8.4" | "rhel-8.6")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
    sudo yum install -y gcc-c++ git ncurses-devel make cmake automake bison patch wget tar xz zip unzip java-11-openjdk-devel python3 zlib-devel diffutils libtool libarchive openssl-devel |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"rhel-9.0")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
    sudo yum install -y gcc-c++ git ncurses-devel make cmake automake bison patch wget tar xz zip unzip java-11-openjdk-devel python3 ghc-resolv zlib-devel diffutils libtool libarchive |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
