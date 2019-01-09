#!/bin/bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/haproxy/build_haproxy.sh
# Execute build script: bash build_haproxy.sh    (provide -h for help)


set -e -o pipefail

PACKAGE_NAME="haproxy"
PACKAGE_VERSION="1.8.14"
CURDIR="$(pwd)"
BUILD_DIR="/usr/local"

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
   
    if [ -f "$BUILD_DIR/haproxy-1.8.14.tar.gz" ]; then
		 rm -rf "$BUILD_DIR/haproxy-1.8.14.tar.gz"
	fi
    printf -- "Cleaned up the artifacts\n" >> "$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"
    
    #Download HAproxy
	cd "$CURDIR"
    wget "http://www.haproxy.org/download/1.8/src/haproxy-${PACKAGE_VERSION}.tar.gz"
    tar xzvf haproxy-1.8.14.tar.gz
    mv haproxy-1.8.14 haproxy
    sudo chmod -Rf 755 haproxy
    sudo cp -Rf haproxy "$BUILD_DIR"/haproxy
    printf -- "Download HAproxy success\n" >> "$LOG_FILE"

    #Give permission to user
	sudo chown -R "$USER" "$BUILD_DIR/haproxy"
    
    #Build and install HAProxy
	cd "$BUILD_DIR"/haproxy
    make TARGET=linux26
    sudo make install
    printf -- "Build and install HAProxy success\n" >> "$LOG_FILE"

    #Add haproxy to /usr/bin
    sudo cp haproxy /usr/bin/
    	
    #cleanup
    cleanup


    #Verify haproxy installation
    if command -v "$PACKAGE_NAME" > /dev/null; then 
        printf -- " %s Installation verified.\n" "$PACKAGE_NAME" 
    else
        printf -- "Error while installing %s, exiting with 127 \n" "$PACKAGE_NAME";
        exit 127;
    fi
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
    echo " build_haproxy.sh  [-d debug] [-y install-without-confirmation]"
    echo
}


while getopts "h?dy" opt; do
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
    esac
done


function gettingStarted() {
    printf -- '\n********************************************************************************************************\n'
    printf -- "\n*Getting Started * \n"
    printf -- "Running haproxy: \n"
    printf -- "haproxy  \n\n"

    printf -- "Command to use with config file\n"
    printf -- "haproxy -f haproxy.config \n"
    printf -- "\nNote: use sudo for users other than root \n"
    printf -- "You have successfully started haproxy.\n"
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
        sudo apt-get install -y wget tar make gcc curl |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;
    "rhel-6.x" |"rhel-7.3" | "rhel-7.4" | "rhel-7.5")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo yum install -y wget tar make gcc unzip curl |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;
    "sles-12.3")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo zypper install -y  tar make gcc curl wget unzip awk |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;
    *)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
        exit 1
        ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
