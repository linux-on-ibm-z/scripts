#!/bin/bash
# © Copyright IBM Corporation 2018.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)

set -e

PACKAGE_NAME="cadvisor"
PACKAGE_VERSION="0.27.4"
CURDIR="$(pwd)"
GO_DEFAULT="$HOME/go"
GO_INSTALL_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Go/install.sh"
REPO_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/CAdvisor/files"
FORCE="false"
LOG_FILE="${CURDIR}/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

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
		printf -- 'Force attribute provided hence continuing with install without confirmation message' | tee -a "$LOG_FILE"
	else
		# Ask user for prerequisite installation
		printf -- "\n\nAs part of the installation , Go 1.10.1 will be installed, \n";
		while true; do
    		read -r -p "Do you want to continue (y/n) ? :  " yn
    		case $yn in
      	 		[Yy]* ) printf -- 'User responded with Yes. \n' | tee -a "$LOG_FILE"; 
					break;;
        		[Nn]* ) exit;;
        		* ) 	echo "Please provide confirmation to proceed.";;
   		 	esac
		done
	fi	
}

function cleanup() {
	rm -rf "${GOPATH}/src/github.com/google/cadvisor"
	rm -rf "${CURDIR}/crc32.go"
	printf -- 'Cleaned up the artifacts\n' >>"$LOG_FILE"
}

function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'

	# Install go
	printf -- "Installing Go... \n" | tee -a "$LOG_FILE"
    curl -s $GO_INSTALL_URL | bash

	# Install cAdvisor
	printf -- '\nInstalling cAdvisor..... \n'
       
	# Set GOPATH if not already set
	if [[ -z "${GOPATH}" ]]; then
		printf -- "Setting default value for GOPATH \n" >>"$LOG_FILE"
		
       	#Check if go directory exists
       	if [ ! -d "$HOME/go" ]; then
              mkdir "$HOME/go"
        fi
       	export GOPATH="${GO_DEFAULT}"
		export PATH=$PATH:$GOPATH/bin
	else
		printf -- "GOPATH already set : Value : %s \n" "$GOPATH" >> "$LOG_FILE"
	fi
		
	printenv >> "$LOG_FILE"
	
	#  Install godep tool
	cd "$GOPATH"
	go get github.com/tools/godep
	printf -- 'Installed godep tool at GOPATH \n' >> "$LOG_FILE"

	# Checkout the code from repository
	mkdir -p "${GOPATH}/src/github.com/google"
	cd "${GOPATH}/src/github.com/google"
	printf -- 'Cloning the cadvisor code \n' >> "$LOG_FILE"
	git clone -b "v${PACKAGE_VERSION}" -q https://github.com/google/cadvisor.git >> "${LOG_FILE}"
	printf -- 'Cloned the cadvisor code \n' >> "$LOG_FILE"
    
	cd "${CURDIR}"
	
	# get config file (NEED TO REPLACE WITH LINK OF ORIGINAL REPO)
	wget -q $REPO_URL/crc32.go
	
	# Replace the crc32.go file
	cp crc32.go "${GOPATH}/src/github.com/google/cadvisor/vendor/github.com/klauspost/crc32/"
	
	# Build cAdvisor
	cd "${GOPATH}/src/github.com/google/cadvisor"
	godep go build .
	
	# Add cadvisor to /usr/bin
	cp "${GOPATH}/src/github.com/google/cadvisor/cadvisor"  /usr/bin/
	printf -- 'Build cAdvisor successfully \n' >> "$LOG_FILE"
	
	#Cleanup
	cleanup
	
	#Verify cadvisor installation		
	if  command -v "$PACKAGE_NAME" > /dev/null ; then		
    	printf -- "%s installation completed. Please check the Usage to start the service.\n" "$PACKAGE_NAME" | tee -a "$LOG_FILE"
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
    
    cat /proc/version >> "$LOG_FILE"
	printf -- '*********************************************************************************************************\n' >>"$LOG_FILE"

	printf -- "Detected %s \n" "$PRETTY_NAME"
	printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" | tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
	echo
	echo "Usage: "
	echo "  install.sh  [-d <debug>] [-v package-version] [-y install-without-confirmation]"
	echo "       default: If no -v specified, latest version will be installed"
	echo
}

while getopts "h?dyv:" opt; do
	case "$opt" in
	h | \?)
		printHelp
		exit 0
		;;
	d)
		set -x
		;;
	v)
		PACKAGE_VERSION="$OPTARG"
		;;
	y)
		FORCE="true"
	esac
done

function printSummary() {
	printf -- '\n***************************************************************************************\n'
	printf -- "Getting Started: \n"
	printf -- "To run Cadvisor , run the following command : \n"
	printf -- "    cadvisor &   (Run in background)  \n"
	printf -- "    cadvisor -logtostderr  (Foreground with console logs)  \n\n"
	printf -- "\nAccess cAdvisor UI using the below link : "
	printf -- "http://<host-ip>:<port>/    [Default port = 8080] \n"
	printf -- '***************************************************************************************\n'
	printf -- '\n'
}

###############################################################################################################

logDetails
prepare #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
	sudo apt-get -qq update > /dev/null
	sudo apt-get -qq install  wget git libseccomp-dev curl  > /dev/null
	configureAndInstall
	;;

"rhel-7.3" | "rhel-7.4" | "rhel-7.5")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
	sudo yum install -y -q wget git libseccomp-devel > /dev/null
	configureAndInstall
	;;

"sles-12.3" | "sles-15")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
	sudo zypper install -y -q git libseccomp-devel wget tar curl gcc > /dev/null
	configureAndInstall
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" | tee -a "$LOG_FILE"
	exit 1
	;;
esac

printSummary
