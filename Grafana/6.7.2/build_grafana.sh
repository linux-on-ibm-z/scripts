#!/bin/bash
# © Copyright IBM Corporation 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Grafana/6.7.2/build_grafana.sh
# Execute build script: bash build_grafana.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="grafana"
PACKAGE_VERSION="6.7.2"
CURDIR="$(pwd)"

PHANTOMJS_INSTALL_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/PhantomJS/build_phantomjs.sh"
GRAFANA_TESTS_PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Grafana/6.7.2/patch/ArrowDataFrame.test.ts.patch"

GO_VERSION="1.14.1"
NODE_JS_VERSION="12.9.1"
PHANTOMJS_VERSION="2.1.1"

GO_DEFAULT="$HOME/go"

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
		printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n'
		exit 1
	fi

	if [[ "$FORCE" == "true" ]]; then
		printf -- 'Force attribute provided hence continuing with install without confirmation message' |& tee -a "$LOG_FILE"
	else
		# Ask user for prerequisite installation
		printf -- "\n\nAs part of the installation , Go "${GO_VERSION}" and PhantomJS "${PHANTOMJS_VERSION}" will be installed, \n"
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
	if [ -f $CURDIR/node-v${NODE_JS_VERSION}-linux-s390x/bin/yarn ]; then
		rm $CURDIR/node-v${NODE_JS_VERSION}-linux-s390x/bin/yarn
	fi

	if [ -f "$CURDIR/node-v${NODE_JS_VERSION}-linux-s390x.tar.xz" ]; then
		rm "$CURDIR/node-v${NODE_JS_VERSION}-linux-s390x.tar.xz"
	fi

	if [ -f "$CURDIR/go${GO_VERSION}.linux-s390x.tar.gz" ]; then
		rm "$CURDIR/go${GO_VERSION}.linux-s390x.tar.gz"
	fi

	printf -- 'Cleaned up the artifacts\n' >>"$LOG_FILE"
}

function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'

	# Install grafana
	printf -- "\nInstalling %s..... \n" "$PACKAGE_NAME"

	# Grafana installation

	# Install NodeJS
	cd "$CURDIR"
	wget https://nodejs.org/dist/v${NODE_JS_VERSION}/node-v${NODE_JS_VERSION}-linux-s390x.tar.xz
	chmod ugo+r node-v${NODE_JS_VERSION}-linux-s390x.tar.xz
	sudo tar -C /usr/local -xf node-v${NODE_JS_VERSION}-linux-s390x.tar.xz
	export PATH=$PATH:/usr/local/node-v${NODE_JS_VERSION}-linux-s390x/bin

	printf -- 'Install NodeJS success \n'

	cd "${CURDIR}"

	# Install go
	printf -- "Installing Go... \n"
	wget https://dl.google.com/go/go${GO_VERSION}.linux-s390x.tar.gz
    chmod ugo+r go${GO_VERSION}.linux-s390x.tar.gz
    sudo tar -C /usr/local -xf go${GO_VERSION}.linux-s390x.tar.gz
    sudo ln -sf /usr/local/go/bin/go /usr/bin/ 
  	sudo ln -sf /usr/local/go/bin/gofmt /usr/bin/
  	printf -- 'Extracted the tar in /usr/local and created symlink\n'

	if [[ "${ID}" != "ubuntu" ]]; then
		sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
		printf -- 'Symlink done for gcc \n'
	fi
	# Set GOPATH if not already set
	if [[ -z "${GOPATH}" ]]; then
		printf -- "Setting default value for GOPATH \n"

		#Check if go directory exists
		if [ ! -d "$HOME/go" ]; then
			mkdir "$HOME/go"
		fi
		export GOPATH="${GO_DEFAULT}"
	else
		printf -- "GOPATH already set : Value : %s \n" "$GOPATH"
	fi
	printenv >>"$LOG_FILE"

	#Build Grafana
	printf -- "Building Grafana... \n"

	#Check if Grafana directory exists
	if [ ! -d "$GOPATH/src/github.com/grafana" ]; then
		mkdir -p "$GOPATH/src/github.com/grafana"
		printf -- "Created grafana Directory at GOPATH"
	fi

	cd "$GOPATH/src/github.com/grafana"
	if [ -d "$GOPATH/src/github.com/grafana/grafana" ]; then
		rm -rf "$GOPATH/src/github.com/grafana/grafana"
		printf -- "Removing Existing grafana Directory at GOPATH"
	fi

	git clone -b v"${PACKAGE_VERSION}" https://github.com/grafana/grafana.git

	printf -- "Created grafana Directory at 1"
	#Give permission
	cd grafana
	make deps-go
	make build-go
	printf -- 'Build Grafana success \n'

	#Add grafana to /usr/bin
	sudo cp "$GOPATH/src/github.com/grafana/grafana/bin/linux-s390x/grafana-server" /usr/bin/
	sudo cp "$GOPATH/src/github.com/grafana/grafana/bin/linux-s390x/grafana-cli" /usr/bin/

	printf -- 'Add grafana to /usr/bin success \n'

	cd "${CURDIR}"
	# Build Grafana frontend assets

    # Apply test case patch
    cd $GOPATH/src/github.com/grafana/grafana
    wget -O ArrowDataFrame.test.ts.patch  $GRAFANA_TESTS_PATCH_URL
    patch --ignore-whitespace packages/grafana-data/src/dataframe/ArrowDataFrame.test.ts < ArrowDataFrame.test.ts.patch
    rm ArrowDataFrame.test.ts.patch

	# Install PhantomJS
	printf -- "Installing PhantomJS... \n"

	sudo wget -O "phantom_setup.sh" $PHANTOMJS_INSTALL_URL
	bash phantom_setup.sh -y

	printf -- 'PhantomJS install success \n'

	# Install yarn
	cd $GOPATH/src/github.com/grafana/grafana
	if [[ "$ID" == "rhel" ]]; then
		sudo env PATH=$PATH LD_LIBRARY_PATH=$LD_LIBRARY_PATH npm install -g yarn
	elif [[ "$DISTRO" == "sles-15.1" ]]; then
	    sudo sed -i'' -r 's/^( +, uidSupport = ).+$/\1false/' /usr/local/node-v${NODE_JS_VERSION}-linux-s390x/lib/node_modules/npm/node_modules/uid-number/uid-number.js
        sudo env PATH=$PATH npm install -g yarn
	else
		sudo env PATH=$PATH npm install -g yarn
	fi
	printf -- 'yarn install success \n'

	if [[ "$ID" == "ubuntu" ]]; then
	{
		if [[ "$DISTRO" == "ubuntu-16.04" || "$DISTRO" == "ubuntu-18.04" ]]; then
			sudo chmod +x ~/.npm
			sudo chmod +x ~/.config
		fi
		# export  QT_QPA_PLATFORM on Ubuntu
		export QT_QPA_PLATFORM=offscreen
	}
	fi

	# Build Grafana frontend assets
	make deps-js
	yarn run jest-ci -u 
	make build-js

	printf -- 'Grafana frontend assets build success \n'

	cd "${CURDIR}"

	# Move build artifacts to default directory
	if [ ! -d "/usr/local/share/grafana" ]; then
		printf -- "Created grafana Directory at /usr/local/share"
		sudo mkdir /usr/local/share/grafana
	fi

	sudo cp -r "$GOPATH/src/github.com/grafana/grafana"/* /usr/local/share/grafana
	#Give permission to user
	sudo chown -R "$USER" /usr/local/share/grafana/
	printf -- 'Move build artifacts success \n'

	#Add grafana config
	if [ ! -d "/etc/grafana" ]; then
		printf -- "Created grafana config Directory at /etc"
		sudo mkdir /etc/grafana/
	fi
	sudo cp /usr/local/share/grafana/conf/defaults.ini /etc/grafana/grafana.ini
	printf -- 'Add grafana config success \n'

	#Create alias
	echo "alias grafana-server='sudo grafana-server -homepath /usr/local/share/grafana -config /etc/grafana/grafana.ini'" >> ~/.bashrc

	# Run Tests
	runTest

	#Cleanup
	cleanup

	#Verify grafana installation
	if command -v "$PACKAGE_NAME-server" >/dev/null; then
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

		cd "$GOPATH/src/github.com/grafana/grafana"
		# Test backend
		make test-go

		# Test frontend
		make test-js
		printf -- "The above phantom js warnings are as expected, Please ignore the same. \n"
		printf -- "Tests completed. \n"

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
	echo "  build_grafana.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests]"
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
	printf -- "To run grafana , run the following command : \n"
	printf -- "    source ~/.bashrc  \n"
	printf -- "    grafana-server  &   (Run in background)  \n"
	printf -- "\nAccess grafana UI using the below link : "
	printf -- "http://<host-ip>:<port>/    [Default port = 3000] \n"
	printf -- "\n Default homepath: /usr/local/share/grafana \n"
	printf -- "\n Default config:  /etc/grafana/grafana.ini \n"
	printf -- '***************************************************************************************\n'
	printf -- '\n'
}

###############################################################################################################

ARGUMENTS=$*
shift $(( $OPTIND-1 ))
# Only run logDetails and prepare for main process
if [[ ! "$1" == "RHEL7" ]]; then
	logDetails
	prepare # Check Prequisites
fi

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04" | "ubuntu-19.10")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	sudo apt-get update
	sudo apt-get install -y python build-essential gcc tar wget git make unzip patch |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"rhel-7.6" | "rhel-7.7")
	#  Install the package with GCC >= 7
	if [[ "$1" == "RHEL7" ]]; then
		gcc --version
		LOG_FILE="$2"
        configureAndInstall |& tee -a "$LOG_FILE"
        exit 0
    fi
    #  Prepare and finish
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	sudo yum install -y make gcc tar wget git unzip scl-utils patch xz devtoolset-7 devtoolset-7-libatomic-devel.s390x|& tee -a "$LOG_FILE"
	echo "bash $0 $ARGUMENTS RHEL7 $LOG_FILE" | scl enable devtoolset-7 -
	;;

"rhel-8.0")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	sudo yum install -y make gcc tar wget git unzip scl-utils patch xz |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"sles-12.4" | "sles-15.1")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	sudo zypper install -y make gcc wget tar git unzip xz gzip curl patch |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "$LOG_FILE"
