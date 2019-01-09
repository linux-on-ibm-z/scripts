#!/bin/bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Heketi/build_heketi.sh
# Execute build script: bash build_heketi.sh    (provide -h for help)



set -e -o pipefail

PACKAGE_NAME="heketi"
PACKAGE_VERSION="8.0.0"
GLIDE_VERSION="v0.13.1"

CURDIR="$(pwd)"
GO_DEFAULT="$HOME/go"

GO_INSTALL_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Go/build_go.sh"

FORCE="false"
TESTS="false"
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
    cat /etc/redhat-release >> "${LOG_FILE}"
    export ID="rhel"
    export VERSION_ID="6.x"
    export PRETTY_NAME="Red Hat Enterprise Linux 6.x"
fi


function prepare() {
    if  command -v "sudo" > /dev/null ;
    then
        printf -- 'Sudo : Yes\n' >> "$LOG_FILE"
    else
        printf -- 'Sudo : No \n' >> "$LOG_FILE"
        printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n';
    exit 1;
    fi;
   
    if [[ "$FORCE" == "true" ]] ;
    then
        printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
    else
        # Ask user for prerequisite installation
        printf -- "\nAs part of the installation , dependencies would be installed/upgraded.\n";
        while true; do
		    read -r -p "Do you want to continue (y/n) ? :  " yn
		    case $yn in
  	 		    [Yy]* ) printf -- 'User responded with Yes. \n' >> "$LOG_FILE"; 
	                    break;;
    		    [Nn]* ) exit;;
    		    *) 	echo "Please provide confirmation to proceed.";;
	 	    esac
        done
    fi	
}


function cleanup() {
    # Remove artifacts
    rm -rf "~/$GOPATH/glide-$GLIDE_VERSION-linux-s390x.tar.gz*"
    printf -- "Cleaned up the artifacts\n" >> "$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"
    
    # Install go
	printf -- "Installing Go... \n" 
	wget  $GO_INSTALL_URL 
    bash build_go.sh -v 1.10.5


	# Set GOPATH if not already set
	if [[ -z "${GOPATH}" ]]; then
		printf -- "Setting default value for GOPATH \n"

		#Check if go directory exists
		if [ ! -d "$HOME/go" ]; then
			mkdir "$HOME/go"
		fi
		
		export GOPATH="${GO_DEFAULT}"
		
        #Check if bin directory exists
		if [ ! -d "$GOPATH/bin" ]; then
			mkdir "$GOPATH/bin"
		fi
		export PATH=$PATH:$GOPATH/bin
	else
		printf -- "GOPATH already set : Value : %s \n" "$GOPATH" 
	fi
	printenv >>"$LOG_FILE"

    # Install glide

    cd "$GOPATH"
    wget https://github.com/Masterminds/glide/releases/download/"$GLIDE_VERSION"/glide-"$GLIDE_VERSION"-linux-s390x.tar.gz
    tar -xzf glide-"$GLIDE_VERSION"-linux-s390x.tar.gz
    export PATH=$GOPATH/linux-s390x:$PATH
    glide --version
    printf -- "Install glide success\n" >> "$LOG_FILE"
  
    # Build heketi
    if [ -d "$GOPATH/src/github.com/heketi/heketi" ]; then
    	echo "Heketi folder already exists, removing it to continue with the installation";
		rm -rf "$GOPATH/src/github.com/heketi/heketi"
	fi
        
	git clone -b v"${PACKAGE_VERSION}" https://github.com/heketi/heketi.git "$GOPATH/src/github.com/heketi/heketi"
    cd "$GOPATH/src/github.com/heketi/heketi"
    
    #configure git to use ssl
    git config --global http.sslVerify true
    
    make
    printf -- "Build and install heketi success\n" >> "$LOG_FILE"

    # Add heketi to /usr/bin
	sudo cp "$GOPATH/src/github.com/heketi/heketi/heketi" /usr/bin/
    
    # Create heketi lib directory
     #Check if lib directory exists
		if [ ! -d /var/lib/heketi ]; then
		    sudo mkdir -p /var/lib/heketi/
		fi


    #Add heketi config
	if [ ! -d "/etc/heketi" ]; then
		printf -- "Created heketi config Directory at /etc" 
		sudo mkdir /etc/heketi/
	fi
    sudo cp "$GOPATH/src/github.com/heketi/heketi/etc/heketi.json" /etc/heketi/heketi.json

    # Run Tests
	runTest

    #cleanup
    cleanup

    #Verify heketi installation
    if command -v "$PACKAGE_NAME" > /dev/null; then 
        printf -- " %s Installation verified.\n" "$PACKAGE_NAME" 
    else
        printf -- "Error while installing %s, exiting with 127 \n" "$PACKAGE_NAME";
        exit 127;
    fi

}

function runTest() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- "TEST Flag is set, continue with running test \n"  >> "$LOG_FILE"
		cd "$GOPATH/src/github.com/heketi/heketi"
        make test
        printf -- "Tests completed. \n" 
	fi
	set -e
}

function logDetails() {
    printf -- '**************************** SYSTEM DETAILS *************************************************************\n' >"$LOG_FILE"
    if [ -f "/etc/os-release" ]; then
        cat "/etc/os-release" >> "$LOG_FILE"
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
    echo " install.sh  [-d debug] [-y install-without-confirmation] [-t install and run tests]"
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
    printf -- "Running heketi: \n"
    printf -- "heketi  \n\n"

    printf -- "Command to use with config file\n"
    printf -- "sudo heketi --config=/etc/heketi/heketi.json \n"
    printf -- "You have successfully started heketi.\n"
    printf -- '**********************************************************************************************************\n'
}
    
logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
    "ubuntu-16.04" | "ubuntu-18.04")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo apt-get update
        sudo apt-get install -y git wget make python mercurial curl |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;
    "rhel-7.3" | "rhel-7.4" | "rhel-7.5")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo yum install -y git wget gcc make tar which mercurial curl |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;
    "sles-12.3" | "sles-15")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo zypper install -y  git wget gcc make tar which python mercurial curl |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;
    *)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
        exit 1
        ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
