#!/usr/bin/env bash
# © Copyright IBM Corporation 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Puppet/6.18.0/build_puppet.sh
# Execute build script: bash build_puppet.sh    (provide -h for help)

set -e -o pipefail

SOURCE_ROOT="$(pwd)"
PACKAGE_NAME="Puppet"
PACKAGE_VERSION="6.18.0"
SERVER_VERSION="6.13.0"
AGENT_VERSION="6.18.0"
RUBY_VERSION="2.7"
RUBY_FULL_VERSION="2.7.1"
JFFI_VERSION="1.2.23"
JRUBY_VERSION="9.2.13.0"
FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

JDK8_URL="https://github.com/AdoptOpenJDK/openjdk8-binaries/releases/download/jdk8u265-b01_openj9-0.21.0/OpenJDK8U-jdk_s390x_linux_openj9_8u265b01_openj9-0.21.0.tar.gz"
JDK11_URL="https://github.com/AdoptOpenJDK/openjdk11-binaries/releases/download/jdk-11.0.8%2B10/OpenJDK11U-jdk_s390x_linux_hotspot_11.0.8_10.tar.gz"

trap cleanup 0 1 2 ERR

#Check if directory exsists
if [ ! -d "$SOURCE_ROOT/logs" ]; then
	mkdir -p "$SOURCE_ROOT/logs"
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
	if [[ -f "ruby"-${RUBY_VERSION}.tar.gz ]]; then
		sudo rm "ruby"-${RUBY_VERSION}.tar.gz
		printf -- 'Cleaned up the artifacts\n' >>"$LOG_FILE"
	fi
}

function buildAgent() {
	#Install Puppet
	cd "$SOURCE_ROOT"
	sudo -E env PATH="$PATH" gem install facter -v 2.5.7
	sudo -E env PATH="$PATH" gem install puppet -v $PACKAGE_VERSION

	printf -- 'Completed Puppet agent setup \n'
}

function buildServer() {
	printf -- 'Build puppetserver and Installation started \n'

	printf -- 'Build jffi lib \n'
	cd $SOURCE_ROOT
	# install OpenJDK 8 and use it to build jffi
	wget -O openjdk8.tar.gz "$JDK8_URL"
	mkdir openjdk8
	tar -zxvf openjdk8.tar.gz -C openjdk8/ --strip-components 1
	wget https://github.com/jnr/jffi/archive/jffi-$JFFI_VERSION.tar.gz
	tar xzf jffi-$JFFI_VERSION.tar.gz
	cd jffi-jffi-$JFFI_VERSION
	JAVA_HOME="${SOURCE_ROOT}/openjdk8" PATH="${SOURCE_ROOT}/openjdk8/bin:${PATH}" ant jar

	printf -- 'Install lein \n'
	cd $SOURCE_ROOT
	wget https://raw.githubusercontent.com/technomancy/leiningen/stable/bin/lein
	chmod +x lein
	sudo mv lein /usr/bin/

	printf -- 'Install OpenJDK 11 \n'
	cd $SOURCE_ROOT
	wget -O openjdk11.tar.gz "$JDK11_URL"
	mkdir openjdk11
	tar -zxvf openjdk11.tar.gz -C openjdk11/ --strip-components 1
	export JAVA_HOME="${SOURCE_ROOT}/openjdk11"
	export PATH="${JAVA_HOME}/bin:${PATH}"

	printf -- 'Get puppetserver \n'
	cd $SOURCE_ROOT
	git clone --recursive --branch $SERVER_VERSION git://github.com/puppetlabs/puppetserver
	cd puppetserver

	printf -- 'Setup config files \n'
	if [[ "$VERSION_ID" != "8.2" ]]; then
		export LANG="en_US.UTF-8"
	fi
	./dev-setup
	cp $SOURCE_ROOT/jffi-jffi-$JFFI_VERSION/build/native.jar  ~/.m2/repository/com/github/jnr/jffi/$JFFI_VERSION/jffi-$JFFI_VERSION-native.jar
	# remove invalid gems
	rm -f ~/.puppetlabs/opt/server/data/puppetserver/vendored-jruby-gems/cache/*.gem
	# re-run
	./dev-setup

	printf -- 'Update JRuby jars\n'
	cd $SOURCE_ROOT
	unzip -q ~/.m2/repository/org/jruby/jruby-stdlib/$JRUBY_VERSION/jruby-stdlib-$JRUBY_VERSION.jar
	cp META-INF/jruby.home/lib/ruby/stdlib/ffi/platform/powerpc-aix/*.rb META-INF/jruby.home/lib/ruby/stdlib/ffi/platform/s390x-linux/
	cp META-INF/jruby.home/lib/ruby/stdlib/ffi/platform/powerpc-aix/platform.conf META-INF/jruby.home/lib/ruby/stdlib/ffi/platform/s390x-linux/
	zip -qr std.jar META-INF
	cp std.jar ~/.m2/repository/org/jruby/jruby-stdlib/$JRUBY_VERSION/jruby-stdlib-$JRUBY_VERSION.jar
	sudo rm -rf META-INF std.jar

	printf -- 'Completed Puppet server setup \n'

}

function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'
	# Download and install Ruby
	if [[ ("$ID" == "rhel" || "$ID" == "sles" )]]; then
		cd "$SOURCE_ROOT"
		wget http://cache.ruby-lang.org/pub/ruby/$RUBY_VERSION/ruby-$RUBY_FULL_VERSION.tar.gz
		tar -xzf ruby-$RUBY_FULL_VERSION.tar.gz
		cd ruby-$RUBY_FULL_VERSION
		./configure && make && sudo -E env PATH="$PATH" make install
	fi

	# Install bundler
	sudo -E env PATH="$PATH" gem install bundler rake-compiler

	# Build server or agent
	if [ "$USEAS" = "server" ]; then
		buildServer
	elif [ "$USEAS" = "agent" ]; then
		buildAgent
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
	printf -- "Puppet installed successfully. \n"
	printf -- '\n'
	printf -- "     To run Puppet server, set the environment variables below and follow from step 2.9 in build instructions.\n"
	printf -- "     	export JAVA_HOME=$SOURCE_ROOT/openjdk11\n"
	printf -- "     	export PATH=\$JAVA_HOME/bin:\$PATH\n"
	printf -- '\n'
	printf -- "     To run Puppet agent, follow from step 3.4 in build instructions.\n"
	printf -- '\n'
	printf -- "More information can be found here : https://puppetlabs.com/\n"
	printf -- '\n'
}


###############################################################################################################

logDetails
DISTRO="$ID-$VERSION_ID"
checkPrequisites #Check Prequisites

case "$DISTRO" in
"ubuntu-18.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
	sudo apt-get update >/dev/null
	if [ "$USEAS" = "server" ]; then
		sudo apt-get install -y g++ libreadline7 libreadline-dev tar make git wget libsqlite3-dev libc6-dev cron locales locales-all unzip libyaml-dev zlibc zlib1g-dev zlib1g libxml2-dev libgdbm-dev openssl1.0 libssl1.0-dev ruby ruby-dev ant zip  |& tee -a "$LOG_FILE"
	elif [ "$USEAS" = "agent" ]; then
		sudo apt-get install -y g++ tar make wget openssl1.0 libssl1.0-dev ruby ruby-dev |& tee -a "$LOG_FILE"
	else
		printf -- "please enter the argument (server/agent) with option -s "
		exit
	fi
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"ubuntu-20.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
	sudo apt-get update >/dev/null
	if [ "$USEAS" = "server" ]; then
		sudo apt-get install -y g++ tar make git wget libsqlite3-dev libc6-dev cron locales locales-all unzip libyaml-dev zlibc zlib1g-dev zlib1g libxml2-dev libgdbm-dev libffi7 ruby ruby-dev ant zip  |& tee -a "$LOG_FILE"
	elif [ "$USEAS" = "agent" ]; then
		sudo apt-get install -y g++ tar make wget ruby ruby-dev libffi7 |& tee -a "$LOG_FILE"
	else
		printf -- "please enter the argument (server/agent) with option -s "
		exit
	fi
	configureAndInstall |& tee -a "$LOG_FILE"
	;;


"rhel-7.6" | "rhel-7.7" | "rhel-7.8" | "rhel-8.1" | "rhel-8.2")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"

	if [ "$USEAS" = "server" ]; then
		sudo yum install -y gcc-c++ readline-devel gawk tar unzip libyaml-devel PackageKit-cron openssl-devel make git wget sqlite-devel glibc-common hostname zip ant |& tee -a "$LOG_FILE"
	elif [ "$USEAS" = "agent" ]; then
		sudo yum install -y gcc-c++ tar openssl-devel make wget gawk hostname |& tee -a "$LOG_FILE"
	else
		printf -- "please enter the argument (server/agent) with option -s "
		exit
	fi
	configureAndInstall |& tee -a "$LOG_FILE"

	;;

"sles-15.1" | "sles-15.2")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"

	if [ "$USEAS" = "server" ]; then
		sudo zypper install -y wget tar make gcc-c++ gawk openssl-devel zlib-devel git ant zip unzip hostname gzip |& tee -a "$LOG_FILE"
	elif [ "$USEAS" = "agent" ]; then
		sudo zypper install -y gcc-c++ tar openssl-devel zlib-devel make wget gawk hostname gzip |& tee -a "$LOG_FILE"
	else
		exit
	fi
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "$LOG_FILE"
