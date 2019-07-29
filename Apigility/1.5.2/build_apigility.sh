#!/usr/bin/env bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Apigility/1.5.2/build_apigility.sh
# Execute build script: bash build_apigility.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="apigility"
PACKAGE_VERSION="1.5.2"
PHP_VERSION="5.6.8"
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
	DISTRO="$ID-$VERSION_ID"
	if [[ ("$DISTRO" == "rhel-7."* || "$ID" == "sles") && -f php-$PHP_VERSION.tar.gz ]]; then
		sudo rm php-$PHP_VERSION.tar.gz
	else
		printf -- 'No artifacts to be cleaned.\n'
	fi
}

function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'

	# Installing PHP for rhel & sles
	DISTRO="$ID-$VERSION_ID"
	if [[ "$DISTRO" == "rhel-7."* || "$ID" == "sles" ]]; then
		#Install Apache Http server
		wget "https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ApacheHttpServer/2.4.39/build_apachehttpserver.sh"
		chmod +x build_apachehttpserver.sh
		bash build_apachehttpserver.sh >>"$LOG_FILE"

		#Install Open SSL
		cd /"$CURDIR"/
		git clone git://github.com/openssl/openssl.git
		cd openssl
		git checkout OpenSSL_1_0_2l
		./config --prefix=/usr --openssldir=/usr/local/openssl shared
		make
		sudo make install

		#Install PHP
		cd /"$CURDIR"/
		wget http://www.php.net/distributions/php-"$PHP_VERSION".tar.gz
		sudo tar xvzf php-"$PHP_VERSION".tar.gz -C "$BUILD_DIR"
		cd /"$BUILD_DIR"/php-"$PHP_VERSION"
		sudo ./configure --prefix=/usr/local/php --with-apxs2=/usr/local/apache2/bin/apxs --with-config-file-path=/usr/local/php --with-mysql --with-openssl --enable-mbstring --enable-xml
		sudo make
		sudo make install
		export PATH=/usr/local/php/bin:$PATH
	fi

	if [[ "$ID" == "ubuntu" ]]; then
		sudo apt-get install -y php php-mbstring php-xml
	fi

	#Get the source for Apigility
	cd /"$CURDIR"/
	git clone https://github.com/zfcampus/zf-apigility-skeleton.git
	cd zf-apigility-skeleton
	git checkout 1.5.2

	#Install composer
	curl -s https://getcomposer.org/installer | php --
	./composer.phar -n update
	./composer.phar -n install

	#Put the skeleton/app in development mode
	./vendor/bin/zf-development-mode enable

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
	echo " build_apigility.sh  [-d debug] [-y install-without-confirmation]"
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

	printf -- "\n\nUsage: \n"
	printf -- "  Apigility installed successfully \n"
	printf -- "  For rhel and sles, run : \n"
	printf -- '  export PATH=/usr/local/php/bin:$PATH \n'
	printf -- "  More information can be found here : https://github.com/zfcampus/zf-apigility-skeleton \n"
	printf -- '\n'
}

###############################################################################################################

logDetails
checkPrequisites #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for apigility from repository \n' |& tee -a "$LOG_FILE"
	sudo apt-get update -y >/dev/null
	sudo apt-get install -y git apache2 curl openssl make wget tar gcc libssl-dev libxml2 libxml2-dev libxml-parser-perl pkg-config |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"rhel-6.x")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for apigility from repository \n' |& tee -a "$LOG_FILE"
	sudo yum install -y curl openssl openssl-devel git wget gcc tar libtool autoconf make pcre pcre-devel libxml2 libxml2-devel libexpat-devel |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"rhel-7.4" | "rhel-7.5" | "rhel-7.6")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for apigility from repository \n' |& tee -a "$LOG_FILE"
	sudo yum install -y curl openssl openssl-devel git wget gcc tar libtool autoconf make pcre pcre-devel libxml2 libxml2-devel libexpat-devel hostname |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;
	
"rhel-8.0")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for apigility from repository \n' |& tee -a "$LOG_FILE"
	sudo yum install -y curl openssl openssl-devel git wget gcc tar libtool autoconf make pcre pcre-devel libxml2 libxml2-devel php.s390x php-devel.s390x php-json.s390x expat.s390x php-mbstring.s390x php-xml.s390x hostname httpd-devel.s390x httpd.s390x |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"sles-12.4")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for apigility from repository \n' |& tee -a "$LOG_FILE"
	sudo zypper install -y curl openssl openssl-devel git wget gcc tar libtool autoconf make pcre pcre-devel libxml2 libxml2-devel libexpat-devel |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"sles-15")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for apigility from repository \n' |& tee -a "$LOG_FILE"
	sudo zypper install -y curl openssl libopenssl-devel git wget gcc tar libtool autoconf make libpcre1 pcre-devel libxml2-tools libxml2-devel libexpat-devel |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "$LOG_FILE"
