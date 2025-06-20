#!/bin/bash
# © Copyright IBM Corporation 2025.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/librdkafka/2.10.1/build_librdkafka.sh
# Execute build script: bash build_librdkafka.sh (provide -h for help)

set -e  -o pipefail

PACKAGE_NAME="librdkafka"
PACKAGE_VERSION="v2.10.1"
SOURCE_ROOT="$(pwd)"
USER="$(whoami)"
FORCE="false"
LOG_FILE="${SOURCE_ROOT}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
TESTS="false"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
	mkdir -p "$SOURCE_ROOT/logs/"
fi

source "/etc/os-release"
PRESERVE_ENVARS=~/.bash_profile

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
		printf -- "\nAs part of the installation, dependencies would be installed/upgraded. \n"
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
}

function cleanup() {
	# Remove artifacts
	cd $SOURCE_ROOT
	printf -- "Cleaned up the artifacts\n" >> "$LOG_FILE"
}

function buildOssl() {
	NAME_OSSL=openssl
	VERSION_OSSL=3.4.0

	printf -- "Start building %s .\n" "$PACKAGE_OSSL"
	if [ -d  $SOURCE_ROOT/$NAME_OSSL-$VERSION_OSSL ]; then
		printf -- "The file already exists. Nothing to do. \n"
		return 0
	fi

	cd $SOURCE_ROOT
	wget --no-check-certificate https://github.com/openssl/openssl/releases/download/openssl-$VERSION_OSSL/openssl-$VERSION_OSSL.tar.gz
	tar -xzf openssl-$VERSION_OSSL.tar.gz
	cd openssl-$VERSION_OSSL
	./config --libdir=/usr/local/lib
	make -j$(nproc)
	sudo make install
	export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
	openssl version
	printf -- "Finished building %s .\n" "$NAME_OSSL-$VERSION_OSSL"
}

function configureAndInstall() {
	source $PRESERVE_ENVARS
	printf -- 'Configuration and Installation started \n'
	if [ $ID$VERSION_ID == rhel8.8 ] || [ $ID$VERSION_ID == rhel8.10 ]; then
		export CFLAGS="-I/usr/local/include"
		export LIBS="-L/usr/local/lib"
	fi
	#Build librdkafka
	cd $SOURCE_ROOT
	git clone -b ${PACKAGE_VERSION} https://github.com/confluentinc/librdkafka.git
	cd librdkafka/
	./configure --install-deps
	make
	sudo make install
	# Run Tests
	runTest
	printf -- "\n Installation of librdkafka was successful \n\n"
}

function runTest() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- "TEST Flag is set , Continue with running test \n"
		source $PRESERVE_ENVARS
		cd $SOURCE_ROOT/librdkafka/
		make -C tests -j1 run_local_quick
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
	echo "  bash build_librdkafka.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests]"
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
	printf -- "The librdkafka build sets up LD_LIBRARY_PATH accordingly.\n In case of issues try exporting LD_LIBRARY_PATH. \n"
	printf -- '*************************************************************************************************\n'
	printf -- '\n'
}

###############################################################################################################

logDetails
prepare #Check Prequisites
echo "export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH" >> $PRESERVE_ENVARS

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"rhel-8.8" | "rhel-8.10" | "rhel-9.2" | "rhel-9.4" | "rhel-9.5")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo yum install -y git make openssl-devel cyrus-sasl-devel python3 gcc gcc-c++ zlib-devel binutils |& tee -a "${LOG_FILE}"
	if [ $ID$VERSION_ID == rhel8.8 ] || [ $ID$VERSION_ID == rhel8.10 ]; then
		sudo yum install -y wget tar perl |& tee -a "${LOG_FILE}"
		buildOssl |& tee -a "${LOG_FILE}"
	fi
  if [ $ID$VERSION_ID == rhel9.2 ] || [ $ID$VERSION_ID == rhel9.4 ] || [ $ID$VERSION_ID == rhel9.5 ]; then
    rm ~/.bash_profile
    touch ~/.bash_profile
	fi
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;
"sles-15.6")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo zypper install -y binutils gcc make libz1 zlib-devel git gcc-c++ openssl-devel |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;
"ubuntu-22.04" | "ubuntu-24.04" | "ubuntu-24.10")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo apt-get update -y
	sudo apt-get install -y git build-essential make zlib1g-dev libpthread-stubs0-dev libssl-dev libsasl2-dev libzstd-dev libcurl4-openssl-dev |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;; 
*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
