#!/usr/bin/env bash
# © Copyright IBM Corporation 2024, 2025.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/InfluxDB/2.7.11/build_influxdb.sh
# Execute build script: bash build_influxdb.sh    (provide -h for help)

set -e -o pipefail

CURDIR="$(pwd)"
PACKAGE_NAME="InfluxDB"
PACKAGE_VERSION="2.7.11"
GO_VERSION="1.22.10"
export GOPATH=$CURDIR
FORCE="false"
TEST="false"
OVERRIDE="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

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
		printf -- 'You can install sudo from repository using apt, yum or zypper based on your distro. \n'
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

function installBazaar() {
	printf -- "Start building Bazaar.\n"

	BZR_VERSION=2.7.0
	BZR_MAJOR_MINOR=$(echo "$BZR_VERSION" | awk -F'.' '{print $1"."$2}')
	wget https://launchpad.net/bzr/"${BZR_MAJOR_MINOR}"/"${BZR_VERSION}"/+download/bzr-"${BZR_VERSION}".tar.gz
	tar zxf bzr-"${BZR_VERSION}".tar.gz
	export PATH=$PATH:$HOME/bzr-"${BZR_VERSION}"

	printf -- "Finished building Bazaar.\n"
}

function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'

    # Install yarn
    printf -- 'Installing yarn...\n'
    cd $CURDIR
    curl -o- -L https://yarnpkg.com/install.sh | bash
    export PATH="$HOME/.yarn/bin:$HOME/.config/yarn/global/node_modules/.bin:$PATH"

    # Install Rust
    printf -- 'Installing rust...\n'
    cd $CURDIR
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source $HOME/.cargo/env

    # Install Go
    printf -- 'Configuration and Installation started \n'
    if [[ "${OVERRIDE}" == "true" ]]
    then
      printf -- 'Go exists on the system. Override flag is set to true hence updating the same\n ' |& tee -a "$LOG_FILE"
    fi

    # Install Go
    printf -- 'Downloading go binaries \n'
		cd $GOPATH
    wget -q https://storage.googleapis.com/golang/go"${GO_VERSION}".linux-s390x.tar.gz |& tee -a  "$LOG_FILE"
    chmod ugo+r go"${GO_VERSION}".linux-s390x.tar.gz
    sudo rm -rf /usr/local/go /usr/bin/go
    sudo tar -C /usr/local -xzf go"${GO_VERSION}".linux-s390x.tar.gz
    sudo ln -sf /usr/local/go/bin/go /usr/bin/ 
    sudo ln -sf /usr/local/go/bin/gofmt /usr/bin/
    printf -- 'Extracted the tar in /usr/local and created symlink\n'
    if [[ "${ID}" != "ubuntu" ]]
    then
      sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc 
      printf -- 'Symlink done for gcc \n' 
    fi
    
    #Verify if go is configured correctly
    if go version | grep -q "$GO_VERSION"
    then
      printf -- "Installed %s successfully \n" "$GO_VERSION"
    else
      printf -- "Error while installing Go, exiting with 127 \n";
      exit 127;
    fi
    go version
    export PATH=$PATH:$GOPATH/bin
    printf -- "Install Go success\n"

    # Install pkg-config
    cd $CURDIR
    export GO111MODULE=on
    go install github.com/influxdata/pkg-config@v0.2.13
    which -a pkg-config

    # Download and configure InfluxDB
    printf -- 'Downloading InfluxDB. Please wait.\n'
    cd $CURDIR
    git clone -b v${PACKAGE_VERSION} https://github.com/influxdata/influxdb.git
    cd influxdb

    #Build InfluxDB
    printf -- 'Building InfluxDB \n'
    printf -- 'Build might take some time. Sit back and relax\n'
    export NODE_OPTIONS=--max_old_space_size=4096
    rustup toolchain install 1.68-s390x-unknown-linux-gnu
    make
    sudo cp ./bin/linux/* /usr/bin
    printf -- 'Successfully installed InfluxDB. \n'

    #Run Test
    runTests
}

function runTests() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- "TEST Flag is set, continue with running test \n"  >> "$LOG_FILE"

		cd ${CURDIR}/influxdb
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
	echo "  bash build_influxdb.sh [-y install-without-confirmation -t run-test-cases]"
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
    printf -- "\nAll relevant binaries are installed in /usr/bin. Be sure to set the PATH as follows:\n"
    printf -- "\n     	export PATH=/usr/local/go/bin:\$PATH\n"
    printf -- "\nMore information can be found here: https://docs.influxdata.com/influxdb/v2.7/get-started\n"
    printf -- '\n\n**********************************************************************************************************\n'
}

###############################################################################################################

logDetails
DISTRO="$ID-$VERSION_ID"
checkPrequisites #Check Prequisites

case "$DISTRO" in
"rhel-8.8" | "rhel-8.10")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
	sudo yum install -y clang git gcc gcc-c++ wget protobuf protobuf-devel tar curl patch pkg-config make nodejs python3 gawk |& tee -a "$LOG_FILE"
	sudo ln -sf /usr/bin/python3 /usr/bin/python
	installBazaar
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"rhel-9.2" | "rhel-9.4" | "rhel-9.5")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
	sudo yum install -y --allowerasing clang git gcc gcc-c++ wget protobuf protobuf-devel tar curl patch pkg-config make nodejs python3 gawk |& tee -a "$LOG_FILE"
	sudo ln -sf /usr/bin/python3 /usr/bin/python
	installBazaar
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"sles-15.6")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
	sudo zypper install -y git gcc gcc-c++ wget which protobuf-devel tar gzip curl patch pkg-config nodejs20 make clang7 gawk |& tee -a "$LOG_FILE"
	installBazaar
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"ubuntu-20.04" | "ubuntu-22.04" | "ubuntu-24.04" | "ubuntu-24.10")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
	sudo apt-get update >/dev/null
	sudo apt-get install -y clang git gcc g++ wget bzr protobuf-compiler libprotobuf-dev curl pkg-config make nodejs |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "$LOG_FILE"
