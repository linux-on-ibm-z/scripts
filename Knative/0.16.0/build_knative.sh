#!/bin/bash
# © Copyright IBM Corporation 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Knative/0.16.0/build_knative.sh
# Execute build script: bash build_knative.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="knative"
PACKAGE_VERSION="0.16.0"
GO_VERSION="1.14.7"
SOURCE_ROOT="$(pwd)"

FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

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
    if kubectl get pods --field-selector=status.phase!=Running -n kube-system >$SOURCE_ROOT/error.txt;then
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
    if kubectl get pods --field-selector=status.phase!=Running -n istio-system | egrep -o '(istio-[a-z]+)' >$SOURCE_ROOT/Completed.txt; then
    	printf 'istio-grafana\nistio-security\n' >$SOURCE_ROOT/expected.txt
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
    rm -rf Completed.txt expected.txt error.txt go${GO_VERSION}.linux-s390x.tar.gz
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
    
}
function installDependencies() {
    #Install Go
    wget "https://dl.google.com/go/go${GO_VERSION}.linux-s390x.tar.gz"
    tar -xf "go${GO_VERSION}.linux-s390x.tar.gz" --one-top-level="go${GO_VERSION}" --strip-components 1
    export GOPATH="$SOURCE_ROOT"
    export PATH="$(pwd)/go${GO_VERSION}/bin":"${GOPATH}/bin":"${PATH}"
    unset GOROOT

    #Install Ko
    go get -u github.com/google/ko/cmd/ko
    export KO_DOCKER_REPO="ko.local"
    export GOARCH="s390x" # override ko default (amd64)

    #Build Knative
    configureAndInstall
}
function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

    #Build net-istio
    mkdir -p "${GOPATH}/src/knative.dev/net-istio"
    cd "${GOPATH}/src/knative.dev/net-istio"
    git clone --branch "v${PACKAGE_VERSION}" https://github.com/knative/net-istio.git .
    sudo -E env PATH="${PATH}" ./hack/release.sh --skip-tests --nopublish --notag-release

    #Build knative-serving
    mkdir -p "${GOPATH}/src/knative.dev/serving"
    cd "${GOPATH}/src/knative.dev/serving"
    git clone --branch "v${PACKAGE_VERSION}" https://github.com/knative/serving.git .
    sudo -E env PATH="${PATH}" ./hack/release.sh --skip-tests --nopublish --notag-release

    #Execute unit tests
    runTest knative-serving

    #Install knative-serving onto cluster.
    kubectl apply -f serving-crds.yaml
    kubectl apply -f serving-core.yaml
    kubectl apply -f ../net-istio/release.yaml

    #Check all knative-serving pods are up
    sleep 30s
    kubectl get pods --field-selector=status.phase!=Running -n knative-serving >$SOURCE_ROOT/error.txt
    if [[ $(wc -l < $SOURCE_ROOT/error.txt) -eq 0 ]]; then
        printf -- "Knative-serving pods are up\n" 
    else
        printf -- "Knative-serving pods are not up\n" 
        exit 1
    fi 

    #Build knative-eventing
    mkdir -p "${GOPATH}/src/knative.dev/eventing"
    cd "${GOPATH}/src/knative.dev/eventing"
    git clone --branch "v${PACKAGE_VERSION}" https://github.com/knative/eventing.git .
    sudo -E env PATH="${PATH}" ./hack/release.sh --skip-tests --nopublish --notag-release

    #Execute unit tests
    runTest knative-eventing

    #Install knative-eventing onto cluster
    kubectl apply -f eventing-crds.yaml
    kubectl apply -f eventing-core.yaml
    kubectl apply -f in-memory-channel.yaml
    kubectl apply -f mt-channel-broker.yaml

    #Check all knative-eventing pods are up
    sleep 30s
    kubectl get pods --field-selector=status.phase!=Running -n knative-eventing >$SOURCE_ROOT/error.txt
    if [[ $(wc -l < $SOURCE_ROOT/error.txt) -eq 0 ]]; then
        printf -- "Knative-eventing pods are up\n" 
    else
        printf -- "Knative-eventing pods are not up\n" 
        exit 1
    fi 
}

function runTest() {
    set +e
    # Knative eventing tests fail when unable to access ~/.config
    sudo chown -R "$(id -un):$(id -gn)" ~/.config
    if [[ "$TESTS" == "true" ]]; then
        go test ./...
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
    printf -- '\n*********************************************************************************************************\n'
    printf -- "*                     Getting Started                 * \n"
    printf -- "         You have successfully installed Knative. \n"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"ubuntu-18.04" | "ubuntu-20.04" | "rhel-8.1" | "rhel-8.2" | "sles-15.1")
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
