#!/bin/bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Kubernetes/build_kubernetes.sh
# Execute build script: bash build_kubernetes.sh    (provide -h for help)



set -e -o pipefail

PACKAGE_NAME="kubernetes"
PACKAGE_VERSION="1.5.7"
CURDIR="$(pwd)"
GO_DEFAULT="$HOME/go"
BUILD_DIR="/usr/local"

GO_INSTALL_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Go/build_go.sh"

FORCE="false"
TESTS="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
   mkdir -p "$CURDIR/logs/"
fi

# Need handling for RHEL 6.10 as it doesn't have os-release file
if [ -f "/etc/os-release" ]; then
    source "/etc/os-release"
else
    cat /etc/redhat-release >> "${LOG_FILE}"
    export ID="rhel"
    export VERSION_ID="6.x"
    export PRETTY_NAME="Red Hat Enterprise Linux 6.x"
fi


function prepare() {
    if  command -v "sudo" > /dev/null ;
    then
        printf -- 'Sudo : Yes\n' >> "$LOG_FILE"
    else
        printf -- 'Sudo : No \n' >> "$LOG_FILE"
        printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n';
    exit 1;
    fi;
   
    if [[ "$FORCE" == "true" ]] ;
    then
        printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
    else
        # Ask user for prerequisite installation
        printf -- "\nAs part of the installation , Go 1.7.1 will be installed, \n";
        while true; do
		    read -r -p "Do you want to continue (y/n) ? :  " yn
		    case $yn in
  	 		    [Yy]* ) printf -- 'User responded with Yes. \n' >> "$LOG_FILE"; 
	                    break;;
    		    [Nn]* ) exit;;
    		    *) 	echo "Please provide confirmation to proceed.";;
	 	    esac
        done
    fi	
}


function cleanup() {
    # Remove artifacts
   

    printf -- "Cleaned up the artifacts\n" >> "$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

   #Install Docker for RHEL
   if [[ "$ID-$VERSION_ID" == "rhel-7.3" ]]; then
	printf -- "Download docker for rhel-7.3  \n"
    cd "$BUILD_DIR"
    sudo wget ftp://ftp.unicamp.br/pub/linuxpatch/s390x/redhat/rhel7.3/docker-17.05.0-ce-rhel7.3-20170523.tar.gz
    sudo tar xzvf docker-17.05.0-ce-rhel7.3-20170523.tar.gz
    cd  docker-17.05.0-ce-rhel7.3-20170523
    sudo cp docker /usr/bin/

    fi
   
   
   #Install Go
   cd "$BUILD_DIR"
   
    wget  $GO_INSTALL_URL 
    bash build_go.sh -v 1.7.1

  	# Set GOPATH if not already set
	if [[ -z "${GOPATH}" ]]; then
		printf -- "Setting default value for GOPATH \n"

		
        #Check if go directory exists
		if [ ! -d "$GO_DEFAULT" ]; then
			sudo mkdir -p "$GO_DEFAULT"
		fi
		export GOPATH="$GO_DEFAULT/kubernetes"
        #Check if bin directory exists
		if [ ! -d "$GOPATH/bin" ]; then
			sudo mkdir -p "$GOPATH/bin"
		fi
        export PATH=$PATH:$GOPATH/bin:$GOPATH/_output/local/go/bin
        export PATH=$PATH:/usr/local/go/bin
	else
		printf -- "GOPATH already set : Value : %s \n" "$GOPATH" 
	fi
	printenv >>"$LOG_FILE"

    # Clone the source code and replace sys package
    #Check if kubernetes directory exists
		if [ -d "$GOPATH" ]; then
			sudo rm -rf "$GOPATH"
		fi

    cd $CURDIR
    git clone -b v"${PACKAGE_VERSION}" https://github.com/kubernetes/kubernetes.git
    sudo chmod -Rf 755 kubernetes
    sudo cp -Rf kubernetes "$GOPATH"

    printf -- 'Download source code success \n'  >> "$LOG_FILE"

     #Give permission to user
	sudo chown -R "$USER" "$GOPATH"
    sudo chown -R "$USER" /usr/local/go/
    
    cd "$GOPATH"/vendor/golang.org/x
    mv sys sys.bak
    git clone https://github.com/linux-on-ibm-z/sys.git

    printf -- 'replace sys package success \n'  >> "$LOG_FILE"

    # Build Kubernetes
    cd "$GOPATH"
    
    # fixes to prevent build errors
    mkdir -p _output/bin
    touch _output/bin/deepcopy-gen
    touch _output/bin/conversion-gen
    touch _output/bin/defaulter-gen
    touch _output/bin/openapi-gen
    chmod u=rwx _output/bin/deepcopy-gen
    chmod u=rwx _output/bin/conversion-gen
    chmod u=rwx _output/bin/defaulter-gen
    chmod u=rwx _output/bin/openapi-gen

    make
    
    printf -- 'build Kubernetes success \n'  >> "$LOG_FILE"
    


echo "export ETCD_UNSUPPORTED_ARCH=s390x" >> ~/.bashrc
echo "export KUBE_ENABLE_CLUSTER_DNS=true" >> ~/.bashrc
echo "export PATH=\$PATH:$GOPATH/_output/local/go/bin" >> ~/.bashrc

   
    # Run Tests
	runTest

    #cleanup
    cleanup

    #Verify kubernetes installation
    if command -v kubectl > /dev/null; then 
        printf -- " %s Installation verified.\n" "$PACKAGE_NAME" 
    else
        printf -- "Error while installing %s, exiting with 127 \n" "$PACKAGE_NAME";
        exit 127;
    fi

}

function runTest() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- "TEST Flag is set, continue with running test \n"  >> "$LOG_FILE"
		cd "$GOPATH"
        make test
        printf -- "Tests completed. \n" 
	fi
	set -e
}

function logDetails() {
    printf -- '**************************** SYSTEM DETAILS *************************************************************\n' >"$LOG_FILE"
    if [ -f "/etc/os-release" ]; then
        cat "/etc/os-release" >> "$LOG_FILE"
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
    echo " build_kubernetes.sh  [-d debug] [-y install-without-confirmation] [-t install and run tests]"
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
    printf -- "\n*Getting Started * \n"
    printf -- "Running kubernetes: \n"
    printf -- "source ~/.bashrc \n"
    printf -- "kubectl version \n"
    printf -- "You have successfully started kubernetes.\n"
    printf -- '**********************************************************************************************************\n'
}
    
logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
    "ubuntu-16.04" | "ubuntu-18.04")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo apt-get update
        sudo apt-get install -y git make iptables gcc wget tar flex subversion binutils-dev bzip2 build-essential vim docker curl |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;
    "rhel-7.3")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo yum install -y install git gcc-c++ which iptables make curl wget  |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;
    "sles-12.3" | "sles-15")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo zypper install -y  git gcc-c++ which iptables make docker curl wget  |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;
    *)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
        exit 1
        ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
