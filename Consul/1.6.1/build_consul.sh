#!/bin/bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Consul/1.6.1/build_consul.sh
# Execute build script: bash build_consul.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="consul"
PACKAGE_VERSION="1.6.1"
CURDIR="$(pwd)"
GOPATH=$CURDIR
#Default GOPATH if not present already.
GO_DEFAULT="$HOME/go"
GO_ROOT_DEFAULT="/usr/local/go"
GO_INSTALL_URL=" https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Go/1.13/build_go.sh"
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

    rm -rf "$CURDIR/go${GO_VERSION}.linux-s390x.tar.gz"
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

    #Download Go
    wget $GO_INSTALL_URL && bash build_go.sh -y -v 1.12.5
    go version
    printf -- "Install Go success\n"

    # Set GOPATH if not already set
        if [[ -z "${GOPATH}" ]]; then
                printf -- "Setting default value for GOPATH \n"

                #Check if go directory exists
                if [ ! -d "${GO_DEFAULT}" ]; then
                        mkdir "${GO_DEFAULT}"
                fi

        #Check if go directory exists
                if [ ! -d "${GO_ROOT_DEFAULT}" ]; then
                        mkdir -p "${GO_ROOT_DEFAULT}"
                fi

                export GOPATH="${GO_DEFAULT}"
                export GOROOT="${GO_ROOT_DEFAULT}"
        #Check if bin directory exists
                if [ ! -d "$GOPATH/bin" ]; then
                        mkdir "$GOPATH/bin"
                fi
        if [ ! -d "$GO_ROOT_DEFAULT/bin" ]; then
                        mkdir "$GO_ROOT_DEFAULT/bin"
                fi
                export PATH=$PATH:$GOPATH/bin
        export PATH=$PATH:$GOROOT/bin
        else
                printf -- "GOPATH already set : Value : %s \n" "$GOPATH"
        fi
        printenv >>"$LOG_FILE"

    #Build and install consul

    mkdir -p $GOPATH/src/github.com/hashicorp
    cd $GOPATH/src/github.com/hashicorp
     #Check if consul directory exists
        if [ -d "$PACKAGE_NAME" ]; then
                rm -rf  "$PACKAGE_NAME"
        fi
    git clone -b v${PACKAGE_VERSION} https://github.com/hashicorp/consul.git
    cd consul

    go get -u github.com/SAP/go-hdb/...
   
    make tools
    make dev

    # Create a symlink
    sudo ln -s $GOPATH/src/github.com/hashicorp/consul/bin/consul /usr/bin/consul
    printf -- "Build and install consul success\n"

    #Run Test
    runTest

    #cleanup
  #  cleanup

    #Verify consul installation
    if command -v "consul" >/dev/null; then
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
        sudo sysctl -w net.ipv6.conf.all.disable_ipv6=0
        sudo sysctl -w net.ipv6.conf.default.disable_ipv6=0
        cd $GOPATH/src/github.com/hashicorp/consul/
        make test 2>&1 | tee -a maketestlog
        cat maketestlog | grep "FAIL" | grep github.com | awk '{print $2}' >>test.txt
        if [ -s $GOPATH/src/github.com/hashicorp/consul/test.txt ]; then
            printf -- '*****************************************************************************************************************************\n'
            printf -- '\nUnexpected test failures detected. Tip : Try running them individually as go test -v <package_name> -run <failed_test_name>
                                         or increasing the timeout using -timeout option to go test command.\n'
            printf -- '*****************************************************************************************************************************\n'
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
    echo " build_consul.sh  [-d debug] [-y install-without-confirmation] [-t install and run tests]"
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
    printf -- "Running consul: \n"
    printf -- "nohup consul agent -dev & \n\n"
    printf -- "You have successfully started consul.\n"
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
    sudo apt-get install -y curl gcc git make wget  |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-7.5" | "rhel-7.6" | "rhel-7.7"| "rhel-8.0")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y  curl gcc git make wget |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-12.4" | "sles-15" | "sles-15.1")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y curl gcc git make wget  |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
