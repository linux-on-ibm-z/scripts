#!/usr/bin/env bash
# © Copyright IBM Corporation 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/InfluxDB/2.0.2/build_influxdb.sh
# Execute build script: bash build_influxdb.sh    (provide -h for help)

set -e -o pipefail

CURDIR="$(pwd)"
PACKAGE_NAME="InfluxDB"
PACKAGE_VERSION="2.0.2"
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

	if [[ -f ${CURDIR}/go1.15.4.linux-s390x.tar.gz ]]; then
		sudo rm ${CURDIR}/go1.15.4.linux-s390x.tar.gz
	fi
	if [[ ${DISTRO} == "sles-12.5" ]]; then
		sudo rm -rf ${CURDIR}/llvm-project
		sudo rm -rf ${CURDIR}/cmake-3.18.3*
	fi
	printf -- 'Cleaned up the artifacts\n' >>"$LOG_FILE"
}

function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'

    # Install cmake and clang for SLES 12 sp5
    if [[ ${DISTRO} == "sles-12.5" ]]; then
	    # install CMake
	    printf -- 'Installing cmake...\n'
	    cd $CURDIR
	    wget https://github.com/Kitware/CMake/releases/download/v3.18.3/cmake-3.18.3.tar.gz
	    tar -xzf cmake-3.18.3.tar.gz
	    cd cmake-3.18.3
	    ./bootstrap
	    make
	    sudo make install
	    hash -r

	    # install Clang
	    printf -- 'Installing clang...\n'
	    cd $CURDIR
	    git clone https://github.com/llvm/llvm-project.git
	    cd llvm-project
	    mkdir build
	    cd build
	    cmake -DLLVM_ENABLE_PROJECTS=clang -DCMAKE_BUILD_TYPE=Release -G "Unix Makefiles" ../llvm
	    make -j4
	    sudo make install
	    clang -v
    fi

    # Install NodeJS for Ubuntu 18.04 and RHEL 7.x
    if [[ ${DISTRO} == "ubuntu-18.04" || ${DISTRO} =~ rhel-7\.* ]]; then
	    printf -- 'Installing node...\n'
	    cd $CURDIR
	    wget https://nodejs.org/download/release/v14.8.0/node-v14.8.0-linux-s390x.tar.xz
	    VERSION=v14.8.0
	    DISTRO=linux-s390x
	    sudo mkdir -p /usr/local/lib/nodejs
	    export PATH=/usr/local/lib/nodejs/node-$VERSION-$DISTRO/bin:$PATH
    fi

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
    printf -- 'Installing Go...\n'
    cd ${CURDIR}
    wget https://golang.org/dl/go1.15.4.linux-s390x.tar.gz
    sudo tar -C /usr/local -xzf go1.15.4.linux-s390x.tar.gz
    export PATH=/usr/local/go/bin:$PATH
    export PATH=$(go env GOPATH)/bin:$PATH

    if [[ "${ID}" != "ubuntu" ]]
    then
	    sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
	    printf -- 'Symlink done for gcc \n'
    fi

    go version

    # Install pkg-config
    cd $CURDIR
    export GO111MODULE=on
    go get github.com/influxdata/pkg-config
    which -a pkg-config

    # Patch Apache Arrow
    cd $CURDIR
    git clone https://github.com/apache/arrow.git
    cd arrow/go/arrow
    git checkout ac86123a3f013ba1eeac2b66c2ccd00810c67871
    wget -O $CURDIR/arrow.patch https://github.com/apache/arrow/commit/aca707086160afd92da62aa2f9537a284528e48a.patch
    git apply $CURDIR/arrow.patch

    # Download and configure InfluxDB
    printf -- 'Downloading InfluxDB. Please wait.\n'
    cd $CURDIR
    git clone https://github.com/influxdata/influxdb.git
    cd influxdb
    git checkout v${PACKAGE_VERSION}

    # Apply patch
    wget ${PATCH_URL}/influxdb.diff
    git apply influxdb.diff
    sleep 2

    #Build InfluxDB
    printf -- 'Building InfluxDB \n'
    printf -- 'Build might take some time. Sit back and relax\n'
    export NODE_OPTIONS=--max_old_space_size=4096
    make
    sudo cp ./bin/linux/* /usr/bin
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
    printf -- "\nAll relevant binaries are installed in /usr/bin. Be sure to set the PATH as follows:\n"
    printf -- "\n     	export PATH=/usr/local/go/bin:\$PATH\n"
    printf -- "\nMore information can be found here: https://v2.docs.influxdata.com/v2.0/get-started/#start-with-influxdb-oss\n"
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
	sudo apt-get install -y clang git gcc g++ wget bzr protobuf-compiler libprotobuf-dev curl pkg-config make  |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"ubuntu-20.04" | "ubuntu-20.10")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
	sudo apt-get update >/dev/null
	sudo apt-get install -y clang git gcc g++ wget bzr protobuf-compiler libprotobuf-dev curl pkg-config make nodejs |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"sles-12.5")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
	sudo zypper install -y git gcc7 gcc7-c++ wget bzr protobuf-devel tar gzip curl patch pkg-config nodejs10 make bzip2 cmake libarchive13 libopenssl-devel unzip zip |& tee -a "$LOG_FILE"
	sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-7 40
	sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-7 40
	sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-7 40
	sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-7 40
	sudo /sbin/ldconfig
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"sles-15.1" | "sles-15.2")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
	sudo zypper install -y git gcc gcc-c++ wget bzr protobuf-devel tar gzip curl patch pkg-config nodejs10 make clang |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"rhel-7.8" | "rhel-7.9")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
	sudo subscription-manager repos --enable rhel-7-server-for-system-z-devtools-rpms
	sudo yum install -y git gcc gcc-c++ wget bzr protobuf tar curl patch pkgconfig make llvm-toolset-7 |& tee -a "$LOG_FILE"
	source /opt/rh/llvm-toolset-7/enable
	clang --version
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"rhel-8.1" | "rhel-8.2" | "rhel-8.3")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
	sudo yum install -y clang git gcc gcc-c++ wget protobuf tar curl patch pkg-config make nodejs python38 |& tee -a "$LOG_FILE"
	sudo ln -sf /usr/bin/python3 /usr/bin/python
	wget https://launchpad.net/bzr/2.7/2.7.0/+download/bzr-2.7.0.tar.gz
	tar zxf bzr-2.7.0.tar.gz
	export PATH=$PATH:$HOME/bzr-2.7.0
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "$LOG_FILE"
