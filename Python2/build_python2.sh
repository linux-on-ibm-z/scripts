#!/bin/bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
#Instructions
#Get Build script : wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Python2/build_python.sh
#Execute build script: bash build_python2.sh

set -e -o pipefail

PACKAGE_NAME="python"
PACKAGE_VERSION="2.7.15"
FORCE=false
CURDIR="$(pwd)"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Python2/patch/test_ssl.patch"
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
	if command -v "sudo" >/dev/null; then
		printf -- 'Sudo : Yes\n'
	else
		printf -- 'Sudo : No \n'
		printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n'
		exit 1
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
	rm /$CURDIR/Python-2.7.15.tar.xz
	printf -- 'Cleaned up the artifacts\n' >>"${LOG_FILE}"
}

function configureAndInstall() {
	printf -- 'Configuration and Installation started \n' |& tee -a "${LOG_FILE}"
	
	#Downloading Source code
	cd "${CURDIR}"
    	wget https://www.python.org/ftp/python/2.7.15/Python-2.7.15.tar.xz 
	tar -xvf Python-2.7.15.tar.xz
    
    	#Applying Patch to fix test_ssl
    	printf -- "\nApplying patch file">>"${LOG_FILE}"
    	cd Python-2.7.15/Lib/test/
    	curl -o "test_ssl.patch" $PATCH_URL
	cp test_ssl.py test_ssl.py.orig
    	patch test_ssl.py < test_ssl.patch

	sed -i "1010 s/u.*/filename)/" test_ssl.py
	diff -u test_ssl.py.orig test_ssl.py || true
    	printf -- "\nPATCH added \n">>"${LOG_FILE}" 

    	#symlink for ncurses header (ONLY FOR SLES)
    	if [[ "$ID" == "sles" ]]; then
		sudo ln -sfv /usr/include/ncurses/* /usr/include/
    	fi

    	#Configure and Build
    	cd $CURDIR/Python-2.7.15
    	./configure --prefix=/usr/local --exec-prefix=/usr/local
	 make

    	#Install binaries
    	sudo make install

    	export PATH="/usr/local/bin:${PATH}"
	printf -- '\nInstalled python successfully \n' >>"${LOG_FILE}"

    	#Cleanup
    	cleanup

    	#Verify python installation
    	if command -V "$PACKAGE_NAME" >/dev/null; then
      		printf -- "%s installation completed. Please check the Usage to start the service.\n" "$PACKAGE_NAME" |& tee -a "$LOG_FILE"
    	else
      		printf -- "Error while installing %s, exiting with 127 \n" "$PACKAGE_NAME"
      		exit 127
    	fi
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
	echo "  build_python.sh  [-d <debug>] [-v package-version] [-y install-without-confirmation]"
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
		;;
	esac
done

function printSummary() {
	printf -- '\n***************************************************************************************\n'
	printf -- "Run python: \n"
	printf -- "    python -V (To Check the version) \n"
	printf -- '***************************************************************************************\n'
	printf -- '\n'
}

###############################################################################################################

logDetails
prepare

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04")
    	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
    	sudo apt-get update
    	sudo apt-get install -y gcc g++ make libncurses5-dev libreadline6-dev libssl-dev libgdbm-dev libc6-dev libsqlite3-dev libbz2-dev xz-utils wget tar curl bzip2 zlib1g-dev libdb1-compat libdb-dev tk8.5-dev gdb patch
    	configureAndInstall
    	;;
"ubuntu-18.04")
    	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
    	apt-get install -y python
    	printf -- "Installation Sucessfull.. \n Binary Exsisted for ubuntu-18.04 \n\n" >> "$LOG_FILE";
    	;;

"rhel-6.10")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
	sudo yum install -y gcc gcc-c++ make ncurses wget tar bzip2-devel zlib-devel xz xz-devel readline-devel sqlite-devel tk-devel ncurses-devel gdbm-devel openssl-devel db4-devel gdb bzip2 patch 
	configureAndInstall
	;;

"rhel-7.3" | "rhel-7.4" | "rhel-7.5")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
	sudo yum install -y gcc gcc-c++ make ncurses wget tar bzip2-devel zlib-devel xz xz-devel readline-devel sqlite-devel tk-devel ncurses-devel gdbm-devel openssl-devel libdb-devel gdb bzip2 patch
	configureAndInstall
	;;

"sles-12.3")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
	sudo zypper install -y gcc gcc-c++ make ncurses wget tar bzip2 zlib-devel xz readline-devel sqlite-devel tk-devel ncurses-devel gdbm-devel openssl-devel libdb-4_8-devel gdb awk netcfg libbz2-devel glibc-locale patch
	configureAndInstall
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "${LOG_FILE}"
	exit 1
	;;
esac

printSummary
