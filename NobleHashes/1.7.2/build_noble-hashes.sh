#!/bin/bash
# ©  Copyright IBM Corporation 2024.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/NobleHashes/1.7.2/build_noble-hashes.sh
# Execute build script: bash build_noble-hashes.sh    (provide -h for help)
#
set -e -o pipefail

PACKAGE_NAME="noble-hashes"
PACKAGE_VERSION="1.7.2"
NODE_JS_VERSION="20.11.0"

FORCE=false
CURDIR="$(pwd)"
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/NobleHashes/${PACKAGE_VERSION}/patch"
NON_ROOT_USER="$(whoami)"
ENV_VARS=$CURDIR/setenv.sh

trap cleanup 1 2 ERR

# Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
   mkdir -p "$CURDIR/logs/"
fi

source "/etc/os-release"

function prepare() {
    if command -v "sudo" > /dev/null; then
        printf -- 'Sudo : Yes\n' >> "$LOG_FILE"
    else
        printf -- 'Sudo : No \n' >> "$LOG_FILE"
        printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n' |& tee -a "${LOG_FILE}"
        exit 1
    fi

    if [[ "$FORCE" == "true" ]]; then
        printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "${LOG_FILE}"
    else
        # Ask user for prerequisite installation
        printf -- "\nAs part of the installation , dependencies would be installed/upgraded, \n" |& tee -a "${LOG_FILE}"
        while true; do
            read -r -p "Do you want to continue (y/n) ? :  " yn
            case $yn in
            [Yy]*)
                printf -- 'User responded with Yes. \n' >> "${LOG_FILE}"
                break
                ;;
            [Nn]*) exit ;;
            *) echo "Please provide confirmation to proceed." ;;
            esac
        done
    fi
}

function cleanup() {
    sudo rm -f "${CURDIR}/node-v${NODE_JS_VERSION}-linux-s390x.tar.xz"
    printf -- 'Cleaned up the artifacts\n' >>"${LOG_FILE}"
}

function configureAndInstall() {
    printf -- '\nConfiguration and Installation started.\n'

    # Install Node.js
    if [[ $DISTRO != "sles-12.5" ]]; then
        printf -- 'Downloading and installing Node.js.\n'
        cd "${CURDIR}"
        sudo mkdir -p /usr/local/lib/nodejs
        wget https://nodejs.org/dist/v${NODE_JS_VERSION}/node-v${NODE_JS_VERSION}-linux-s390x.tar.xz
        sudo tar xf node-v${NODE_JS_VERSION}-linux-s390x.tar.xz -C /usr/local/lib/nodejs
        export PATH=/usr/local/lib/nodejs/node-v${NODE_JS_VERSION}-linux-s390x/bin:$PATH
        echo "export PATH=$PATH" >> $ENV_VARS
    fi
    printf -- 'nodejs version: %s\n' $(node -v)

    cd $CURDIR
    git clone https://github.com/paulmillr/noble-hashes.git
    cd noble-hashes
    git checkout "$PACKAGE_VERSION"
    curl -sSL "${PATCH_URL}/noble-hashes.patch" | git apply -
    npm install
    npm run build
    printf -- 'Built noble-hashes successfully.\n'

    # Run Tests
    cd $CURDIR
    runTest

    # Cleanup
    cd $CURDIR
    cleanup
}

function runTest() {
    set +e
    if [[ "$TESTS" == "true" ]]; then
        printf -- "TEST Flag is set, continue with running test \n"

        cd $CURDIR/noble-hashes
        npm run test

        printf -- '**********************************************************************************************************\n'
        printf -- 'Completed test execution.\n'
        printf -- '**********************************************************************************************************\n'
    fi
    set -e
}


function logDetails() {
    printf -- '**************************** SYSTEM DETAILS *************************************************************\n'
    if [ -f "/etc/os-release" ]; then
        cat "/etc/os-release"
    fi
    cat /proc/version
    printf -- '*********************************************************************************************************\n'
    printf -- "Detected %s \n" "$PRETTY_NAME"
    printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION"
}

# Print the usage message
function printHelp() {
    echo
    echo "Usage: "
    echo "bash build_noble-hashes.sh  [-d debug] [-y install-without-confirmation] [-t test]"
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
    printf -- '\n*********************************************************************************************\n'
    printf -- "Getting Started:\n\n"
    printf -- "Note: To set the environment variables needed for noble-hashes, please run:\n"
    printf -- "  source $CURDIR/setenv.sh\n\n"
    printf -- "See: https://paulmillr.com/noble and https://github.com/paulmillr/noble-hashes for\n"
    printf -- "informantion on using noble-hashes\n"
    printf -- '*********************************************************************************************\n'
    printf -- '\n'
}

###############################################################################################################

logDetails |& tee "${LOG_FILE}"
prepare

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-22.04" | "ubuntu-23.10")
    printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
    sudo apt-get update
    sudo apt-get install -y tar xz-utils wget curl git
    configureAndInstall |& tee -a "${LOG_FILE}"
    ;;

"rhel-8.6" | "rhel-8.8" | "rhel-8.9")
    printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
    sudo yum install -y tar xz wget curl git
    configureAndInstall |& tee -a "${LOG_FILE}"
    ;;

"rhel-9.0" | "rhel-9.2" | "rhel-9.3")
    printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
    sudo yum install -y --allowerasing tar xz wget curl git
    configureAndInstall |& tee -a "${LOG_FILE}"
    ;;

"sles-12.5")
    printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
    sudo zypper install -y nodejs18 npm18 tar xz wget curl git
    configureAndInstall |& tee -a "${LOG_FILE}"
    ;;

"sles-15.5")
    printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
    sudo zypper install -y tar xz wget curl git
    configureAndInstall |& tee -a "${LOG_FILE}"
    ;;

*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "${LOG_FILE}"
    exit 1
    ;;
esac

cleanup
gettingStarted |& tee -a "${LOG_FILE}"
