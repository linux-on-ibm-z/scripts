#!/usr/bin/env bash
# © Copyright IBM Corporation 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/CockroachDB/20.1.5/build_crdb.sh
# Execute build script: bash build_crdb.sh    (provide -h for help)
set -e  -o pipefail

CURDIR="$(pwd)"
PACKAGE_NAME="CockroachDB"
PACKAGE_VERSION="20.1.5"
FORCE="false"
TEST="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/CockroachDB/20.1.5/patch"

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
	sudo rm -rf ${CURDIR}/go1.13.11.linux-s390x.tar.gz
	sudo rm -rf ${CURDIR}/node-v12.18.2-linux-s390x.tar.xz
	printf -- 'Cleaned up the artifacts\n' >>"$LOG_FILE"	
}

function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'
	
	# Install go
	printf -- 'Installing Go...\n'
	cd ${CURDIR}
	wget https://storage.googleapis.com/golang/go1.13.11.linux-s390x.tar.gz
	chmod ugo+r go1.13.11.linux-s390x.tar.gz
	sudo tar -C /usr/local -xzf go1.13.11.linux-s390x.tar.gz
	export PATH=$PATH:/usr/local/go/bin
	go version

	# Install Nodejs and yarn
	printf -- 'Installing Nodejs and yarn...\n'
	cd ${CURDIR}
	wget https://nodejs.org/dist/v12.18.2/node-v12.18.2-linux-s390x.tar.xz
	chmod ugo+r node-v12.18.2-linux-s390x.tar.xz
	sudo tar -C /usr/local -xf node-v12.18.2-linux-s390x.tar.xz
	export PATH=$PATH:/usr/local/node-v12.18.2-linux-s390x/bin
	node -v
	sudo env PATH=$PATH npm install -g yarn

	# Change the ownership of .config
	printf -- 'Change the .config ownership...\n'
	cd
	mkdir -p .config
	sudo chown -R $(whoami):$(whoami) .config

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
	sleep 2
	
	# Applying patches
	printf -- 'Apply patches....\n'
	cd ${CURDIR}/src/github.com/cockroachdb/cockroach/vendor
	curl -sSL $PATCH_URL/vendor.diff | git apply || echo "Error: Patch Cockroach vendor files"

	#Build CockroachDB
	printf -- 'Building CockroachDB.... \n'
	printf -- 'Build might take some time. Sit back and relax\n'
	cd ${CURDIR}/src/github.com/cockroachdb/cockroach
	make build
	sudo env GOPATH=$GOPATH PATH=$PATH make install

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
"ubuntu-18.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
	sudo apt-get update >/dev/null
    sudo apt-get install -y autoconf automake cmake wget libncurses5-dev bison xz-utils patch g++ curl git |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;
*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "$LOG_FILE"
