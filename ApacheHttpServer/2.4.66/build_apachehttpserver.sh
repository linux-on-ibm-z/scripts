#!/usr/bin/env bash
# © Copyright IBM Corporation 2025.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ApacheHttpServer/2.4.66/build_apachehttpserver.sh
# Execute build script: bash build_apachehttpserver.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="apachehttpserver"
PACKAGE_VERSION="2.4.66"
APR_VERSION="1.7.6"
APR_UTIL_VERSION="1.6.3"
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
		printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n'
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
	printf -- 'No artifacts to be cleaned.\n'
}

function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'
  
	#Creating daemon user for sles 15.7
	if [[ "$ID-$VERSION_ID" == "sles-15.7" ]]; then
         sudo ln -s /usr/bin/python3 /usr/bin/python 
	       sudo groupadd daemon
	       sudo useradd -G daemon daemon
	fi

	#Download the source code
	printf -- 'Downloading apachehttpserver and supporting packages \n'
	cd "$CURDIR"
	git clone -b "$PACKAGE_VERSION" https://github.com/apache/httpd.git

	cd "$CURDIR/httpd/srclib"
	git clone -b "$APR_VERSION" https://github.com/apache/apr.git

	cd "$CURDIR/httpd/srclib"
	git clone -b "$APR_UTIL_VERSION" https://github.com/apache/apr-util.git

	#Building http server
	printf -- 'Building http server \n'
	cd "$CURDIR/httpd"
	./buildconf
	./configure --with-included-apr --prefix=/usr/local

	#Installation step
	make
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
	echo "  bash build_apachehttpserver.sh [-d debug] [-h help] [-y install without user prompt]"
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
	printf -- " Apache Http server installed successfully \n"
	printf -- " More information can be found here : https://github.com/apache/httpd \n"
	printf -- '\n'
}

###############################################################################################################

logDetails
checkPrequisites #Check Prequisites
DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"rhel-8.10" | "rhel-9.4" | "rhel-9.6" )
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- 'Installing the dependencies for HTTP server from repository \n' |& tee -a "$LOG_FILE"
    sudo yum install -y git openssl openssl-devel python3 gcc libtool autoconf make pcre pcre-devel libxml2 libxml2-devel expat-devel diffutils file which procps wget tar |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-10.0")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- 'Installing the dependencies for HTTP server from repository \n' |& tee -a "$LOG_FILE"
    sudo yum install -y git openssl openssl-devel python3 gcc libtool autoconf make pcre2 pcre2-devel libxml2 libxml2-devel expat-devel diffutils file which procps wget tar |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-15.7")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- 'Installing the dependencies for HTTP server from repository \n' |& tee -a "$LOG_FILE"
    sudo zypper install -y git openssl libopenssl-devel python3 gcc libtool autoconf make libpcre1 pcre-devel libxml2-tools libxml2-devel libexpat-devel which procps wget tar awk |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"ubuntu-22.04" | "ubuntu-24.04" | "ubuntu-25.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    sudo apt-get update >/dev/null
    sudo apt-get install -y git python3 openssl gcc autoconf2.69 make libtool-bin libpcre3-dev libxml2 libexpat1 libexpat1-dev wget tar |& tee -a "$LOG_FILE"
    sudo ln -s /usr/bin/python3 /usr/bin/python
    sudo rm -rf /usr/bin/autoconf
    sudo ln -s /usr/bin/autoconf2.69 /usr/bin/autoconf
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"ubuntu-25.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    sudo apt-get update >/dev/null
    sudo apt-get install -y git python3 openssl gcc autoconf2.69 make libtool-bin libpcre3-dev libxml2-dev libexpat1 libexpat1-dev wget tar |& tee -a "$LOG_FILE"
    sudo ln -s /usr/bin/python3 /usr/bin/python
    sudo rm -rf /usr/bin/autoconf
    sudo ln -s /usr/bin/autoconf2.69 /usr/bin/autoconf
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac
gettingStarted |& tee -a "$LOG_FILE"
