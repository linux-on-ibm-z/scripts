#!/bin/bash
# © Copyright IBM Corporation 2019, 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/PhantomJS/build_phantomjs.sh
# Execute build script: bash build_phantomjs.sh    (provide -h for help)
#

set -e -o pipefail

PACKAGE_NAME="phantomjs"
PACKAGE_VERSION="2.1.1"

CONF_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/PhantomJS/patch"


CURDIR="$(pwd)"
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
FORCE="false"
TESTS="false"

trap cleanup 1 2 ERR

# Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
	mkdir -p "$CURDIR/logs/"
fi

source "/etc/os-release"

function checkPrequisites() {
	# Check Sudo exist
	if command -v "sudo" >/dev/null; then
		printf -- 'Sudo : Yes\n'
	else
		printf -- 'Sudo : No \n'
		printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n'
		exit 1
	fi

	if [[ "$FORCE" == "true" ]]; then
		printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
	else
		# Ask user for prerequisite installation
		printf -- "\n\nAs part of the installation , some package dependencies will be installed, \n"
		while true; do
			read -r -p "Do you want to continue (y/n) ? :  " yn
			case $yn in
			[Yy]*)
				printf -- 'User responded with Yes. \n' |& tee -a "$LOG_FILE"
				break
				;;
			[Nn]*) exit ;;
			*) echo "Please provide confirmation to proceed." ;;
			esac
		done
	fi

}

function cleanup() {
	sudo rm -rf "${CURDIR}/openssl"
	sudo rm -rf "${CURDIR}/curl"
	sudo rm -rf "${CURDIR}/curl/mk-ca-bundle.pl"
	sudo rm -rf "${CURDIR}/JSStringRef.h.diff" 
	printf -- 'Cleaned up the artifacts\n'
}

function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'

	# Build OpenSSL 1.0.2 for SLES 15 SP1 and RHEL 8.0
	if [[ "${DISTRO}" == "sles-15.1" ]] || [[ "${DISTRO}" == "rhel-8.0" ]]; then
		# Build OpenSSL 1.0.2
		cd "$CURDIR"

		#Check if directory exists
		if [ -d "$CURDIR/openssl/" ]; then
			rm -rf "$CURDIR/openssl"
			printf -- 'remove openssl directory success\n' 
		fi
		
		git clone  -b OpenSSL_1_0_2l git://github.com/openssl/openssl.git
		cd openssl
		./config --prefix=/usr --openssldir=/usr/local/openssl shared
		make
		sudo make install
	fi

	# gperf 3.1 and python alias for RHEL 8.0
	if [[ "${DISTRO}" == "rhel-8.0" ]]; then
	    # build and install gperf
	    cd $CURDIR
		wget http://ftp.gnu.org/pub/gnu/gperf/gperf-3.1.tar.gz
		tar xvf gperf-3.1.tar.gz
		cd gperf-3.1
		./configure
		make
		sudo make install
		export PATH=/usr/local/bin/:$PATH
        # link python -> python2
		sudo ln -sf /usr/bin/python2 /usr/bin/python
	fi

	# Curl 7.52.1 for SLES 15 SP1
	if [[ "${VERSION_ID}" == "15.1" ]]; then
		# Build cURL 7.52.1
		cd "$CURDIR"
		#Check if directory exsists
		if [ -d "$CURDIR/curl/" ]; then
			rm -rf "$CURDIR/curl"
			printf -- 'remove curl directory success\n' 
		fi

		git clone  -b curl-7_52_1 git://github.com/curl/curl.git
		cd curl
		./buildconf
		./configure --prefix=/usr/local --with-ssl --disable-shared
		make && sudo make install
		export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib64
		export PATH=/usr/local/bin:$PATH
		printf -- 'Build cURL success\n' 

		# Generate ca-bundle.crt for curl
		echo insecure >>"$HOME/.curlrc"
		sudo wget  https://raw.githubusercontent.com/curl/curl/curl-7_53_0/lib/mk-ca-bundle.pl
		pwd
		perl mk-ca-bundle.pl -k

		SSL_CERT_FILE=$(pwd)/ca-bundle.crt
		export SSL_CERT_FILE

		rm "$HOME/.curlrc"

		printf -- 'Build OpenSSL success\n' 
	fi

	# Install Phantomjs
	cd "$CURDIR"
	#Check if directory exsists
	if [ -d "$CURDIR/phantomjs/" ]; then
		rm -rf "$CURDIR/phantomjs"
		printf -- 'remove phantomjs directory success\n'
	fi

	git clone  -b "${PACKAGE_VERSION}" git://github.com/ariya/phantomjs.git
	cd phantomjs
	git submodule init
	git submodule update
	printf -- 'Clone Phantomjs repo success\n' 
	
	# Download  JSStringRef.h (SLES 15 SP1 and RHEL 8.0 Only)
	if [[ "${DISTRO}" == "sles-15.1" ]] || [[ "${DISTRO}" == "rhel-8.0" ]]; then
		# Patch config file
		curl -o "JSStringRef.h.diff"  $CONF_URL/JSStringRef.h.diff
		# replace config file
		patch "${CURDIR}/phantomjs/src/qt/qtwebkit/Source/JavaScriptCore/API/JSStringRef.h" JSStringRef.h.diff
		printf -- "Updated JSStringRef.h for %s \n" "$ID-$VERSION_ID"
	fi

	# Modify build.py for RHEL 8.0
	if [[ "${DISTRO}" == "rhel-8.0" ]]; then
		sed -i '202s/$/,/;203i\                "-no-pch"' ${CURDIR}/phantomjs/build.py
		printf -- "Updated build.py for %s \n" "$ID-$VERSION_ID"
	fi

	# Build Phantomjs
	python build.py
	printf -- 'Build Phantomjs success \n'
	# Add Phantomjs to /usr/bin
	sudo cp "${CURDIR}/phantomjs/bin/phantomjs" /usr/bin/
	printf -- 'Add Phantomjs to /usr/bin success \n' 

	# Run Tests
	runTest

	#Clean up
	cleanup

	#Verify if phantomjs is configured correctly
	if command -v "$PACKAGE_NAME" >/dev/null; then
		printf -- "%s installation completed. Please check the Usage to start the service.\n" "$PACKAGE_NAME" 
	else
		printf -- "Error while installing %s, exiting with 127 \n" "$PACKAGE_NAME"
		exit 127
	fi
}

function runTest() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- "TEST Flag is set, continue with running test \n"

		cd "${CURDIR}/phantomjs/test"
		python run-tests.py

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
	echo "  install.sh  [-d <debug>]  [-y install-without-confirmation] [-t install-with-tests]"
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
	printf -- "\n\nUsage: \n"
	printf -- "\n\nTo run PhantomJS , run the following command: \n"
	printf -- "\n\nFor Ubuntu: export QT_QPA_PLATFORM=offscreen \n"
	printf -- "\nphantomjs &   (Run in background)  \n"
	printf -- '\n'
}

###############################################################################################################
function verify_repo_install() {
	#Verify if package is configured correctly
	if command -v "$PACKAGE_NAME" >/dev/null; then
		printf -- "%s installation completed. Please check the Usage to start the service.\n" "$PACKAGE_NAME" 
	else
		printf -- "Error while installing %s, exiting with 127 \n" "$PACKAGE_NAME"
		exit 127
	fi
}

logDetails
checkPrequisites #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04" | "ubuntu-19.10")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	sudo apt-get update 

	printf -- 'Installing the PhantomJS from repository \n' |& tee -a "$LOG_FILE"
	sudo apt-get install -y phantomjs  |& tee -a "$LOG_FILE"
	verify_repo_install |& tee -a "$LOG_FILE"
	;;

"rhel-7.5" | "rhel-7.6" | "rhel-7.7")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for PhantomJS from repository \n' |& tee -a "$LOG_FILE"
	sudo yum -y  install gcc gcc-c++ make flex bison gperf ruby openssl-devel freetype-devel fontconfig-devel libicu-devel sqlite-devel libpng-devel libjpeg-devel libXfont.s390x libXfont-devel.s390x xorg-x11-utils.s390x xorg-x11-font-utils.s390x tzdata.noarch tzdata-java.noarch xorg-x11-fonts-Type1.noarch xorg-x11-font-utils.s390x python python-setuptools git wget tar |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"rhel-8.0")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for PhantomJS from repository \n' |& tee -a "$LOG_FILE"
	sudo yum -y install gcc gcc-c++ make flex bison ruby openssl-devel freetype-devel fontconfig-devel libicu-devel sqlite-devel libpng-devel libjpeg-devel xorg-x11-utils.s390x xorg-x11-font-utils.s390x tzdata.noarch tzdata-java.noarch xorg-x11-fonts-Type1.noarch xorg-x11-font-utils.s390x python2 python2-setuptools git wget tar patch |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"sles-12.4")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for PhantomJS from repository \n' |& tee -a "$LOG_FILE"
    sudo zypper install -y gcc gcc-c++ make flex bison gperf ruby openssl-devel freetype-devel fontconfig-devel libicu-devel sqlite-devel libpng-devel libjpeg-devel git xorg-x11-devel xorg-x11-essentials xorg-x11-fonts xorg-x11 xorg-x11-util-devel libXfont-devel libXfont1 python python-setuptools |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"sles-15.1")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for PhantomJS from repository \n' |& tee -a "$LOG_FILE"
    sudo zypper install -y gcc gcc-c++ make flex bison gperf ruby freetype2-devel fontconfig-devel libicu-devel sqlite3-devel libpng16-compat-devel libjpeg8-devel python2 python2-setuptools git xorg-x11-devel xorg-x11-essentials xorg-x11-fonts xorg-x11 xorg-x11-util-devel libXfont-devel libXfont1 autoconf automake libtool wget patch |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "$LOG_FILE"
