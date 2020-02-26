#!/bin/bash
# ©  Copyright IBM Corporation 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/grpc-node/1.24.2/build_grpc-node.sh
# Execute build script: bash build_grpc-node.sh    (provide -h for help)
#

set -e -o pipefail

PACKAGE_NAME="grpc-node"
PACKAGE_VERSION="grpc@1.24.2"

FORCE=false
WORKDIR="/usr/local"
CURDIR="$(pwd)"
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 1 2 ERR

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
		printf -- 'Sudo : Yes\n'
	else
		printf -- 'Sudo : No \n'
		printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n'
		exit 1
	fi

	if [[ "$FORCE" == "true" ]]; then
		printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "${LOG_FILE}"
	else
		# Ask user for prerequisite installation
		printf -- "\nAs part of the installation, dependencies would be installed/upgraded. \n"
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
	if [[ "${VERSION_ID}" == "8.0" ]]; then
		sudo rm -rf "${WORKDIR}/Python-2.7.16.tar.xz"
	fi
	sudo rm -rf "${WORKDIR}/node-v13.3.0-linux-s390x.tar.xz"
	printf -- 'Cleaned up the artifacts\n' >>"${LOG_FILE}"
}

function runTest() {
    set +e
    if [[ "$TESTS" == "true" ]]; then
		cd "${WORKDIR}/grpc-node"
		
		if [[ "$DISTRO" == "rhel-7.5" || "$DISTRO" == "rhel-7.6" || "$DISTRO" == "rhel-7.7" ]];then
			printf -- 'RHEL 7.x distro have issue with node11-gcc4.8.5. Removing node11 from tests. \n' >>"${LOG_FILE}"
			sed -i -e 's/6 7 8 9 10 11 12/6 7 8 9 10 12/g' run-tests.sh
		fi	
		
		./run-tests.sh
	fi
}

function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'

	# Install Python 2.7.16 (for RHEL 8.0)
	if [[ "${VERSION_ID}" == "8.0" ]]; then
		cd "${WORKDIR}"
		wget https://www.python.org/ftp/python/2.7.16/Python-2.7.16.tar.xz
		tar -xvf Python-2.7.16.tar.xz
		cd Python-2.7.16
		./configure --prefix=/usr/local --exec-prefix=/usr/local
		make
		sudo make install		
		python -V
		printf -- 'Installed Python successfully for Rhel 8.0 \n'
	fi

	#Install node
	cd "${WORKDIR}"
	wget https://nodejs.org/dist/v13.3.0/node-v13.3.0-linux-s390x.tar.xz
	chmod ugo+r node-v13.3.0-linux-s390x.tar.xz
	sudo tar -C /usr/local -xf node-v13.3.0-linux-s390x.tar.xz
	export PATH=$PATH:/usr/local/node-v13.3.0-linux-s390x/bin	
	
	#Install grpc-node	
	printf -- 'Building and Installing grpc-node..... \n'
	cd "${WORKDIR}"
	git clone https://github.com/grpc/grpc-node.git
	cd grpc-node/
	git checkout grpc@1.24.2
	git submodule update --init --recursive
	cd packages/grpc-native-core/
	npm install --build-from-source --unsafe-perm
	printf -- 'grpc-node built successfully \n'

	if [[ "$DISTRO" == "rhel-7.6" || "$DISTRO" == "ubuntu-19.10" ]];then
		npm install --save-dev electron-mocha@8.1.2
	fi
	
	#Cleanup
	cleanup
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
	echo "  install.sh  [-d debug] [-y install-without-confirmation]"
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
	printf -- '\n********************************************************************************************************\n'
	printf -- "\n* grpc-node installed successfully. * \n"
	printf -- '**********************************************************************************************************\n'
}

###############################################################################################################

logDetails
prepare

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04" | "ubuntu-19.10")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
	sudo apt-get update
	sudo apt-get install -y gcc g++ git make wget python curl |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

"rhel-7.5" | "rhel-7.6" | "rhel-7.7")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
	sudo yum install -y gcc-c++ git make wget curl python |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

"rhel-8.0")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
	sudo yum install -y gcc-c++ git make wget curl |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;
	
"sles-12.4" | "sles-15.1")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
	sudo zypper install gcc-c++ git-core make wget curl python |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "${LOG_FILE}"
	exit 1
	;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
