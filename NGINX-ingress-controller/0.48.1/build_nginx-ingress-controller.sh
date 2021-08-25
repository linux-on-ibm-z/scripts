#!/bin/bash
# © Copyright IBM Corporation 2021.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/NGINX-ingress-controller/0.48.1/build_nginx-ingress-controller.sh
# Execute build script: bash build_nginx-ingress-controller.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="nginx-ingress-controller"
PACKAGE_VERSION="v0.48.1"
SOURCE_ROOT="$(pwd)"
GO_DEFAULT="$HOME/go"

TESTS="false"
FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
GO_INSTALL_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Go/1.16.5/build_go.sh"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/NGINX-ingress-controller/0.48.1/patch"

trap cleanup 0 1 2 ERR

# Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
    mkdir -p "$SOURCE_ROOT/logs/"
fi

if [ -f "/etc/os-release" ]; then
    source "/etc/os-release"
fi

function prepare() {
    if command -v "sudo" >/dev/null; then
        printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
    else
        printf -- 'Sudo : No \n' >>"$LOG_FILE"
        printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n'
        exit 1
    fi

    printf -- "\nCheck if Docker is already present on the system . . . \n" | tee -a "$LOG_FILE"
    if [ -x "$(command -v docker)" ]; then
        docker --version | grep "Docker version" | tee -a "$LOG_FILE"
        echo "Docker exists !!" | tee -a "$LOG_FILE"
        docker ps 2>&1 | tee -a "$LOG_FILE"
    else
        printf -- "\n Please install docker !! \n" | tee -a "$LOG_FILE"
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
    rm -rf "$GOPATH/src/k8s.io/ingress-nginx/nginx_ingress_code_patch.diff"
    rm -rf "$GOPATH/src/k8s.io/ingress-nginx/7355.diff"
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

    # Install Go
    cd "$SOURCE_ROOT"
    wget $GO_INSTALL_URL 
    bash build_go.sh
    printf -- "Installed Go successfully.\n" >> "$LOG_FILE"
    

   	# Set GOPATH if not already set
	if [[ -z "${GOPATH}" ]]; then
		printf -- "\nSetting default value for GOPATH. \n"
		
        # Check if go directory exists
		if [ ! -d "$GO_DEFAULT" ]; then
			mkdir -p "$GO_DEFAULT"
		fi
		export GOPATH="$GO_DEFAULT"
        
	else
        printf -- "\nGOPATH already set : Value : %s \n" "$GOPATH"
        if [ ! -d "$GOPATH" ]; then
            mkdir -p "$GOPATH"
        fi
	fi

    # Download nginx-ingress-controller
    cd "$SOURCE_ROOT"
    mkdir -p "$GOPATH/src/k8s.io/"
    cd "$GOPATH/src/k8s.io/"
    git clone https://github.com/kubernetes/ingress-nginx.git
    cd ingress-nginx/
    git checkout controller-$PACKAGE_VERSION
    printf -- "Cloned nginx-ingress-controller successfully.\n"

    # Give permission to user
    sudo chown -R "$USER" "$GOPATH/src/k8s.io/ingress-nginx/"

    # Build NGINX Ingress Controller with the new image
    cd "$GOPATH/src/k8s.io/ingress-nginx/"
    # Add patches
    curl -o nginx_ingress_code_patch.diff $PATCH_URL/nginx_ingress_code_patch.diff
    git apply "$GOPATH/src/k8s.io/ingress-nginx/nginx_ingress_code_patch.diff"
    printf -- "Patched source code successfully.\n" 

    cd "$GOPATH/src/k8s.io/ingress-nginx/"
    wget https://patch-diff.githubusercontent.com/raw/kubernetes/ingress-nginx/pull/7355.diff
    git apply 7355.diff

    # Build nginx image for s390x
    cd "$GOPATH/src/k8s.io/ingress-nginx/images/nginx/"
    make build

    # Build test-runner image for s390x
    cd "$GOPATH/src/k8s.io/ingress-nginx/images/test-runner/"
    make build
    docker tag local/e2e-test-runner:"v$(date +%m%d%Y)-1de9a24b2" gcr.io/ingress-nginx/e2e-test-runner:$PACKAGE_VERSION

    # Build NGINX Ingress Controller with the new image
    cd "$GOPATH/src/k8s.io/ingress-nginx/"
    sudo make build image

    printf -- "Built and installed nginx-ingress-controller successfully\n" 

    # Run Test
    runTest

    # Cleanup
    cleanup

}

function runTest() {

    set +e
    if [[ "$TESTS" == "true" ]]; then
        printf -- 'Running tests \n\n' |& tee -a "$LOG_FILE"
        cd "$GOPATH/src/k8s.io/ingress-nginx/"
        sudo make test
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
    echo "  bash build_nginx-ingress-controller.sh  [-d debug] [-y install-without-confirmation] [-t run tests]"
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
    printf -- "\n * Getting Started * \n\n"
    printf -- "Deploying nginx-ingress-controller: \n\n"
    printf -- " cd \$GOPATH/src/k8s.io/ingress-nginx/ \n"
    printf -- " kubectl apply -f deploy/static/provider/baremetal/deploy.yaml \n\n"
    printf -- "* Verify installed version * \n\n"
    printf -- " POD_NAMESPACE=ingress-nginx\n"
    printf -- " POD_NAME=\$(kubectl get pods --all-namespaces | grep ingress-nginx-controller | awk '{print \$2}') \n"
    printf -- " kubectl exec -it \$POD_NAME -n \$POD_NAMESPACE -- /nginx-ingress-controller --version \n"
    printf -- '\n********************************************************************************************************\n'
}

logDetails
prepare # Check prerequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"ubuntu-18.04" | "ubuntu-20.04" | "ubuntu-21.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y curl git make |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-7.8" | "rhel-7.9" | "rhel-8.2" | "rhel-8.3" | "rhel-8.4")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y curl git make |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-12.5" | "sles-15.2" | "sles-15.3")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y curl git make |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
