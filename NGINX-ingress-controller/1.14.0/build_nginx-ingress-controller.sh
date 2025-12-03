#!/bin/bash
# © Copyright IBM Corporation 2025.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/NGINX-ingress-controller/1.14.0/build_nginx-ingress-controller.sh
# Execute build script: bash build_nginx-ingress-controller.sh    (provide -h for help)
USER_IN_GROUP_DOCKER=$(id -nGz "$USER" | tr '\0' '\n' | grep -c '^docker$')
set -e -o pipefail

PACKAGE_NAME="nginx-ingress-controller"
PACKAGE_VERSION="1.14.0"
SOURCE_ROOT="$(pwd)"
GO_VERSION="1.25.3"
NGINX_VERSION="2.2.4"
TESTRUNNER_VERSION="2.2.4"

TESTS="false"
FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/NGINX-ingress-controller/1.14.0/patch"
BUILD_ENV="$HOME/setenv.sh"

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

    if command -v "docker" >/dev/null; then
        printf -- 'Docker : Yes\n' >>"$LOG_FILE"
    else
        printf -- 'Docker : No \n' >>"$LOG_FILE"
        printf -- 'Please install Docker based on your distro. \n'
        exit 1
    fi

    if [[ "$USER_IN_GROUP_DOCKER" == "1" ]]; then
        printf "User %s belongs to group docker\n" "$USER" |& tee -a "${LOG_FILE}"
    else
        printf "Please ensure User %s belongs to group docker.\n" "$USER" |& tee -a "${LOG_FILE}"
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
    rm -f "${SOURCE_ROOT}/go${GO_VERSION}.linux-s390x.tar.gz"
    docker container stop registry > /dev/null 2>&1 || true
    docker container rm -v registry > /dev/null 2>&1 || true
    docker buildx rm ingress-nginx > /dev/null 2>&1 || true
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

    # Install Go
    cd "$SOURCE_ROOT"
    wget -q https://go.dev/dl/go${GO_VERSION}.linux-s390x.tar.gz
    chmod ugo+r go${GO_VERSION}.linux-s390x.tar.gz
    sudo tar -C /usr/local -xzf go${GO_VERSION}.linux-s390x.tar.gz
    export PATH=/usr/local/go/bin:$PATH
    echo "export PATH=$PATH" >> "$BUILD_ENV"
    : "${GOPATH:=$(go env GOPATH)}"
    export GOPATH
    echo "export GOPATH=$GOPATH" >> "$BUILD_ENV"

    # Download nginx-ingress-controller
    cd "$SOURCE_ROOT"
    mkdir -p "$GOPATH/src/k8s.io/"
    cd "$GOPATH/src/k8s.io/"
    git clone -b controller-v$PACKAGE_VERSION https://github.com/kubernetes/ingress-nginx.git
    cd ingress-nginx/
    printf -- "Cloned nginx-ingress-controller successfully.\n"

    # Add patches
    cd "$GOPATH/src/k8s.io/ingress-nginx/"
    curl -sSL "${PATCH_URL}/nginx_ingress_code_patch.diff" | git apply -
    I_N_BUILDER_CONFIG="$GOPATH/src/k8s.io/ingress-nginx/buildx-config.toml"
    cat << EOF > "${I_N_BUILDER_CONFIG}"
[registry."localhost:5000"]
http = true
insecure = true
EOF
    printf -- "Patched source code successfully.\n"

    # Start local docker registry
    docker run -d -p 5000:5000 --restart always --name registry registry:2

    # Build nginx image for s390x
    cd "$GOPATH/src/k8s.io/ingress-nginx/images/nginx/"
    make PLATFORMS="linux/s390x" REGISTRY="localhost:5000" I_N_BUILDER_CONFIG="${I_N_BUILDER_CONFIG}" push
    
    # Build test-runner image for s390x
    cd "$GOPATH/src/k8s.io/ingress-nginx/images/test-runner/"
    make PLATFORMS="linux/s390x" REGISTRY="localhost:5000" BASE_IMAGE="localhost:5000/nginx:v${NGINX_VERSION}" I_N_BUILDER_CONFIG="${I_N_BUILDER_CONFIG}" push

    # Build NGINX Ingress Controller image
    cd "$GOPATH/src/k8s.io/ingress-nginx/"
    make BASE_IMAGE="localhost:5000/nginx:v${NGINX_VERSION}" build image
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
        make E2E_IMAGE="localhost:5000/e2e-test-runner:v${TESTRUNNER_VERSION}" test
        make E2E_IMAGE="localhost:5000/e2e-test-runner:v${TESTRUNNER_VERSION}" lua-test
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
"rhel-8.10" | "rhel-9.4" | "rhel-9.6")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y --allowerasing curl git make wget |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-15.6" | "sles-15.7")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y curl git make which wget |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"ubuntu-22.04" | "ubuntu-24.04" | "ubuntu-25.04" )
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
