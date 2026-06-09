#!/bin/bash
# © Copyright IBM Corporation 2026.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/osquery/5.23.0/build_osquery.sh
# Execute build script: bash build_osquery.sh

set -e -o pipefail

PACKAGE_NAME="osquery"
PACKAGE_VERSION="5.23.0"
TOOLCHAIN_VERSION="1.3.0"
FORCE="false"
SOURCE_ROOT="$(pwd)"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/osquery/5.23.0/patch"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
TOOLCHAIN_BUILD="$SOURCE_ROOT/toolchain-build"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
        mkdir -p "$SOURCE_ROOT/logs/"
fi

source "/etc/os-release"
DISTRO="$ID-$VERSION_ID"

function prepare() {
        if command -v "sudo" >/dev/null; then
		printf -- 'Sudo : Yes\n' >> "$LOG_FILE"
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
                printf -- 'User responded with Yes. \n' >> "$LOG_FILE"
                                break
                                ;;
                        [Nn]*) exit ;;
                        *) echo "Please provide confirmation to proceed." ;;
                        esac
                done
        fi
}

function cleanup() {
        # Remove artifacts
        cd $SOURCE_ROOT
        docker rm -f osquery-toolchain-build
        printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function InstallOsqueryToolchain() {
        printf -- 'Installation of osquery-toolchain started \n' |& tee -a "${LOG_FILE}"
        # Install osquery-toolchain

        cd "${SOURCE_ROOT}"
        docker run --privileged=true -i --name osquery-toolchain-build ubuntu:22.04 bash -c \
"apt-get update; \
DEBIAN_FRONTEND=noninteractive apt-get install -y sudo vim git python3 python3-pip python3-setuptools python3-psutil \
python3-six python3-wheel g++ gcc automake autoconf gettext bison flex unzip help2man libtool-bin libncurses-dev \
make ninja-build patch texinfo gawk wget xz-utils bzip2 cmake pkg-config ca-certificates file perl rpm binutils curl; \
useradd -m test || true; \
usermod -aG sudo test; \
chown -R test:test /home/test; \
cd /home/test; \
git clone -b $TOOLCHAIN_VERSION https://github.com/osquery/osquery-toolchain.git; \
cd osquery-toolchain;
curl -sSL $PATCH_URL/toolchain_ubuntu.patch | git apply -
bash -n build.sh; 
sudo -u test bash -c 'cd /home/test/osquery-toolchain; ./build.sh /home/test/toolchain-build;'; \
cd /home/test/toolchain-build/final; \
mv sysroot osquery-toolchain; \
tar -pcvJf osquery-toolchain-$TOOLCHAIN_VERSION.tar.xz osquery-toolchain;
"
        docker cp osquery-toolchain-build:/home/test/toolchain-build/final/osquery-toolchain-$TOOLCHAIN_VERSION.tar.xz .
        mkdir $TOOLCHAIN_BUILD
        tar -xJvf osquery-toolchain-$TOOLCHAIN_VERSION.tar.xz -C $TOOLCHAIN_BUILD
}

function configureAndInstall() {
        printf -- 'Configuration and Installation started \n' |& tee -a "${LOG_FILE}"

        # Install osquery toolchain
        InstallOsqueryToolchain |& tee -a "${LOG_FILE}"

        # Verfication of osquery toolchain
        export OSQUERY_TOOLCHAIN_SYSROOT="$TOOLCHAIN_BUILD/osquery-toolchain"
        $OSQUERY_TOOLCHAIN_SYSROOT/usr/bin/clang --version

        # Install python pacakges
        printf -- "Installing python pacakges\n"
        if [[ $DISTRO == "ubuntu-24.04" || $DISTRO == "ubuntu-25.10" ]]; then
                python3 -m pip install --user --break-system-packages timeout_decorator thrift==0.11.0 osquery pexpect==3.3 docker
        else
                python3 -m pip install --user timeout_decorator thrift==0.11.0 osquery pexpect==3.3 docker
        fi

        # Download Source code
        cd "${SOURCE_ROOT}"
        git clone -b ${PACKAGE_VERSION} https://github.com/osquery/osquery.git

        # Configure and build and install osquery
        cd osquery
        git submodule update --init --recursive
        curl -sSL ${PATCH_URL}/osquery_generated.patch | git apply -
        curl -sSL ${PATCH_URL}/osquery_main.patch | git apply -
        curl -sSL ${PATCH_URL}/ebpf_common.patch | git apply -
        curl -sSL ${PATCH_URL}/ebpfpub.patch | git apply -
        curl -sSL ${PATCH_URL}/rocksdb.patch | git apply -
        curl -sSL ${PATCH_URL}/s2n.patch | git apply -
        curl -sSL ${PATCH_URL}/test_cases.patch | git apply -
        if [[ $DISTRO == "rhel"* ]]; then
                curl -sSL ${PATCH_URL}/linux_test_case_rhel.patch | git apply -
        fi

        printf -- "Building osquery\n"
        mkdir -p build && cd build
        cmake -DOSQUERY_TOOLCHAIN_SYSROOT="$OSQUERY_TOOLCHAIN_SYSROOT" -DOSQUERY_BUILD_TESTS=ON ..
        cmake --build . -j1

        printf -- '\nInstalled osquery successfully \n' >>"${LOG_FILE}"

        # Verify osquery installation 
        ./osquery/osqueryi --version
        ./osquery/osqueryi --json "select version from os_version;"

        printf -- "osquery build completed successfully. \n"

        # Run Tests
        runTest

        # Cleanup
        cleanup
}

function runTest() {
        set +e
        if [[ "$TESTS" == "true" ]]; then
                printf -- "TEST Flag is set, continue with running test \n" >> "$LOG_FILE"
                cd "$SOURCE_ROOT/osquery/build"
                ctest --output-on-failure -j1
                printf -- "Tests completed successfully. \n"
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
        echo "bash build_osquery.sh  [-d debug] [-y install-without-confirmation] [-t run-tests]"
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
        printf -- '\n***************************************************************************************\n'
        printf -- "                       Getting Started                \n"
        printf -- "osquery ${PACKAGE_VERSION} installed successfully.       \n"
        printf -- "Information regarding the post-installation steps can be found here : \n"
 	printf -- "https://osquery.readthedocs.io/en/stable/introduction/using-osqueryi/#executing-sql-queries\n"
        printf -- "Run osquery: \n"
        printf -- "    cd $SOURCE_ROOT/osquery/build \n"
        printf -- "    ./osquery/osqueryi --version (To check the version) \n\n"
        printf -- '***************************************************************************************\n'
        printf -- '\n'
}

###############################################################################################################

logDetails
prepare #Check Prequisites

case "$DISTRO" in
"rhel-8.10" | "rhel-9.6" | "rhel-9.7" | "rhel-10.0" | "rhel-10.1")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo yum install -y git python3 python3-pip python3-setuptools python3-psutil python3-six python3-wheel python3-devel \
        gcc-c++ gcc automake autoconf gettext bison flex unzip help2man libtool ncurses-devel make ninja-build curl\
        patch texinfo gawk wget xz bzip2 cmake pkgconfig ca-certificates file perl rpm binutils | tee -a "$LOG_FILE"

        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"ubuntu-22.04" | "ubuntu-24.04" | "ubuntu-25.10")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo apt-get update
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git python3 python3-pip python3-setuptools python3-psutil \
        python3-six python3-wheel g++ gcc automake autoconf gettext bison flex unzip help2man libtool-bin libncurses-dev \
        make ninja-build patch texinfo gawk wget xz-utils bzip2 cmake pkg-config ca-certificates file perl rpm binutils curl | tee -a "$LOG_FILE"

        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;	

*)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "${LOG_FILE}"
        exit 1
        ;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
