#!/bin/bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Protobuf/3.11.2/build_protobuf.sh
# Execute build script: bash build_protobuf.sh    (provide -h for help)
#
set -e -o pipefail

PACKAGE_NAME="protobuf"
PACKAGE_VERSION="3.11.2"
CURDIR="$(pwd)"
FORCE="false"
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
BUILD_DIR="$HOME"
TESTS="false"

trap cleanup 0 1 2 ERR

#Check if directory exists
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
		printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
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

	# Check if Protobuf directory exists
	if [ -d "$BUILD_DIR/protobuf" ]; then
		sudo rm -rf "$BUILD_DIR/protobuf"
	fi

	# Check if file exists
	if [ -f "$BUILD_DIR/gcc-4.9.4.tar.gz" ]; then
		sudo rm -rf "$BUILD_DIR/gcc-4.9.4*"
	fi

	printf -- 'Cleaned up the artifacts\n'
}

function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'

	# Install protobuf
	printf -- "\nInstalling %s..... \n" "$PACKAGE_NAME"

	# Protobuf installation

	if [[ "$ID-$VERSION_ID" == "rhel-6.x" || "$ID-$VERSION_ID" == "rhel-8.0" || "$ID-$VERSION_ID" == "sles-15.1" || "$ID-$VERSION_ID" == "ubuntu-19.10" ]]; then

		cd "$BUILD_DIR"
		#Check if gcc directory exists
		if [ -d "$BUILD_DIR/gcc-4.9.4" ]; then
			sudo rm -rf "$BUILD_DIR/gcc-4.9.4"
		fi

        wget http://ftp.gnu.org/gnu/gcc/gcc-4.9.4/gcc-4.9.4.tar.gz
        tar xzf gcc-4.9.4.tar.gz
        cd gcc-4.9.4/
        ./contrib/download_prerequisites
        mkdir build
        cd build/
        ../configure --enable-shared --disable-multilib --enable-threads=posix --with-system-zlib --enable-languages=c,c++
        make -j2
        sudo make install
        export PATH=/usr/local/bin:$PATH

		printf -- 'GCC successfully built \n'
	fi

	#Give permission
	sudo chown -R "$USER" "$BUILD_DIR"

	cd "$BUILD_DIR"
	#Check if protobuf directory exists
	if [ -d "$BUILD_DIR/protobuf" ]; then
		sudo rm -rf "$BUILD_DIR/protobuf"
	fi

    git clone -b v"${PACKAGE_VERSION}" https://github.com/protocolbuffers/protobuf.git
	cd protobuf
	git submodule update --init --recursive
	./autogen.sh
	./configure
	make

	# Run Tests
	runTest

	sudo make install
	sudo ldconfig
	printf -- 'Build protobuf success \n'

	#Cleanup
	cleanup

	#Verify protobuf installation
	if command -v "protoc" >/dev/null; then
		printf -- "%s installation completed. Please check the Usage to start the service.\n" "$PACKAGE_NAME"
	else
		printf -- "Error while installing %s, exiting with 127 \n" "$PACKAGE_NAME"
		exit 127
	fi
}

function runTest() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- "TEST Flag is set, continue with running test \n"

		# Test build
		make check
		printf -- "Tests completed. \n"

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
	printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" |& tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
	echo "Usage: "
	echo "  install.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests]"
	echo "Note: With tests, the build may take up to an additional 15 mins."
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
		printf -- "\nBuilding with tests may take up to an additional 15 mins.\n"
		;;
	esac
done

function gettingStarted() {
	printf -- '\n***************************************************************************************\n'
	printf -- "Getting Started: \n"
	printf -- "protoc --version \n"
	printf -- '***************************************************************************************\n'
	printf -- '\n'
}

###############################################################################################################

logDetails
prepare # Check Prerequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04" | "ubuntu-19.10")
	printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	sudo apt-get update

    if [[ "$DISTRO" == "ubuntu-19.10" ]]; then
        sudo apt-get install -y autoconf automake bzip2 g++ git gzip libtool make tar wget zlib1g-dev |& tee -a "$LOG_FILE"
    else
        sudo apt-get install -y autoconf automake g++-4.8 git gzip libtool make |& tee -a "$LOG_FILE"
        sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-4.8 10
        sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-4.8 10
    fi
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"rhel-6.x" | "rhel-7.5" | "rhel-7.6" | "rhel-7.7" | "rhel-8.0")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"

	if [[ "$DISTRO" == "rhel-6.x" || "$DISTRO" == "rhel-8.0" ]]; then
		sudo yum install -y  autoconf automake bzip2 gcc-c++ git gzip libtool make tar wget zlib-devel |& tee -a "$LOG_FILE"
	else
		sudo yum install -y  autoconf automake gcc-c++ git gzip libtool make |& tee -a "$LOG_FILE"
	fi
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"sles-12.4" | "sles-15.1")
	printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"

    if [[ "$DISTRO" == "sles-12.4" ]]; then
        sudo zypper install -y autoconf automake gawk gcc-c++ git gzip libtool make |& tee -a "$LOG_FILE"
    else
        sudo zypper install -y autoconf automake bzip2 gawk gcc-c++ git gzip libtool make tar wget zlib-devel |& tee -a "$LOG_FILE"
    fi
	configureAndInstall |& tee -a "$LOG_FILE"
	;;
*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "$LOG_FILE"
