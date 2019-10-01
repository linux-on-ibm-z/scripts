#!/bin/bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/CouchDB/2.3.1/build_couchdb.sh
# Execute build script: bash build_couchdb.sh  (provide -h for help)
#

set -e -o pipefail

PACKAGE_NAME="couchdb"
PACKAGE_VERSION="2.3.1"
PYTHON_VERSION="3.7.1"
CURDIR="$(pwd)"
REPO_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/CouchDB/2.3.1/patch"

PYTHON_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Python3/build_python3.sh"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
FORCE="false"
TESTS="false"
trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
	mkdir -p "$CURDIR/logs/"
fi

# Need handling for RHEL 6.10 as it doesn't have os-release file
if [ -f "/etc/os-release" ]; then
	source "/etc/os-release"
elif grep "6.10" /etc/redhat-release;then
    cat /etc/redhat-release |& tee -a "$LOG_FILE"
	export ID="rhel"
	export VERSION_ID="6.10"
	export PRETTY_NAME="Red Hat Enterprise Linux 6.10"
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
		printf -- '\nFollowing packages are needed before going ahead\n'
		printf -- '1:Erlang\t\tVersion: 21.0\n'
		printf -- '2:git\t\tVersion: 2.16.0 \n'
		printf -- '3:SpiderMonkey\t\tVersion: 1.8.5\n'
		printf -- '4:GCC\t\tVersion: gcc-4.9.4 \n'

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
	cd "${CURDIR}"
	if [[ "$TESTS" == "true" ]]; then
		curl -o couch_compress_tests.erl.diff $REPO_URL/couch_compress_tests.erl.diff
		patch "${CURDIR}/src/couch/test/couch_compress_tests.erl" couch_compress_tests.erl.diff
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

function buildGCC() {

	printf -- 'Building GCC \n'
	cd "${CURDIR}"
	wget ftp://gcc.gnu.org/pub/gcc/releases/gcc-4.9.4/gcc-4.9.4.tar.gz
	tar -xvzf gcc-4.9.4.tar.gz
	cd gcc-4.9.4/
	./contrib/download_prerequisites
	cd "${CURDIR}"
	mkdir gccbuild
	cd gccbuild/
	../gcc-4.9.4/configure --prefix="${CURDIR}"/install/gcc-4.9.4 --enable-checking=release --enable-languages=c,c++ --disable-multilib
	make
	sudo make install
	export PATH="${CURDIR}"/install/gcc-4.9.4/bin:$PATH
	gcc --version
	printf -- 'Built GCC successfully \n' |& tee -a "$LOG_FILE"

}

function installDependency() {
	printf -- 'Installing dependencies\n' | tee -a "$LOG_FILE"
	cd "${CURDIR}"
	if [[ "${ID}" == "rhel" ]]; then
		curl -o build_python_3.sh "${PYTHON_URL}"
		bash build_python_3.sh -v $PYTHON_VERSION
		sudo cp /usr/local/bin/python3 /usr/bin/
	fi
	printf -- 'Installed python successfully\n' | tee -a "$LOG_FILE"
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

	#Only for rhel and ubuntu 18.04
	if [ "${ID}" == "rhel" ] || [ ${VERSION_ID} == "18.04" ]; then
		cd "${CURDIR}"
		wget http://www.erlang.org/download/otp_src_21.0.tar.gz
		tar zxf otp_src_21.0.tar.gz
		cd otp_src_21.0
		export ERL_TOP="${CURDIR}/otp_src_21.0"
		./configure --prefix=/usr
		make
		sudo make install
	fi

	#Install SpiderMonkey 1.8.5 (Only for RHEL 6.10 and Ubuntu 18.04)
	if [ ${VERSION_ID} == "18.04" ] || [ ${VERSION_ID} == "6.10" ]; then
		printf -- '\nDownloading SpiderMonkey\n'
		cd "${CURDIR}"
		wget http://ftp.mozilla.org/pub/mozilla.org/js/js185-1.0.0.tar.gz
		tar zxf js185-1.0.0.tar.gz
		cd js-1.8.5

		cd "${CURDIR}"
		curl -o jsval.h.diff $REPO_URL/jsval.h.diff
		patch "${CURDIR}/js-1.8.5/js/src/jsval.h" jsval.h.diff

		curl -o jsvalue.h.diff $REPO_URL/jsvalue.h.diff
		patch "${CURDIR}/js-1.8.5/js/src/jsvalue.h" jsvalue.h.diff

		curl -o Makefile.in.diff $REPO_URL/Makefile.in.diff
		patch "${CURDIR}/js-1.8.5/js/src/Makefile.in" Makefile.in.diff

		#Preparing the source code
		cd "${CURDIR}/js-1.8.5/js/src"

		# For RHEL 6.10
		if [[ "${VERSION_ID}" == "6.10" ]]; then
			autoconf-2.13
		fi

		#For Ubuntu 18.04
		if [[ ${VERSION_ID} == "18.04" ]]; then
			autoconf2.13
		fi

		#explicit export needed since spidermonkey needs gcc version 4.9.4
		export PATH="${CURDIR}"/install/gcc-4.9.4/bin:$PATH
		gcc --version
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
	printf -- '\nFor more help visit http://docs.couchdb.org/en/2.3.1/index.html \n' |& tee -a "$LOG_FILE"
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
	sudo apt-get install -y build-essential pkg-config erlang erlang-dev erlang-reltool gcc python3 python3-pip python3-venv curl git patch wget tar make autoconf automake autoconf g++ libmozjs185-dev libicu-dev libcurl4-openssl-dev |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"

	;;

"ubuntu-18.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
	sudo apt-get update
	sudo apt-get install -y build-essential pkg-config erlang erlang-dev erlang-reltool ncurses-base g++-5 gcc-5 python python3 python3-pip python3-venv curl git patch wget tar make zip autoconf2.13 automake libicu-dev libcurl4-openssl-dev libncurses5-dev |& tee -a "$LOG_FILE"

	sudo rm -rf /usr/bin/gcc /usr/bin/g++ /usr/bin/cc
	sudo ln -s /usr/bin/gcc-5 /usr/bin/gcc
	sudo ln -s /usr/bin/g++-5 /usr/bin/g++
	sudo ln -s /usr/bin/gcc /usr/bin/cc
	configureAndInstall |& tee -a "$LOG_FILE"

	;;
"rhel-7.5" | "rhel-7.6" | "rhel-7.7" )
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for Go from repository \n' |& tee -a "$LOG_FILE"
	sudo yum install -y libicu-devel libcurl-devel wget tar m4 pkgconfig make libtool which gcc-c++ gcc openssl openssl-devel patch js-devel java-1.8.0-openjdk-devel perl-devel gettext-devel unixODBC-devel python3 |&  tee -a "${LOG_FILE}"
	configureAndInstall |&  tee -a "${LOG_FILE}"
	;;

"rhel-6.10")
	sudo yum install -y libicu-devel wget tar m4 make patch perl-devel xz libtool which curl java-1.8.0-ibm-devel openssl-devel ncurses-devel unixODBC-devel gettext-devel cvs zip gcc-c++ glib2-devel gtk2-devel fontconfig-devel libnotify-devel libIDL-devel alsa-lib-devel libXt-devel freetype-devel pkgconfig dbus-glib-devel curl-devel autoconf213 xorg-x11-proto-devel libX11-devel libXau-devel libXext-devel wireless-tools-devel glibc-static libstdc++ libatomic_ops-devel |&  tee -a "${LOG_FILE}"
	#call for python script
	installDependency
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