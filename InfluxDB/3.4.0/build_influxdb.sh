#!/usr/bin/env bash
# © Copyright IBM Corporation 2025.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/InfluxDB/3.4.0/build_influxdb.sh
# Execute build script: bash build_influxdb.sh    (provide -h for help)

set -e -o pipefail

CURDIR="$(pwd)"
PACKAGE_NAME="InfluxDB"
PACKAGE_VERSION="3.4.0"
FORCE="false"
TEST="false"
OVERRIDE="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/InfluxDB/${PACKAGE_VERSION}/patch"


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


function configureAndInstall() {
    printf -- 'Configuration and Installation started \n'

    # Install Rust
    printf -- 'Installing rust...\n'
    cd $CURDIR
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source $HOME/.cargo/env
    cargo install cargo-nextest --locked
    
    # Setup arrow-rs
    cd $CURDIR
    git clone https://github.com/apache/arrow-rs.git
    cd arrow-rs
    git checkout 55.2.0
    curl -sSL ${PATCH_URL}/arrow.patch | patch -p1 || error "arrow.patch"

    # Download and configure InfluxDB
    printf -- 'Downloading InfluxDB. Please wait.\n'
    cd $CURDIR
    git clone --depth 1 -b v${PACKAGE_VERSION} https://github.com/influxdata/influxdb.git
    cd influxdb
    curl -sSL ${PATCH_URL}/influxdb.patch | patch -p1 || error "influxdb.patch"
    sed -i "s|SOURCE_ROOT|$CURDIR|g" Cargo.toml

    #Build InfluxDB
    printf -- 'Building InfluxDB \n'
    printf -- 'Build might take some time. Sit back and relax\n'
    cargo build --profile release
    sudo cp ./target/release/influxdb3 /usr/bin
    printf -- 'Successfully installed InfluxDB. \n'

    #Run Test
    runTests
}

function runTests() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- "TEST Flag is set, continue with running test \n"  >> "$LOG_FILE"

		cd ${CURDIR}/influxdb
		cargo nextest run --workspace --nocapture --no-fail-fast
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
    printf -- '\n********************************************************************************************************\n'
    printf -- "\n* Getting Started * \n"
    printf -- "\nInfluxDB binary has been installed at /usr/bin/influxdb3\n"
    printf -- "\nMore information can be found here: https://docs.influxdata.com/influxdb3/core/get-started\n"
    printf -- '\n\n**********************************************************************************************************\n'
}

###############################################################################################################

logDetails
DISTRO="$ID-$VERSION_ID"
checkPrequisites #Check Prequisites

case "$DISTRO" in
"rhel-8.10")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
	sudo yum install -y clang git wget curl patch pkg-config python3.12 python3.12-devel unzip |& tee -a "$LOG_FILE"
	wget https://github.com/protocolbuffers/protobuf/releases/download/v32.0/protoc-32.0-linux-s390_64.zip
	sudo unzip -q protoc-32.0-linux-s390_64.zip -d /usr/local/
	rm protoc-32.0-linux-s390_64.zip
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"rhel-9.4" | "rhel-9.6" | "rhel-10.0")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
	sudo yum install -y clang git wget protobuf protobuf-devel curl patch pkg-config python3 python3-devel |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"sles-15.6" | "sles-15.7")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
	sudo zypper install -y git wget which protobuf-devel curl patch pkg-config clang gawk make python311 python311-devel |& tee -a "$LOG_FILE"
	sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 60
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"ubuntu-22.04" | "ubuntu-24.04" | "ubuntu-25.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
	sudo apt-get update >/dev/null
	sudo apt-get install -y  build-essential pkg-config libssl-dev clang curl git protobuf-compiler python3 python3-dev python3-pip python3-venv libprotobuf-dev |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "$LOG_FILE"
