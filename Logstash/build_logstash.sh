#!/bin/bash
# ©  Copyright IBM Corporation 2018, 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Logstash/build_logstash.sh
# Execute build script: bash build_logstash.sh    (provide -h for help)
#

set -e -o pipefail

PACKAGE_NAME="logstash"
PACKAGE_VERSION="6.6.0"

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
	sudo rm -rf "${WORKDIR}/ibm-java-s390x-sdk-8.0-5.26.bin" "${WORKDIR}/installer.properties"
	sudo rm -rf "${WORKDIR}/jffi-1.2.18.zip" "${WORKDIR}/logstash-${PACKAGE_VERSION}.zip"
	sudo rm -rf "${WORKDIR}/apache-ant-1.10.0-bin.tar.gz"
	printf -- 'Cleaned up the artifacts\n' >>"${LOG_FILE}"
}

function configureAndInstall() {
	#cleanup
	printf -- 'Configuration and Installation started \n'

	# Install IBMSDK
	printf -- 'Configuring IBMSDK \n'
	cd "${WORKDIR}"
	sudo wget -q http://public.dhe.ibm.com/ibmdl/export/pub/systems/cloud/runtimes/java/8.0.5.26/linux/s390x/ibm-java-s390x-sdk-8.0-5.26.bin
	sudo wget -q https://raw.githubusercontent.com/zos-spark/scala-workbench/master/files/installer.properties.java
	tail -n +3 installer.properties.java | sudo tee installer.properties
	sudo cat installer.properties
	sudo chmod +x ibm-java-s390x-sdk-8.0-5.26.bin
	sudo ./ibm-java-s390x-sdk-8.0-5.26.bin -r installer.properties

	export JAVA_HOME=/opt/ibm/java
	export PATH="${JAVA_HOME}/bin:$PATH"
	java -version

	# Install Ant (for RHEL 6.10)
	if [[ "${VERSION_ID}" == "6.x" ]]; then
		cd "${WORKDIR}"
		sudo wget -q http://archive.apache.org/dist/ant/binaries/apache-ant-1.10.0-bin.tar.gz
		sudo tar -zxvf apache-ant-1.10.0-bin.tar.gz
		export ANT_HOME="${WORKDIR}/apache-ant-1.10.0"
		export PATH="${ANT_HOME}/bin:${PATH}"
		ant -version
		printf -- 'Installed Ant successfully for Rhel 6.10 \n'
	fi

	#Install Logstash
	printf -- 'Installing Logstash..... \n'
	printf -- 'Download source code of Logstash\n'
	cd "${WORKDIR}"
	sudo wget -q https://artifacts.elastic.co/downloads/logstash/logstash-"${PACKAGE_VERSION}".zip
	sudo unzip -u logstash-"${PACKAGE_VERSION}".zip

	printf -- 'Jruby runs on JVM and needs a native library (libjffi-1.2.so: java foreign language interface). Get jffi source code and build with ant.\n' |& tee -a "${LOG_FILE}"
	cd "${WORKDIR}"
	sudo wget -q https://github.com/jnr/jffi/archive/jffi-1.2.18.zip
	sudo unzip -u jffi-1.2.18.zip
	sudo chmod 777 "${WORKDIR}/logstash-${PACKAGE_VERSION}/" "${WORKDIR}/jffi-jffi-1.2.18/"
	cd jffi-jffi-1.2.18
	ant

	printf -- 'Add libjffi-1.2.so to LD_LIBRARY_PATH\n'
	export LD_LIBRARY_PATH="${WORKDIR}/jffi-jffi-1.2.18/build/jni/:$LD_LIBRARY_PATH"

	# Add config/logstash.yml to /etc/logstash/config/
	sudo mkdir -p /etc/logstash/config/
	sudo cp -Rf "${WORKDIR}/logstash-${PACKAGE_VERSION}/config/logstash.yml" /etc/logstash/config/logstash.yml

	# Include Logstash in the PATH

	sudo ln -s "${WORKDIR}/logstash-${PACKAGE_VERSION}/bin/logstash" /usr/bin/
	printf -- 'Installed logstash successfully \n'

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
	printf -- '\n********************************************************************************************************\n'
	printf -- "\n*Getting Started * \n"
	printf -- "Run Logstash: \n"
	printf -- "    export LD_LIBRARY_PATH=/usr/share/local/jffi-jffi-1.2.18/build/jni/ "
	printf -- "    logstash -V (To Check the version) \n"
	printf -- '**********************************************************************************************************\n'
}

###############################################################################################################

logDetails
prepare

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
	sudo apt-get update
	sudo apt-get install -y ant make wget unzip tar gcc |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

"rhel-6.x")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
	sudo yum install -y wget unzip tar gcc make |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

"rhel-7.4" | "rhel-7.5" | "rhel-7.6")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
	sudo yum install -y ant wget unzip make gcc tar |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

"sles-12.3")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
	sudo zypper install -y --type pattern Basis-Devel |& tee -a "${LOG_FILE}"
	sudo zypper install -y ant wget unzip make gcc tar |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

"sles-15")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
	sudo zypper install -y ant wget unzip make gcc tar |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "${LOG_FILE}"
	exit 1
	;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
