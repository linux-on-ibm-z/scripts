#!/bin/bash
# © Copyright IBM Corporation 2021, 2023.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)

################################################################################################################################################################
#Script     :   build_prow.sh
#Description:   The script builds Prow (commits till 28-Feb-2023) on Linux on IBM Z for RHEL (7.8, 7.9, 8.6, 8.7, 9.0, 9.1), Ubuntu (20.04, 22.04, 22.10) and SLES (12 SP5, 15 SP4).
#Maintainer :   LoZ Open Source Ecosystem (https://www.ibm.com/community/z/usergroups/opensource)
#Info/Notes :   Please refer to the instructions first for Building Prow mentioned in wiki( https://github.com/linux-on-ibm-z/docs/wiki/Building-Prow ).
#               Build and Test logs can be found in $CURDIR/logs/.
#               By Default, system tests are turned off. To run system tests for Prow, pass argument "-t" to shell script.
#
#Download build script :   wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Prow/build_prow.sh
#Run build script      :   bash build_prow.sh       #(To only build Prow, provide -h for help)
#                          bash build_prow.sh -t    #(To build Prow and run unit tests)
#
################################################################################################################################################################

USER_IN_GROUP_DOCKER=$(id -nGz $USER | tr '\0' '\n' | grep '^docker$' | wc -l)
set -e
set -o pipefail

PACKAGE_NAME="prow"
PACKAGE_VERSION="master"
GOLANG_VERSION="go1.19.5.linux-s390x.tar.gz"
FORCE="false"
TESTS="false"
CURDIR="$(pwd)"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Prow/patch"
GO_INSTALL_URL="https://golang.org/dl/${GOLANG_VERSION}"
GO_DEFAULT="$CURDIR/go"
GO_FLAG="DEFAULT"
LOGDIR="$CURDIR/logs"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

# Check if directory exists
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
        printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n'
        exit 1
    fi
	
	if [[ $(which docker) && $(docker --version) ]]; then
		printf --  'Found docker installed...\n' >>"$LOG_FILE"
	else
		printf --  'Docker : No \n' >>"$LOG_FILE"
		printf --  'Please install docker to proceed...\n'
		exit 1
	fi

    if [[ "$USER_IN_GROUP_DOCKER" == "1" ]]; then
        printf "User $USER belongs to group docker\n" |& tee -a "${LOG_FILE}"
    else
        printf "Please ensure User $USER belongs to group docker\n"
        exit 1
    fi

    if [[ "$FORCE" == "true" ]]; then
        printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
    else
        printf -- 'As part of the installation, dependencies would be installed/upgraded.\n'

        while true; do
            read -r -p "Do you want to continue (y/n) ? :  " yn
            case $yn in
            [Yy]*)

                break
                ;;
            [Nn]*) exit ;;
            *) echo "Please provide Correct input to proceed." ;;
            esac
        done
    fi
}

function cleanup() {
	sudo rm -rf go go1.19.5.linux-s390x.tar.gz jq
    printf -- '\nCleaned up the artifacts.\n' >>"$LOG_FILE"
}

function configureAndInstall() {
    printf -- '\nConfiguration and Installation started \n'
    # Install go
    cd "$CURDIR"
    export LOG_FILE="$LOGDIR/configuration-$(date +"%F-%T").log"
    printf -- "\nInstalling Go ... \n" | tee -a "$LOG_FILE"
    wget $GO_INSTALL_URL
    sudo tar -C /usr/local -xzf ${GOLANG_VERSION}

    # Set GOPATH if not already set
    if [[ -z "${GOPATH}" ]]; then
        printf -- "\nSetting default value for GOPATH \n"
        # Check if go directory exists
        if [ ! -d "$CURDIR/go" ]; then
            mkdir "$CURDIR/go"
        fi
        export GOPATH="${GO_DEFAULT}"
    else
        printf -- "\nGOPATH already set : Value : %s \n" "$GOPATH"
        if [ ! -d "$GOPATH" ]; then
            mkdir -p "$GOPATH"
        fi
        export GO_FLAG="CUSTOM"
    fi
	
    if [[ $(s390x-linux-gnu-gcc --version) ]]; then
        printf --  'Found s390x-linux-gnu-gcc binary in the PATH...\n' >>"$LOG_FILE"
    else
        printf --  'Did not found s390x-linux-gnu-gcc binary in the PATH. Creating symlink...\n' >>"$LOG_FILE"
        sudo ln -s /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
    fi
	
    if [[ "${DISTRO}" == "rhel-7.8" ]] || [[ "${DISTRO}" == "rhel-7.9" ]]; then
        cd "$CURDIR"
        wget --no-check-certificate https://mirrors.edge.kernel.org/pub/software/scm/git/git-2.25.1.tar.gz
        tar xf git-2.25.1.tar.gz
        cd git-2.25.1/
        make configure
        ./configure --prefix=/usr/local
        make all
        sudo make install
        git --version
    fi
	
    export PATH=/usr/local/go/bin:$PATH
    export PATH=/usr/local/bin:$PATH
    
    # Build jq
    printf -- "Building jq ...\n"
    cd "$CURDIR"
    git clone https://github.com/stedolan/jq.git
    cd jq/
    git checkout jq-1.5
    autoreconf -fi
    ./configure --disable-valgrind
    sudo make LDFLAGS=-all-static -j$(nproc)
    sudo make install
    /usr/local/bin/jq --version

    # Build Prow
    printf -- "Building Prow ...\n"
    cd "$CURDIR"
    git clone https://github.com/kubernetes/test-infra.git
    cd test-infra/
    git checkout 89ac42333a8e7d3d88eda931740199b2a25252ea
    curl -o test-infra-patch.diff  $PATCH_URL/test-infra-patch.diff
    git apply test-infra-patch.diff
    make -C prow build-images

    # Exporting Prow ENV to $CURDIR/setenv.sh for later use
    cd $CURDIR
    cat <<EOF >setenv.sh
export GOPATH=$GOPATH
export PATH=$PATH
export LOGDIR=$LOGDIR
EOF
}

function runTest() {
    cd "$CURDIR"
    cd test-infra/
    mkdir _bin/jq-1.5
    cp /usr/local/bin/jq _bin/jq-1.5/jq
    cp /usr/local/bin/jq _bin/jq-1.5/jq-linux64
    make test	
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
    echo "bash  build_prow.sh  [-y install-without-confirmation] [-t install-with-tests]"
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
        if grep SUCCESSFULLY "$VERIFY_LOG" >/dev/null; then
            TESTS="true"
            printf -- "%s is detected with version %s .\n" "$PACKAGE_NAME" "$PACKAGE_VERSION" |& tee -a "$LOG_FILE"
            runTest |& tee -a "$LOG_FILE"
            exit 0

        else
            TESTS="true"
        fi
        ;;
    esac
done

function printSummary() {
    printf -- '\n***********************************************************************************************************************************\n'
    printf -- "\n* Getting Started * \n"
    printf -- '\n\nFor information on Getting started with Prow visit: \n https://docs.prow.k8s.io/docs/getting-started-develop/#building-testing-and-deploying \n\n'
    printf -- '***********************************************************************************************************************************\n'
}

logDetails
prepare

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-20.04" | "ubuntu-22.04" | "ubuntu-22.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- "Installing dependencies ... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y zip tar unzip git vim wget make curl python2.7-dev python3.8-dev gcc g++ python3-distutils libtool libtool-bin autoconf 2>&1 | tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
	
"rhel-7.8" | "rhel-7.9" | "rhel-8.6" | "rhel-8.7" | "rhel-9.0" | "rhel-9.1")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- "Installing dependencies ... it may take some time.\n"
    sudo yum install -y zip tar unzip git vim wget make curl python3-devel gcc gcc-c++ libtool autoconf curl-devel expat-devel gettext-devel openssl-devel zlib-devel perl-CPAN perl-devel 2>&1 | tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"sles-12.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- "Installing dependencies ... it may take some time.\n"
    sudo zypper install -y zip tar unzip git vim wget make curl python3-devel gcc gcc-c++ libtool autoconf libnghttp2-devel 2>&1 | tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
    
"sles-15.4")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- "Installing dependencies ... it may take some time.\n"
    sudo zypper install -y zip tar unzip git vim wget make curl python3-devel gcc gcc-c++ libtool autoconf 2>&1 | tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

# Run tests
if [[ "$TESTS" == "true" ]]; then
    runTest |& tee -a "$LOG_FILE"
fi

cleanup
printSummary |& tee -a "$LOG_FILE"
