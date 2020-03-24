#!/bin/bash
# © Copyright IBM Corporation 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/cAdvisor/0.35.0/build_cadvisor.sh
# Execute build script: bash build_cadvisor.sh    (provide -h for help)
#

set -e

PACKAGE_NAME="cadvisor"
PACKAGE_VERSION="0.35.0"
CURDIR="$(pwd)"

GO_INSTALL_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Go/1.13.5/build_go.sh"
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

if [ -f "/etc/os-release" ]; then
	source "/etc/os-release"


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
	rm -rf "${GOPATH}/src/github.com/google/cadvisor/test_results.log"
	rm -rf "${GOPATH}/src/github.com/google/cadvisor/failures.txt"
	rm -rf "${GOPATH}/src/github.com/google/cadvisor/expected_failures.txt"
	rm -rf "${GOPATH}/src/github.com/google/cadvisor/generated_failures.txt"
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
		go test -short `go list ./... | grep -v Microsoft` 2>&1 | tee test_results.log
		grep "^FAIL" test_results.log > generated_failures.txt
				cat generated_failures.txt
				awk '{print $1 " " $2}' generated_failures.txt > failures.txt
				echo 'FAIL github.com/google/cadvisor/machine' > expected_failures.txt
				if [[ "$DISTRO" == "rhel-8.0" ]]; then
					echo 'FAIL' >> expected_failures.txt
				fi
				cat failures.txt
				cat expected_failures.txt

        if diff -u --ignore-all-space failures.txt expected_failures.txt; then
			echo "Ignore TestTopology failure as it is known issue on system Z."
		else
			echo "Unexpected test failures encountered!!"
		fi
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
	sudo apt-get install -y wget git curl patch golang-1.10 |& tee -a "${LOG_FILE}"
	export PATH=/usr/lib/go-1.10/bin/:$PATH
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

"ubuntu-19.10")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo apt-get update 
	sudo apt-get install -y wget git curl patch golang-1.12 |& tee -a "${LOG_FILE}"
	export PATH=/usr/lib/go-1.12/bin/:$PATH
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

"rhel-7.5" | "rhel-7.6" | "rhel-7.7")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo yum install -y  wget git patch golang gcc |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;
	
"rhel-8.0" | "rhel-8.1")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo yum install -y curl git golang patch |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

"sles-12.4" | "sles-12.5" | "sles-15.1")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo zypper  install -y git wget tar curl gcc patch curl |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
