#!/bin/bash
# ©  Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Kibana/7.0.0/build_kibana.sh
# Execute build script: bash build_kibana.sh    (provide -h for help)
#
set -e -o pipefail

PACKAGE_NAME="kibana"
PACKAGE_VERSION="7.0.0"

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
	if command -v "sudo" > /dev/null; then
		printf -- 'Sudo : Yes\n' >> "$LOG_FILE"
	else
		printf -- 'Sudo : No \n' >> "$LOG_FILE"
		printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n'
		exit 1
	fi

	if [[ "$FORCE" == "true" ]]; then
		printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "${LOG_FILE}"
	else
		# Ask user for prerequisite installation
		printf -- "\nAs part of the installation , dependencies would be installed/upgraded, \n"
		while true; do
			read -r -p "Do you want to continue (y/n) ? :  " yn
			case $yn in
			[Yy]*)
				printf -- 'User responded with Yes. \n' >> "${LOG_FILE}"
				break
				;;
			[Nn]*) exit ;;
			*) echo "Please provide confirmation to proceed." ;;
			esac
		done
	fi
}

function cleanup() {
	sudo rm -rf "${WORKDIR}/kibana-${PACKAGE_VERSION}-linux-x86_64.tar.gz" "${WORKDIR}/node-v10.15.2-linux-s390x.tar.gz" "${WORKDIR}/gcc-4.9.4.tar.gz" "${WORKDIR}/gcc_build"
	printf -- 'Cleaned up the artifacts\n' >>"${LOG_FILE}"
}

function buildGCC() {
	printf -- 'Building GCC \n'
	cd "${CURDIR}"
	wget ftp://gcc.gnu.org/pub/gcc/releases/gcc-4.9.4/gcc-4.9.4.tar.gz
	tar -xvzf gcc-4.9.4.tar.gz
	cd gcc-4.9.4/
	./contrib/download_prerequisites
	cd "${CURDIR}"
	mkdir -p gcc_build
	cd gcc_build/
	../gcc-4.9.4/configure --prefix="/opt/gcc" --enable-checking=release --enable-languages=c,c++ --disable-multilib
	make
	sudo make install
	export PATH=/opt/gcc/bin:$PATH
	export LD_LIBRARY_PATH='/opt/gcc/lib64'
	printf -- 'Built GCC successfully \n'
}

function configureAndInstall() {
	#cleanup
	printf -- '\nConfiguration and Installation started \n'

	export PATH=/opt/gcc/bin:$PATH
	export LD_LIBRARY_PATH='/opt/gcc/lib64'

	# Install Nodejs
	printf -- 'Downloading Nodejs binaries \n'
	cd "${WORKDIR}"

	sudo wget https://nodejs.org/dist/v10.15.2/node-v10.15.2-linux-s390x.tar.gz
	sudo tar xvf node-v10.15.2-linux-s390x.tar.gz

	if [ ! -d "$WORKDIR/nodejs" ]; then
		sudo mv node-v10.15.2-linux-s390x nodejs
	fi


	sudo chmod +x nodejs
	export PATH=$PWD/nodejs/bin:$PATH
	node -v  >> "${LOG_FILE}"

	#Install Kibana
	printf -- '\nInstalling Kibana..... \n'
	printf -- 'Download Kibana release package and extract\n'

	cd "${WORKDIR}"
	sudo wget https://artifacts.elastic.co/downloads/kibana/kibana-"${PACKAGE_VERSION}"-linux-x86_64.tar.gz
	sudo tar xvf kibana-"${PACKAGE_VERSION}"-linux-x86_64.tar.gz

	printf -- 'Replace Node.js in the package with the installed Node.js.\n'
	cd "${WORKDIR}/kibana-${PACKAGE_VERSION}-linux-x86_64"
	sudo mv node node_old # rename the node
	sudo ln -sf "${WORKDIR}"/nodejs node

	# Add config/kibana.yml to /etc/kibana/config/
	sudo mkdir -p /etc/kibana/config/
	sudo cp -Rf "${WORKDIR}/kibana-${PACKAGE_VERSION}-linux-x86_64/config/kibana.yml" /etc/kibana/config/kibana.yml

	# Add kibana to /usr/bin
	sudo ln -sf "${WORKDIR}/kibana-${PACKAGE_VERSION}-linux-x86_64/bin/kibana" /usr/bin/
	printf -- 'Installed kibana successfully \n'

	#Cleanup
	cleanup

	#Verify kibana installation
	if command -v "$PACKAGE_NAME" >/dev/null; then
		printf -- "%s installation completed. Please check the Usage to start the service.\n" "$PACKAGE_NAME"
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
	echo "  install.sh  [-d debug] [-y install-without-confirmation]"
	echo
}

while getopts "h?dy" opt; do
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
	printf -- '\n***************************************************************************************\n'
	printf -- "Getting Started: \n"
	printf -- "Pre-requisite: Ensure Elasticsearch instance is running.\nUpdate the Kibana configuration file /etc/kibana/config/kibana.yml to set elasticsearch.url to the Elasticsearch host. \n"
	printf -- "Start Kibana: \n"
	printf -- "    kibana  & (Run in background) \n"
	printf -- "\nAccess kibana UI using the below link : "
	printf -- "http://<host-ip>:<port>/    [Default port = 5601] \n"
	printf -- '***************************************************************************************\n'
	printf -- '\n'
}

###############################################################################################################

logDetails
prepare

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04")
	printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
	sudo apt-get update
	sudo apt-get install -y wget tar |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

"rhel-7.4" | "rhel-7.5" | "rhel-7.6")
	printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
	sudo yum install -y  wget tar make flex gcc gcc-c++ binutils-devel bzip2 |& tee -a "${LOG_FILE}"
	buildGCC |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

"sles-12.4" | "sles-15")
	printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
	sudo zypper  install -y wget tar |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "${LOG_FILE}"
	exit 1
	;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
