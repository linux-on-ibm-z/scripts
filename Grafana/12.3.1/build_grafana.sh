#!/bin/bash
# © Copyright IBM Corporation 2025.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Grafana/12.3.1/build_grafana.sh
# Execute build script: bash build_grafana.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="grafana"
PACKAGE_VERSION="12.3.1"
CURDIR="$(pwd)"
GOLANG_VERSION="1.25.5"
GO_INSTALL_URL="https://golang.org/dl/go${GOLANG_VERSION}.linux-s390x.tar.gz"
GO_DEFAULT="$HOME/go"
NODE_JS_VERSION="24.11.0"

FORCE="false"
TESTS="false"
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

# Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
	mkdir -p "$CURDIR/logs/"
fi

source "/etc/os-release"

function prepare() {
	if command -v "sudo" >/dev/null; then
		printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
	else
		printf -- 'Sudo : No \n' >>"$LOG_FILE"
		printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n'
		exit 1
	fi

	if [[ "$FORCE" == "true" ]]; then
		printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
	else
		# Ask user for prerequisite installation
		printf -- "\n\nAs part of the installation , Go "${GO_VERSION}", NodeJS "${NODE_JS_VERSION}" will be installed, \n"
		while true; do
			read -r -p "Do you want to continue (y/n) ? :  " yn
			case $yn in
			[Yy]*)
				printf -- 'User responded with Yes. \n' |& tee -a "$LOG_FILE"
				break
				;;
			[Nn]*) exit ;;
			*) echo "Please provide confirmation to proceed." ;;
			esac
		done
	fi
}

function cleanup() {
	rm -f "$CURDIR/go${GO_VERSION}.linux-s390x.tar.gz" \
	    "$CURDIR/grafana-${PACKAGE_VERSION}.linux-amd64.tar.gz" \
		"$CURDIR/node-v${NODE_JS_VERSION}-linux-s390x.tar.xz"

	printf -- 'Cleaned up the artifacts\n' >>"$LOG_FILE"
}

function installNodejs() {
	cd "$CURDIR"
	wget https://nodejs.org/dist/v${NODE_JS_VERSION}/node-v${NODE_JS_VERSION}-linux-s390x.tar.xz
	chmod ugo+r node-v${NODE_JS_VERSION}-linux-s390x.tar.xz
	sudo tar -C /usr/local -xf node-v${NODE_JS_VERSION}-linux-s390x.tar.xz
	export PATH=$PATH:/usr/local/node-v${NODE_JS_VERSION}-linux-s390x/bin

	sudo chmod ugo+w -R /usr/local/node-v${NODE_JS_VERSION}-linux-s390x/
	npm install -g yarn
	yarn set version 4.10.3
	yarn --version

	cd "$CURDIR"/grafana
	yarn install --immutable
	cd "$CURDIR"
}

function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'

	cd "${CURDIR}"
    # Install go
    printf -- "\nInstalling Go ... \n" | tee -a "$LOG_FILE"
    wget $GO_INSTALL_URL
    sudo tar -C /usr/local -xzf "go${GOLANG_VERSION}.linux-s390x.tar.gz"

    if [[ "${ID}" != "ubuntu" ]]; then
        sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
        printf -- 'Symlink done for gcc \n'
    fi

    # Set GOPATH if not already set
    if [[ -z "${GOPATH}" ]]; then
        printf -- "\nSetting default value for GOPATH \n"
        # Check if go directory exists
        if [ ! -d "$HOME/go" ]; then
            mkdir "$HOME/go"
        fi
        export GOPATH="${GO_DEFAULT}"
    else
        printf -- "\nGOPATH already set : Value : %s \n" "$GOPATH"
        if [ ! -d "$GOPATH" ]; then
            mkdir -p "$GOPATH"
        fi
    fi
    export PATH=/usr/local/go/bin:$PATH

	printf -- "Building Grafana... \n"
	git clone -b v"${PACKAGE_VERSION}" https://github.com/grafana/grafana.git
	cd grafana
	go mod download
	make build-go
	printf -- 'Build Grafana success \n'
	cd "${CURDIR}"
	printf -- "Building Grafana distribution... \n"
	# Download the grafana distribution to get the pre-built frontend files
	wget https://dl.grafana.com/oss/release/grafana-${PACKAGE_VERSION}.linux-amd64.tar.gz
	mkdir grafana-dist
	tar -x -C grafana-dist --strip-components=1 -f grafana-${PACKAGE_VERSION}.linux-amd64.tar.gz
	rm grafana-dist/bin/*
	cp grafana/bin/linux-s390x/grafana grafana/bin/linux-s390x/grafana-server grafana/bin/linux-s390x/grafana-cli grafana-dist/bin/
	printf -- 'Build Grafana distribution success \n'

	# Run Tests
	cd "${CURDIR}"
	runTest

	#Cleanup
	cd "${CURDIR}"
	cleanup
}

function runTest() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- "TEST Flag is set, continue with running test \n"

		cd "${CURDIR}/grafana"
		# Test backend
		go test -short -timeout=30m ./pkg/...

		# Test frontend
		installNodejs
		cd "${CURDIR}/grafana"
		export NODE_OPTIONS="--max-old-space-size=8192"
		echo fs.inotify.max_user_watches=524288 | sudo tee -a /etc/sysctl.conf && sudo sysctl -p
		yarn test --no-watch

		printf -- '**********************************************************************************************************\n'
        printf -- 'Some backend and frontend tests may fail and will pass when rerun.\n\n'
        printf -- 'Failed backend tests can be rerun with the commands:\n'
        printf -- "    export PATH=/usr/local/go/bin:$PATH\n"
        printf -- "    cd ${CURDIR}/grafana\n"
        printf -- '    go test -short -timeout=30m ./pkg/...'
        printf -- '\nFailed frontend tests can be rerun with the commands:\n'
        printf -- "    export PATH=\$PATH:/usr/local/node-v${NODE_JS_VERSION}-linux-s390x/bin\n"
        printf -- '    export NODE_OPTIONS="--max-old-space-size=8192"\n'
        printf -- "    cd ${CURDIR}/grafana\n"
        printf -- '    yarn test --no-watch --onlyFailures\n'
        printf -- '**********************************************************************************************************\n'
		
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
	echo " bash build_grafana.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests]"
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
	printf -- '\n***************************************************************************************\n'
	printf -- "Getting Started: \n"
	printf -- "To run grafana , run the following commands: \n"
	printf -- "    cd ${CURDIR}/grafana-dist/\n"
	printf -- "    ./bin/grafana server\n"
	printf -- "\nAccess grafana UI using the below link:\n"
	printf -- "    http://<host-ip>:<port>/    [Default port = 3000] \n"
	printf -- '***************************************************************************************\n'
	printf -- '\n'
}

###############################################################################################################

logDetails
prepare # Check Prequisites

DISTRO="$ID-$VERSION_ID"
printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
case "$DISTRO" in
"rhel-8.10" | "rhel-9.4" | "rhel-9.6" | "rhel-9.7" | "rhel-10.0" | "rhel-10.1")
	ALLOWERASING=""
	if [[ "$DISTRO" == rhel-9* ]]; then
		ALLOWERASING="--allowerasing"
    fi
	sudo yum install -y ${ALLOWERASING} make gcc gcc-c++ tar wget git git-core patch xz curl python3 procps |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"sles-15.7" | "sles-16.0")
	sudo zypper install -y make gcc gcc-c++ wget tar git-core xz gzip curl patch python3 |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"ubuntu-22.04" | "ubuntu-24.04" | "ubuntu-25.10")
	sudo apt-get update
	sudo apt-get install -y gcc g++ tar wget git make xz-utils patch curl python3 |& tee -a "$LOG_FILE"
	if [[ "$DISTRO" != ubuntu-22.04 ]]; then
		sudo apt-get install -y python3-setuptools |& tee -a "$LOG_FILE"
	fi
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "$LOG_FILE"
