#!/usr/bin/env bash
# © Copyright IBM Corporation 2019, 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Puppet/6.5.0/build_puppet.sh
# Execute build script: bash build_puppet.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="puppet"
PACKAGE_VERSION="6.5.0"
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

source "/etc/os-release"

function checkPrequisites() {
	printf -- "Checking Prequisites\n"

	if [ -z "$USEAS" ]; then
		printf "Option -s must be specified with argument server/agent \n"
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
		sudo /usr/bin/gem install puppet -v $PACKAGE_VERSION 
	else
		cd "$CURDIR"
		sudo /usr/local/bin/gem install bundler rake-compiler
		cd "$CURDIR"
		sudo /usr/local/bin/gem install puppet -v $PACKAGE_VERSION 
	fi

	if [ "$USEAS" = "server" ]; then
	        printf -- 'Build puppetserver and Installation started \n'
	        printf -- 'Build jffi lib \n'
                cd $CURDIR
                if [[ "$DISTRO" ==  "sles-12.4" ]]; then
                    zypper install -y  java-1_8_0-openjdk-devel 
                    export JAVA_HOME=/usr/lib64/jvm/java-1.8.0-openjdk-1.8.0
                    export PATH=$JAVA_HOME/bin:$PATH
                else 
 
                	wget https://github.com/AdoptOpenJDK/openjdk8-binaries/releases/download/jdk8u222-b10/OpenJDK8U-jdk_s390x_linux_hotspot_8u222b10.tar.gz
                	tar zxf OpenJDK8U-jdk_s390x_linux_hotspot_8u222b10.tar.gz
                	export JAVA_HOME=$CURDIR/jdk8u222-b10
                	export PATH=$JAVA_HOME/bin:$PATH
                	if [[ "$ID" == "sles" ]]; then
                   	   sudo ln -s /usr/lib64/libffi.so.7 /usr/lib64/libffi.so.6     # sles only 
                 	fi
                fi 
                wget https://github.com/jnr/jffi/archive/jffi-1.2.18.tar.gz
                tar -xzvf jffi-1.2.18.tar.gz
                cd jffi-jffi-1.2.18
                ant jar
	        printf -- 'Download openjdk-11 and set up \n'
                cd $CURDIR
                wget https://github.com/AdoptOpenJDK/openjdk11-binaries/releases/download/jdk-11.0.3%2B7/OpenJDK11U-jdk_s390x_linux_hotspot_11.0.3_7.tar.gz
                tar xvf OpenJDK11U-jdk_s390x_linux_hotspot_11.0.3_7.tar.gz
                export JAVA_HOME=$CURDIR/jdk-11.0.3+7
                export PATH=$JAVA_HOME/bin:$PATH
	        printf -- 'Download lein   \n'
                wget https://raw.githubusercontent.com/technomancy/leiningen/stable/bin/lein
                chmod +x lein && sudo  mv lein /usr/bin/

	        printf -- 'Get puppetserver and build \n'
                cd $CURDIR
                git clone --recursive git://github.com/puppetlabs/puppetserver
                cd puppetserver
                git checkout 6.5.0
                cd ruby/puppet/
                git checkout 8cae8a17dbac08d2db0238d5bce2f1e4d1898d65
                cd ../..
                ./dev-setup	
	        printf -- 'Update  jruby jars\n'
                cd $CURDIR
                cp $CURDIR/jffi-jffi-1.2.18/build/native.jar  ~/.m2/repository/com/github/jnr/jffi/1.2.17/jffi-1.2.17-native.jar
                unzip ~/.m2/repository/org/jruby/jruby-stdlib/9.2.0.0/jruby-stdlib-9.2.0.0.jar

                cp META-INF/jruby.home/lib/ruby/stdlib/ffi/platform/powerpc-aix/*.rb META-INF/jruby.home/lib/ruby/stdlib/ffi/platform/s390x-linux/
 
                zip -r std.jar META-INF
                cp std.jar ~/.m2/repository/org/jruby/jruby-stdlib/9.2.0.0/jruby-stdlib-9.2.0.0.jar
	        printf -- 'completed build puppetserver\n'

		#Locate the $confdir by command
		confdir=~/.puppetlabs/etc/puppet
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
		printf -- "please enter the argument (server/agent) with option -s "
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
	echo "  build_puppet.sh [-s server/agent]  "
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
	printf -- "     For server installation, Set a user specified password for puppet user.\n"
	printf -- "      	-Running \"sudo passwd puppet\" will prompt for new password.\n"
	printf -- "     	-And please follow from step 2.12 in build instructions.\n"
	printf -- "     For agent installation, please follow from step 3.7 in build instructions\n"
	printf -- "  More information can be found here : https://puppetlabs.com/\n"
	printf -- '\n'
}

###############################################################################################################

logDetails
DISTRO="$ID-$VERSION_ID"
checkPrequisites #Check Prequisites

case "$DISTRO" in
"ubuntu-16.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for puppet from repository \n' |& tee -a "$LOG_FILE"
	sudo apt-get update >/dev/null
	sudo apt-get install -y g++ libreadline6 libreadline6-dev tar openssl unzip libyaml-dev libssl-dev make git wget libsqlite3-dev libc6-dev cron locales ruby ruby-dev iptables ant zip |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"ubuntu-18.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for puppet from repository \n' |& tee -a "$LOG_FILE"
	sudo apt-get update >/dev/null
	sudo apt-get install -y g++ libreadline7 libreadline-dev tar make git wget libsqlite3-dev libc6-dev cron locales unzip libyaml-dev zlibc zlib1g-dev zlib1g libxml2-dev libgdbm-dev openssl1.0 libssl1.0-dev ant zip |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"rhel-7.7" | "rhel-7.5" | "rhel-7.6" | "rhel-8.0")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for puppet from repository \n' |& tee -a "$LOG_FILE"

	if [[ "$ID" == "rhel" && "$VERSION_ID" == "8.0" ]]; then	
	sudo yum update -y |& tee -a "$LOG_FILE"
	sudo yum install -y gcc-c++ readline-devel tar openssl unzip libyaml PackageKit-cron openssl-devel make git wget sqlite-devel glibc-common hostname procps-ng diffutils glibc-langpack-en ant zip |& tee -a "$LOG_FILE"

	else
	
	sudo yum install -y gcc-c++ readline-devel tar openssl unzip libyaml-devel PackageKit-cron openssl-devel make git wget sqlite-devel glibc-common hostname ant zip |& tee -a "$LOG_FILE"
	fi
	configureAndInstall |& tee -a "$LOG_FILE"
	
	;;

"sles-12.4" | "sles-15.1")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for puppet from repository \n' |& tee -a "$LOG_FILE"
	
	sudo zypper install -y gawk gzip gcc-c++ readline-devel tar openssl unzip libopenssl-devel make git wget sqlite-devel glibc-locale cron net-tools curl ant zip|& tee -a "$LOG_FILE"
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
