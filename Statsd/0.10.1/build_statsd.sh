#!/bin/bash
# © Copyright IBM Corporation 2023.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Statsd/0.10.1/build_statsd.sh
# Execute build script: bash build_statsd.sh    (provide -h for help)
#

set -e  -o pipefail

PACKAGE_NAME="statsd"
PACKAGE_VERSION="0.10.1"

CURDIR="$(pwd)"
SOURCE_ROOT="$(pwd)"
USER="$(whoami)"
NODE_VERSION="v18.16.0"


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
	  rm -rf $SOURCE_ROOT/node-${NODE_VERSION}-linux-s390x.tar.xz
	  rm -rf $SOURCE_ROOT/gcc-5.4.0.tar.gz
    printf -- "Cleaned up the artifacts\n" >> "$LOG_FILE"

}
function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'

	#Install Nodejs
	cd $SOURCE_ROOT
	wget https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-s390x.tar.xz
	chmod ugo+r node-${NODE_VERSION}-linux-s390x.tar.xz
	sudo tar -C /usr/local -xf node-${NODE_VERSION}-linux-s390x.tar.xz
	export PATH=$PATH:/usr/local/node-${NODE_VERSION}-linux-s390x/bin
	node -v
	

	#Install Statsd
	printf -- 'Installing Statsd.. \n'
	cd $SOURCE_ROOT
	git clone https://github.com/etsy/statsd.git
	cd statsd
	git checkout v0.10.1
	
	npm install
	
	# Run Tests
	runTest

	#Cleanup
	cleanup

	printf -- "\n Installation of %s %s was sucessful \n\n" $PACKAGE_NAME $PACKAGE_VERSION
	gettingStarted |& tee -a "${LOG_FILE}"
}

function runTest() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- "TEST Flag is set , Continue with running test \n" 						
		export PATH=$PATH:/usr/local/node-${NODE_VERSION}-linux-s390x/bin
		cd $SOURCE_ROOT/statsd/
		./run_tests.js

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
	echo "  bash build_statsd.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests]"
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
	printf -- "To run Statsd daemon : \n"
	printf -- "  $ cd $SOURCE_ROOT/statsd  \n"
	printf -- "  $ export PATH=\$PATH:/usr/local/node-${NODE_VERSION}-linux-s390x/bin  \n"
	printf -- "  $ node stats.js <path_to_config> #eg: node stats.js $SOURCE_ROOT/statsd/exampleConfig.js  \n\n"
	printf -- "Usage:  \n"
	printf -- "The basic line protocol expects metrics to be sent in the format: <metricname>:<value>|<type>  \n"
	printf -- 'e.g. echo "foo:1|c" | nc -u -w2 127.0.0.1 8125  \n'
	printf -- "\n\n"
	printf -- '*************************************************************************************************\n'
	printf -- '\n'
}

###############################################################################################################

logDetails
prepare #Check Prequisites

DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"ubuntu-20.04" | "ubuntu-22.04" | "ubuntu-22.10" | "ubuntu-23.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo apt-get update -y
	sudo apt-get install -y git wget tar unzip hostname python3 g++ make xz-utils |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

"sles-15.4")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
	sudo zypper install -y git wget tar unzip hostname make gcc-c++ xz gzip python3 nmap procps  |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"rhel-8.6" | "rhel-8.7" | "rhel-9.0" | "rhel-9.1")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo yum install -y git wget tar unzip hostname make gcc-c++ xz gzip python3 nmap procps netcat |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac
