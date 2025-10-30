#!/bin/bash
# © Copyright IBM Corporation 2025.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
#Instructions
#Get Build script : wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Python3/3.13.9/build_python3.sh
#Execute build script: bash build_python3.sh

set -e -o pipefail

PACKAGE_NAME="python"
PACKAGE_VERSION="3.13.9"
TESTS="false"
FORCE="false"
CURDIR="$(pwd)"
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
BUILD_ENV="${CURDIR}/setenv.sh"

trap "" 1 ERR

if [ ! -d "${CURDIR}/logs/" ]; then
        mkdir -p "${CURDIR}/logs/"
fi


source "/etc/os-release"

function prepare() {
        printf -- 'Preparing installation \n' |& tee -a "${LOG_FILE}"
        if command -v "sudo" >/dev/null; then
                printf -- 'Sudo : Yes\n'
        else
                printf -- 'Sudo : No \n'
                printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n'
                exit 1
        fi

        printf -- "Preparing the installation for Python ${PACKAGE_VERSION}\n"

        if [[ "$FORCE" == "true" ]]; then
                printf -- 'Force attribute provided hence continuing with install without confirmation message \n' |& tee -a "${LOG_FILE}"
        else
                # Ask user for prerequisite installation
                printf -- "\n\nAs part of the installation some dependencies might be installed, \n"
                while true; do
                        read -r -p "Do you want to continue (y/n) ? :  " yn
                        case $yn in
                        [Yy]*)
                                printf -- 'User responded with Yes. \n' |& tee -a "${LOG_FILE}"
                                break
                                ;;
                        [Nn]*) exit ;;
                        *) echo "Please provide confirmation to proceed." ;;
                        esac
                done
        fi
}

function cleanup() {
        rm "$CURDIR/Python-${PACKAGE_VERSION}.tgz"
        printf -- 'Cleaned up the artifacts\n' >>"${LOG_FILE}"
}


function configureAndInstall() {
        printf -- 'Configuration and Installation started \n' |& tee -a "${LOG_FILE}"

        #Download Source code
        cd "${CURDIR}"
        wget "https://www.python.org/ftp/${PACKAGE_NAME}/${PACKAGE_VERSION}/Python-${PACKAGE_VERSION}.tgz"
        tar -xzf "Python-${PACKAGE_VERSION}.tgz"

        #Configure and build and install Python3
        cd "$CURDIR/Python-${PACKAGE_VERSION}"
        ./configure
        make
        sudo make install
	
        printf -- '\nInstalled python successfully \n' >>"${LOG_FILE}"

        #Run tests
        runTest

        #Cleanup
        cleanup

        #Verify python installation
        if command -V "$PACKAGE_NAME"${PACKAGE_VERSION:0:1} >/dev/null; then
                printf -- "%s installation completed. Please check the Usage to start the service.\n" "$PACKAGE_NAME" |& tee -a "$LOG_FILE"
        else
                printf -- "Error while installing %s, exiting with 127 \n" "$PACKAGE_NAME"
                exit 127
        fi
}

function runTest() {
        set +e
        if [[ "$TESTS" == "true" ]]; then
                printf -- "TEST Flag is set, continue with running test \n" >> "$LOG_FILE"
                cd "$CURDIR/Python-${PACKAGE_VERSION}"
                sudo make test 2>&1| tee -a test_results.log

                grep "Tests result: SUCCESS\|Tests result: FAILURE then SUCCESS" test_results.log

                if [[ $? != 0 ]]; then
                        printf -- "Tests execution failed. \n"
                else
                        printf -- "Tests completed successfully. \n"
                fi
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
        echo "  bash build_python3.sh  [-d <debug>] [-v package-version] [-y install-without-confirmation]  [-t install-with-tests] "
        echo "       default: If no -v specified, latest version will be installed "
        echo "This script supports Python version $PACKAGE_VERSION"
        echo
}

while getopts "h?dytv:" opt; do
        case "$opt" in
        h | \?)
                printHelp
                exit 0
                ;;
        d)
                set -x
                ;;
        v)
                PACKAGE_VERSION="$OPTARG"
                LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
                ;;
        y)
                FORCE="true"
                ;;
        t)
                TESTS="true"
                ;;
        esac
done

function printSummary() {
        printf -- '\n***************************************************************************************\n'
        printf -- "Run python: \n"
        printf -- "    python3 -V (To check the version) \n\n"
        printf -- '***************************************************************************************\n'
        printf -- '\n'
}

###############################################################################################################

logDetails
prepare

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
 "rhel-8.10" | "rhel-9.4" | "rhel-9.6" | "rhel-10.0")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo yum install -y bzip2-devel gcc gcc-c++ gdbm-devel libdb-devel libffi-devel libuuid-devel make ncurses-devel openssl-devel tar tk-devel wget xz zlib-devel diffutils xz-devel patch
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"sles-15.6" | "sles-15.7")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo zypper ref -s
        sudo zypper install -y gawk gcc gcc-c++ gdbm-devel libbz2-devel libdb-4_8-devel libffi-devel libnsl-devel libopenssl-devel libuuid-devel make ncurses-devel tar tk-devel wget xz-devel zlib-devel gzip 
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;
	
"ubuntu-22.04" | "ubuntu-24.04" | "ubuntu-25.04")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo apt-get update
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y gcc g++ libbz2-dev libdb-dev libffi-dev libgdbm-dev liblzma-dev libncurses-dev libreadline-dev libsqlite3-dev libssl-dev make tar tk-dev uuid-dev wget xz-utils zlib1g-dev patch
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;	

*)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "${LOG_FILE}"
        exit 1
        ;;
esac

printSummary |& tee -a "${LOG_FILE}"
