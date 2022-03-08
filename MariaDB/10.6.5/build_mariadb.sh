#!/bin/bash
# © Copyright IBM Corporation 2021, 2022
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/MariaDB/10.6.5/build_mariadb.sh
# Execute build script: bash build_mariadb.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="mariadb"
PACKAGE_VERSION="10.6.5"
CURDIR="$(pwd)"

TESTS="false"
FORCE="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

MARIADB_NO_DEFAULTS=""

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
    mkdir -p "$CURDIR/logs/"
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
    
    # Install Git, only for RHEL7.x as it has older version in repo because of which cmake throws error while updating submodules.
    cd "$CURDIR"
    DISTRO="$ID-$VERSION_ID"
    if [[ "$DISTRO" == "rhel-7.8" || "$DISTRO" == "rhel-7.9" ]]; then
        sudo yum remove -y git
        sudo yum groupinstall -y "Development Tools"
        sudo yum install -y gettext-devel openssl-devel perl-devel perl-CPAN zlib-devel curl-devel
        wget https://github.com/git/git/archive/refs/tags/v2.26.3.tar.gz
        tar -xvzf v2.26.3.tar.gz
        cd git-2.26.3
        make configure
        ./configure --prefix=/usr/local
        sudo make install
        export PATH=/usr/local/bin:$PATH
        git --version
    fi
    printf -- "Install Git success\n" >>"$LOG_FILE"
    
    # Download mariadb
    cd "$CURDIR"
    git clone https://github.com/MariaDB/server.git
    cd server
    git checkout mariadb-${PACKAGE_VERSION}
    git submodule update --init --recursive
    # Build and install mariadb
    mkdir build  && cd build
    cmake "$CURDIR"/server
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
        printf -- 'Running tests \n\n'

        cd "$CURDIR"/server/build/mysql-test
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
    printf -- "sudo /usr/local/mysql/bin/mysqld_safe --user=mysql & \n"
    printf -- "You have successfully started mariadb.\n"
    printf -- "\n To Display version \n"
    printf -- "\n sudo -u mysql mysqladmin version --user=mysql \n"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"ubuntu-18.04" | "ubuntu-20.04" | "ubuntu-21.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y git gcc g++ make wget tar cmake libssl-dev libncurses-dev bison scons libboost-dev libboost-program-options-dev check libpam0g-dev |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
    
"rhel-7.8" | "rhel-7.9")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y gcc gcc-c++ make wget curl tar cmake openssl-devel ncurses-devel bison boost-devel check-devel perl-Test-Simple perl-Time-HiRes openssl libpcre3-dev pam-devel patch hostname |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"rhel-8.2" | "rhel-8.4")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y git gcc which gcc-c++ make wget tar cmake openssl-devel ncurses-devel bison boost-devel check-devel perl-Test-Simple perl-Time-HiRes openssl pcre-devel pam-devel perl-Memoize.noarch patch diffutils hostname libarchive |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"sles-12.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y git gcc gcc-c++ make which wget tar gzip cmake libopenssl-devel ncurses-devel-5.9-72.1 bison glibc-locale boost-devel check-devel gawk pam-devel patch |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"sles-15.3")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y which git gcc gcc-c++ make wget tar gzip cmake libopenssl-devel ncurses-devel bison glibc-locale boost-devel libboost_program_options-devel check-devel gawk pam-devel patch hostname|& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
