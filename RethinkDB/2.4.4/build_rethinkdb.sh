#!/usr/bin/env bash
# © Copyright IBM Corporation 2024, 2025.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/RethinkDB/2.4.4/build_rethinkdb.sh
# Execute build script: bash build_rethinkdb.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="rethinkdb"
PACKAGE_VERSION="v2.4.4"
PRE_VERSION="v2.4.1"
CURDIR="$(pwd)"
FORCE="false"
TESTS="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exsists
if [ ! -d "$CURDIR/logs" ]; then
	mkdir -p "$CURDIR/logs"
fi

if [ -f "/etc/os-release" ]; then
	source "/etc/os-release"
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

function buildPython2(){
    cd $CURDIR
    wget https://www.python.org/ftp/python/2.7.18/Python-2.7.18.tar.xz
    tar -xvf Python-2.7.18.tar.xz
	cd $CURDIR/Python-2.7.18
	./configure --prefix=/usr/local --exec-prefix=/usr/local
	make
	sudo make install
	sudo ln -sf /usr/local/bin/python /usr/bin/python2
	python2 -V
}

function runTest() {
	set +e
	cd "${CURDIR}"
	if [[ "$TESTS" == "true" ]]; then
		printf -- 'Running test cases for RethinkDB\n'
		cd $CURDIR/rethinkdb
		make -j4 DEBUG=1

		# Running Unit Tests
		printf -- "Running Unit tests\n" >> "$LOG_FILE"
		./build/debug/rethinkdb-unittest

		# Running Integration Tests
		printf -- "Building Python and Ruby drivers\n" >> "$LOG_FILE"
		git clone -b $PRE_VERSION https://github.com/rethinkdb/rethinkdb $CURDIR/rethinkdb-$PRE_VERSION
		cd $CURDIR/rethinkdb-$PRE_VERSION
		./configure --allow-fetch
		make py-driver
		make rb-driver
		cp -r build/drivers ../rethinkdb/build/
		printf -- "Running Integration tests\n" >> "$LOG_FILE"
		cd $CURDIR/rethinkdb
		./test/run -j4 '!unit'

		printf -- '\n\n COMPLETED TEST EXECUTION !! \n' |& tee -a "$LOG_FILE"
	fi
	set -e
}

function cleanup() {
	sudo rm -rf $CURDIR/rethinkdb-$PRE_VERSION
}

function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'

	# Download RethinkDB source code
	cd $CURDIR
	git clone -b $PACKAGE_VERSION https://github.com/rethinkdb/rethinkdb && cd rethinkdb

	# Configure and build RethinkDB 
	./configure --allow-fetch --fetch protoc
	make -j4
	
	#  Install RethinkDB
	sudo make install
	
	# Execute Test Cases
	if [[ "$TESTS" == "true" ]]; then
        runTest
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
	echo "bash build_rethinkdb.sh [-d debug]  [-y install-without-confirmation]  [-t build-with-tests]"
	echo
}


while getopts "h?ydt" opt; do
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
	printf -- "  RethinkDB $PACKAGE_VERSION installed successfully \n"
	printf -- "  Start RethinkDB server using : \n"
	printf -- "    rethinkdb --bind all \n"
	printf -- "  More information can be found here : https://rethinkdb.com/ \n"
	printf -- '\n'
}

###############################################################################################################

logDetails
checkPrequisites #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"rhel-8.8" | "rhel-8.10")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for RethinkDB from repository \n' |& tee -a "$LOG_FILE"
	sudo yum install -y python2-devel python2 openssl-devel libcurl-devel jemalloc-devel wget tar unzip bzip2 m4 git-core boost gcc-c++ ncurses-devel curl which patch make ncurses zlib-devel zlib procps protobuf-devel protobuf-compiler xz |& tee -a "$LOG_FILE"
	sudo ln -s /usr/bin/python2 /usr/bin/python |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"rhel-9.2" | "rhel-9.4" | "rhel-9.5")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for RethinkDB from repository \n' |& tee -a "$LOG_FILE"
	sudo yum install -y openssl-devel libcurl-devel jemalloc-devel wget tar unzip bzip2 m4 git-core boost gcc-c++ ncurses-devel curl which patch make ncurses zlib-devel zlib procps protobuf-devel protobuf-compiler xz
        buildPython2 |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"sles-15.6")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for RethinkDB from repository \n' |& tee -a "$LOG_FILE"
	sudo zypper install -y gcc gcc-c++ make libopenssl-devel zlib-devel wget tar patch unzip autoconf automake m4 libtool libicu-devel protobuf-devel libprotobuf-c-devel boost-devel termcap curl libcurl-devel git bzip2 awk gzip xz readline-devel libncurses5 ncurses-devel netcfg libbz2-devel glibc-locale  |& tee -a "$LOG_FILE"
	buildPython2 |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;
		
*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "$LOG_FILE"
