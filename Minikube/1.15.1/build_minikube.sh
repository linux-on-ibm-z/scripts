#!/bin/bash
# © Copyright IBM Corporation 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Minikube/1.15.1/build_minikube.sh
# Execute build script: bash build_minikube.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="minikube"
PACKAGE_VERSION="1.15.1"

CURDIR="$(pwd)"
GO_INSTALL_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Go/1.15.3/build_go.sh"
FORCE="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
    mkdir -p "$CURDIR/logs/"
fi

if [ -f "/etc/os-release" ]; then
    source "/etc/os-release"
fi

function prepare() {
    
    if command -v "sudo" >/dev/null; then
        printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
    else
        printf -- 'Sudo : No \n' >>"$LOG_FILE"
        printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n'
        exit 1
    fi

    if command -v "docker" >/dev/null; then
        printf -- 'docker : Yes\n' >>"$LOG_FILE"
    else
        printf -- 'docker : No \n' >>"$LOG_FILE"
        printf -- 'Please install docker before proceeding with the script. \n'
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
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"
    
    #Download and install go
    curl -sSLO $GO_INSTALL_URL
    bash build_go.sh
    
    #build storage-provisioner-image
    git clone https://github.com/kubernetes/minikube.git
    cd minikube
    git checkout v$PACKAGE_VERSION
    make storage-provisioner-image
    
    export KUBERNETES_VERSION=`curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt`
    MINIKUBE_BINARY_URL=https://github.com/kubernetes/minikube/releases/download/v$PACKAGE_VERSION/minikube-linux-s390x
    KUBECTL_BINARY_URL=https://storage.googleapis.com/kubernetes-release/release/$KUBERNETES_VERSION/bin/linux/s390x/kubectl

    cd "$CURDIR"

    # Install minikube binary
    curl -LO $MINIKUBE_BINARY_URL && sudo install minikube-linux-s390x /usr/bin/minikube && rm -rf minikube-linux-s390x
    # Install kubectl binary
    curl -Lo kubectl $KUBECTL_BINARY_URL && chmod +x kubectl && sudo cp kubectl /usr/bin/ && rm kubectl

    printf -- "Build and install minikube success\n" >> "$LOG_FILE"

    #cleanup
    cleanup
}

function logDetails() {
    printf -- '**************************** SYSTEM DETAILS *************************************************************\n' >"$LOG           _FILE"
    if [ -f "/etc/os-release" ]; then
        cat "/etc/os-release" >>"$LOG_FILE"
    fi

    cat /proc/version >>"$LOG_FILE"
    printf -- '*********************************************************************************************************\n' >>"$LO           G_FILE"
    printf -- "Detected %s \n" "$PRETTY_NAME"
    printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" |& tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
    echo
    echo "Usage: "
    echo " build_minikube.sh  [-d debug] [-y install-without-confirmation]"
    echo
}

while getopts "h?dy" opt; do
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
    esac
done

function gettingStarted() {
    printf -- '\n********************************************************************************************************\n'
    printf -- "\n*Getting Started * \n"
    printf -- "Run following commands to get started: \n"
    printf -- "sudo systemctl daemon-reload   \n"
    printf -- "sudo systemctl restart docker   \n"
    printf -- 'export KUBERNETES_VERSION=`curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt`  \n'
    printf -- "export MINIKUBE_WANTUPDATENOTIFICATION=false   \n"
    printf -- "export MINIKUBE_WANTREPORTERRORPROMPT=false   \n"
    printf -- 'export MINIKUBE_HOME=$HOME   \n'
    printf -- "export CHANGE_MINIKUBE_NONE_USER=true   \n"
    printf -- "mkdir \$HOME/.kube   \n"
    printf -- "touch \$HOME/.kube/config   \n"
    printf -- 'export KUBECONFIG=$HOME/.kube/config   \n'
    printf -- 'sudo -E minikube start --vm-driver=none --kubernetes-version=$KUBERNETES_VERSION\n'
    printf -- '**********************************************************************************************************\n'
    printf -- "Note: If minikube fails to start execute 'setenforce 0' then retry.\n"
    printf -- '**********************************************************************************************************\n'
    printf -- "View the pods via the command: kubectl get pods --all-namespaces\n"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"ubuntu-18.04" | "ubuntu-20.04" | "ubuntu-20.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y wget curl conntrack git make |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-7.8" | "rhel-7.9" | "rhel-8.1" | "rhel-8.2" | "rhel-8.3" )
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y wget curl conntrack git make |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-12.5" | "sles-15.1" | "sles-15.2" )
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y wget curl conntrack-tools git make
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
