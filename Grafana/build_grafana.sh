#!/bin/bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Grafana/build_grafana.sh
# Execute build script: bash build_grafana.sh    (provide -h for help)


set -e -o pipefail

PACKAGE_NAME="grafana"
PACKAGE_VERSION="5.4.3"
CURDIR="$(pwd)"

GO_INSTALL_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Go/build_go.sh"
PHANTOMJS_INSTALL_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/PhantomJS/build_phantomjs.sh"
GRAFANA_CONFIG_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Grafana/conf/grafana.ini"


GO_DEFAULT="$HOME/go"


FORCE="false"
TESTS="false"
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
BUILD_DIR="/usr/local"

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
		printf -- 'Force attribute provided hence continuing with install without confirmation message' |& tee -a "$LOG_FILE"
	else
		# Ask user for prerequisite installation
		printf -- "\n\nAs part of the installation , Go 1.10.4 and PhantomJS 2.1.1 will be installed, \n"
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

	if [ -f /usr/local/node-v8.15.0-linux-s390x/bin/yarn ]; then
		sudo rm /usr/local/node-v8.15.0-linux-s390x/bin/yarn
	fi

	if [ -f "$BUILD_DIR/node-v8.15.0-linux-s390x.tar.xz" ]; then
		sudo rm "$BUILD_DIR/node-v8.15.0-linux-s390x.tar.xz"
	fi

	printf -- 'Cleaned up the artifacts\n' >>"$LOG_FILE"
}

function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'

	# Install grafana
	printf -- "\nInstalling %s..... \n" "$PACKAGE_NAME"

	# Grafana installation

	#Install NodeJS
	cd "$BUILD_DIR"
	sudo wget https://nodejs.org/dist/v8.15.0/node-v8.15.0-linux-s390x.tar.xz
	sudo chmod ugo+r node-v8.15.0-linux-s390x.tar.xz
	sudo tar -C "$BUILD_DIR" -xf node-v8.15.0-linux-s390x.tar.xz
	export PATH=$PATH:/usr/local/node-v8.15.0-linux-s390x/bin

	printf -- 'Install NodeJS success \n' 

	cd "${CURDIR}"

	# Install go
	printf -- "Installing Go... \n" 
	curl $GO_INSTALL_URL | sudo bash

	# Set GOPATH if not already set
	if [[ -z "${GOPATH}" ]]; then
		printf -- "Setting default value for GOPATH \n"

		#Check if go directory exists
		if [ ! -d "$HOME/go" ]; then
			sudo mkdir "$HOME/go"
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
		sudo mkdir -p "$GOPATH/src/github.com/grafana"
		printf -- "Created grafana Directory at GOPATH"
	fi

	cd "$GOPATH/src/github.com/grafana"
	if [ -d "$GOPATH/src/github.com/grafana/grafana" ]; then
		sudo rm -rf "$GOPATH/src/github.com/grafana/grafana"
		printf -- "Removing Existing grafana Directory at GOPATH"
	fi
	#Give permission
	sudo chown -R "$USER" "$GOPATH/src/github.com/grafana/"

	git clone  -b v"${PACKAGE_VERSION}" https://github.com/grafana/grafana.git

	printf -- "Created grafana Directory at 1"
	#Give permission
	sudo chown -R "$USER" "$GOPATH/src/github.com/grafana/grafana/" "$GOPATH/src/github.com/" "$GOPATH/"
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

	# Install PhantomJS
	printf -- "Installing PhantomJS... \n" 

	sudo curl  -o "phantom_setup.sh"  $PHANTOMJS_INSTALL_URL  
	bash phantom_setup.sh -y

	printf -- 'PhantomJS install success \n' 

	# Install yarn
	cd $GOPATH/src/github.com/grafana/grafana
	sudo env PATH=$PATH npm install -g yarn
	printf -- 'yarn install success \n'
	
	if [[ "$ID" == "ubuntu" ]]; then
		sudo chown -R $USER:$GROUP ~/.npm
		sudo chown -R $USER:$GROUP ~/.config
		# export  QT_QPA_PLATFORM on Ubuntu
		export QT_QPA_PLATFORM=offscreen
	fi	

	# Build Grafana frontend assets
	make deps-js
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
	sudo curl  -o "grafana.ini"  $GRAFANA_CONFIG_URL
	sudo cp grafana.ini /etc/grafana/
	printf -- 'Add grafana config success \n'

	#Create alias
	echo "alias grafana-server='grafana-server -homepath /usr/local/share/grafana -config /etc/grafana/grafana.ini'" >> ~/.bashrc

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
	printf -- "\n Default config: /etc/grafana/grafana.ini \n"
	printf -- '***************************************************************************************\n'
	printf -- '\n'
}

###############################################################################################################

logDetails
prepare #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	sudo apt-get  update
	sudo apt-get install -y  python build-essential gcc tar wget git make unzip curl |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"rhel-7.4" | "rhel-7.5" | "rhel-7.6")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	sudo yum install -y  make gcc tar wget git unzip curl  |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"sles-12.3" | "sles-15")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	sudo zypper install -y make gcc wget tar git unzip curl  |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "$LOG_FILE"
