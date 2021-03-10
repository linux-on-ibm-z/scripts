#!/usr/bin/env bash
# © Copyright IBM Corporation 2021.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/CockroachDB/20.2.5/build_crdb.sh
# Execute build script: bash build_crdb.sh    (provide -h for help)
set -e  -o pipefail

CURDIR="$(pwd)"
PACKAGE_NAME="CockroachDB"
PACKAGE_VERSION="20.2.5"
FORCE="false"
TEST="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exsists
if [ ! -d "$CURDIR/logs" ]; then
	mkdir -p "$CURDIR/logs"
fi

source "/etc/os-release"

function checkPrequisites() {
	printf -- "Checking Prequisites\n"

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
	sudo rm -rf ${CURDIR}/go1.13.15.linux-s390x.tar.gz
	sudo rm -rf ${CURDIR}/node-v12.18.2-linux-s390x.tar.xz
	printf -- 'Cleaned up the artifacts\n' >>"$LOG_FILE"
}

function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'

	# for rhel 7.x
	if [[ ${DISTRO} =~ rhel-7\.* || ${DISTRO} =~ sles-12\.* ]]; then
		# Install cmake
		printf -- 'Installing CMake...\n'
		cd ${CURDIR}
		wget https://github.com/Kitware/CMake/releases/download/v3.13.4/cmake-3.13.4.tar.gz
		tar -xvzf cmake-3.13.4.tar.gz
		cd cmake-3.13.4
		./bootstrap
		make
		sudo make install
		cmake --version
	fi

	# Install go
	printf -- 'Installing Go...\n'
	cd ${CURDIR}
	wget https://storage.googleapis.com/golang/go1.13.15.linux-s390x.tar.gz
	chmod ugo+r go1.13.15.linux-s390x.tar.gz
	sudo tar -C /usr/local -xzf go1.13.15.linux-s390x.tar.gz
	export PATH=$PATH:/usr/local/go/bin
	go version

	# Install Nodejs and yarn
	printf -- 'Installing Nodejs and yarn...\n'
	cd ${CURDIR}
	wget https://nodejs.org/dist/v12.20.1/node-v12.20.1-linux-s390x.tar.xz
	chmod ugo+r node-v12.20.1-linux-s390x.tar.xz
	sudo tar -C /usr/local -xf node-v12.20.1-linux-s390x.tar.xz
	export PATH=$PATH:/usr/local/node-v12.20.1-linux-s390x/bin
	node -v

	if [[ "${ID}" == "sles" ]]; then
		sudo chmod ugo+w -R /usr/local/node-v12.20.1-linux-s390x
		env PATH=$PATH npm install -g yarn
	else
		sudo env PATH=$PATH npm install -g yarn
	fi

	# Change .config ownership only on ubuntu
	if [[ "${ID}" == "ubuntu" ]]; then
		# Change the ownership of .config
		printf -- 'Change the .config ownership...\n'
		cd
		mkdir -p .config # Create one in case if the folder does not exist
		sudo chown -R $(whoami):$(whoami) .config
	fi

	# Download and configure CockroachDB
	printf -- 'Downloading CockroachDB source code. Please wait.\n'
	export GOPATH=${CURDIR}
	cd ${CURDIR}
	mkdir -p $(go env GOPATH)/src/github.com/cockroachdb
	cd $(go env GOPATH)/src/github.com/cockroachdb
	git clone https://github.com/cockroachdb/cockroach
	cd cockroach
	git checkout v$PACKAGE_VERSION
	git submodule update --init --recursive

	# Applying patches
	printf -- 'Apply patches....\n'
	cd ${CURDIR}/src/github.com/cockroachdb/cockroach
	curl -sSL https://github.com/cockroachdb/cockroach/commit/0de1fd4d19b9cf39ea2c4cce668714c8ec9394b4.patch | git apply - ||  echo "Error: Patch Cockroach code files"
	curl -sSL https://github.com/ianlancetaylor/cgosymbolizer/commit/d43e30eacb43da92f28d523438f977af0a7b6072.patch | git apply --directory=vendor/github.com/ianlancetaylor/cgosymbolizer - ||  echo "Error: Patch cgosymbolizer code files"
	curl -sSL https://github.com/apache/arrow/commit/aca707086160afd92da62aa2f9537a284528e48a.patch | git apply --directory=vendor/github.com/apache/arrow --exclude '**/array/bufferbuilder_numeric_test.go' - ||  echo "Error: Patch arrow code files"
	curl -sSL https://github.com/cockroachdb/snappy/commit/060abe547466cfd7cec09e53846e9e205d019045.patch | git apply --directory=c-deps/snappy - ||  echo "Error: Patch snappy code files"

	# Build CockroachDB
	printf -- 'Building CockroachDB.... \n'
	printf -- 'Build might take some time. Sit back and relax\n'
	cd ${CURDIR}/src/github.com/cockroachdb/cockroach
	make build
	sudo env GOPATH=$GOPATH PATH=$PATH make install
	sudo mkdir -p /usr/local/lib/cockroach
	sudo cp lib/libgeos.so /usr/local/lib/cockroach/
	sudo cp lib/libgeos_c.so /usr/local/lib/cockroach/
	printf -- 'Successfully installed CockroachDB. \n'

	#Run Test
	runTests

	cleanup
}

function runTests() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- "TEST Flag is set, continue with running test \n"  >> "$LOG_FILE"

		cd ${CURDIR}/src/github.com/cockroachdb/cockroach
		make test
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
	echo "  build_crdb.sh [-y install-without-confirmation -t run-test-cases]"
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
	printf -- '\n********************************************************************************************************\n'
	printf -- "\n* Getting Started * \n"
	printf -- "\nAll relevant binaries are installed in /usr/local/bin. \n"
	printf -- '\n\n**********************************************************************************************************\n'
}

###############################################################################################################

logDetails
DISTRO="$ID-$VERSION_ID"
checkPrequisites #Check Prequisites

case "$DISTRO" in
"ubuntu-18.04" | "ubuntu-20.04" | "ubuntu-20.10")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
	sudo apt-get update >/dev/null
	sudo apt-get install -y autoconf automake cmake wget libncurses5-dev bison xz-utils patch g++ curl git |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"sles-12.5")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
	sudo zypper install -y autoconf automake wget ncurses-devel bison patch tar gzip gawk xz python gcc7-c++ zlib-devel bzip2 curl git  |& tee -a "$LOG_FILE"
	sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-7 100
	sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-7 100
	sudo update-alternatives --install /usr/bin/cpp cpp /usr/bin/cpp-7 100
	sudo ln -f -s /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"sles-15.2")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
	sudo zypper install -y autoconf automake wget ncurses-devel bison patch tar gzip cmake gawk xz gcc-c++ git python curl |& tee -a "$LOG_FILE"
	sudo ln -f -s /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"rhel-7.8" | "rhel-7.9")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
	sudo subscription-manager repos --enable=rhel-7-server-for-system-z-rhscl-rpms || true
	sudo yum install -y git autoconf automake wget ncurses-devel bison patch tar gzip xz make bzip2 zlib-devel devtoolset-7-gcc-c++ devtoolset-7-gcc curl diffutils |& tee -a "$LOG_FILE"
	source /opt/rh/devtoolset-7/enable
	sudo ln -f -s /opt/rh/devtoolset-7/root/usr/bin/s390x-redhat-linux-gcc /opt/rh/devtoolset-7/root/usr/bin/s390x-linux-gnu-gcc
	sudo ln -f -s /opt/rh/devtoolset-7/root/usr/bin/s390x-redhat-linux-c++ /opt/rh/devtoolset-7/root/usr/bin/s390x-linux-gnu-c++
	sudo ln -f -s /opt/rh/devtoolset-7/root/usr/bin/s390x-redhat-linux-g++ /opt/rh/devtoolset-7/root/usr/bin/s390x-linux-gnu-g++
	configureAndInstall |& tee -a "$LOG_FILE"
  ;;

"rhel-8.1" | "rhel-8.2" | "rhel-8.3")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
	sudo yum install -y gcc-c++ autoconf cmake git wget make ncurses-devel curl xz diffutils bison |& tee -a "$LOG_FILE"
	sudo ln -f -s /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
    configureAndInstall |& tee -a "$LOG_FILE"
  ;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "$LOG_FILE"
