#!/usr/bin/env bash
# © Copyright IBM Corporation 2021.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Htop/3.1.2/build_htop.sh
# Execute build script: bash build_htop.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="htop"
PACKAGE_VERSION="3.1.2"
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
 
 	if [[ ${DISTRO} =~ rhel-7\.* || ${DISTRO} =~ sles-* || ${DISTRO} =~ ubuntu-18\.* ]]; then
		# Install Automake
		printf -- 'Installing Automake...\n'
		cd /"$CURDIR"/
		wget https://ftp.gnu.org/gnu/automake/automake-1.16.5.tar.gz
		tar -xvf automake-1.16.5.tar.gz
		cd automake-1.16.5
		./configure
		make
		sudo make install
		export PATH=/usr/local/bin:$PATH
		automake --version
	fi
	
	# Download and unpack the htop 3.1.2 source code
	cd /"$CURDIR"/
	git clone https://github.com/htop-dev/htop.git
 	cd htop
	git checkout 3.1.2

	# Configure and build htop-3.1.2
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
	echo "  build_htop.sh [-d debug]  [-y install-without-confirmation] "
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

"ubuntu-18.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for Htop from repository \n' |& tee -a "$LOG_FILE"
    	sudo apt-get update -y >/dev/null
	sudo apt-get install -y gcc git make wget tar libncursesw5 libcunit1-ncurses libncursesw5-dev autoconf |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;
	
"ubuntu-20.04" | "ubuntu-21.04" | "ubuntu-21.10")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for Htop from repository \n' |& tee -a "$LOG_FILE"
    	sudo apt-get update -y >/dev/null
	sudo apt-get install -y gcc git make wget tar libncursesw5 libcunit1-ncurses libncursesw5-dev automake |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"rhel-7.8" | "rhel-7.9")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for Htop from repository \n' |& tee -a "$LOG_FILE"
	sudo yum install -y ncurses ncurses-devel gcc make git wget tar xz autoconf libtool |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;
	
"rhel-8.2" | "rhel-8.4" | "rhel-8.5")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for Htop from repository \n' |& tee -a "$LOG_FILE"
	sudo yum install -y ncurses ncurses-devel gcc git make wget tar automake |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"sles-12.5" | "sles-15.2" | "sles-15.3")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for Htop from repository \n' |& tee -a "$LOG_FILE"
	sudo zypper install -y ncurses ncurses-devel gcc make wget tar awk git autoconf libtool xz gzip|& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "$LOG_FILE"
