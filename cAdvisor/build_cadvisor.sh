#!/bin/bash
# © Copyright IBM Corporation 2018, 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/cAdvisor/build_cadvisor.sh
# Execute build script: bash build_cadvisor.sh    (provide -h for help)
#

set -e

PACKAGE_NAME="cadvisor"
PACKAGE_VERSION="0.32.0"
CURDIR="$(pwd)"

GO_INSTALL_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Go/build_go.sh"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/cAdvisor/patch"

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
		DISTRO="$ID"
		if [[ "$DISTRO" == "sles" ]] ; then
		printf -- "\nAs part of the installation , Go 1.10.5 will be installed, \n"
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
	fi
	fi
}

function cleanup() {
	rm -rf "${CURDIR}/crc32.go.diff"
	printf -- 'Cleaned up the artifacts\n' |& tee -a "${LOG_FILE}"
}

function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'
	DISTRO="$ID"
	# Install go
	printf -- "Installing Go... \n" 
	if [[ "$DISTRO" == "sles" ]];then
	curl $GO_INSTALL_URL | bash -s -- -v 1.10.5
	fi
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

	#  Install godep tool
	cd "$GOPATH"
	go get github.com/tools/godep
	printf -- 'Installed godep tool at GOPATH \n' 

	# Checkout the code from repository
	if [ ! -d "${GOPATH}/src/github.com/google" ]; then
		mkdir -p "${GOPATH}/src/github.com/google"
	fi
	
	#Remove so that there is no conflict while doing clone on subsequent tries.
	rm -rf "${GOPATH}/src/github.com/google/cadvisor" 


	cd "${GOPATH}/src/github.com/google"
	git clone -b "v${PACKAGE_VERSION}"  https://github.com/google/cadvisor.git
	printf -- 'Cloned the cadvisor code \n'

	cd "${CURDIR}"

	# patch config file
	curl  -o "crc32.go.diff" $PATCH_URL/crc32.go.diff 
	patch "${GOPATH}/src/github.com/google/cadvisor/vendor/github.com/klauspost/crc32/crc32.go" crc32.go.diff 

	# Build cAdvisor
	cd "${GOPATH}/src/github.com/google/cadvisor"
	"${GOPATH}"/bin/godep go build . 

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
		go test -short "$(go list ./... | grep -v Microsoft)"   

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
"ubuntu-16.04" | "ubuntu-18.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo apt-get update 
	sudo apt-get install -y wget git libseccomp-dev curl patch golang-1.10 |& tee -a "${LOG_FILE}"
	export PATH=/usr/lib/go-1.10/bin/:$PATH
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

"rhel-7.4" | "rhel-7.5" | "rhel-7.6")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo yum install -y  wget git libseccomp-devel patch golang |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

"sles-12.3" | "sles-15")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo zypper  install -y git libseccomp-devel wget tar curl gcc patch  |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
