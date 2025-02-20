#!/bin/bash
# © Copyright IBM Corporation 2025.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/NGINX-ingress-controller/1.12.0/build_nginx-ingress-controller.sh
# Execute build script: bash build_nginx-ingress-controller.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="nginx-ingress-controller"
PACKAGE_VERSION="1.12.0"
SOURCE_ROOT="$(pwd)"
GO_DEFAULT="$HOME/go"

TESTS="false"
FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/NGINX-ingress-controller/1.12.0/patch"
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
        sudo docker --version | grep "Docker version" | tee -a "$LOG_FILE"
        echo "Docker exists !!" | tee -a "$LOG_FILE"
        sudo docker ps 2>&1 | tee -a "$LOG_FILE"
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
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

    # Install Go
    cd "$SOURCE_ROOT"
    PRESERVE_ENVARS=~/.bash_profile
    wget https://go.dev/dl/go1.22.0.linux-s390x.tar.gz
    chmod ugo+r go1.22.0.linux-s390x.tar.gz
    sudo tar -C /usr/local -xzf go1.22.0.linux-s390x.tar.gz
    echo "export PATH=/usr/local/go/bin:$PATH" >> $PRESERVE_ENVARS
    export PATH=/usr/local/go/bin:$PATH
    echo "export GOPATH=$(go env GOPATH)" >> $PRESERVE_ENVARS

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
    export TAG=v1.12.0
    mkdir -p "$GOPATH/src/k8s.io/"
    cd "$GOPATH/src/k8s.io/"
    git clone -b controller-v$PACKAGE_VERSION https://github.com/kubernetes/ingress-nginx.git
    cd ingress-nginx/
    printf -- "Cloned nginx-ingress-controller successfully.\n"

    # Give permission to user
    sudo chown -R "$USER" "$GOPATH/src/k8s.io/ingress-nginx/"

    # Add patches
    cd "$GOPATH/src/k8s.io/ingress-nginx/"
    curl -o nginx_ingress_code_patch.diff $PATCH_URL/nginx_ingress_code_patch.diff
    git apply "$GOPATH/src/k8s.io/ingress-nginx/nginx_ingress_code_patch.diff"
    printf -- "Patched source code successfully.\n"

    # Build test-runner image for s390x
    cd "$GOPATH/src/k8s.io/ingress-nginx/images/test-runner/"
    sudo make build
    sudo docker tag local/e2e-test-runner:"v$(date +%Y%m%d)--8ee438427" gcr.io/ingress-nginx/e2e-test-runner:v$PACKAGE_VERSION

    # Build NGINX Ingress Controller image
    cd "$GOPATH/src/k8s.io/ingress-nginx/"
    if [[ "${ID}" == "sles" ]]; then
        sudo make build image PKG=k8s.io/ingress-nginx ARCH=s390x COMMIT_SHA=$(git rev-parse --short HEAD) REPO_INFO=$(git config --get remote.origin.url) TAG=v$PACKAGE_VERSION
    else
        sudo make build image
    fi
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
    echo "bash build_nginx-ingress-controller.sh  [-d debug] [-y install-without-confirmation] [-t run tests]"
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

function printSummary() {
    printf -- '\n***********************************************************************************************************************************\n'
    printf -- "\n* Getting Started * \n"
    printf -- '\n\nFor information on Getting started with NGINX-ingress-controller visit: \nhttps://github.com/kubernetes/ingress-nginx \n\n'
    printf -- '***********************************************************************************************************************************\n'
}

logDetails
# Check prerequisites
prepare

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"rhel-8.8" | "rhel-8.10" | "rhel-9.2" | "rhel-9.4" | "rhel-9.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y curl git make wget |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-15.6")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y curl git make which wget |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"ubuntu-20.04" | "ubuntu-22.04" | "ubuntu-24.04" | "ubuntu-24.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y curl git make wget |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

printSummary |& tee -a "$LOG_FILE"
