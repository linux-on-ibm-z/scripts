#!/bin/bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/MariaDB/10.4.7/build_mariadb.sh
# Execute build script: bash build_mariadb.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="mariadb"
PACKAGE_VERSION="10.4.7"
CURDIR="$(pwd)"
BUILD_DIR="/usr/local"

MARIADB_CONN_VERSION="3.1.2"
TESTS="false"
FORCE="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
    mkdir -p "$CURDIR/logs/"
fi

# Need handling for RHEL 6.10 as it doesn't have os-release file
if [ -f "/etc/os-release" ]; then
    source "/etc/os-release"
else
    cat /etc/redhat-release >>"${LOG_FILE}"
    export ID="rhel"
    export VERSION_ID="6.x"
    export PRETTY_NAME="Red Hat Enterprise Linux 6.x"
fi

function prepare() {
    if command -v "sudo" >/dev/null; then
        printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
    else
        printf -- 'Sudo : No \n' >>"$LOG_FILE"
        printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n'
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
    # Remove artifacts

    if [ -f "$CURDIR/mariadb-${PACKAGE_VERSION}.tar.gz" ]; then
        rm -rf "$CURDIR/mariadb-${PACKAGE_VERSION}.tar.gz"
    fi

    #rm "$CURDIR"/mariadb_com.h.diff
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function buildGCC() {
   
    if [[ "$DISTRO" == "rhel-6.x" ]]; then
      printf -- "Build gcc 4.8.2 for rhel-6.x\n" >>"$LOG_FILE"
      cd $CURDIR 
      sudo yum install -y subversion gcc-c++ binutils-devel bzip2
      wget http://ftp.gnu.org/gnu/gcc/gcc-4.8.2/gcc-4.8.2.tar.bz2
      tar xf gcc-4.8.2.tar.bz2
      cd gcc-4.8.2
      ./contrib/download_prerequisites
      mkdir $CURDIR/gccbuild
      cd $CURDIR/gccbuild
      ../gcc-4.8.2/configure  --prefix="/opt/gcc"  --enable-shared --with-system-zlib --enable-threads=posix  --enable-__cxa_atexit --enable-checking --enable-gnu-indirect-function  --enable-languages="c,c++" --disable-bootstrap --disable-multilib
      make all
      sudo make install
      export PATH=/opt/gcc/bin:$PATH
      export LD_LIBRARY_PATH=/opt/gcc/lib64:/opt/gcc/lib:$LD_LIBRARY_PATH
      sudo mv /usr/bin/gcc /usr/bin/gcc.bkup
      sudo ln -s /opt/gcc/bin/gcc /usr/bin/gcc
      sudo mv /usr/bin/c++ /usr/bin/c++.bkup
      sudo ln -s /opt/gcc/bin/c++ /usr/bin/c++
      sudo rm -rf /usr/lib64/libstdc++.so.6 && ln -s /opt/gcc/lib64/libstdc++.so.6.0.18 /usr/lib64/libstdc++.so.6
      gcc --version
    fi
}
function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

    # Download mariadb
    cd "$CURDIR"
    wget https://github.com/MariaDB/server/archive/mariadb-${PACKAGE_VERSION}.tar.gz
    tar xzf mariadb-${PACKAGE_VERSION}.tar.gz

    # Get MariaDB Connector/C source into libmariadb folder
    git clone git://github.com/MariaDB/mariadb-connector-c.git
    cd mariadb-connector-c
    git checkout v${MARIADB_CONN_VERSION}
    cp -r "$CURDIR"/mariadb-connector-c/* "$CURDIR"/server-mariadb-${PACKAGE_VERSION}/libmariadb/

    # Get wsrep-lib source into wsrep-lib folder
    cd "$CURDIR"
    git clone https://github.com/codership/wsrep-lib.git
    cd wsrep-lib
    git checkout 55427188c152739fb2021fa997cad4b89b8c2fc7 
    git submodule update --init --recursive
    cp -r "$CURDIR"/wsrep-lib/* "$CURDIR"/server-mariadb-${PACKAGE_VERSION}/wsrep-lib/

    # Build and install mariadb
    mv  "$CURDIR"/server-mariadb-${PACKAGE_VERSION} "$CURDIR"/mariadb
    rm -rf "$CURDIR"/server-mariadb-${PACKAGE_VERSION}
    sudo mkdir "$BUILD_DIR"/build_mariadb/
    #Give permission
    sudo chown -R "$USER" "$BUILD_DIR"/build_mariadb/
    cd "$BUILD_DIR"/build_mariadb/
    cmake "$CURDIR"/mariadb/
    make
    sudo make install
    printf -- "Build mariadb success\n"

    sudo groupadd mysql || true
    sudo useradd -g mysql mysql || true

    cd /usr/local/mysql
    sudo chown -R mysql .
    sudo chmod -R o+rwx .

    sudo scripts/mysql_install_db --user=mysql
    sudo cp support-files/mysql.server /etc/init.d/mysql

    # Create a symlink
    sudo ln -sf /usr/local/mysql/bin/mysqladmin /usr/bin/mysqladmin

    printf -- "Installation mariadb success\n"
    # Run Test
    runTest

    # Verify mariadb installation
    if command -v "/usr/local/mysql/bin/mysqladmin" >/dev/null; then
        printf -- " %s Installation verified.\n" "$PACKAGE_NAME"
    else
        printf -- "Error while installing %s, exiting with 127 \n" "$PACKAGE_NAME"
        exit 127
    fi
}

function runTest() {

    set +e
    if [[ "$TESTS" == "true" ]]; then
        printf -- 'Running tests \n\n' |& tee -a "$LOG_FILE"
        sudo /usr/local/mysql/bin/mysqld_safe --user=mysql &
        cd "$BUILD_DIR"/build_mariadb/mysql-test
        ./mtr --suite=unit --force --max-test-fail=0
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
    echo " build_mariadb.sh  [-d debug] [-y install-without-confirmation] [-t install and run tests]"
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
    printf -- "\n*Getting Started * \n"
    printf -- "Running mariadb: \n"
    printf -- "mysqladmin version --user=mysql  \n\n"
    printf -- "You have successfully started mariadb.\n"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04" | "ubuntu-19.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y git gcc g++ make wget tar cmake libssl-dev libncurses-dev bison scons libboost-dev libboost-program-options-dev check openssl libpcre3-dev libpam0g-dev |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-6.x" | "rhel-7.5" | "rhel-7.6" |"rhel-7.7")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y git gcc gcc-c++ make wget tar cmake openssl-devel ncurses-devel bison python boost-devel check-devel perl-Test-Simple perl-Time-HiRes pam-devel |& tee -a "$LOG_FILE"
    buildGCC |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-8.0")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y git gcc gcc-c++ make wget tar cmake openssl-devel ncurses-devel bison python2 boost-devel check-devel perl-Test-Simple perl-Time-HiRes openssl pam-devel perl-Memoize.noarch |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-12.4")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y git gcc gcc-c++ make wget tar gzip cmake libopenssl-devel ncurses-devel bison glibc-locale python boost-devel check-devel scons gawk pam-devel |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-15" | "sles-15.1")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y git gcc gcc-c++ make wget tar gzip cmake libopenssl-devel ncurses-devel bison glibc-locale python boost-devel libboost_program_options-devel check-devel gawk pam-devel |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
