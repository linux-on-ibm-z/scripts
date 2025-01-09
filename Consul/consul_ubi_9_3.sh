#!/bin/bash
# Package	    : Consul
# Version	    : v1.20.2
# Source repo	    : https://github.com/hashicorp/consul.git
# Tested on	    : UBI: 9.3
# Language          : go
# Travis-Check      : True
# Script License    : Apache License, Version 2 or later
# Maintainer	    : Firoj Patel <Firoj.Patel@ibm.com> 
#
# Disclaimer: This script has been tested in root mode on given
# ==========  platform using the mentioned version of the package.
#             It may not work as expected with newer versions of the
#             package and/or distribution. In such case, please
#             contact "Maintainer" of this script.
#
# ----------------------------------------------------------------------------

set -e -o pipefail

PACKAGE_NAME="Consul"
PACKAGE_VERSION=${1:-"1.20.2"}
GO_VERSION="1.18.8"
SOURCE_ROOT="$(pwd)"

GO_DEFAULT="$HOME/go"
FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
    mkdir -p "$SOURCE_ROOT/logs/"
fi

source "/etc/os-release"

yum install -y sudo

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
    fi
}

function cleanup() {
    # Remove artifacts
	rm -rf $SOURCE_ROOT/build_go.sh
    	printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function install_go() {

	#Install Go 
	
	printf -- "\n Installing go ${GO_VERSION} \n" |& tee -a "$LOG_FILE"    
	cd $SOURCE_ROOT
	wget https://golang.org/dl/go${GO_VERSION}.linux-s390x.tar.gz
	sudo tar -C /usr/local -xvzf go${GO_VERSION}.linux-s390x.tar.gz
	export PATH=/usr/local/go/bin:$PATH
	
	if [[ "${ID}" != "ubuntu" ]]
    	then
        sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
        printf -- 'Symlink done for gcc \n'
    	fi
	   

    	printf -- "Completed go installation successfully. \n" >>"$LOG_FILE"
}
function configureAndInstall() {
    printf -- "Configuration and Installation started \n"
    
    if ! [[ $DISTRO =~ "ubuntu" ]]
    then
      sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
    fi
    
    # Install Go
    printf -- 'Installing go\n'
    cd ${GOPATH}
    wget https://go.dev/dl/go${GO_VERSION}.linux-s390x.tar.gz
    tar -xzf go${GO_VERSION}.linux-s390x.tar.gz
    
    sudo rm -rf /usr/local/go /usr/bin/go
    sudo ln -sf $GOPATH/go/bin/go /usr/bin/ 
    sudo ln -sf $GOPATH/go/bin/gofmt /usr/bin/

    go version
    printf -- "Install Go success\n"

    # Build and install consul
    mkdir -p $GOPATH/src/github.com/hashicorp
    cd $GOPATH/src/github.com/hashicorp
    rm -rf consul

    printf -- "Building and installing consul\n"
    git clone --depth 1 -b v${PACKAGE_VERSION} https://github.com/hashicorp/consul.git
    cd consul
    make tools
    make dev

    # Create a symlink
    sudo ln -sf $GOPATH/bin/consul /usr/bin/consul
    printf -- "Build and install consul success\n"

    # Run Test
    runTest

    cd "$SOURCE_ROOT"

    # Verify consul installation
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
        printf -- 'Running consul tests \n\n'
        cd $GOPATH/src/github.com/hashicorp/consul/
  
	printf -- 'Increasing go test and ci timeout \n\n'
        sed -i "s/timeout: 10m/timeout: 2h/1" .golangci.yml
        sed -i "s/  go test -v/  go test -v -timeout=2h/1" Makefile

        make test 2>&1 | tee -a maketestlog
        grep "FAIL" maketestlog | grep github.com | awk '{print $2}' >>test.txt

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
    echo "bash build_consul.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests] "
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
    printf -- "	Consul installed successfully. \n"
    printf -- "The tools is installed at $GOPATH/bin. \n"
    printf -- "More information can be found here : https://github.com/hashicorp/consul \n"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"ubuntu-18.04" | "ubuntu-20.04" | "ubuntu-22.04" | "ubuntu-22.10")
    	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    	printf -- "Installing dependencies... it may take some time.\n"
    	sudo apt-get update
	sudo apt-get install -y git gcc make curl wget tar |& tee -a "$LOG_FILE"
	install_go 
	export GOPATH=$SOURCE_ROOT
	export PATH=$GOPATH/bin:$PATH
	configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-7.8" | "rhel-7.9" | "rhel-8.4" | "rhel-8.6" | "rhel-8.7" | "rhel-9.0" | "rhel-9.1" | "rhel-9.3")
    	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    	printf -- "Installing dependencies... it may take some time.\n"
	sudo yum install -y git gcc make wget tar |& tee -a "$LOG_FILE"
    	install_go 
	export GOPATH=$SOURCE_ROOT
	export PATH=$GOPATH/bin:$PATH
	configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-12.5" | "sles-15.3" | "sles-15.4")
    	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    	printf -- "Installing dependencies... it may take some time.\n"
	sudo zypper install -y git gcc make wget curl tar gzip |& tee -a "$LOG_FILE"
	install_go 
	export GOPATH=$SOURCE_ROOT
	export PATH=$GOPATH/bin:$PATH
    	configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"