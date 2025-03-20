#!/usr/bin/env bash
# © Copyright IBM Corporation 2025.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Zabbix/7.0.10/build_zabbixagent.sh
# Execute build script: bash build_zabbixagent.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="zabbixagent"
URL_NAME="zabbix"
PACKAGE_VERSION="7.0.10"
MAJOR_VERSION="7.0"
CURDIR="$(pwd)"

FORCE="false"
source "/etc/os-release"
DISTRO="$ID-$VERSION_ID"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-${DISTRO}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exsists
if [ ! -d "$CURDIR/logs" ]; then
	mkdir -p "$CURDIR/logs"
fi

function checkPrequisites() {
	if command -v "sudo" >/dev/null; then
		printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
	else
		printf -- 'Sudo : No \n' >>"$LOG_FILE"
		printf -- 'Sudo is required. Please install it using apt, yum or zypper based on your distro. \n'
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
	if [ -f ${URL_NAME}-${PACKAGE_VERSION}.tar.gz ]; then
		sudo rm ${URL_NAME}-${PACKAGE_VERSION}.tar.gz
	fi
	printf -- 'Cleaned up the artifacts\n' >>"$LOG_FILE"
}

function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'

	#Download Zabbix agent
	cd "$CURDIR"
	wget https://cdn.zabbix.com/zabbix/sources/stable/${MAJOR_VERSION}/${URL_NAME}-${PACKAGE_VERSION}.tar.gz
	tar -xvf ${URL_NAME}-${PACKAGE_VERSION}.tar.gz

	#Install Zabbix agent
	cd "$CURDIR"/${URL_NAME}-${PACKAGE_VERSION}
	export CFLAGS="-std=gnu99"
	./configure --enable-agent
	make
	sudo make install

	export PATH=$PATH:/usr/local/sbin/

	#start the zabbix agent
	echo "Starting zabbix agent"
	zabbix_agentd
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
	echo "  bash build_zabbixagent.sh [-d debug] [-y install-without-confirmation]"
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
	printf -- "\n\nUsage: \n"
	printf -- "  If you get an error \" cannot open /tmp/zabbix_agentd.log\", \n"
	printf -- "  Change file permissions of Zabbix agent log file using the command :\n"
	printf -- "  \"sudo chmod 766 /tmp/zabbix_agentd.log\" and start Zabbix agent again. \n"
	printf -- "\n"
	printf -- "  Verify the installed Zabbix agent version with the following command:\n"
	printf -- "     zabbix_get -s <host_ip> -k \"agent.version\" \n"
}

###############################################################################################################

logDetails
checkPrequisites #Check Prequisites

case "$DISTRO" in
 "rhel-8.8" | "rhel-8.10" | "rhel-9.2" | "rhel-9.4" | "rhel-9.5")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for Zabbix agent from repository \n' |& tee -a "$LOG_FILE"
	sudo yum install -y tar wget make gcc pcre-devel |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"sles-15.6")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for Zabbix agent from repository \n' |& tee -a "$LOG_FILE"
	sudo zypper install -y tar wget make gcc awk pcre-devel |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"ubuntu-20.04" | "ubuntu-22.04" | "ubuntu-24.04" | "ubuntu-24.10")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for Zabbix agent from repository \n' |& tee -a "$LOG_FILE"
	sudo apt-get update >/dev/null
	sudo apt-get -y install tar wget make gcc libpcre3-dev |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "$LOG_FILE"
