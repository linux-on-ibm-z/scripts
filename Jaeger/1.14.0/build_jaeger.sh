#!/bin/bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Jaeger/1.14.0/build_jaeger.sh
# Execute build script: bash build_jaeger.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="jaeger"
PACKAGE_VERSION="1.14.0"
CURDIR="$(pwd)"

FORCE="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
CONF_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Jaeger/1.14.0/patch"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
    mkdir -p "$CURDIR/logs/"
fi

# Set the Distro ID
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
    # Remove artifacts
	sudo rm -rf "$GOPATH/src/github.com/jaegertracing/jaeger/status_linux.go.diff"
	sudo rm -rf "$CURDIR/go1.11.4.linux-s390x.tar.gz"
	sudo rm -rf "$CURDIR/node-v8.16.0-linux-s390x.tar.gz"
    	printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function configureAndInstall() {
    	printf -- "Configuration and Installation started \n"

	#Build GO
	cd $CURDIR
	wget https://dl.google.com/go/go1.11.4.linux-s390x.tar.gz
	chmod ugo+r go1.11.4.linux-s390x.tar.gz
	sudo tar -C /usr/local -xzf go1.11.4.linux-s390x.tar.gz
	export PATH=$PATH:/usr/local/go/bin
    
	if [ "$ID" != "ubuntu" ]; then
        sudo ln /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc       
    	fi
	
	#Install Nodejs
	cd $CURDIR
	wget https://nodejs.org/dist/v8.16.0/node-v8.16.0-linux-s390x.tar.gz
	tar -xvf node-v8.16.0-linux-s390x.tar.gz
	export PATH=$CURDIR/node-v8.16.0-linux-s390x/bin:$PATH
     
	#Install Yarn
	npm install -g yarn
	
	
	#Set Environment Variable
	cd $CURDIR
  export GOPATH=$CURDIR
  export PATH=$GOPATH/bin:$PATH        

  #Clone Jaeger source and get Jaeger modules
	cd $CURDIR
	mkdir -p $GOPATH/src/github.com/jaegertracing
    	cd $GOPATH/src/github.com/jaegertracing
    	git clone https://github.com/jaegertracing/jaeger.git
    	cd jaeger/
    	git checkout v1.14.0
    	git submodule update --init --recursive
	
	#Install build tools
	go get -d -u github.com/golang/dep
    	cd $GOPATH/src/github.com/golang/dep
    	DEP_LATEST=$(git describe --abbrev=0 --tags)
    	git checkout $DEP_LATEST
    	go install -ldflags="-X main.version=$DEP_LATEST" ./cmd/dep
    	cd $GOPATH/src/github.com/jaegertracing/jaeger/
    	make install-ci     
	
	# Make changes to plugin/storage/badger/stats_linux.go
	sudo curl -o "status_linux.go.diff"  $CONF_URL/status_linux.go.diff
	sudo patch -l plugin/storage/badger/stats_linux.go status_linux.go.diff
	printf -- 'Updated plugin/storage/badger/stats_linux.go \n'
	
	#Build Jaeger
	make build-all-in-one-linux
	printf -- 'Jaeger build completed successfully. \n'
	
	# Run Tests
    	runTest |& tee -a "$LOG_FILE"
}

function runTest() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- "TEST Flag is set, continue with running test \n"  >> "$LOG_FILE"
		cd ${GOPATH}/src/github.com/jaegertracing/jaeger
		sed -i '26d' Makefile
		sed -i '26i RACE=' Makefile
        	make test 
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
    echo " build_jaeger.sh  [-d debug] [-y install-without-confirmation] "
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
    	printf -- "*                     Getting Started                 * \n"
    	printf -- "           You have successfully installed Jaeger. \n"
	printf -- "         To Run Jaeger run the following commands :\n"
	printf -- "         export GOPATH=$CURDIR \n"
	printf -- "         export PATH=\"\${PATH}:${CURDIR}/bin:${CURDIR}/node-v8.16.0-linux-s390x/bin:/usr/local/go/bin\" \n"
	printf -- "         For Ubuntu only: export QT_QPA_PLATFORM=offscreen \n"		    
	printf -- "         cd $CURDIR/src/github.com/jaegertracing/jaeger \n"           
    	printf -- "         go run -tags ui ./cmd\/all-in-one/main.go & \n"
    	printf -- '**********************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04" | "ubuntu-19.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y git make wget python tar gcc |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-7.5" | "rhel-7.6" | "rhel-7.7")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y git make wget python tar gcc which |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-8.0")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y git make wget python2 tar gcc which |& tee -a "$LOG_FILE"
    sudo ln -s /usr/bin/python2 /usr/bin/python
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-12.4" | "sles-15" | "sles-15.1")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y git make wget python tar gcc which gzip |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
