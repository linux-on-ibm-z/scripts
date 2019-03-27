#!/bin/bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/NGINX-ingress-controller/0.20.0/build_nginx-ingress-controller.sh
# Execute build script: bash build_nginx-ingress-controller.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="nginx-ingress-controller"
PACKAGE_VERSION="0.20.0"
CURDIR="$(pwd)"
BUILD_DIR="/usr/local"
GO_DEFAULT="$HOME/go"

TESTS="false"
FORCE="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
GO_INSTALL_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Go/build_go.sh"
REPO_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/NGINX-ingress-controller/0.20.0/patch"


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

    # rm "$CURDIR/default-backend.yaml.diff"
    # rm "$CURDIR/Dockerfile.diff"
    # rm "$CURDIR/go-in-docker.sh.diff"
    # rm "$CURDIR/test.sh.diff"
    # rm "$CURDIR/with-rbac.yaml.diff"
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"


    if [[ "$ID" == "rhel" || "$ID" == "sles"  ]]; then

        #Install Go
        cd "$CURDIR"
        wget  $GO_INSTALL_URL 
        bash build_go.sh -v $GO_VERSION
        printf -- "Install go success\n" >> "$LOG_FILE"
    
    fi

   	# Set GOPATH if not already set
	if [[ -z "${GOPATH}" ]]; then
		printf -- "Setting default value for GOPATH \n"
		
        #Check if go directory exists
		if [ ! -d "$GO_DEFAULT" ]; then
			mkdir -p "$GO_DEFAULT"
		fi
		export GOPATH="$GO_DEFAULT"
        
	else
        export GOPATH="$GOPATH"
		printf -- "GOPATH already set : Value : %s \n" "$GOPATH" 
	fi

    #Download nginx-ingress-controller
    cd "$CURDIR"
    export DOCKER=docker
    mkdir -p $GOPATH/src/k8s.io/
    cd $GOPATH/src/k8s.io/
    git clone -b "nginx-${PACKAGE_VERSION}" https://github.com/kubernetes/ingress-nginx.git
    printf -- "Download nginx-ingress-controller success\n"

    #Give permission to user
    sudo chown -R "$USER" "$GOPATH/src/k8s.io/ingress-nginx/"

    #Build NGINX Ingress Controller with the new image
    
    cd "$CURDIR"
    # Add patches
    curl -o Dockerfile.diff $REPO_URL/Dockerfile.diff
	patch "$GOPATH/src/k8s.io/ingress-nginx/images/e2e/Dockerfile" Dockerfile.diff
    printf -- "Patch Dockerfile success\n" 

    #Build e2e image for s390x
    cd "$GOPATH/src/k8s.io/ingress-nginx/images/e2e/"
    make docker-build

    cd "$CURDIR"
    # Add patches
    curl -o go-in-docker.sh.diff $REPO_URL/go-in-docker.sh.diff
	patch "$GOPATH/src/k8s.io/ingress-nginx/build/go-in-docker.sh" go-in-docker.sh.diff
    printf -- "Patch go-in-docker.sh success\n" 


    #Build NGINX Ingress Controller with the new image
    cd "$GOPATH/src/k8s.io/ingress-nginx/"
    make build ARCH=s390x

    cd "$CURDIR"
    # patch for deployment
    curl -o default-backend.yaml.diff $REPO_URL/default-backend.yaml.diff
	patch "$GOPATH/src/k8s.io/ingress-nginx/deploy/default-backend.yaml" default-backend.yaml.diff
    printf -- "Patch default-backend.yaml success\n" 
    
    curl -o with-rbac.yaml.diff $REPO_URL/with-rbac.yaml.diff
	patch "$GOPATH/src/k8s.io/ingress-nginx/deploy/with-rbac.yaml" with-rbac.yaml.diff
    printf -- "Patch with-rbac.yaml success\n" 

    printf -- "Build and install nginx-ingress-controller success\n" 

    #Run Test
    runTest

    #cleanup
    cleanup

}

function runTest() {

    set +e
    if [[ "$TESTS" == "true" ]]; then
        printf -- 'Running tests \n\n' |& tee -a "$LOG_FILE"
          cd $GOPATH/src/k8s.io/ingress-nginx/
      # Add patches
        curl -o test.sh.diff $REPO_URL/test.sh.diff
        patch "$GOPATH/src/k8s.io/ingress-nginx/build/test.sh" test.sh.diff
        printf -- "Patch test.sh success\n" 
        make test ARCH=s390x
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
    echo " build_nginx-ingress-controller.sh  [-d debug] [-y install-without-confirmation] [-t install and run tests]"
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
    printf -- "Running nginx-ingress-controller: \n"
    printf -- " cd \$GOPATH/src/k8s.io/ingress-nginx/deploy/ \n\n"
    printf -- " kubectl apply -f namespace.yaml \n"
    printf -- " kubectl apply -f default-backend.yaml \n"
    printf -- " kubectl apply -f configmap.yaml \n"
    printf -- " kubectl apply -f tcp-services-configmap.yaml \n"
    printf -- " kubectl apply -f udp-services-configmap.yaml \n"
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
    sudo apt-get install -y git make golang-1.10 curl patch  |& tee -a "$LOG_FILE"
    export PATH=/usr/lib/go-1.10/bin:$PATH 
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-7.3" | "rhel-7.4" | "rhel-7.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y git make curl patch  |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-12.3" | "sles-15")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y git make curl patch |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
