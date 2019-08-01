#!/usr/bin/env bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Puppet/5.5.2/build_puppet.sh
# Execute build script: bash build_puppet.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="puppet"
PACKAGE_VERSION="5.5.2"
CURDIR="$(pwd)"
RUBY_VERSION="2.4.5"
OPENSSL_VERSION="1.0.2k"

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
	printf -- "Checking Prequisites\n"

	if [ -z "$USEAS" ]; then
		printf "Option -s must be specified with argument master/agent \n"
		exit
	fi

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

	if [[ ("$ID" == "sles" || "$ID" == "rhel") && -f "ruby"-${RUBY_VERSION}.tar.gz ]]; then
		sudo rm "ruby"-${RUBY_VERSION}.tar.gz
	fi

	if [[ "$ID" == "sles" && -f "openssl"-${OPENSSL_VERSION}.tar.gz ]]; then
		sudo rm "ruby"-${RUBY_VERSION}.tar.gz
		printf -- 'Cleaned up the artifacts\n' >>"$LOG_FILE"
	fi

	if [[ "$ID" == "ubuntu" ]]; then
		printf -- 'No artifacts to be cleaned.\n'
	fi
}

function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'
	#Download and install Ruby
	if [[ "$ID" == "rhel" ]]; then
		cd "$CURDIR"
		wget http://cache.ruby-lang.org/pub/ruby/2.4/ruby-2.4.5.tar.gz
		tar -xvf ruby-2.4.5.tar.gz
		cd ruby-2.4.5
		./configure && make && sudo -E make install
	fi

	if [[ "$ID" == "sles" ]]; then
		cd "$CURDIR"
		wget http://cache.ruby-lang.org/pub/ruby/2.4/ruby-2.4.5.tar.gz
		tar -xvf ruby-2.4.5.tar.gz
		cd ruby-2.4.5
		./configure LDFLAGS='-L/$CURDIR/openssl-1.0.2k' --with-openssl-include=/$CURDIR/openssl-1.0.2k/include --with-openssl-dir=/usr/
		make && sudo -E make install
	fi

	if [[ "$ID" == "ubuntu" && "$VERSION_ID" == "18.04" ]]; then
		cd "$CURDIR"
		wget http://cache.ruby-lang.org/pub/ruby/2.4/ruby-2.4.1.tar.gz
		tar -xvf ruby-2.4.1.tar.gz
		cd ruby-2.4.1
		./configure && make && sudo -E make install
	fi

	#Install bundler
	if [[ "$ID" == "ubuntu" && "$VERSION_ID" == "16.04" ]]; then
		cd "$CURDIR"
		sudo /usr/bin/gem install bundler rake-compiler
		cd "$CURDIR"
		sudo /usr/bin/gem install puppet -v 5.5.2
	else
		cd "$CURDIR"
		sudo /usr/local/bin/gem install bundler rake-compiler
		cd "$CURDIR"
		sudo /usr/local/bin/gem install puppet -v 5.5.2
	fi

	if [ "$USEAS" = "master" ]; then
		#Locate the $confdir by command
		confdir=$(puppet master --configprint confdir)
		echo "$confdir"
		if [[ ! -f "$confdir" ]]; then
			mkdir -p "$confdir"
		fi

		# Add sample puppet.conf
		mkdir "$confdir"/modules
		mkdir "$confdir"/manifests
		cd "$confdir"
		touch puppet.conf
		wget https://raw.githubusercontent.com/puppetlabs/puppet/master/conf/auth.conf
		mkdir -p "$confdir"/opt/puppetlabs/puppet
		mkdir -p "$confdir"/var/log/puppetlabs

		# Create "puppet" user and group
		sudo useradd -d /home/puppet -m -s /bin/bash puppet
		sudo /usr/local/bin/puppet resource group puppet ensure=present

	elif [ "$USEAS" = "agent" ]; then
		#Locate the $confdir by command
		confdir=$(puppet agent --configprint confdir)
		echo "$confdir"
		if [[ ! -f "$confdir" ]]; then
			mkdir -p "$confdir"
		fi

		cd "$confdir"
		mkdir -p "$confdir"/opt/puppetlabs/puppet
		mkdir -p "$confdir"/var/log/puppetlabs
		touch puppet.conf
	else
		printf -- "please enter the argument (master/agent) with option -s "
		exit
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
	echo "  build_puppet.sh [-s master/agent]  [-d debug]"
	echo
}

while getopts "h?dy?s:" opt; do
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
	s)
		export USEAS=$OPTARG
		;;
	esac
done

function gettingStarted() {

	printf -- "\n\nUsage: \n"
	printf -- "  puppet installed successfully \n"
	printf -- "     For master installation, Set a user specified password for puppet user.\n"
	printf -- "      	-Running \"sudo passwd puppet\" will prompt for new password.\n"
	printf -- "     	-And please follow from step 2.8 in build instructions.\n"
	printf -- "     For agent installation, please follow from step 3.7 in build instructions\n"
	printf -- "  More information can be found here : https://puppetlabs.com/\n"
	printf -- "  More information about test cases can be found here : https://tickets.puppetlabs.com/browse/PUP-8708 \n"
	printf -- '\n'
}

###############################################################################################################

logDetails
checkPrequisites #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for puppet from repository \n' |& tee -a "$LOG_FILE"
	sudo apt-get update >/dev/null
	sudo apt-get install -y g++ libreadline6 libreadline6-dev tar openssl unzip libyaml-dev libssl-dev make git wget libsqlite3-dev libc6-dev cron locales ruby ruby-dev iptables |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"ubuntu-18.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for puppet from repository \n' |& tee -a "$LOG_FILE"
	sudo apt-get update >/dev/null
	sudo apt-get install -y g++ libreadline7 libreadline-dev tar make git wget libsqlite3-dev libc6-dev cron locales unzip libyaml-dev zlibc zlib1g-dev zlib1g libxml2-dev libgdbm-dev openssl1.0 libssl1.0-dev |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"rhel-6.x" | "rhel-7.4" | "rhel-7.5" | "rhel-7.6" | "rhel-8.0")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for puppet from repository \n' |& tee -a "$LOG_FILE"

	if [[ "$ID" == "rhel" && "$VERSION_ID" == "8.0" ]]; then	
	sudo yum update -y |& tee -a "$LOG_FILE"
	sudo yum install -y gcc-c++ readline-devel tar openssl unzip libyaml PackageKit-cron openssl-devel make git wget sqlite-devel glibc-common hostname procps-ng diffutils glibc-langpack-en |& tee -a "$LOG_FILE"

	else
	
	sudo yum install -y gcc-c++ readline-devel tar openssl unzip libyaml-devel PackageKit-cron openssl-devel make git wget sqlite-devel glibc-common hostname |& tee -a "$LOG_FILE"
	fi
	configureAndInstall |& tee -a "$LOG_FILE"
	
	;;

"sles-12.4" | "sles-15")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for puppet from repository \n' |& tee -a "$LOG_FILE"
	sudo zypper install -y gcc-c++ readline-devel tar openssl unzip libopenssl-devel make git wget sqlite-devel glibc-locale cron net-tools curl |& tee -a "$LOG_FILE"
	#Build Openssl 1.0.2k
	cd "$CURDIR"
	wget https://www.openssl.org/source/old/1.0.2/openssl-1.0.2k.tar.gz
	tar zxf openssl-1.0.2k.tar.gz
	cd openssl-1.0.2k
	./config --prefix=/usr --openssldir=/etc/ssl --libdir=lib shared zlib-dynamic
	make
	sudo make install
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "$LOG_FILE"
