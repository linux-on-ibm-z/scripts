#!/bin/bash
# © Copyright IBM Corporation 2024.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/CouchDB/3.3.3/build_couchdb.sh
# Execute build script: bash build_couchdb.sh  (provide -h for help)
#

set -e -o pipefail

PACKAGE_NAME="couchdb"
PACKAGE_VERSION="3.3.3"
CURDIR="$(pwd)"
DATE_AND_TIME="$(date +"%F-%T")"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-${DATE_AND_TIME}.log"
FORCE="false"
TESTS="false"
trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
	mkdir -p "$CURDIR/logs/"
fi

if [ -f "/etc/os-release" ]; then
	source "/etc/os-release"
else
    printf -- "%s Package with version %s is currently not supported for %s .\n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
fi

function prepare() {

	if command -v "sudo" >/dev/null; then
		printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
	else
		printf -- 'Sudo : No \n' >>"$LOG_FILE"
		printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n'
		exit 1
	fi

	if [[ "$FORCE" == "true" ]]; then
		printf -- 'Force attribute provided hence continuing with install without confirmation message'
	else
		printf -- '\nBuild might take some time...'
		while true; do
			read -r -p "Do you want to continue (y/n) ? :  " yn
			case $yn in
			[Yy]*)

				break
				;;
			[Nn]*) exit ;;
			*) echo "Please provide Correct input to proceed." ;;
			esac
		done
	fi
}

function runTest() {
	set +e
	cd "${CURDIR}"/couchdb
	if [[ "$TESTS" == "true" ]]; then
		make check
	fi
	set -e
}

function cleanup() {
	printf -- '\nCleaned up the artifacts\n' |& tee -a "$LOG_FILE"
	sudo rm -rf $CURDIR/*.tar.gz
}

function configureAndInstall() {
	printf -- '\nConfiguration and Installation started \n'
		
  #Install Erlang
	cd "${CURDIR}"
	wget https://github.com/erlang/otp/releases/download/OTP-24.3.4.10/otp_src_24.3.4.10.tar.gz
	tar zxf otp_src_24.3.4.10.tar.gz
	cd otp_src_24.3.4.10
	export ERL_TOP="${CURDIR}/otp_src_24.3.4.10"
	./configure --prefix=/usr
	make
	sudo make install
	
	#Install elixir
	cd "${CURDIR}"
	git clone https://github.com/elixir-lang/elixir.git
 	cd elixir
	git checkout v1.13.4
	export LANG=en_US.UTF-8 
	make
	sudo make install
	printf -- 'Elixir installed, version:\n'
	elixir -v

	#Install nodejs
	cd "${CURDIR}"
	printf -- 'Installing nodejs\n'
	sudo mkdir -p /usr/local/lib/nodejs
	wget https://nodejs.org/dist/v14.21.3/node-v14.21.3-linux-s390x.tar.gz
	sudo tar xzvf node-v14.21.3-linux-s390x.tar.gz -C /usr/local/lib/nodejs
	sudo ln -s /usr/local/lib/nodejs/node-v14.21.3-linux-s390x/bin/* /usr/bin/
	printf -- 'node version\n'
	node -v
	printf -- 'npm version\n'
	npm -v

	#Install chromedriver@105.0.0
	cd "${CURDIR}"
	printf -- 'Installing chromedriver@105.0.0\n'
	git clone -b 105.0.0 https://github.com/giggio/node-chromedriver.git
	cd node-chromedriver
	sed -i "s#process.arch === 'arm64' || process.arch === 'x64'#process.arch === 'arm64' || process.arch === 's390x' || process.arch === 'x64'#g" install.js
	npm ci
	npm pack
  
	#Download the CouchDB source code
	cd "${CURDIR}"
	printf -- '\nDownloading  CouchDB. Please wait.\n'
	git clone https://github.com/apache/couchdb.git
  cd couchdb
 	git checkout $PACKAGE_VERSION 

	#Configure and build CouchDB
	cd "${CURDIR}/couchdb"
	export LD_LIBRARY_PATH=/usr/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
	./configure 
	cd src/fauxton/
	npm i $CURDIR/node-chromedriver/chromedriver-105.0.0.tgz
	cd ../../
	make release
	
	# Add CouchDB group 
	sudo groupadd couchdb 
	sudo usermod -aG couchdb $(whoami)

	#copy couchdb folder to default location
	sudo cp -r "${CURDIR}/couchdb/rel/couchdb" /opt/
	
	# Permissions
	sudo chown "$(whoami)":couchdb -R /opt/couchdb
	
	sudo find /opt/couchdb -type d -exec chmod 0770 {} \;
	
	chmod 0644 /opt/couchdb/etc/*
	
	sudo sed -i 's/;admin = mysecretpassword/admin = mysecretpassword/' /opt/couchdb/etc/local.ini

	printf -- 'Build process completed successfully\n'
	
	#Run tests
	runTest
	printf -- 'Couchdb built succesfully\n'
}

function logDetails() {
	printf -- 'SYSTEM DETAILS\n' >"$LOG_FILE"
	if [ -f "/etc/os-release" ]; then
		cat "/etc/os-release" >>"$LOG_FILE"
	fi

	cat /proc/version >>"$LOG_FILE"
	printf -- "\nDetected %s \n" "$PRETTY_NAME"
	printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" |& tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
	echo
	echo "Usage: "
	echo "bash build_couchdb.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests]"
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

function printSummary() {
	printf -- '\n\nRun following command to run couchdb server.\n'
	printf -- '\n\n  /opt/couchdb/bin/couchdb & \n'
	printf -- '\nFor more help visit http://docs.couchdb.org/en/3.3.3/index.html \n'
}

logDetails
#checkPrequisites
prepare |& tee -a "$LOG_FILE"

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"rhel-7.8" | "rhel-7.9")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for couchdb from repository \n' |& tee -a "$LOG_FILE"
	sudo yum install -y libicu-devel libcurl-devel wget tar m4 pkgconfig make libtool which rh-git227-git.s390x gcc-c++ gcc openssl-devel patch js-devel java-11-openjdk-devel perl-devel gettext-devel unixODBC-devel python3-devel ncurses-devel procps-ng |&  tee -a "$LOG_FILE"
	#Enable git 2.27
  	source /opt/rh/rh-git227/enable
	configureAndInstall |&  tee -a "$LOG_FILE"
	;;
*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

# Print Summary
printSummary |& tee -a "$LOG_FILE"
