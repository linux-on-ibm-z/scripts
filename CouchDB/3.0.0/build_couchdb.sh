#!/bin/bash
# © Copyright IBM Corporation 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/CouchDB/3.0.0/build_couchdb.sh
# Execute build script: bash build_couchdb.sh  (provide -h for help)
#

set -e -o pipefail

PACKAGE_NAME="couchdb"
PACKAGE_VERSION="3.0.0"
CURDIR="$(pwd)"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/CouchDB/3.0.0/patch"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
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
		printf -- 'You can install sudo from repository using apt, yum or zypper based on your distro. \n'
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
	export PATH=$PATH:/usr/local/bin
		make check
	fi
	set -e
}

function cleanup() {
	printf -- '\nCleaned up the artifacts\n' |& tee -a "$LOG_FILE"
	rm -rf "${CURDIR}/jsval.h.diff"
	rm -rf "${CURDIR}/jsvalue.h.diff"
	rm -rf "${CURDIR}/Makefile.in.diff"
	rm -rf "${CURDIR}/couch_compress_tests.erl.diff"

}

function startServer() {
	printf -- 'Starting server\n' | tee -a "$LOG_FILE"
	sudo $CURDIR/couchdb/dev/run &
	sleep 50s
	printf -- 'Server started successfully\n' | tee -a "$LOG_FILE"
}

function configureAndInstall() {
	printf -- '\nConfiguration and Installation started \n'
	#Installing dependencies
	printf -- 'User responded with Yes. \n'


  	#Install Python for RHEL and Ubuntu16.04
 	 if [ "${ID}" == "rhel" ] || [ ${VERSION_ID} == "16.04" ]; then
		cd "${CURDIR}"
		wget -q https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Python3/3.8.1/build_python3.sh
		bash build_python3.sh  -y
	fi
  

	#only for rhel
	if [[ "${ID}" == "rhel" ]]; then
		cd "${CURDIR}"
		wget https://github.com/git/git/archive/v2.16.0.tar.gz
		tar -zxf v2.16.0.tar.gz
		cd git-2.16.0
		make configure
		./configure --prefix=/usr
		make
		sudo make install
	fi


  #Install Erlang
		cd "${CURDIR}"
		wget http://www.erlang.org/download/otp_src_22.2.tar.gz
		tar zxf otp_src_22.2.tar.gz
		cd otp_src_22.2
		export ERL_TOP="${CURDIR}/otp_src_22.2"
		./configure --prefix=/usr
		make
		sudo make install
	
  
  #Install elixir
  cd "${CURDIR}"
  git clone https://github.com/elixir-lang/elixir.git
  cd elixir
  git checkout v1.10.2
  export LANG=en_US.UTF-8 
  if [[ "${ID}" == "ubuntu" ]]; then
  sudo locale-gen en_US.UTF-8
  fi
  make
  sudo make install

	#Install SpiderMonkey 1.8.5 (Only for Ubuntu 18.04)
	if [ ${VERSION_ID} == "18.04" ]; then
		printf -- '\nDownloading SpiderMonkey\n'
		cd "${CURDIR}"
		wget http://ftp.mozilla.org/pub/mozilla.org/js/js185-1.0.0.tar.gz
		tar zxf js185-1.0.0.tar.gz
		cd js-1.8.5

		cd "${CURDIR}"
		curl -o jsval.h.diff $PATCH_URL/jsval.h.diff
		patch "${CURDIR}/js-1.8.5/js/src/jsval.h" jsval.h.diff

		curl -o jsvalue.h.diff $PATCH_URL/jsvalue.h.diff
		patch "${CURDIR}/js-1.8.5/js/src/jsvalue.h" jsvalue.h.diff

		curl -o Makefile.in.diff $PATCH_URL/Makefile.in.diff
		patch "${CURDIR}/js-1.8.5/js/src/Makefile.in" Makefile.in.diff

		#Preparing the source code
		cd "${CURDIR}/js-1.8.5/js/src"	

		autoconf2.13
	
		#Configure, build & install SpiderMonkey
		mkdir -p "${CURDIR}/js-1.8.5/js/src/build_OPT.OBJ"
		cd "${CURDIR}/js-1.8.5/js/src/build_OPT.OBJ"
		../configure --prefix=/usr
		make
		sudo make install

		printf -- 'SpiderMonkey installed succesfully\n'
	fi
	#Download the CouchDB source code
	cd "${CURDIR}"
	printf -- '\nDownloading  CouchDB. Please wait.\n'
	git clone -b $PACKAGE_VERSION https://github.com/apache/couchdb.git

	#Configure and build CouchDB
	cd "${CURDIR}/couchdb"
	./configure -c --disable-docs --disable-fauxton
	export LD_LIBRARY_PATH=/usr/lib
	make

	#Run tests
	runTest
	printf -- 'Couchdb Installed succesfully\n'
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
	echo "  build_couchdb.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests]"
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
	printf -- '\n\nInstallation completed successfully.\n' |& tee -a "$LOG_FILE"
	printf -- '\nFor more help visit http://docs.couchdb.org/en/3.0.0/index.html \n' |& tee -a "$LOG_FILE"
}

logDetails
#checkPrequisites
prepare |& tee -a "$LOG_FILE"

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
	sudo apt-get update
	sudo apt-get install -y build-essential pkg-config gcc curl git patch wget tar make autoconf automake autoconf g++ libmozjs185-dev libicu-dev libcurl4-openssl-dev locales libncurses-dev libssl-dev unixodbc-dev libwxgtk3.0-dev openjdk-8-jdk |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"

	;;

"ubuntu-18.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
	sudo apt-get update
	sudo apt-get install -y build-essential pkg-config ncurses-base g++-5 gcc-5 python python3 python3-pip python3-venv curl git patch wget tar make zip autoconf2.13 automake libicu-dev libcurl4-openssl-dev libncurses5-dev locales libncurses-dev libssl-dev unixodbc-dev libwxgtk3.0-dev openjdk-8-jdk |& tee -a "$LOG_FILE"

	sudo rm -rf /usr/bin/gcc /usr/bin/g++ /usr/bin/cc
	sudo ln -s /usr/bin/gcc-5 /usr/bin/gcc
	sudo ln -s /usr/bin/g++-5 /usr/bin/g++
	sudo ln -s /usr/bin/gcc /usr/bin/cc
	configureAndInstall |& tee -a "$LOG_FILE"

	;;
"rhel-7.5" | "rhel-7.6" | "rhel-7.7" )
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for Go from repository \n' |& tee -a "$LOG_FILE"
	sudo yum install -y libicu-devel libcurl-devel wget tar m4 pkgconfig make libtool which gcc-c++ gcc openssl openssl-devel patch js-devel java-1.8.0-openjdk-devel perl-devel gettext-devel unixODBC-devel |&  tee -a "${LOG_FILE}"
	configureAndInstall |&  tee -a "${LOG_FILE}"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

#Start server
startServer

# Print Summary
printSummary |& tee -a "$LOG_FILE"
