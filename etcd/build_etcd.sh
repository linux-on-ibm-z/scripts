#!/bin/bash
# © Copyright IBM Corporation 2018, 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/etcd/build_etcd.sh
# Execute build script: bash build_etcd.sh    (provide -h for help)


set -e -o pipefail
PACKAGE_NAME="etcd"
PACKAGE_VERSION="3.3.12"
CURDIR="$(pwd)"

CONFIG_ETCD="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/etcd/conf/etcd.conf.yml"


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
        printf -- "\nAs part of the installation , Go 1.10.x will be installed, \n";
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
    rm -rf "${GOPATH}/src/github.com/coreos/etcd"
    printf -- "Cleaned up the artifacts\n" >> "$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"
    
    #GO Installation
    if [[ "$ID" != "ubuntu" ]];then
    printf -- "\n\n Installing Go \n" 
    cd $HOME
    wget https://storage.googleapis.com/golang/go1.10.3.linux-s390x.tar.gz
    chmod ugo+r go1.10.3.linux-s390x.tar.gz
    sudo tar -C /usr/local -xzf go1.10.3.linux-s390x.tar.gz
    export PATH=$PATH:/usr/local/go/bin
    sudo ln /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
    fi    
    
    # Install etcd
    printf -- 'Installing etcd..... \n'
            
    # Set GOPATH if not already set
    if [[ -z "${GOPATH}" ]];then
        printf -- "Setting default value for GOPATH \n" 
        
        #Check if directory exsists
        if [ ! -d "$HOME/go" ];then
            mkdir "$HOME/go"
        fi

        export GOPATH="$HOME/go"
        export PATH=$PATH:$GOPATH/bin
    else
        printf -- "GOPATH already set : Value : %s \n" "$GOPATH"
    fi
    
    printenv >> "$LOG_FILE"
    
    #ETCD_DATA_DIR path
    if [[ -z "${ETCD_DATA_DIR}" ]]; then
        printf -- "Setting default value for ETCD \n" 
        if [ ! -d "$GOPATH/etcd" ];
        then
            mkdir -p "/$GOPATH/etcd"
        fi
            export ETCD_DATA_DIR=/$GOPATH/etcd
        else
            printf -- "ETCD_DATA_DIR already set \n" 
    fi
    
    printenv >> "$LOG_FILE"
    
    # Checkout the code from repository
    cd "${GOPATH}"
    mkdir -p "/${GOPATH}/src/github.com/coreos"
    cd "/${GOPATH}/src/github.com/coreos"
    
    printf -- 'Cloning etcd code \n' 
    git clone http://github.com/coreos/etcd 
    cd etcd
    git checkout "v${PACKAGE_VERSION}" 
    printf -- 'Cloned the etcd code \n' 
    
    # Build etcd
    printf -- "\nBuilding etcd\n" 
    ./build

    #Get etcd.conf.yml in /etc/etcd/
    if [ ! -d /etc/etcd ];then
        sudo mkdir /etc/etcd/
    fi

    curl $CONFIG_ETCD | sudo tee /etc/etcd/etcd.conf.yml
    printf -- "Added etcd.conf.yml in /etc/etcd \n" 
            
    # Add etcd to /usr/bin
    sudo cp "${GOPATH}/src/github.com/coreos/etcd/bin/etcd" /usr/bin/            
    printf -- 'etcd built successfully \n' 

    #Run tests
    runTest
    
    #cleanup
    cleanup

    #Verify etcd installation
    if command -v "$PACKAGE_NAME" > /dev/null; then 
        printf -- " %s Installation verified.\n" "$PACKAGE_NAME" 
    else
        printf -- "Error while installing %s, exiting with 127 \n" "$PACKAGE_NAME";
        exit 127;
    fi

}
#Tests function
function runTest() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- "TEST Flag is set, continue with running test \n"
		cd "${GOPATH}/src/github.com/coreos/etcd"
		PASSES='bom dep build unit' ./test
		printf -- "Tests completed. \n" |& tee -a "$LOG_FILE"
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
    printf -- "Running etcd: \n"
    printf -- "     etcd  \n\n"
    printf -- "In case of error etcdmain: etcd on unsupported platform without ETCD_UNSUPPORTED_ARCH=s390x , set following\n"
    printf -- "     export ETCD_UNSUPPORTED_ARCH=s390x \n"
    printf -- "etcd will listen on port 2379 for client communication and on port 2380 for server-to-server communication.\n"
    printf -- "Next, let's set a single key, and then retrieve it:\n"
    printf -- "     curl -L http://127.0.0.1:2379/v2/keys/mykey -XPUT -d value='this is awesome' \n"
    printf -- "     curl -L http://127.0.0.1:2379/v2/keys/mykey \n"
    printf -- "\nThe Configuration file can be found in  /etc/etcd/etcd.conf.yml \n"
    printf -- "Command to use with config file\n"
    printf -- "     etcd --config-file=/etc/etcd/etcd.conf.yml \n"
    printf -- "You have successfully started etcd and written a key to the store.\n"
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
        sudo apt-get install -y git curl wget tar gcc golang-1.10 |& tee -a "${LOG_FILE}"
	export PATH=/usr/lib/go-1.10/bin:$PATH 
	go version
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;
    "rhel-7.4" | "rhel-7.5" | "rhel-7.6")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo yum install -y curl git wget tar gcc which |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;
    "sles-12.3" | "sles-15")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo zypper install -y  curl git wget tar gcc which |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;
    *)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
        exit 1
        ;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
