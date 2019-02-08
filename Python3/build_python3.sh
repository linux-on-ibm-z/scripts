#!/bin/bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
#Instructions
#Get Build script : wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Python3/build_python3.sh
#Execute build script: bash build_python3.sh

set -e -o pipefail

PACKAGE_NAME="python"
PACKAGE_VERSION="3.7.1"
TESTS="false"
FORCE=false
CURDIR="$(pwd)"
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap "" 1 2 ERR

if [ ! -d "${CURDIR}/logs/" ]; then
	mkdir -p "${CURDIR}/logs/"
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
	printf -- 'Preparing installation \n' |& tee -a "${LOG_FILE}"
	if command -v "sudo" >/dev/null; then
		printf -- 'Sudo : Yes\n'
	else
		printf -- 'Sudo : No \n'
		printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n'
		exit 1
	fi

	if [[ "${PACKAGE_VERSION}" == "3.6.5" ]]; then
		printf -- 'Preparing the installation for python 3.6.5 \n'
	elif [[ "${PACKAGE_VERSION}" == "3.7.1" ]]; then
		printf -- 'Preparing the installation for python 3.7.1 \n'
	else
		printf -- 'Provided python version is not supported by this script \n'
		printf -- 'This script supports python version 3.6.5 and 3.7.1 \n'
	fi

	if [[ "$FORCE" == "true" ]]; then
		printf -- 'Force attribute provided hence continuing with install without confirmation message' |& tee -a "${LOG_FILE}"
	else
		# Ask user for prerequisite installation
		printf -- "\n\nAs part of the installation some dependencies might be installed, \n"
		while true; do
			read -r -p "Do you want to continue (y/n) ? :  " yn
			case $yn in
			[Yy]*)
				printf -- 'User responded with Yes. \n' |& tee -a "${LOG_FILE}"
				break
				;;
			[Nn]*) exit ;;
			*) echo "Please provide confirmation to proceed." ;;
			esac
		done
	fi
}

function cleanup() {
	rm "$CURDIR/Python-${PACKAGE_VERSION}.tar.xz"
	printf -- 'Cleaned up the artifacts\n' >>"${LOG_FILE}"
}

function configureAndInstall() {
	printf -- 'Configuration and Installation started \n' |& tee -a "${LOG_FILE}"

	#Downloading Source code
	cd "${CURDIR}"
	wget "https://www.python.org/ftp/${PACKAGE_NAME}/${PACKAGE_VERSION}/Python-${PACKAGE_VERSION}.tar.xz"
	tar -xvf "Python-${PACKAGE_VERSION}.tar.xz"

	#Configure and Build
	cd "$CURDIR/Python-${PACKAGE_VERSION}"
	./configure --prefix=/usr/local --exec-prefix=/usr/local

	cd "$CURDIR/Python-${PACKAGE_VERSION}"
	make

	#Install binaries
	cd "$CURDIR/Python-${PACKAGE_VERSION}"
	sudo make install

	export PATH="/usr/local/bin:${PATH}"
	printf -- '\nInstalled python successfully \n' >>"${LOG_FILE}"

	#Run tests
	runTest

	#Cleanup
	cleanup

	#Verify python installation
	if command -V "$PACKAGE_NAME"${PACKAGE_VERSION:0:1} >/dev/null; then
		printf -- "%s installation completed. Please check the Usage to start the service.\n" "$PACKAGE_NAME" |& tee -a "$LOG_FILE"
	else
		printf -- "Error while installing %s, exiting with 127 \n" "$PACKAGE_NAME"
		exit 127
	fi
}

function runTest() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- "TEST Flag is set, continue with running test \n"
		cd "$CURDIR/Python-${PACKAGE_VERSION}"
		make test

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
	echo "  build_python_3.sh  [-d <debug>] [-v package-version] [-y install-without-confirmation]"
	echo "       default: If no -v specified, latest version will be installed "
	echo "This script supports python version 3.6.5 and 3.7.1 "
	echo
}

while getopts "h?dytv:" opt; do
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
		LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

		;;
	y)
		FORCE="true"
		;;
	t)
		TESTS="true"
		;;
	esac
done

function printSummary() {
	printf -- '\n***************************************************************************************\n'
	printf -- "Run python: \n"
	printf -- "export PATH="/usr/local/bin:\$PATH" \n"
	printf -- "    python3 -V (To Check the version) \n"

	printf -- '***************************************************************************************\n'
	printf -- '\n'
}

###############################################################################################################

logDetails
# prepare

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
	sudo apt-get update
	sudo apt-get install -y gcc g++ make libncurses5-dev libreadline6-dev libssl-dev libgdbm-dev libc6-dev libsqlite3-dev libbz2-dev xz-utils libffi-dev patch wget tar zlib1g-dev patch
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;
"ubuntu-18.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
	if [[ "${PACKAGE_VERSION}" == "3.6.5" ]]; then
		printf -- 'Preparing the installation for python 3.6.5 \n' >>"$LOG_FILE"
		sudo apt-get update
		sudo apt-get install -y python3
		printf -- "Installed python3 successfully from the repository \n\n" >>"$LOG_FILE"
	else
		sudo apt-get update
		sudo apt-get install -y gcc g++ make libncurses5-dev libreadline6-dev libssl-dev libgdbm-dev libc6-dev libsqlite3-dev libbz2-dev xz-utils libffi-dev patch wget tar zlib1g-dev
		configureAndInstall |& tee -a "${LOG_FILE}"
	fi
	;;

"rhel-6.x")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
	sudo yum install -y curl gcc gcc-c++ make ncurses patch xz xz-devel wget tar zlib zlib-devel libffi-devel git
	if [[ "${PACKAGE_VERSION}" == "3.7.1" ]]; then
		cd "${CURDIR}"
		git clone git://github.com/openssl/openssl.git
		cd openssl
		git checkout OpenSSL_1_0_2l
		./config --prefix=/usr --openssldir=/usr/local/openssl shared
		make
		sudo make install
	fi
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

"rhel-7.3" | "rhel-7.4" | "rhel-7.5")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
	sudo yum install -y gcc gcc-c++ make ncurses patch wget tar zlib zlib-devel xz xz-devel libffi-devel
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

"sles-12.3")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
	sudo zypper install -y gcc gcc-c++ make ncurses patch wget tar zlib-devel zlib libffi-devel
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

"sles-15")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
	if [[ "${PACKAGE_VERSION}" == "3.6.5" ]]; then
		printf -- 'Preparing the installation for python 3.6.5 \n' >>"$LOG_FILE"
		sudo zypper install -y python3
		printf -- "Installed python3 successfully from the repository \n\n" >>"$LOG_FILE"
	else
		sudo zypper install -y gcc gcc-c++ make ncurses patch wget tar zlib-devel zlib libffi-devel
		configureAndInstall |& tee -a "${LOG_FILE}"
	fi
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "${LOG_FILE}"
	exit 1
	;;
esac

printSummary |& tee -a "${LOG_FILE}"
