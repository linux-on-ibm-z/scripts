#!/bin/bash
# © Copyright IBM Corporation 2021.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/cAdvisor/0.37.5/build_cadvisor.sh
# Execute build script: bash build_cadvisor.sh    (provide -h for help)
#

set -e

PACKAGE_NAME="cadvisor"
PACKAGE_VERSION="0.37.5"
CURDIR="$(pwd)"

GO_INSTALL_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Go/1.16.2/build_go.sh"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/cAdvisor/${PACKAGE_VERSION}/patch"

#Default GOPATH if not present already.
GO_DEFAULT="$HOME/go"

FORCE="false"
TESTS="false"
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
   mkdir -p "$CURDIR/logs/"
fi

source "/etc/os-release"

function prepare() {
	if command -v "sudo" >/dev/null; then
		printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
	else
		printf -- 'Sudo : No \n' >>"$LOG_FILE"
		printf -- 'Install sudo from a repository using apt, yum or zypper based on your distro. \n'
		exit 1
	fi

	if [[ "$FORCE" == "true" ]]; then
		printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
	else
		# Ask user for prerequisite installation
		DISTRO="$ID"
		printf -- "\nAs part of the installation , Go 1.16.2 will be installed, \n"
		while true; do
			read -r -p "Do you want to continue (y/n) ? :  " yn
			case $yn in
			[Yy]*)
				printf -- 'User responded with Yes. \n' >> "$LOG_FILE"
				break
				;;
			[Nn]*) exit ;;
			*) echo "Please provide confirmation to proceed." ;;
			esac
		done
	#fi
	fi
}

function cleanup() {
	rm -rf  "${GOPATH}/src/github.com/google/cadvisor/go_sum.patch"
	rm -rf  "${GOPATH}/src/github.com/google/cadvisor/go_mod.patch"
	rm -rf "${GOPATH}/src/github.com/google/cadvisor/test_results.log"
	rm -rf "${GOPATH}/src/github.com/google/cadvisor/failures.txt"
	rm -rf "${GOPATH}/src/github.com/google/cadvisor/expected_failures.txt"
	rm -rf "${GOPATH}/src/github.com/google/cadvisor/generated_failures.txt"
	printf -- 'Cleaned up the artifacts\n' |& tee -a "${LOG_FILE}"
}

function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'
	# Install go
	printf -- "Installing Go... \n" 
	curl $GO_INSTALL_URL | bash 
	# Install cAdvisor
	printf -- '\nInstalling cAdvisor..... \n'

	# Set GOPATH if not already set
	if [[ -z "${GOPATH}" ]]; then
		printf -- "Setting default value for GOPATH \n"
		#Check if go directory exists
		if [ ! -d "$HOME/go" ]; then
			mkdir "$HOME/go"
		fi
		export GOPATH="${GO_DEFAULT}"
		export PATH=$PATH:$GOPATH/bin
	else
		printf -- "GOPATH already set : Value : %s \n" "$GOPATH"
	fi

	printenv >> "$LOG_FILE"

	# Checkout the code from repository
	if [ ! -d "${GOPATH}/src/github.com/google" ]; then
		mkdir -p "${GOPATH}/src/github.com/google"
	fi
	
	#Remove so that there is no conflict while doing clone on subsequent tries.
	rm -rf "${GOPATH}/src/github.com/google/cadvisor" 

	cd "${GOPATH}/src/github.com/google"
	git clone https://github.com/google/cadvisor.git
	printf -- 'Cloned the cadvisor code \n'
	cd "${GOPATH}/src/github.com/google/cadvisor/"
	git checkout v${PACKAGE_VERSION}
	
	# Build cAdvisor
	cd "${GOPATH}/src/github.com/google/cadvisor/cmd"
	curl  -o "go_mod.patch" $PATCH_URL/go_mod.patch
	curl  -o "go_sum.patch" $PATCH_URL/go_sum.patch
	patch --ignore-whitespace go.mod < go_mod.patch
	patch --ignore-whitespace go.sum < go_sum.patch
	cd "${GOPATH}/src/github.com/google/cadvisor/"
	sed -i "s|-short -race|-short|" Makefile
	make build

	# Add cadvisor to /usr/bin
	sudo cp -f "${GOPATH}/src/github.com/google/cadvisor/cadvisor" /usr/bin/
	printf -- 'Build cAdvisor successfully \n' 

	# Run Tests
	runTest

	#Cleanup
	cleanup

	#Verify cadvisor installation
	if command -v "$PACKAGE_NAME" >/dev/null; then
		printf -- "%s installation completed. Please check the Usage to start the service.\n" "$PACKAGE_NAME" 
	else
		printf -- "Error while installing %s, exiting with 127 \n" "$PACKAGE_NAME"
		exit 127
	fi
}

function runTest() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- "TEST Flag is set , Continue with running test \n"
		
		cd "${GOPATH}/src/github.com/google/cadvisor"
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
	echo "  install.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests]"
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
	printf -- '\n***********************************************************************************************\n'
	printf -- "Getting Started: \n"
	printf -- "To run cAdvisor , run the following command : \n"
	printf -- "    cadvisor &   (Run in background)  \n"
	printf -- "    cadvisor -logtostderr  (Foreground with console logs)  \n\n"
	printf -- "\nAccess cAdvisor UI using the below link : "
	printf -- "http://<host-ip>:<port>/    [Default port = 8080] \n"
	printf -- '*************************************************************************************************\n'
	printf -- '\n'
}

###############################################################################################################

logDetails
prepare #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-18.04" | "ubuntu-20.04" | "ubuntu-20.10")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo apt-get update 
	sudo apt-get install -y wget git curl patch make |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

"rhel-7.8" | "rhel-7.9")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo yum install -y  wget git patch golang gcc make |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;
	
"rhel-8.1" | "rhel-8.2" | "rhel-8.3")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo yum install -y curl git golang patch make |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

"sles-12.5" | "sles-15.2")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo zypper  install -y git wget tar curl gcc patch curl make |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
