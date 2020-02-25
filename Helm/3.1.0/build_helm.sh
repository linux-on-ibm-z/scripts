#!/bin/bash
# © Copyright IBM Corporation 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/helm/3.1.0/build_helm.sh
# Execute build script: bash build_helm.sh    (provide -h for help)
#
set -e -o pipefail

PACKAGE_NAME="helm"
PACKAGE_VERSION="3.1.0"
CURDIR="$PWD"
HELM_REPO_URL="https://github.com/helm/helm.git"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
FORCE="false"
TEST="false"
GOPATH="${CURDIR}"
trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
        mkdir -p "$CURDIR/logs/"
fi

source "/etc/os-release"

function prepare() {

        if command -v "sudo" >/dev/null; then
                printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
        else
                printf -- 'Sudo : No \n' >>"$LOG_FILE"
                printf -- 'You can install sudo from repository using apt, yum or zypper based on your distro. \n'
                exit 1
        fi

        if [ $(command -v helm) ]
        then
        printf -- "helm detected skipping helm installation \n" |& tee -a "$LOG_FILE"
                exit 0
        fi
}

function cleanup() {

        rm -rf "${CURDIR}/src/k8s.io/helm"
        printf -- '\nCleaned up the artifacts\n' >>"$LOG_FILE"
}

function configureAndInstall() {
        printf -- '\nConfiguration and Installation started \n'

        #Setting environment variable needed for building
        export GOPATH="${CURDIR}"
        export PATH=$GOPATH/bin:$PATH

        # Install go
        printf -- 'Installing Go...\n'
        wget https://storage.googleapis.com/golang/go1.13.4.linux-s390x.tar.gz
        chmod ugo+r go1.13.4.linux-s390x.tar.gz
        sudo tar -C /usr/local -xzf go1.13.4.linux-s390x.tar.gz
        export PATH=$PATH:/usr/local/go/bin

        if [[ "${ID}" != "ubuntu" ]]
        then
                sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
                printf -- 'Symlink done for gcc \n'
        fi

        go version

        # Download and configure helm
        printf -- 'Downloading helm. Please wait.\n'
        mkdir -p $GOPATH/src/helm.sh
        cd $GOPATH/src/helm.sh
        git clone -b v$PACKAGE_VERSION $HELM_REPO_URL
        sleep 2

        #Build helm
        printf -- 'Building helm \n'
        printf -- 'Build might take some time. Sit back and relax\n'
        cd $GOPATH/src/helm.sh/helm
        make


        printenv >>"$LOG_FILE"

        #Run Test
        runTests

        # Copies the binaries to /usr/local/bin
        sudo cp $GOPATH/src/helm.sh/helm/bin/helm /usr/local/bin
        printf -- '\nCopied binary in /usr/local/bin\n'

        cleanup

}

function runTests() {
        set +e
        if [[ "$TESTS" == "true" ]]; then
                printf -- "TEST Flag is set, continue with running test \n"  >> "$LOG_FILE"

                #Install prerequisite
                cd $GOPATH
                wget https://github.com/golangci/golangci-lint/releases/download/v1.21.0/golangci-lint-1.21.0-linux-s390x.tar.gz
                tar zxf golangci-lint-1.21.0-linux-s390x.tar.gz
                sudo cp golangci-lint-1.21.0-linux-s390x/golangci-lint /usr/local/bin

                cd $GOPATH/src/helm.sh/helm
                make test
        fi
        set -e
}

function logDetails() {
        printf -- 'SYSTEM DETAILS\n' >"$LOG_FILE"
        if [ -f "/etc/os-release" ]; then
                cat "/etc/os-release" >>"$LOG_FILE"
        fi

        cat /proc/version >>"$LOG_FILE"
        printf -- "\nDetected %s \n" "$PRETTY_NAME"
        printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" |& tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
        echo
        echo "Usage: "
        echo "  build_helm.sh  [-d debug] [-y install-without-confirmation -t run-test-cases]"
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
        printf -- '\n********************************************************************************************************\n'
        printf -- "\n* Getting Started * \n"
        printf -- "\n*All relevant binaries are created and placed in /usr/local/bin \n"
        printf -- '\n\n**********************************************************************************************************\n'

}

logDetails
prepare

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04" | "ubuntu-19.10")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo apt-get update
        sudo apt-get install -y wget tar git make patch socat gcc
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

"rhel-7.5" | "rhel-7.6" | "rhel-7.7" | "rhel-8.0" | "rhel-8.1")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo yum install -y wget tar git make iptables-devel.s390x iptables-utils.s390x iptables.s390x patch socat gcc
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

"sles-12.4" | "sles-15.1")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo zypper install -y  wget tar git iptables patch curl device-mapper-devel bison make which socat gzip gcc
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

*)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
        exit 1
        ;;
esac

printSummary |& tee -a "$LOG_FILE"
