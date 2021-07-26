#!/bin/bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Minikube/0.30.0/build_minikube.sh
# Execute build script: bash build_minikube.sh    (provide -h for help)



set -e -o pipefail

PACKAGE_NAME="minikube"
PACKAGE_VERSION="0.30.0"

CURDIR="$(pwd)"
GO_DEFAULT="$HOME/go"

GO_INSTALL_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Go/1.11.4/build_go.sh"
CONF_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Minikube/0.30.0/patch"

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
    
    if  command -v "docker" > /dev/null ;
    then
        printf -- 'docker : Yes\n' >> "$LOG_FILE"
    else
        printf -- 'docker : No \n' >> "$LOG_FILE"
        printf -- 'Please install docker before proceeding with the script. \n';
    exit 1;
    fi;
   
    if [[ "$FORCE" == "true" ]] ;
    then
        printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
    else
        # Ask user for prerequisite installation
        printf -- "\nAs part of the installation , dependencies would be installed/upgraded.\n";
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
    rm -rf "${CURDIR}/Makefile.diff"
    rm -rf "${CURDIR}/addon-manager.yaml.diff"
    rm -rf "${CURDIR}/dashboard-dp.yaml.diff"
    rm -rf "${CURDIR}/heapster-rc.yaml.diff" 
    rm -rf "${CURDIR}/kube-dns-controller.yaml.diff" 
    rm -rf "${CURDIR}/storage-provisioner.yaml.diff" 
    rm -rf "${CURDIR}/constants.go.diff" 
    rm -rf "${CURDIR}/Dockerfile.diff" 
    rm -rf "${CURDIR}/build_docker.sh" 
    

    printf -- "Cleaned up the artifacts\n" >> "$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"
    
    cd "$CURDIR"

    if [[ "$ID" == "sles" ]]; then
	 # Install go
	 printf -- "Installing Go... \n" 
	 # wget  $GO_INSTALL_URL 
     curl -o "build_go.sh"  "$GO_INSTALL_URL"
     bash build_go.sh 
     printf -- "install Go success\n" >> "$LOG_FILE"
	fi
   
    cd "$CURDIR"

	# Set GOPATH if not already set
	if [[ -z "${GOPATH}" ]]; then
		printf -- "Setting default value for GOPATH \n"

		#Check if go directory exists
		if [ ! -d "$HOME/go" ]; then
			mkdir "$HOME/go"
		fi
		
		export GOPATH="${GO_DEFAULT}"
		
        #Check if bin directory exists
		if [ ! -d "$GOPATH/bin" ]; then
			mkdir "$GOPATH/bin"
		fi
		export PATH=$PATH:$GOPATH/bin
	else
		printf -- "GOPATH already set : Value : %s \n" "$GOPATH" 
	fi
	printenv >>"$LOG_FILE"

      
    # clone minikube 
    git clone -b v"$PACKAGE_VERSION" https://github.com/kubernetes/minikube.git "$GOPATH/src/k8s.io/minikube"
	
    #Give permission to user
	sudo chown -R "$USER" "$GOPATH/src/k8s.io/minikube"

    cd "$CURDIR"

    #Add patches
	curl -o "Makefile.diff"  "$CONF_URL/Makefile.diff"
	patch "$GOPATH/src/k8s.io/minikube/Makefile" Makefile.diff
	printf -- 'Updated Makefile : success\n' 

    curl -o "addon-manager.yaml.diff"  "$CONF_URL/addon-manager.yaml.diff"
	patch "$GOPATH/src/k8s.io/minikube/deploy/addons/addon-manager.yaml" addon-manager.yaml.diff
	printf -- 'Updated addon-manager.yaml : success\n' 
        
    curl -o "dashboard-dp.yaml.diff"  "$CONF_URL/dashboard-dp.yaml.diff"
	patch "$GOPATH/src/k8s.io/minikube/deploy/addons/dashboard/dashboard-dp.yaml" dashboard-dp.yaml.diff
	printf -- 'Updated dashboard-dp.yaml : success\n' 

	curl -o "heapster-rc.yaml.diff"  "$CONF_URL/heapster-rc.yaml.diff"
	patch "$GOPATH/src/k8s.io/minikube/deploy/addons/heapster/heapster-rc.yaml" heapster-rc.yaml.diff
	printf -- 'Updated heapster-rc.yaml : success\n' 

	curl -o "kube-dns-controller.yaml.diff"  "$CONF_URL/kube-dns-controller.yaml.diff"
	patch "$GOPATH/src/k8s.io/minikube/deploy/addons/kube-dns/kube-dns-controller.yaml" kube-dns-controller.yaml.diff
	printf -- 'Updated kube-dns-controller.yaml : success\n' 

	curl -o "storage-provisioner.yaml.diff"  "$CONF_URL/storage-provisioner.yaml.diff"
	patch "$GOPATH/src/k8s.io/minikube/deploy/addons/storage-provisioner/storage-provisioner.yaml" storage-provisioner.yaml.diff
	printf -- 'Updated storage-provisioner.yaml : success\n' 
    
    curl -o "constants.go.diff"  "$CONF_URL/constants.go.diff"
	patch "$GOPATH/src/k8s.io/minikube/pkg/minikube/constants/constants.go" constants.go.diff
	printf -- 'Updated constants.go : success\n' 

    curl -o "Dockerfile.diff"  "$CONF_URL/Dockerfile.diff"
	patch "$GOPATH/src/k8s.io/minikube/deploy/storage-provisioner/Dockerfile" Dockerfile.diff
	printf -- 'Updated Dockerfile : success\n' 


    cd "$GOPATH/src/k8s.io/minikube"
    make out/minikube-linux-s390x
    #Add minikube to /usr/bin
    sudo cp ./out/minikube-linux-s390x /usr/bin/minikube

    #Adding dependencies to path 
	echo "export PATH=/usr/lib/go-1.10/bin:\$PATH " >> ~/.bashrc

    printf -- "Build and install minikube success\n" >> "$LOG_FILE"

    # Run Tests
	runTest

    #cleanup
    cleanup
  
}

function runTest() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- "TEST Flag is set, continue with running test \n"  >> "$LOG_FILE"
		cd "$GOPATH/src/k8s.io/minikube"
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
    echo " build_minikube.sh  [-d debug] [-y install-without-confirmation] [-t install and run tests]"
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
    printf -- "Run following commands to get started: \n"
    printf -- "export PATH=/usr/lib/go-1.10/bin:\$PATH \n"
    printf -- "or Restart the terminal to reflect changes\n\n"
    
    printf -- "Start docker:   \n"
    printf -- "systemctl daemon-reload   \n"
    printf -- "systemctl restart docker   \n"

    printf -- "Command to use: \n"
    printf -- "minikube start \n"
    printf -- "You have successfully started minikube.\n"
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
        sudo apt-get install -y tar wget gcc git make python golang-1.10 curl patch |& tee -a "$LOG_FILE"
        export PATH=/usr/lib/go-1.10/bin:$PATH
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;
    "rhel-7.4" | "rhel-7.5" | "rhel-7.6")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo yum install -y tar wget gcc git make python golang curl patch |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;
    "sles-12.4" | "sles-15")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo zypper install -y  tar wget gcc git make python curl patch |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;
    *)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
        exit 1
        ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
