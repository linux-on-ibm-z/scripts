#!/bin/bash
# © Copyright IBM Corporation 2019, 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Knative/0.10.0/build_knative.sh
# Execute build script: bash build_knative.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="knative"
PACKAGE_VERSION="0.10.0"
SOURCE_ROOT="$(pwd)"

FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
CONF_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Knative/${PACKAGE_VERSION}/patch"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
    mkdir -p "$SOURCE_ROOT/logs/"
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
    
    #Check if Kubernetes cluster is up
    if sudo kubectl get pods --field-selector=status.phase!=Running -n kube-system >$SOURCE_ROOT/error.txt;then
	    if [[ $(wc -l < $SOURCE_ROOT/error.txt) -eq 0 ]]; then
		    printf -- "Kubernetes cluster is up\n" |& tee -a "$LOG_FILE"
    	else
        	printf -- "Kubernetes cluster is not up\n" |& tee -a "$LOG_FILE"
        	exit 1
    	fi
    else 
	    printf -- "Kubernetes not installed\n" |& tee -a "$LOG_FILE"
	    exit 1
    fi
    
    #Check if Istio is integrated with Kubernetes
    if sudo kubectl get pods --field-selector=status.phase!=Running -n istio-system | egrep -o '(istio-[a-z]+)' >$SOURCE_ROOT/Completed.txt; then
    	printf 'istio-cleanup\nistio-grafana\nistio-security\n' >$SOURCE_ROOT/expected.txt
    	if ! diff -q $SOURCE_ROOT/Completed.txt $SOURCE_ROOT/expected.txt &>/dev/null; then
        	printf -- "Istio is not integrated with Kubenetes\n" |& tee -a "$LOG_FILE"
            exit 1
   	    else
        	printf -- "Istio is integrated with Kubernetes\n" |& tee -a "$LOG_FILE"
    	fi 
    else
	    printf -- "Istio not integrated with Kubernetes\n" |& tee -a $LOG_FILE
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
    cd $SOURCE_ROOT
    rm -rf Completed.txt expected.txt error.txt go1.13.linux-s390x.tar.gz go1.12.5.linux-s390x.tar.gz src/knative.dev/serving/.ko.yaml.patch 
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
    
}
function installDependencies() {
    #Create a local registry to push images to
    sudo docker pull sinenomine/registry-s390x
    sudo docker tag sinenomine/registry-s390x:latest s390x/registry:2
    sudo docker run -it -d -p 5000:5000 s390x/registry:2
    export KO_DOCKER_REPO="localhost:5000/v0.7.0"

    #Install go version 12.5
    sudo rm -rf /usr/local/go
    wget https://dl.google.com/go/go1.12.5.linux-s390x.tar.gz
    sudo tar -C /usr/local -xzf go1.12.5.linux-s390x.tar.gz
    export GOROOT=/usr/local/go
    export GOPATH=$SOURCE_ROOT
    export PATH=/usr/local/go/bin:$PATH

    #Install go dependencies
    cd $GOPATH
    go get -u github.com/golang/dep/cmd/dep
    go get -u github.com/google/ko/cmd/ko
    export PATH=$PATH:$GOPATH/bin
    
    #Build Knative
    configureAndInstall 
}
function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

    #Build knative-build
    mkdir ${GOPATH}/src/knative.dev
    cd ${GOPATH}/src/knative.dev
    git clone https://github.com/knative/build.git
    cd build/
    git checkout v0.7.0
    sudo -E env PATH=$PATH ./hack/release.sh --skip-tests --nopublish --notag-release
    sudo docker tag ko.local/github.com/knative/build/build-base:latest localhost:5000/v0.7.0/ko.local/github.com/knative/build/build-base:latest
    sudo docker push localhost:5000/v0.7.0/ko.local/github.com/knative/build/build-base:latest

    #Build knative-serving
    #Update go version to 1.13
    cd $GOPATH
    sudo rm -rf /usr/local/go
    wget https://dl.google.com/go/go1.13.linux-s390x.tar.gz
    sudo tar -C /usr/local -xzf go1.13.linux-s390x.tar.gz
    #Download the code
    cd ${GOPATH}/src/knative.dev/
    git clone https://github.com/knative/serving.git
    cd serving/
    git checkout v$PACKAGE_VERSION
    
    #Edit .ko.yaml:
    curl -o .ko.yaml.patch $CONF_URL/.ko.yaml.patch
    patch -l .ko.yaml .ko.yaml.patch
	
    #Generate yaml, publish docker images and deploy knative-serving pods
    sudo -E env PATH=$PATH ./hack/release.sh --skip-tests --nopublish --notag-release
    sudo -E env PATH=$PATH KO_DOCKER_REPO=$KO_DOCKER_REPO ko publish ./cmd/activator ./cmd/autoscaler ./cmd/autoscaler-hpa ./cmd/controller ./cmd/default-domain ./cmd/networking/certmanager/ ./cmd/queue ./cmd/webhook
    sudo kubectl apply -f serving.yaml -n knative-serving || true
	
    #Check all knative-serving pods are up:
    sleep 30s
    sudo kubectl get pods --field-selector=status.phase!=Running -n knative-serving >$SOURCE_ROOT/error.txt
    if [[ $(wc -l < $SOURCE_ROOT/error.txt) -eq 0 ]]; then
        printf -- "Knative-serving pods are up\n" 
    else
        printf -- "Knative-serving pods are not up\n" 
        exit 1
    fi 

    #Remove '-race' keyword occurrences from these files.
    sed -i -e 's/-race//g' vendor/knative.dev/test-infra/scripts/e2e-tests.sh
    sed -i -e 's/-race//g' vendor/knative.dev/test-infra/scripts/presubmit-tests.sh 

    #Execute unit tests 
    runTest knative-serving 

    #Build knative-eventing
    #Download the code, build and deploy
    cd ${GOPATH}/src/knative.dev/
    git clone https://github.com/knative/eventing.git
    cd eventing/
    git checkout v$PACKAGE_VERSION
    cp ../serving/.ko.yaml .
    sudo -E env PATH=$PATH ./hack/release.sh --skip-tests --nopublish --notag-release
    sudo kubectl apply -f eventing.yaml -n knative-eventing

    #Check all knative-eventing pods are up
    sleep 30s
    sudo kubectl get pods --field-selector=status.phase!=Running -n knative-eventing >$SOURCE_ROOT/error.txt 
    if [[ $(wc -l < $SOURCE_ROOT/error.txt) -eq 0 ]]; then
        printf -- "Knative-eventing pods are up\n" 
    else
        printf -- "Knative-eventing pods are not up\n" 
        exit 1
    fi 

    #Remove '-race' keyword occurrences from these files. 
    sed -i -e 's/-race//g' vendor/knative.dev/test-infra/scripts/e2e-tests.sh
    sed -i -e 's/-race//g' vendor/knative.dev/test-infra/scripts/presubmit-tests.sh

    #Execute unit tests:
    runTest knative-eventing 
}

function runTest() {
    set +e
    if [[ "$TESTS" == "true" ]]; then
        if [ $1 == "knative-serving" ]; then
            sudo -E env PATH=$PATH ./test/presubmit-tests.sh --unit-tests 
            if grep 'FAIL: TestAutoscalerPanicModeExponentialTrackAndStablize' "$LOG_FILE"; then
                printf -- "Expected failure found\n"
            fi
        elif [ $1 == "knative-eventing" ]; then
            sudo -E env PATH=$PATH ./test/presubmit-tests.sh --unit-tests 
        fi
    else
        printf -- "TEST FLAG not set\n" 
    fi
    set -e
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
    echo " build_knative.sh  [-d debug] [-y install-without-confirmation] [-t install-with-test]"
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
    printf -- "         You have successfully installed Knative. \n"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04" | "ubuntu-19.04" | "rhel-7.5" | "rhel-7.6" | "rhel-7.7" | "rhel-8.0" | "sles-12.4" | "sles15")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    installDependencies |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
