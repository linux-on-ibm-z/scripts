#!/bin/bash
# © Copyright IBM Corporation 2018.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Prometheus/build_prometheus.sh
# Execute build script: bash build_prometheus.sh    (provide -h for help)
#

set -e -o pipefail

PACKAGE_NAME="prometheus"
PACKAGE_VERSION="2.4.2"
CURDIR="$(pwd)"

GO_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Go/build_go.sh"
CONFIG_PROM="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Prometheus/conf/prometheus.yml"
TEST_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Prometheus/patch/Makefile.common.diff"

FORCE="false"
TESTS="false"

LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
trap cleanup 0 1 2 ERR 

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
	mkdir -p "$CURDIR/logs/"
fi

# Need handling for RHEL 6.10 as it doesn't have os-release file
if [ -f "/etc/os-release" ];then
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
           
    if command -v "go" > /dev/null;
    then
        printf -- "Go : Yes\n";
    else
        printf -- "Go : No \n";
        printf -- "This setup includes installation of Go.\n";
    fi

    if command -v $PACKAGE_NAME > /dev/null;
    then
        printf -- "%s : Yes \n" "$PACKAGE_NAME" |& tee -a  "$LOG_FILE"
        printf -- "\nYou already have the package installed on ur system.\n"
    else
        printf -- "%s : No \n" "$PACKAGE_NAME" ;
        printf -- 'Package not present on system \n\n'
    fi;

    if [[ "$FORCE" == "true" ]] ;
	then
	    printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
	else
		# Ask user for prerequisite installation
		printf -- "As part of the installation , Go 1.10.1 will be installed, \n";
		while true; do
    		read -r -p "Do you want to continue (y/n) ? :  " yn
    		case $yn in
      	 		[Yy]* ) printf -- 'User responded with Yes. \n' 
				        break;;
        		[Nn]* ) exit;;
        		*) 	echo "Please provide confirmation to proceed.";;
   		 	esac
		done
	fi	
}

function cleanup() {
    # Remove artifacts
    rm -rf "${GOPATH}/src/github.com/prometheus"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

    #GO Installation
    printf -- "\n\n Installing Go \n" 
    curl $GO_URL | bash
        
    # Install prometheus
    printf -- 'Installing prometheus..... \n'
                
    # Set GOPATH if not already set
    if [[ -z "${GOPATH}" ]];then
        printf -- "Setting default value for GOPATH \n" 
            
        #Check if directory exists
        if [ ! -d "$HOME/go" ];then
            mkdir "$HOME/go"
        fi
        export GOPATH="$HOME/go"
        export PATH=$PATH:$GOPATH/bin
    else
        printf -- "GOPATH already set : Value : %s \n" "$GOPATH" 
    fi
    
    printenv >> "$LOG_FILE"

    # Checkout the code from repository
    cd "${GOPATH}"
    mkdir -p "$GOPATH/src/github.com/prometheus"
    cd "$GOPATH/src/github.com/prometheus"
    printf -- 'Cloning Prometheus code \n'
    
    if [ -d prometheus ];then
        rm -rf prometheus
    fi
    
    git clone -b "v${PACKAGE_VERSION}"  https://github.com/prometheus/prometheus.git       
    printf -- 'Cloned the prometheus code \n' 

    # Build prometheus
    printf -- "\nBuilding prometheus\n"
    cd prometheus
    make build

    #Get a prometheus.yml in etc/prometheus/
    if [ ! -d /etc/prometheus ];then
        sudo mkdir /etc/prometheus/
    fi

    curl $CONFIG_PROM | sudo tee /etc/prometheus/prometheus.yml
    printf -- "Added prometheus.yml in /etc/prometheus \n" 
    
    # Add prometheus to /usr/bin
    sudo cp "${GOPATH}/src/github.com/prometheus/prometheus/prometheus" /usr/bin/                        
    printf -- 'Build prometheus successfully \n' 
          
    #Run tests
    runTest

    #Cleanup
	cleanup

    #Verify prometheus installation
    if command -v "$PACKAGE_NAME" > /dev/null; then 
        printf -- " %s Installation verified... continue with prometheus installation...\n" "$PACKAGE_NAME" 
    else
        printf -- "Error while installing %s, exiting with 127 \n" "$PACKAGE_NAME";
        exit 127;
    fi
}

function runTest() {

	if [[ "$TESTS" == "true" ]]; then
		printf -- "TEST Flag is set. continue with running test \n"
        cd $GOPATH/src/github.com/prometheus/prometheus
        
        pwd
        #Applying Patch to fix test_ssl
        printf -- "\nApplying patch file"
        curl -o "patch.diff" $TEST_URL
        patch Makefile.common < patch.diff
		make test 
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
    echo " install.sh  [-d debug] [-y install-without-confirmation]"
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
        exit 0
    ;;
    t)
        TESTS="true"
        ;;
    esac
done

function gettingStarted() {
    printf -- '\n***************************************************************************************\n'
    printf -- "\n\n* Getting Started * \n"
    printf -- "\nRunning prometheus: \n"
    printf -- " prometheus --config.file=/etc/prometheus/prometheus.yml  \n\n"
    printf -- "The Config file prometheus.yml can be found in  /etc/prometheus/ \n\n"
    printf -- " Access Prometheus on browser\n"
	printf -- "Open http://<ip_address>:9090 in your browser to access Web UI. \n"
	printf -- '***************************************************************************************\n'
}
        
logDetails
prepare #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
    "ubuntu-16.04" | "ubuntu-18.04")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        sudo apt-get update
        sudo apt-get install -y make cmake gcc g++ wget tar git curl |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

    "rhel-7.3" | "rhel-7.4" | "rhel-7.5")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        sudo yum install -y make cmake gcc wget tar git curl |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

    "sles-12.3" | "sles-15")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        sudo zypper install -y make cmake gcc gcc-c++ wget tar git curl |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

    *)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
        exit 1
        ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
