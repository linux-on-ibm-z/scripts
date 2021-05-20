#!/bin/bash
# © Copyright IBM Corporation 2021.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/HAProxy/2.3.10/build_haproxy.sh
# Execute build script: bash build_haproxy.sh    (provide -h for help)


set -e -o pipefail

PACKAGE_NAME="haproxy"
PACKAGE_VERSION="2.3.10"
CURDIR="$(pwd)"

FORCE="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
   mkdir -p "$CURDIR/logs/"
fi

source "/etc/os-release"

function prepare() {
    if  command -v "sudo" > /dev/null ;
    then
        printf -- 'Sudo : Yes\n' >> "$LOG_FILE"
    else
        printf -- 'Sudo : No \n' >> "$LOG_FILE"
        printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n';
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
    if [ -f "$CURDIR/haproxy-${PACKAGE_VERSION}.tar.gz" ]; then
		rm -rf "$CURDIR/haproxy-${PACKAGE_VERSION}.tar.gz"
        rm -rf "haproxy-${PACKAGE_VERSION}"
	fi
    printf -- "Cleaned up the artifacts\n" >> "$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

    # Download HAProxy
	cd "$CURDIR"
    wget "http://www.haproxy.org/download/2.3/src/haproxy-${PACKAGE_VERSION}.tar.gz"
    tar xzvf "haproxy-${PACKAGE_VERSION}.tar.gz"
    cd "haproxy-${PACKAGE_VERSION}"
    printf -- "Downloaded HAProxy.\n" >> "$LOG_FILE"

    # Build and install HAProxy
    make TARGET=linux-glibc
    sudo make install
    printf -- "Succesfully built and installed HAProxy.\n" >> "$LOG_FILE"

    # Add haproxy to /usr/bin
    sudo ln -sf /usr/local/sbin/haproxy /usr/sbin/

    # Cleanup
    cleanup

    # Verify haproxy installation
    if command -v /usr/local/sbin/haproxy > /dev/null; then
        printf -- "HAProxy installation verified.\n" "$PACKAGE_NAME"
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
    printf -- "\n* Getting Started * \n"
    printf -- "Running HAProxy: \n"
    printf -- "     haproxy [-f <cfgfile|cfgdir>]\n"
    printf -- "\nNote: Use sudo for users other than root \n\n"
    printf -- '********************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
    "ubuntu-18.04" | "ubuntu-20.04" | "ubuntu-21.04")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo apt-get update
        sudo apt-get install -y gcc gzip make tar wget |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;
    "rhel-7.8" | "rhel-7.9" | "rhel-8.1"| "rhel-8.2" | "rhel-8.3")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo yum install -y  gcc gzip make tar wget |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;
    "sles-12.5" | "sles-15.2")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo zypper install -y awk gcc gzip make tar wget |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;
    *)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
        exit 1
        ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
