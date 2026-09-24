#!/bin/bash
# © Copyright IBM Corporation 2026.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/CouchDB/3.5.2/build_couchdb.sh
# Execute build script: bash build_couchdb.sh    (provide -h for help)
#

set -e  -o pipefail

PACKAGE_NAME="CouchDB"
PACKAGE_VERSION="3.5.2"
CURDIR="$(pwd)"
SOURCE_ROOT="$(pwd)"
USER="$(whoami)"
NODE_VERSION="v18.20.8"
ELIXIR_VERSION="v1.17.3"
ERLANG_VERSION="27.3"

FORCE="false"
TESTS="false"
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
   mkdir -p "$CURDIR/logs/"
fi


if [ -f "/etc/os-release" ]; then
	source "/etc/os-release"
fi

function prepare() {
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
		printf -- "\nAs part of the installation, dependencies would be installed/upgraded. \n"
		while true; do
			read -r -p "Do you want to continue (y/n) ? :  " yn
			case $yn in
			[Yy]*)
				printf -- 'User responded with Yes. \n' >> "$LOG_FILE"
				break
				;;
			[Nn]*) exit ;;
			*) echo "Please provide confirmation to proceed." ;;
			esac
		done
	fi
}

function cleanup() {
  # Remove artifacts
	rm -rf $SOURCE_ROOT/node-${NODE_VERSION}-linux-s390x.tar.gz
  printf -- "Cleaned up the artifacts\n" >> "$LOG_FILE"

}
function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'

  #Install Erlang
	wget -q https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Erlang/${ERLANG_VERSION}/build_erlang.sh
	bash build_erlang.sh -y -j OpenJDK21 
       
  #Elixir
  cd $SOURCE_ROOT
  git clone https://github.com/elixir-lang/elixir.git
	cd elixir
	git checkout ${ELIXIR_VERSION}
	export LANG=C.utf8
	export LC_ALL=C.utf8
	make -j$(nproc)
	sudo make install
	elixir -v


	#Install Nodejs
	cd $SOURCE_ROOT
	sudo mkdir -p /usr/local/lib/nodejs
	wget https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-s390x.tar.gz
	sudo tar xzvf node-${NODE_VERSION}-linux-s390x.tar.gz -C /usr/local/lib/nodejs
	export PATH=/usr/local/lib/nodejs/node-${NODE_VERSION}-linux-s390x/bin:$PATH
	node -v
	npm -v
         
	#Install Couchdb
	printf -- 'Installing couchdb.. \n'
	cd $SOURCE_ROOT
	git clone https://github.com/apache/couchdb.git
	cd couchdb
	git checkout ${PACKAGE_VERSION}
	export LD_LIBRARY_PATH=/usr/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
	if [ "$DISTRO" = "rhel-8.10" ]; then
    		SPIDERMONKEY_VERSION=60
	elif [[ "$DISTRO" == rhel-9.* ]]; then
    		SPIDERMONKEY_VERSION=78
	elif [ "$DISTRO" = "ubuntu-22.04" ] || [ "$DISTRO" = "ubuntu-24.04" ]; then
    		SPIDERMONKEY_VERSION=102
	fi
	./configure --spidermonkey-version ${SPIDERMONKEY_VERSION}
	make release
	
	# Run Tests
	runTest

	#Cleanup
	cleanup

	printf -- "\n Installation of %s %s was successful \n\n" $PACKAGE_NAME $PACKAGE_VERSION
	gettingStarted |& tee -a "${LOG_FILE}"
}

function runTest() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- "TEST Flag is set , Continue with running test \n" 						
		cd $SOURCE_ROOT/couchdb/
		make check

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
	echo "  bash build_couchdb.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests]"
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
	printf -- '\n***********************************************************************************************\n'
	printf -- "Getting Started: \n"
	printf -- "For User Registration, Security, First Run and  Running as a Daemon instructions please follow the  official documention: https://docs.couchdb.org/en/stable/install/unix.html#installation-from-source \n"
	printf -- '*************************************************************************************************\n'
	printf -- '\n'
}

###############################################################################################################

logDetails
prepare #Check Prequisites

DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"ubuntu-22.04" | "ubuntu-24.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo apt-get update -y
        sudo apt-get install -y libicu-dev openssl libssl-dev build-essential pkg-config libtool help2man python3 python3-dev python3-pip git libmozjs-102-dev python3-venv |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;
"rhel-8.10")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
        sudo yum install -y openssl openssl-devel libicu-devel gcc-c++ pkg-config libtool help2man python3.11 python3.11-devel python3.11-pip git mozjs60 mozjs60-devel perl-Test-Harness procps-ng|& tee -a "${LOG_FILE}"
        sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 60
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;
"rhel-9.6" | "rhel-9.7" | "rhel-9.8")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
        sudo yum install -y openssl openssl-devel libicu-devel gcc-c++ pkg-config libtool help2man python3.11 python3.11-devel python3.11-pip git mozjs78 mozjs78-devel perl-Test-Harness procps-ng|& tee -a "${LOG_FILE}"
        sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 60
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac
