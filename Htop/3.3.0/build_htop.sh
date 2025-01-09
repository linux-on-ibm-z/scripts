#!/usr/bin/env bash
# © Copyright IBM Corporation 2024, 2025
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Htop/3.3.0/build_htop.sh
# Execute build script: bash build_htop.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="htop"
PACKAGE_VERSION="3.3.0"
CURDIR="$(pwd)"

FORCE="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exsists
if [ ! -d "$CURDIR/logs" ]; then
	mkdir -p "$CURDIR/logs"
fi

if [ -f "/etc/os-release" ]; then
	source "/etc/os-release"
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
	if [ -f ${PACKAGE_NAME}-${PACKAGE_VERSION}.tar.gz ]; then
		sudo rm ${PACKAGE_NAME}-${PACKAGE_VERSION}.tar.gz
	fi
}

function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'
 
	# Download and unpack the htop 3.3.0 source code
	cd /"$CURDIR"/
	git clone -b $PACKAGE_VERSION https://github.com/htop-dev/htop.git
 	cd htop

	# Configure and build htop-3.3.0
	cd /"$CURDIR"/htop
	./autogen.sh
	./configure
	make

	#  Install htop
	sudo make install
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
	echo "  bash build_htop.sh [-d debug]  [-y install-without-confirmation] "
	echo
}

while getopts "h?yd" opt; do
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
	esac
done

function gettingStarted() {

	printf -- '\n*********************************************************************************************\n'
	printf -- "\n\nUsage: \n"
	printf -- "  Htop installed successfully \n"
	printf -- "  Launch htop to monitor the system using : \n"
	printf -- "    htop \n"
	printf -- "  More information can be found here : https://htop.dev/ \n"
	printf -- '\n'
	printf -- '\n*********************************************************************************************\n'
}

###############################################################################################################

logDetails
checkPrequisites #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in

"rhel-8.8" | "rhel-8.10")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for Htop from repository \n' |& tee -a "$LOG_FILE"
	sudo yum install -y ncurses-devel automake autoconf gcc git make |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;
	
"sles-15.6")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for Htop from repository \n' |& tee -a "$LOG_FILE"
	sudo zypper install -y ncurses ncurses-devel gcc make wget tar awk git autoconf libtool xz gzip|& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"ubuntu-20.04" | "ubuntu-22.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for Htop from repository \n' |& tee -a "$LOG_FILE"
    	sudo apt-get update -y >/dev/null
	sudo apt install -y libncursesw5-dev autotools-dev autoconf build-essential git |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "$LOG_FILE"
