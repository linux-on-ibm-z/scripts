#!/bin/bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Minikube/1.2.0/build_minikube.sh
# Execute build script: bash build_minikube.sh    (provide -h for help)



set -e -o pipefail

PACKAGE_NAME="minikube"
PACKAGE_VERSION="1.2.0"

CURDIR="$(pwd)"
GO_DEFAULT="$HOME/go"

GO_INSTALL_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Go/1.12.5/build_go.sh"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Minikube/1.2.0/patch"

FORCE="false"
TESTS="false"
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
                    *)  echo "Please provide confirmation to proceed.";;
                    esac
        done
    fi
}


function cleanup() {
    # Remove artifacts
    rm -rf "${CURDIR}/Makefile.diff"
    rm -rf "${CURDIR}/addon-manager.yaml.tmpl.diff"
    rm -rf "${CURDIR}/storage-provisioner.yaml.tmpl.diff"
    rm -rf "${CURDIR}/Dockerfile.diff"
    printf -- "Cleaned up the artifacts\n" >> "$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

    cd "$CURDIR"
         # Install go
         printf -- "Installing Go... \n"
         # wget  $GO_INSTALL_URL
     curl -o "build_go.sh"  "$GO_INSTALL_URL"
     bash build_go.sh
     printf -- "install Go success\n" >> "$LOG_FILE"

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
    curl -o "Makefile.diff"  "$PATCH_URL/Makefile.diff"
        patch "$GOPATH/src/k8s.io/minikube/Makefile" Makefile.diff
        printf -- 'Updated Makefile : success\n'
        
    curl -o "addon-manager.yaml.tmpl.diff"  "$PATCH_URL/addon-manager.yaml.tmpl.diff"
        patch "$GOPATH/src/k8s.io/minikube/deploy/addons/addon-manager.yaml.tmpl" addon-manager.yaml.tmpl.diff
        printf -- 'Updated addon-manager.yaml : success\n'

    curl -o "storage-provisioner.yaml.tmpl.diff"  "$PATCH_URL/storage-provisioner.yaml.tmpl.diff"
        patch "$GOPATH/src/k8s.io/minikube/deploy/addons/storage-provisioner/storage-provisioner.yaml.tmpl" storage-provisioner.yaml.tmpl.diff
        printf -- 'Updated storage-provisioner.yaml.tmpl : success\n'

    curl -o "Dockerfile.diff"  "$PATCH_URL/Dockerfile.diff"
        patch "$GOPATH/src/k8s.io/minikube/deploy/storage-provisioner/Dockerfile" Dockerfile.diff
        printf -- 'Updated Dockerfile : success\n'


    cd "$GOPATH/src/k8s.io/minikube"
    make out/minikube-linux-s390x
    #Add minikube to /usr/bin
    sudo cp ./out/minikube-linux-s390x /usr/bin/minikube

    #Adding dependencies to path
        echo "export PATH=/usr/local/go/bin:\$PATH " >> ~/.bashrc

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
                                go get -u github.com/golangci/golangci-lint/cmd/golangci-lint
                                mkdir -p $GOPATH/src/k8s.io/minikube/out/linters
                                cp $GOPATH/bin/golangci-lint $GOPATH/src/k8s.io/minikube/out/linters/
                                make test
                                printf -- "Tests completed. \n"
        fi
        set -e
}

function logDetails() {
    printf -- '**************************** SYSTEM DETAILS *************************************************************\n' >"$LOG           _FILE"
    if [ -f "/etc/os-release" ]; then
        cat "/etc/os-release" >> "$LOG_FILE"
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
    printf -- "export PATH=/usr/local/go/bin:\$PATH \n"
    printf -- "export GOPATH=\$HOME/go \n"
    printf -- "or Restart the terminal to reflect changes\n\n"
    printf -- "Start docker:   \n"
    printf -- "systemctl daemon-reload   \n"
    printf -- "systemctl restart docker   \n"
    printf -- "cd \$GOPATH/src/k8s.io/minikube   \n"   
    printf -- "make storage-provisioner-image   \n" 
    printf -- "curl -Lo kubectl https://storage.googleapis.com/kubernetes-release/release/\$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/s390x/kubectl && chmod +x kubectl && sudo cp kubectl /usr/local/bin/ && rm kubectl   \n" 
    printf -- "export MINIKUBE_WANTUPDATENOTIFICATION=false   \n" 
    printf -- "export MINIKUBE_WANTREPORTERRORPROMPT=false   \n" 
    printf -- "export MINIKUBE_HOME=$HOME   \n" 
    printf -- "export CHANGE_MINIKUBE_NONE_USER=true   \n" 
    printf -- "mkdir \$HOME/.kube   \n" 
    printf -- "touch \$HOME/.kube/config   \n" 
    printf -- "export KUBECONFIG=$HOME/.kube/config   \n" 
    printf -- "sudo -E minikube start --vm-driver=none \n"
    printf -- "You have successfully started minikube.\n"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
    "ubuntu-16.04" | "ubuntu-18.04" | "ubuntu-19.04" )
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo apt-get update
        sudo apt-get install -y tar wget gcc git make python curl patch libvirt-dev |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;
    "rhel-7.5" | "rhel-7.6")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo yum install -y tar wget gcc git make python curl patch libvirt-devel |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;
    "rhel-8.0")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo yum install -y tar wget gcc git make python2 curl patch libvirt-devel |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;
    "sles-12.4")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo zypper install -y tar wget gcc git make python curl libvirt libvirt-devel libtasn1-devel which
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;
    "sles-15")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo zypper install -y  tar wget gcc git make python curl patch libvirt-devel |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;
    *)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
        exit 1
        ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
