#!/bin/bash
# © Copyright IBM Corporation 2018.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)

set -e

PACKAGE_NAME="protobuf"
PACKAGE_VERSION="3.6.1"
CURDIR="$(pwd)"
FORCE="false"
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
BUILD_DIR="/usr/local"
TESTS="false"
trap cleanup 0 1 2 ERR

#Check if directory exsists
if [ ! -d "$CURDIR/logs/" ]; then
	mkdir -p "$CURDIR/logs/"
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

function prepare() {
	if command -v "sudo" >/dev/null; then
		printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
	else
		printf -- 'Sudo : No \n' >>"$LOG_FILE"
		printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n'
		exit 1
	fi

	if [[ "$FORCE" == "true" ]]; then
		printf -- 'Force attribute provided hence continuing with install without confirmation message\n' | tee -a "$LOG_FILE"
	else
		# Ask user for prerequisite installation
		printf -- "\nAs part of the installation , some dependencies will be installed, \n"
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

	#Check if Protobuf directory exists
	if [ -d "$BUILD_DIR/protobuf" ]; then
		sudo rm -rf "$BUILD_DIR/protobuf"
	fi

	printf -- 'Cleaned up the artifacts\n' >>"$LOG_FILE"
}

function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'

	# Install protobuf
	printf -- "\nInstalling %s..... \n" "$PACKAGE_NAME"

	# Protobuf installation

	if [[ "$ID-$VERSION_ID" == "rhel-6.x" ]]; then

		cd "$BUILD_DIR"
		sudo wget -q http://ftp.gnu.org/gnu/gcc/gcc-4.8.2/gcc-4.8.2.tar.bz2
		bunzip2 gcc-4.8.2.tar.bz2
		tar xf gcc-4.8.2.tar
		cd gcc-4.8.2/
		./contrib/download_prerequisites
		cd "$BUILD_DIR"
		sudo mkdir gccbuild
		cd gccbuild/
		../gcc-4.8.2/configure --prefix="$HOME/install/gcc-4.8.2" --enable-shared --disable-multilib --enable-threads=posix --with-system-zlib --enable-languages=c,c++

		make && sudo make install
		export PATH=$HOME/install/gcc-4.8.2/bin:$PATH
		printf -- 'GCC build success \n' | tee -a "$LOG_FILE"
	fi

	#Give permission
	sudo chown -R "$USER" "$BUILD_DIR"

	cd "$BUILD_DIR"
	git clone -q -b v"${PACKAGE_VERSION}" git://github.com/google/protobuf.git
	
	#Give permission
	sudo chown -R "$USER" "$BUILD_DIR/protobuf"

	cd protobuf
	git config --global url."git://github.com/".insteadOf "https://github.com/"
	git submodule update --init --recursive
	printf -- 'Git clone protobuf success \n' | tee -a "$LOG_FILE"

	./autogen.sh
	./configure
	make

	# Run Tests
	runTest

	sudo make install
	sudo ldconfig
	export LD_LIBRARY_PATH=/usr/local/lib
	printf -- 'Build protobuf success \n' | tee -a "$LOG_FILE"

	
	
	#Cleanup
	cleanup

	#Verify protobuf installation
	if command -v "protoc" >/dev/null; then
		printf -- "%s installation completed. Please check the Usage to start the service.\n" "$PACKAGE_NAME" | tee -a "$LOG_FILE"
	else
		printf -- "Error while installing %s, exiting with 127 \n" "$PACKAGE_NAME"
		exit 127
	fi
}


function runTest() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- "TEST Flag is set. continue with running test \n"

		# Test build 
		make check

		printf -- "Tests completed. \n" | tee -a "$LOG_FILE"

	fi
	set -e
}

function logDetails() {
	printf -- '**************************** SYSTEM DETAILS *************************************************************\n' >"$LOG_FILE"
	if [ -f "/etc/os-release" ]; then
		cat "/etc/os-release" >>"$LOG_FILE"
	else
		cat "/etc/redhat-release" >>"${LOG_FILE}"
	fi

	cat /proc/version >>"$LOG_FILE"
	printf -- '*********************************************************************************************************\n' >>"$LOG_FILE"

	printf -- "Detected %s \n" "$PRETTY_NAME"
	printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" | tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
	echo
	echo "Usage: "
	echo "  install.sh  [-d <debug>] [-v package-version] [-y install-without-confirmation] [-t install-with-tests]"
	echo "       default: If no -v specified, latest version will be installed"
	echo
}

while getopts "h?dytv:" opt; do
	case "$opt" in
	h | \?)
		printHelp
		exit 0
		;;
	d)
		set -x
		;;
	v)
		PACKAGE_VERSION="$OPTARG"
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
	printf -- '\n***************************************************************************************\n'
	printf -- "Getting Started: \n"
	printf -- "protoc --version \n"
	printf -- '***************************************************************************************\n'
	printf -- '\n'
}

###############################################################################################################

logDetails
prepare #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04")
	printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
	sudo apt-get -qq update
	sudo apt-get install -y -qq tar wget autoconf libtool automake g++ make git bzip2 curl unzip zlib1g-dev >/dev/null
	configureAndInstall
	;;

"rhel-6.x" | "rhel-7.3" | "rhel-7.4" | "rhel-7.5")
	printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"

	if [[ "$DISTRO" == "rhel-6.x" ]]; then
		sudo yum install -y -q tar wget gcc-c++ make git bzip2 curl unzip zlib zlib-devel bison binutils-devel autoconf automake libtool >/dev/null
		printf -- "\nInstalling for %s \n" "$DISTRO" | tee -a "$LOG_FILE"
	else

		sudo yum install -y -q tar wget autoconf libtool automake gcc-c++ make git bzip2 curl unzip zlib zlib-devel curl >/dev/null
	fi

	configureAndInstall
	;;

"sles-12.3" | "sles-15")
	printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
	sudo zypper -q install -y tar wget autoconf libtool automake gcc-c++ make git bzip2 curl unzip zlib zlib-devel >/dev/null
	configureAndInstall
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" | tee -a "$LOG_FILE"
	exit 1
	;;
esac

printSummary
