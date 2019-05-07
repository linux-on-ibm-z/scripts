#!/usr/bin/env bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Zabbix/4.2.0/build_zabbixserver.sh
# Execute build script: bash build_zabbixserver.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="zabbixserver"
URL_NAME="zabbix"
PACKAGE_VERSION="4.2.0"
PHP_VERSION="5.6.8"
CURDIR="$(pwd)"
BUILD_DIR="/usr/local/share"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Zabbix/${PACKAGE_VERSION}/patch"

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

	if [ -f ${URL_NAME}-${PACKAGE_VERSION}.tar.gz ]; then
		sudo rm ${URL_NAME}-${PACKAGE_VERSION}.tar.gz
	fi

	if [[ ("$ID" == "rhel" && "$VERSION_ID" == "6.10") && -f php-$PHP_VERSION.tar.gz ]]; then
		sudo rm php-$PHP_VERSION.tar.gz
	fi
	printf -- 'Cleaned up the artifacts\n' >>"$LOG_FILE"
}

function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'

	# Installing PHP for rhel 6.10
	if [[ "$ID" == "rhel" && "$VERSION_ID" == "6.10" ]]; then
		cd /"$CURDIR"/
		wget http://www.php.net/distributions/php-"$PHP_VERSION".tar.gz
		sudo tar xvzf php-"$PHP_VERSION".tar.gz -C "$BUILD_DIR"
		cd /"$BUILD_DIR"/php-"$PHP_VERSION"
		sudo ./configure --prefix=/usr/local/php --with-apxs2=/usr/sbin/apxs --with-config-file-path=/usr/local/php --with-mysql --with-gd --with-zlib --with-gettext --enable-bcmath --enable-mbstring --enable-sockets --with-jpeg-dir --with-png-dir --with-jpeg-dir=/usr/include/jpeglib.h --enable-gd-native-ttf --enable-ctype --with-mysqli --with-freetype-dir=/usr/lib --with-ldap --with-libdir=lib64
		sudo make
		sudo make install
		sudo cp /"$BUILD_DIR"/php-"$PHP_VERSION"/php.ini-development /usr/local/php/php.ini
	fi

	# Configure httpd to enable PHP
	if [[ "$ID" == "rhel" ]]; then
		if [[ "$VERSION_ID" == "6.10" ]]; then
			curl -o "rhel6-httpd.conf" $PATCH_URL/rhel6-httpd.conf.diff
			sudo patch "/etc/httpd/conf/httpd.conf" "rhel6-httpd.conf"
			sudo rm rhel6-httpd.conf
		fi

		if [[ "$VERSION_ID" == "7.4" || "$VERSION_ID" == "7.5" || "$VERSION_ID" == "7.6" ]]; then
			curl -o "rhel7-httpd.conf" $PATCH_URL/rhel7.x-httpd.conf.diff
			sudo patch "/etc/httpd/conf/httpd.conf" "rhel7-httpd.conf"
			sudo rm rhel7-httpd.conf
		fi
	fi

	if [[ "$ID" == "sles" ]]; then
		if [[ "$VERSION_ID" == "12.4" ]]; then
			curl -o "sles12-httpd.conf" $PATCH_URL/sles12-httpd.conf.diff
			sudo patch "/etc/apache2/httpd.conf" "sles12-httpd.conf"
			sudo rm sles12-httpd.conf
		fi

		if [[ "$VERSION_ID" == "15" ]]; then
			curl -o "sles15-httpd.conf" $PATCH_URL/sles15-httpd.conf.diff
			sudo patch "/etc/apache2/httpd.conf" "sles15-httpd.conf"
			sudo rm sles15-httpd.conf
		fi
	fi

	if [[ "$ID" == "ubuntu" ]]; then
		if [[ "$VERSION_ID" == "16.04" ]]; then
			curl -o "ubuntu16-apache2.conf" $PATCH_URL/ubuntu16-apache2.conf.diff
			sudo patch "/etc/apache2/apache2.conf" "ubuntu16-apache2.conf"
			sudo rm ubuntu16-apache2.conf
		fi

		if [[ "$VERSION_ID" == "18.04" || "$VERSION_ID" == "19.04" ]]; then
			curl -o "ubuntu18-apache2.conf" $PATCH_URL/ubuntu18-apache2.conf.diff
			sudo patch "/etc/apache2/apache2.conf" "ubuntu18-apache2.conf"
			sudo rm ubuntu18-apache2.conf
		fi
	fi

	#Download and install zabbix server
	cd /"$CURDIR"/
	wget https://versaweb.dl.sourceforge.net/project/${URL_NAME}/ZABBIX%20Latest%20Stable/${PACKAGE_VERSION}/${URL_NAME}-${PACKAGE_VERSION}.tar.gz
	sudo tar -xvf ${URL_NAME}-${PACKAGE_VERSION}.tar.gz -C $BUILD_DIR

	cd /"$BUILD_DIR"/${URL_NAME}-${PACKAGE_VERSION}
	sudo ./configure --enable-server --with-mysql --enable-ipv6 --with-net-snmp --with-libcurl --with-libxml2

	# Installation
	sudo make
	sudo make install

	# Creating a user
	sudo /usr/sbin/groupadd ${URL_NAME} || echo "group already exist"
	sudo /usr/sbin/useradd -g ${URL_NAME} ${URL_NAME} || echo "user already exist"

	# Installing Zabbix web interface
	if [[ "$ID" == "ubuntu" || "$ID" == "rhel" ]]; then
		cd /"$BUILD_DIR"/${URL_NAME}-${PACKAGE_VERSION}/frontends/php/
		sudo mkdir -p /var/www/html/${URL_NAME}
		sudo cp -rf * /var/www/html/${URL_NAME}/
		cd /var/www/html/${URL_NAME}
		sudo chown -R ${URL_NAME}:${URL_NAME} conf
	fi

	if [[ "$ID" == "sles" ]]; then
		cd /"$BUILD_DIR"/${URL_NAME}-${PACKAGE_VERSION}/frontends/php/
		sudo mkdir -p /srv/www/htdocs/${URL_NAME}
		sudo cp -rf * /srv/www/htdocs/${URL_NAME}
		cd /srv/www/htdocs/${URL_NAME}
		sudo chown -R ${URL_NAME}:${URL_NAME} conf
	fi

	#cleanup
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
	echo "  build_zabbixserver.sh [-d debug]"
	echo
}

while getopts "h?d" opt; do
	case "$opt" in
	h | \?)
		printHelp
		exit 0
		;;
	d)
		set -x
		;;
	esac
done

function gettingStarted() {

	printf -- " Please follow following steps from the build instructions to complete the installation :\n"
	printf -- " Step 5: Prerequisites to start Zabbix server. \n"
	printf -- "      a) Start httpd server. \n"
	printf -- "      b) Start MySQL/MariaDB service in a directory with proper permissions. \n"
	printf -- "      c) Create database and grant privileges to zabbix user. \n"
	printf -- " Step 6: Change php.ini for the respective distribution. \n"
	printf -- " Step 7: Start Zabbix server. \n"
	printf -- "      a) Start Zabbix server and restart http service. \n"
	printf -- "      b) Verify the installed Zabbix server version with the given command. \n"
	printf -- "      c) After starting Zabbix server, direct your Web browser to the Zabbix Console. "
	printf -- "\n\nReference: \n"
	printf -- " More information can be found here : https://www.zabbix.com/documentation/4.0/manual/installation\n"
	printf -- '\n'
	printf -- ""
}

###############################################################################################################

logDetails
checkPrequisites #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for Zabbix server from repository \n' |& tee -a "$LOG_FILE"
	sudo apt-get update >/dev/null
	sudo apt-get -y install wget curl vim gcc make snmp snmptrapd ceph libmysqld-dev libmysqlclient-dev libxml2-dev libsnmp-dev libcurl3 libcurl4-openssl-dev git apache2 php php-mysql libapache2-mod-php mysql-server php7.0-xml php7.0-gd php-bcmath php-mbstring php7.0-ldap libevent-dev libpcre3-dev |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"ubuntu-18.04" | "ubuntu-19.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for Zabbix server from repository \n' |& tee -a "$LOG_FILE"
	sudo apt-get update >/dev/null
	sudo apt-get -y install wget curl vim gcc make snmp snmptrapd ceph libmysqld-dev libmysqlclient-dev libxml2-dev libsnmp-dev libcurl4 libcurl4-openssl-dev git apache2 php php-mysql libapache2-mod-php mysql-server php7.2-xml php7.2-gd php-bcmath php-mbstring php7.2-ldap libevent-dev libpcre3-dev |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"rhel-6.x")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for Zabbix server from repository \n' |& tee -a "$LOG_FILE"
	sudo yum install -y tar wget curl vim gcc pcre pcre-devel make net-snmp net-snmp-devel httpd-devel mysql mysql-server mysql-devel mysql-libs git httpd libcurl-devel libxml2-devel libjpeg-devel libpng-devel freetype freetype-devel openldap openldap-devel libevent-devel pcre-devel patch |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"rhel-7.4" | "rhel-7.5" | "rhel-7.6")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for Zabbix server from repository \n' |& tee -a "$LOG_FILE"
	sudo yum install -y httpd tar wget curl vim gcc make net-snmp net-snmp-devel mariadb mariadb-server mariadb-devel php-mysql mariadb-libs git httpd php php-mysql libcurl-devel libxml2-devel php-xml php-gd php-bcmath php-mbstring php-ldap libevent-devel pcre-devel patch |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"sles-12.4")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for Zabbix server from repository \n' |& tee -a "$LOG_FILE"
	sudo zypper install -y wget tar curl vim gcc make net-snmp net-snmp-devel mariadb libmysqld-devel net-tools git apache2 apache2-devel apache2-mod_php5 php5 php5-mysql php5-xmlreader php5-xmlwriter php5-gd php5-bcmath php5-mbstring php5-ctype php5-sockets php5-gettext libcurl-devel libxml2 libxml2-devel openldap2-devel openldap2 php5-ldap libevent-devel pcre-devel patch |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"sles-15")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for Zabbix server from repository \n' |& tee -a "$LOG_FILE"
	sudo zypper install -y wget tar curl vim gcc make net-snmp net-snmp-devel mariadb libmysqld-devel net-tools git apache2 apache2-devel apache2-mod_php7 php7 php7-mysql php7-xmlreader php7-xmlwriter php7-gd php7-bcmath php7-mbstring php7-ctype php7-sockets php7-gettext libcurl-devel libxml2 libxml2-devel openldap2-devel openldap2 php7-ldap libevent-devel pcre-devel patch |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "$LOG_FILE"
