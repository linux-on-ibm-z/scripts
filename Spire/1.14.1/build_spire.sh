#!/usr/bin/env bash
# © Copyright IBM Corporation 2026.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Spire/1.14.1/build_spire.sh
# Execute build script: bash build_spire.sh    (provide -h for help)

set -e -o pipefail

SOURCE_ROOT="$(pwd)"
PACKAGE_NAME="Spire"
PACKAGE_VERSION="1.14.1"
FORCE="false"
TEST="false"
OVERRIDE="false"
LOG_FILE="$SOURCE_ROOT/logs/$PACKAGE_NAME-$PACKAGE_VERSION-$(date +"%F-%T").log"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Spire/$PACKAGE_VERSION/patch"

trap 0 1 2 ERR

#Check if directory exsists
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
        printf -- 'You can install sudo from repository using apt, yum or zypper based on your distro. \n'
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
    printf -- 'Configuration and Installation started \n'
    cd $SOURCE_ROOT
    git clone -b v$PACKAGE_VERSION https://github.com/spiffe/spire.git
    cd spire/
    curl -sSL $PATCH_URL/spire.patch | git apply - 
    make 
    printf -- 'Build Complete \n'
    runTests
}

function runTests() {
    set +e
    if [[ "$TESTS" == "true" ]]; then
        printf -- "TEST Flag is set, continue with running test \n"

        cd $SOURCE_ROOT/spire
        make test
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
    echo "  bash build_spire.sh [-y install-without-confirmation] [-t run-test-cases]"
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
    printf -- "\n* Binaries can be found under $SOURCE_ROOT/spire/bin folder. * \n"
    printf -- "\n* Refer https://spiffe.io/docs/latest/try/getting-started-linux-macos-x/#starting-the-spire-server to start the server and agent.* \n"
    printf -- '\n\n**********************************************************************************************************\n'
}

###############################################################################################################

logDetails
DISTRO="$ID-$VERSION_ID"
checkPrequisites #Check Prequisites

case "$DISTRO" in
"rhel-8.10" | "rhel-9.4" | "rhel-9.6" | "rhel-9.7" | "rhel-10.0" | "rhel-10.1")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
    if [[ "$DISTRO" == rhel-9* || "$DISTRO" == rhel-10* ]]; then
        sudo yum install --allowerasing -y curl wget git make gcc openssl-devel |& tee -a "$LOG_FILE"
    else
        sudo yum install -y curl wget git make gcc openssl-devel |& tee -a "$LOG_FILE"
    fi
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"sles-15.7" | "sles-16.0")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
    sudo zypper install -y curl wget git-core make gcc openssl-devel which tar gzip awk |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"ubuntu-22.04" | "ubuntu-24.04" | "ubuntu-25.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
    sudo apt-get update >/dev/null
    sudo apt-get install -y curl wget git make gcc libssl-dev libc6-dev |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
