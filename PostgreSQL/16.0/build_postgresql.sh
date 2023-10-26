#!/usr/bin/env bash
# © Copyright IBM Corporation 2023.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/PostgreSQL/16.0/build_postgresql.sh
# Execute build script: bash build_postgresql.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="postgresql"
PACKAGE_VERSION="16.0"
CURDIR="$(pwd)"
TESTS="true"
FORCE="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exsists
if [ ! -d "$CURDIR/logs" ]; then
        mkdir -p "$CURDIR/logs"
fi

source "/etc/os-release"

function checkPrequisites() {
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
        rm -rf "${CURDIR}/postgresql-${PACKAGE_VERSION}.tar.gz"
}

function runTest() {

        if [[ "$TESTS" == "true" ]]; then
                printf -- "TEST Flag is set, continue with running test \n"
                unset LANG
                cd "${CURDIR}/postgresql-${PACKAGE_VERSION}"
        make check
        printf -- "Test execution completed. \n"
        else
                printf -- "TEST Flag is not set, skipping tests \n"
        fi
}

function configureAndInstall() {
        printf -- 'Configuration and Installation started \n'

        #check if postgres user exists
        if id "postgres" >/dev/null 2>&1; then
                        printf -- 'Detected Postgres user in the system. Using the same\n'
        else
                        printf -- 'Creating postgres user. \n'
                        sudo useradd postgres -m -U
                        sudo passwd postgres
        fi

        cd "${CURDIR}"
        wget "https://ftp.postgresql.org/pub/source/v${PACKAGE_VERSION}/postgresql-${PACKAGE_VERSION}.tar.gz"
        tar xf "postgresql-${PACKAGE_VERSION}.tar.gz"
        cd "postgresql-${PACKAGE_VERSION}"
        ./configure --without-icu
        make
        sudo make install

        #Run tests
        runTest

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
        echo " bash build_postgresql.sh [-d debug] [-t Execute test cases after build] [-y install-without-confirmation]"
        echo
}

while getopts "h?dty" opt; do
        case "$opt" in
        h | \?)
                printHelp
                exit 0
                ;;
        d)
                set -x
                ;;
        t)
                TESTS="true"
                ;;
        y)
                FORCE="true"
                ;;
        esac
done

function gettingStarted() {

        printf -- "\n\nUsage: \n"
        printf -- "  PostgreSQL has been successfully installed in the system. \n"
        printf -- "  Post installation steps: \n"
        printf -- "  Update the PATH variable using :\n"
        printf -- '     export PATH=$PATH:/usr/local/pgsql/bin \n'
        printf -- "  More information on starting the postgresql server can be found here : https://github.com/linux-on-ibm-z/docs/wiki/Building-PostgreSQL-16.x \n"
        printf -- '\n'
}

###############################################################################################################

logDetails
checkPrequisites #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"rhel-7.8" | "rhel-7.9" | "rhel-8.6" | "rhel-8.8" | "rhel-9.0" | "rhel-9.2")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- 'Installing the dependencies for postgresql from repository \n' |& tee -a "$LOG_FILE"

        if [[ "$VERSION_ID" == "8.6" || "$VERSION_ID" == "8.8" || "$VERSION_ID" == "9.0" || "$VERSION_ID" == "9.2" ]]; then
        sudo yum install -y git wget gcc gcc-c++ tar make readline-devel zlib-devel bison flex glibc-langpack-en procps-ng diffutils patch curl |& tee -a "$LOG_FILE"
        else
        sudo yum install -y git wget build-essential gcc gcc-c++ tar make readline-devel zlib-devel bison flex patch curl |& tee -a "$LOG_FILE"
        fi

        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

 "ubuntu-23.04" | "ubuntu-23.10" ) 
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        sudo apt-get update >/dev/null
        sudo apt-get install -y bison flex wget build-essential git gcc tar make zlib1g-dev libreadline-dev patch curl |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

 "sles-12.5" | "sles-15.4" | "sles-15.5")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- 'Installing the dependencies for postgresql from repository \n' |& tee -a "$LOG_FILE"
        sudo zypper install -y git-core wget gcc gcc-c++ tar make readline-devel zlib-devel bison flex gawk patch curl gzip |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

*)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
        exit 1
        ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
