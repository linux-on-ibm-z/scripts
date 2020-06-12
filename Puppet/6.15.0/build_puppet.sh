#!/usr/bin/env bash
# © Copyright IBM Corporation 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Puppet/6.15.0/build_puppet.sh
# Execute build script: bash build_puppet.sh    (provide -h for help)

set -e -o pipefail

CURDIR="$(pwd)"
PACKAGE_NAME="Puppet"
PACKAGE_VERSION="6.15.0"
SERVER_VERSION="6.11.0"
AGENT_VERSION="6.15.0"
RUBY_VERSION="2.7"
RUBY_FULL_VERSION="2.7.0"
JFFI_VERSION="1.2.23"
JRUBY_VERSION="9.2.11.1"
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

	if [[ -f "ruby"-${RUBY_VERSION}.tar.gz ]]; then
		sudo rm "ruby"-${RUBY_VERSION}.tar.gz
		printf -- 'Cleaned up the artifacts\n' >>"$LOG_FILE"
	fi
}

function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'
	#Download and install Ruby
	if [[ ("$ID" == "rhel" || "$ID" == "sles" || "$ID" == "ubuntu" && "$VERSION_ID" == "16.04")]]; then
		cd "$CURDIR"
		wget http://cache.ruby-lang.org/pub/ruby/$RUBY_VERSION/ruby-$RUBY_FULL_VERSION.tar.gz
		tar -xzf ruby-$RUBY_FULL_VERSION.tar.gz
		cd ruby-$RUBY_FULL_VERSION
		./configure && make && sudo -E make install
	fi

	#Install bundler
	if [[ "$VERSION_ID" == "18.04" || "$VERSION_ID" == "20.04" && "$ID" == "ubuntu" ]]; then
		cd "$CURDIR"
		sudo /usr/bin/gem install bundler rake-compiler
	else
		cd "$CURDIR"
		sudo /usr/local/bin/gem install bundler rake-compiler
	fi

	if [ "$USEAS" = "server" ]; then
        printf -- 'Build puppetserver and Installation started \n'
        printf -- 'Build jffi lib \n'
        # install Java 8 and build jffi

	if [[ "$ID" == "sles" ]]; then
		sudo zypper install -y java-1_8_0-openjdk-devel
		export JAVA_HOME=/usr/lib64/jvm/java-1.8.0-openjdk
		export PATH=$JAVA_HOME/bin:$PATH
	else	
        	cd $CURDIR
	        wget https://github.com/AdoptOpenJDK/openjdk8-binaries/releases/download/jdk8u252-b09/OpenJDK8U-jdk_s390x_linux_hotspot_8u252b09.tar.gz
        	tar zxf OpenJDK8U-jdk_s390x_linux_hotspot_8u252b09.tar.gz
	        export JAVA_HOME=$CURDIR/jdk8u252-b09
	        export PATH=$JAVA_HOME/bin:$PATH
 	fi

	echo "Build jffi!!"
	echo ""
        wget https://github.com/jnr/jffi/archive/jffi-$JFFI_VERSION.tar.gz
        tar xzf jffi-$JFFI_VERSION.tar.gz
        cd jffi-jffi-$JFFI_VERSION
        ant jar

        printf -- 'Download lein   \n'
        cd $CURDIR
        wget https://raw.githubusercontent.com/technomancy/leiningen/stable/bin/lein
        chmod +x lein && sudo  mv lein /usr/bin/

        printf -- 'Download openjdk-11 and set up \n'
        cd $CURDIR
        wget https://github.com/AdoptOpenJDK/openjdk11-binaries/releases/download/jdk-11.0.7%2B10/OpenJDK11U-jdk_s390x_linux_hotspot_11.0.7_10.tar.gz
        tar xzf OpenJDK11U-jdk_s390x_linux_hotspot_11.0.7_10.tar.gz
        export JAVA_HOME=$CURDIR/jdk-11.0.7+10
        export PATH=$JAVA_HOME/bin:$PATH

        printf -- 'Get puppetserver \n'
        cd $CURDIR
        git clone --recursive --branch $SERVER_VERSION git://github.com/puppetlabs/puppetserver
        cd puppetserver

        printf -- 'Setup config files \n'
        export LANG="en_US.UTF-8"
        ./dev-setup
		cp $CURDIR/jffi-jffi-$JFFI_VERSION/build/native.jar  ~/.m2/repository/com/github/jnr/jffi/$JFFI_VERSION/jffi-$JFFI_VERSION-native.jar
		# remove invalid gems
		rm -f ~/.puppetlabs/opt/server/data/puppetserver/vendored-jruby-gems/cache/*.gem
		# re-run
		./dev-setup

        #Locate the $confdir
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

        printf -- 'Update JRuby jars\n'
        cd $CURDIR
        unzip -q ~/.m2/repository/org/jruby/jruby-stdlib/$JRUBY_VERSION/jruby-stdlib-$JRUBY_VERSION.jar
        cp META-INF/jruby.home/lib/ruby/stdlib/ffi/platform/powerpc-aix/*.rb META-INF/jruby.home/lib/ruby/stdlib/ffi/platform/s390x-linux/
        cp META-INF/jruby.home/lib/ruby/stdlib/ffi/platform/powerpc-aix/platform.conf META-INF/jruby.home/lib/ruby/stdlib/ffi/platform/s390x-linux/
        zip -qr std.jar META-INF
        cp std.jar ~/.m2/repository/org/jruby/jruby-stdlib/$JRUBY_VERSION/jruby-stdlib-$JRUBY_VERSION.jar
        rm -rf META-INF std.jar

        printf -- 'Completed Puppet server setup \n'

	elif [ "$USEAS" = "agent" ]; then
		#Install Puppet
		if [[ "$ID" == "ubuntu" && "$VERSION_ID" == "18.04" || "$VERSION_ID" == "20.04" ]]; then
			cd "$CURDIR"
			sudo /usr/bin/gem install facter -v 2.5.7
			sudo /usr/bin/gem install puppet -v $PACKAGE_VERSION
		else
			cd "$CURDIR"
			sudo /usr/local/bin/gem install facter -v 2.5.7
			sudo /usr/local/bin/gem install puppet -v $PACKAGE_VERSION
		fi

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

		printf -- 'Completed Puppet agent setup \n'
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
	printf -- "     	export JAVA_HOME=$CURDIR/jdk-11.0.7+10\n"
	printf -- "     	export PATH=\$JAVA_HOME/bin:\$PATH\n"
	printf -- "     	export confdir=~/.puppetlabs/etc/puppet\n"
	printf -- '\n'
	printf -- "     To run Puppet agent, set \$confdir and follow from step 3.7 in build instructions.\n"
	printf -- "     	export confdir=\`puppet agent --configprint confdir\`\n"
	printf -- '\n'
	printf -- "More information can be found here : https://puppetlabs.com/\n"
	printf -- '\n'
}


###############################################################################################################

logDetails
DISTRO="$ID-$VERSION_ID"
checkPrequisites #Check Prequisites

case "$DISTRO" in
"ubuntu-16.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
	sudo apt-get update >/dev/null
	if [ "$USEAS" = "server" ]; then
		sudo apt-get install -y wget zip unzip tar git g++ make rake libreadline6 libreadline6-dev openssl libyaml-dev libssl-dev libsqlite3-dev libc6-dev cron locales locales-all ant zip |& tee -a "$LOG_FILE"
	elif [ "$USEAS" = "agent" ]; then
		sudo apt-get install -y g++ tar make wget openssl libssl-dev |& tee -a "$LOG_FILE"
	else
		printf -- "please enter the argument (server/agent) with option -s "
		exit
	fi
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

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
	sudo ln -s /usr/lib/s390x-linux-gnu/libffi.so.7 /usr/lib/s390x-linux-gnu/libffi.so.6
	configureAndInstall |& tee -a "$LOG_FILE"
	;;


"rhel-7.6" | "rhel-7.7" | "rhel-7.8" | "rhel-8.1" | "rhel-8.2")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"

	if [[ "$DISTRO" == "rhel-7.8" ]]; then
	  set +e
	  sudo yum list installed glibc-2.17-307.el7.1.s390 |& tee -a "$LOG_FILE"
	  if [[ $? ]]; then
		sudo yum downgrade -y glibc glibc-common |& tee -a "$LOG_FILE"
		sudo yum downgrade -y krb5-libs |& tee -a "$LOG_FILE"
		sudo yum downgrade -y libss e2fsprogs-libs e2fsprogs libcom_err |& tee -a "$LOG_FILE"
		sudo yum downgrade -y libselinux-utils libselinux-python libselinux |& tee -a "$LOG_FILE"
	  fi
	  set -e
	fi

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

"sles-15.1")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"

	if [ "$USEAS" = "server" ]; then
		sudo zypper install -y wget tar make gcc-c++ gawk openssl-devel git ant zip unzip hostname gzip |& tee -a "$LOG_FILE"
	elif [ "$USEAS" = "agent" ]; then
		sudo zypper install -y gcc-c++ tar openssl-devel make wget gawk hostname gzip |& tee -a "$LOG_FILE"
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
