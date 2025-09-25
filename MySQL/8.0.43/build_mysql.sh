#!/bin/bash
# © Copyright IBM Corporation 2025
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/MySQL/8.0.43/build_mysql.sh
# Execute build script: bash build_mysql.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="mysql"
PACKAGE_VERSION="8.0.43"
SOURCE_ROOT="$(pwd)"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/MySQL/${PACKAGE_VERSION}/patch"

FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
BUILD_ENV="$HOME/setenv.sh"

#Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
    mkdir -p "$SOURCE_ROOT/logs/"
fi

source "/etc/os-release"

function prepare() {
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

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"
    #Download the MySQL source code from Github
    cd $SOURCE_ROOT
    git clone -b mysql-$PACKAGE_VERSION https://github.com/mysql/mysql-server.git
    cd mysql-server
    curl -sSL "${PATCH_URL}/NdbHW.patch" | git apply -
    curl -sSL "${PATCH_URL}/router-test.patch" | git apply -
    curl -sSL "${PATCH_URL}/ut0rnd.patch" | git apply -
    mkdir build
    cd build
    #Configure, build and install MySQL
    cmake .. -DDOWNLOAD_BOOST=1 -DWITH_BOOST=. -DWITH_SSL=system

    make -j $(nproc)
    sudo make install

    printf -- "MySQL build completed successfully. \n"

  # Run Tests
    runTest
}

function runTest() {
    set +e

    if [[ "$TESTS" == "true" ]]; then
        printf -- "TEST Flag is set, continue with running test \n"
        cd $SOURCE_ROOT/mysql-server/build
        export LD_PRELOAD=$SOURCE_ROOT/mysql-server/build/library_output_directory/libprotobuf-lite.so.24.4.0${LD_PRELOAD:+:${LD_PRELOAD}}
        printf -- "export LD_PRELOAD=\"${LD_PRELOAD}\"\n"  >> "${BUILD_ENV}"
        make test
        printf -- "Tests completed. \n"
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
    echo "bash build_mysql.sh  [-d debug] [-y install-without-confirmation] [-t install and run tests]"
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
    printf -- "                       Getting Started                \n"
    printf -- " MySQL 8.0.x installed successfully.       \n"
    printf -- " Information regarding the post-installation steps can be found here : https://dev.mysql.com/doc/refman/8.0/en/postinstallation.html\n"
    printf -- " Starting MySQL Server: \n"
    printf -- " sudo useradd mysql   \n"
    printf -- " sudo groupadd mysql \n"
    printf -- " cd /usr/local/mysql  \n"
    printf -- " sudo mkdir mysql-files \n"
    printf -- " sudo chown mysql:mysql mysql-files \n"
    printf -- " sudo chmod 750 mysql-files \n"
    printf -- " sudo bin/mysqld --initialize --user=mysql \n"
    printf -- " sudo bin/mysqld_safe --user=mysql & \n"
    printf -- "           You have successfully started MySQL Server.\n"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

rm -rf ${BUILD_ENV}

case "$DISTRO" in
"rhel-8.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y curl wget bison bzip2 git hostname ncurses-devel openssl-devel pkgconfig tar procps zlib-devel doxygen cmake diffutils rpcgen make libtirpc-devel libarchive gcc-toolset-12-gcc gcc-toolset-12-gcc-c++ gcc-toolset-12-binutils net-tools |& tee -a "$LOG_FILE"
    source /opt/rh/gcc-toolset-12/enable

    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-15.6")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y curl make cmake bison gcc14 gcc14-c++ git hostname ncurses-devel procps openssl-devel pkg-config gawk doxygen libtirpc-devel rpcgen tar wget net-tools-deprecated xz timezone |& tee -a "$LOG_FILE"
    sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-14 14
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-14 14
    sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-14 14
    sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-14 14
    sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
    sudo ln -sf /usr/bin/cpp-14 /usr/bin/cpp

    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
