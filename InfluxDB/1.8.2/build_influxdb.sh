#!/usr/bin/env bash
# © Copyright IBM Corporation 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/InfluxDB/1.8.2/build_influxdb.sh
# Execute build script: bash build_influxdb.sh    (provide -h for help)

set -e -o pipefail

CURDIR="$(pwd)"
PACKAGE_NAME="InfluxDB"
PACKAGE_VERSION="1.8.2"
FORCE="false"
TEST="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/InfluxDB/${PACKAGE_VERSION}/patch"

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

	if [[ -f ${CURDIR}/go1.13.14.linux-s390x.tar.gz ]]; then
		sudo rm ${CURDIR}/go1.13.14.linux-s390x.tar.gz
		printf -- 'Cleaned up the artifacts\n' >>"$LOG_FILE"
	fi
}

function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'

    # Install go
    printf -- 'Installing Go...\n'
    cd ${CURDIR}
    wget https://storage.googleapis.com/golang/go1.13.14.linux-s390x.tar.gz
    chmod ugo+r go1.13.14.linux-s390x.tar.gz
    sudo tar -C /usr/local -xzf go1.13.14.linux-s390x.tar.gz
    export PATH=$PATH:/usr/local/go/bin
    export PATH=$(go env GOPATH)/bin:$PATH

    if [[ "${ID}" != "ubuntu" ]]
    then
            sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
            printf -- 'Symlink done for gcc \n'
    fi

    go version

	# Download and configure InfluxDB
    printf -- 'Downloading InfluxDB. Please wait.\n'
    export GO111MODULE=on
    git clone https://github.com/influxdata/influxdb.git
    cd influxdb
    git checkout v${PACKAGE_VERSION}

	# Apply patch
	wget ${PATCH_URL}/patch_functions.diff
    patch --ignore-whitespace query/functions.go < patch_functions.diff
    sleep 2

    #Build InfluxDB
    printf -- 'Building InfluxDB \n'
    printf -- 'Build might take some time. Sit back and relax\n'
    go clean ./...
    go build ./...
    go install -ldflags="-X main.version=v${PACKAGE_VERSION}" ./...

    printf -- 'Successfully installed InfluxDB. \n'

    #Run Test
    runTests

    cleanup
}

function runTests() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- "TEST Flag is set, continue with running test \n"  >> "$LOG_FILE"

		cd ${CURDIR}/influxdb
		go test ./...
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
	echo "  build_influxdb.sh [-y install-without-confirmation -t run-test-cases]"
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
    export PATH=$PATH:/usr/local/go/bin
    GOPATH=$(go env GOPATH)
    printf -- '\n********************************************************************************************************\n'
    printf -- "\n* Getting Started * \n"
    printf -- "\nAll relevant binaries are installed in ${GOPATH}/bin. Be sure to set the PATH as follows:\n"
	printf -- "\n     	export PATH=${GOPATH}/bin:/usr/local/go/bin:\$PATH\n"
    printf -- "\nMore information can be found here: https://docs.influxdata.com/influxdb/v1.8/introduction/get-started/\n"
    printf -- '\n\n**********************************************************************************************************\n'
}

###############################################################################################################

logDetails
DISTRO="$ID-$VERSION_ID"
checkPrequisites #Check Prequisites

case "$DISTRO" in
"ubuntu-18.04" | "ubuntu-20.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
	sudo apt-get update >/dev/null
    sudo apt-get install -y git gcc g++ wget tar patch  |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"sles-12.5" | "sles-15.1" | "sles-15.2")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
    sudo zypper install -y git gcc gcc-c++ wget tar gzip patch |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"rhel-7.6" | "rhel-7.7" | "rhel-7.8" | "rhel-8.1" | "rhel-8.2")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
    sudo yum install -y git gcc wget tar patch |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "$LOG_FILE"
