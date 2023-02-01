#!/bin/bash
# © Copyright IBM Corporation 2021, 2023.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Prow/build_prow.sh
# Execute build script: bash build_prow.sh    (provide -h for help)

PACKAGE_NAME="prow"
PACKAGE_VERSION="master"
SOURCE_ROOT="$(pwd)"

FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
    mkdir -p "$SOURCE_ROOT/logs/"
fi

# Set the Distro ID
source "/etc/os-release"
	
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
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function configureAndInstall() {
    
    printf -- "Bazel Installation started \n"
    
    wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Bazel/3.4.1/build_bazel.sh
    bash build_bazel.sh -y
    export PATH=$SOURCE_ROOT/bazel-s390x/output:$PATH
    
    printf -- "Prow Installation started \n"
    cd $SOURCE_ROOT
    git clone  https://github.com/linux-on-ibm-z/test-infra.git
    cd test-infra/
    git checkout s390x-prow-20201124
    sed -i "s|1.15.2|1.14.4|g" WORKSPACE
    bazel --output_base=/tmp/bazel/output build "--host_javabase=@local_jdk//:jdk" //prow/...
    
    cd $SOURCE_ROOT/test-infra/
    bazel --output_base=/tmp/bazel/output run //prow/cmd/hook:image
    bazel --output_base=/tmp/bazel/output run //prow/cmd/plank:image
    bazel --output_base=/tmp/bazel/output run //prow/cmd/horologium:image
    bazel --output_base=/tmp/bazel/output run //prow/cmd/sinker:image
    bazel --output_base=/tmp/bazel/output run //prow/cmd/crier:image
    bazel --output_base=/tmp/bazel/output run //prow/cmd/deck:image
    bazel --output_base=/tmp/bazel/output run //prow/cmd/tide:image
    bazel --output_base=/tmp/bazel/output run //prow/cmd/status-reconciler:image
    bazel --output_base=/tmp/bazel/output run //prow/cmd/prow-controller-manager:image
    bazel --output_base=/tmp/bazel/output run //prow/cmd/initupload:image
    bazel --output_base=/tmp/bazel/output run //prow/cmd/sidecar:image
    bazel --output_base=/tmp/bazel/output run //prow/cmd/clonerefs:image
    bazel --output_base=/tmp/bazel/output run //prow/cmd/entrypoint:image
    bazel --output_base=/tmp/bazel/output run //ghproxy:image
    
    #Run Tests
    runTest 
    
    printf -- "\n* Completed prow build. *\n"
    
}

function runTest() {
    if [[ "$TESTS" == "true" ]]; then    
        printf -- "TEST Flag is set, continue with running test \n"  >> "$LOG_FILE"
        cd $SOURCE_ROOT/test-infra/
        bazel --output_base=/tmp/bazel/output test "--host_javabase=@local_jdk//:jdk" //prow/... |& tee -a "$LOG_FILE"   
    fi
}
function logDetails() {
    printf -- '**************************** SYSTEM DETAILS *************************************************************\n' >>"$LOG_FILE"
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
    echo "bash build_prow.sh  [-d debug] [-y install-without-confirmation] [-t install-with-test]"
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
    	printf -- "         You have successfully built Prow. \n"
	    printf -- "      Docker images created with 'bazel/prow/cmd/<component_name>:image' \n"
    	printf -- '**********************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"ubuntu-18.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update  
    sudo apt-get install -y zip tar unzip git vim wget make curl python2.7-dev python3.8-dev gcc g++ python3-distutils golang-1.18
    sudo update-alternatives --install /usr/bin/go go /usr/lib/go-1.18/bin/go 50
    sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.8 50
    go version
    python -V
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
