#!/bin/bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/CFSSL/1.3.4/build_cfssl.sh
# Execute build script: bash build_cfssl.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="CFSSL"
PACKAGE_VERSION="1.3.4"
SOURCE_ROOT="$(pwd)"

GO_DEFAULT="$HOME/go"

FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
    mkdir -p "$SOURCE_ROOT/logs/"
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
	rm -rf $SOURCE_ROOT/build_go.sh
    	printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function install_go() {

	#Install Go
	
	printf -- "\n Installing go \n" |& tee -a "$LOG_FILE"    
	cd $SOURCE_ROOT
	wget "https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Go/1.13/build_go.sh" |& tee -a "$LOG_FILE" 
    	chmod +x build_go.sh
    	bash build_go.sh -v 1.12.7 |& tee -a "$LOG_FILE"

    	printf -- "Completed go installation successfully. \n" >>"$LOG_FILE"
}
function configureAndInstall() {
    	printf -- "Configuration and Installation started \n"
	printf -- "Build and install CFSSL \n"
	
	#Installing CFSSL
	cd $SOURCE_ROOT
	go get -u github.com/cloudflare/cfssl/cmd/cfssl
	go get -u github.com/cloudflare/cfssl/cmd/cfssljson
	cd $GOPATH/src/github.com/cloudflare/cfssl
	git checkout 1.3.4
	
	printf -- 'CFSSL installed successfully. \n'
	printf -- "The tools will be installed in $GOPATH/bin."
	
	#runTests
	runTest    
}

function runTest() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- "\nTEST Flag is set, continue with running test \n"
		cd $GOPATH/src/github.com/cloudflare/cfssl
		./test.sh
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
    echo " build_cfssl.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests] "
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
    printf -- "	CFSSL installed successfully. \n"
    printf -- "More information can be found here : https://github.com/cloudflare/cfssl \n"
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
	sudo apt-get install -y git gcc make |& tee -a "$LOG_FILE"
	install_go 
	export GOPATH=$SOURCE_ROOT
	export PATH=$GOPATH/bin:$PATH
	configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-7.5" | "rhel-7.6" | "rhel-8.0")
    	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    	printf -- "Installing dependencies... it may take some time.\n"
	sudo yum install -y git gcc make wget |& tee -a "$LOG_FILE"
    	install_go 
	export GOPATH=$SOURCE_ROOT
	export PATH=$GOPATH/bin:$PATH
	configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-12.4" | "sles-15")
    	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    	printf -- "Installing dependencies... it may take some time.\n"
	sudo zypper install -y git gcc make wget |& tee -a "$LOG_FILE"
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


