#!/usr/bin/env bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ApacheZooKeeper/build_zookeeper.sh
# Execute build script: bash build_zookeeper.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="zookeeper"
PACKAGE_VERSION="3.4.12"
CURDIR="$(pwd)"
BUILD_DIR="/usr/local"

FORCE="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exsists
if [ ! -d "$CURDIR/logs" ]; then
	mkdir -p "$CURDIR/logs"
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

function checkPrequisites() {
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
		printf -- "\nAs part of the installation , dependencies would be installed/upgraded.\n"
		while true; do
			read -r -p "Do you want to continue (y/n) ? :  " yn
			case $yn in
			[Yy]*)
				printf -- 'User responded with Yes. \n' >>"$LOG_FILE"
				break
				;;
			[Nn]*) exit ;;
			*) echo "Please provide confirmation to proceed." ;;
			esac
		done
	fi
}

function cleanup() {
	rm -rf "${PACKAGE_NAME}"-"${PACKAGE_VERSION}".tar.gz*
	printf -- 'Cleaned up the artifacts\n'
}

function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'

	#Download the source code
	cd "$CURDIR"
	wget http://www-eu.apache.org/dist/zookeeper/stable/${PACKAGE_NAME}-${PACKAGE_VERSION}.tar.gz
	tar zxf ${PACKAGE_NAME}-${PACKAGE_VERSION}.tar.gz
	sudo mv ${PACKAGE_NAME}-${PACKAGE_VERSION} $BUILD_DIR/${PACKAGE_NAME}
	cd $BUILD_DIR/${PACKAGE_NAME}

	mv conf/zoo_sample.cfg conf/zoo.cfg
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
	echo "build_zookeeper.sh [-d debug]"
	echo
}

while getopts "h?d" opt; do
	case "$opt" in
	h | \?)
		printHelp
		exit 0
		;;
	d)
		set -x
		;;
	esac
done

function gettingStarted() {

	printf -- "\n\nUsage: \n"
	printf -- "  Apache zookeeper installed successfully \n"
	printf -- "    To run zookeeper server ,use sudo /usr/local/zookeeper/bin/zkServer.sh start \n"
	printf -- "    To run zookeeper client ,use sudo /usr/local/zookeeper/bin/zkCli.sh \n"
	printf -- "  More information can be found here : https://github.com/apache/zookeeper \n"
	printf -- '\n'
}

###############################################################################################################

logDetails
checkPrequisites #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	sudo apt-get update >/dev/null
	sudo apt-get install -y openjdk-8-jdk |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"rhel-6.x")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for zookeeper from repository \n' |& tee -a "$LOG_FILE"
	sudo yum install -y java-1.8.0-ibm wget tar |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"rhel-7.4" | "rhel-7.5" | "rhel-7.6")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for zookeeper from repository \n' |& tee -a "$LOG_FILE"
	sudo yum install -y java-1.8.0-openjdk wget tar |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"sles-12.3" | "sles-15")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for zookeeper from repository \n' |& tee -a "$LOG_FILE"
	sudo zypper install -y java-1_8_0-openjdk wget tar |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "$LOG_FILE"
