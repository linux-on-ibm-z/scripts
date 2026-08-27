#!/bin/bash
# © Copyright IBM Corporation 2026.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)

################################################################################################################################################################
#Script     :   build_calico.sh
#Description:   The script builds Calico version v3.32.1 on Linux on IBM Z for RHEL (8.10, 9.6, 9.7, 9.8, 10.0, 10.1, 10.2), Ubuntu (22.04, 24.04) and SLES (15 SP7).
#Maintainer :   LoZ Open Source Ecosystem (https://www.ibm.com/community/z/usergroups/opensource)
#Info/Notes :   Please refer to the instructions first for Building Calico mentioned in wiki( https://github.com/linux-on-ibm-z/docs/wiki/Building-Calico-3.x ).
#               Build and Test logs can be found in $SOURCE_ROOT/logs/.
#               By Default, system tests are turned off. To run system tests for Calico, pass argument "-t" to shell script.
#
#Download build script :   wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Calico/3.32.1/build_calico.sh
#Run build script      :   bash build_calico.sh       #(To only build Calico, provide -h for help)
#                          bash build_calico.sh -t    #(To build Calico and run system tests)
#
#################################################################################################################################################################

USER_IN_GROUP_DOCKER=$(id -nGz $USER | tr '\0' '\n' | grep '^docker$' | wc -l)
set -e
set -o pipefail

PACKAGE_NAME="calico"
PACKAGE_VERSION="v3.32.1"
GOLANG_VERSION="1.25.11"
FORCE="false"
TESTS="false"
export SOURCE_ROOT=$(pwd)
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Calico/3.32.1/patch"
GO_INSTALL_URL="https://go.dev/dl/go"$GOLANG_VERSION".linux-s390x.tar.gz"
GO_DEFAULT="$SOURCE_ROOT/go"
GO_FLAG="DEFAULT"
LOGDIR="$SOURCE_ROOT/logs"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

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
    rm -rf "$SOURCE_ROOT/go"$GOLANG_VERSION".linux-s390x.tar.gz" $SOURCE_ROOT/release $SOURCE_ROOT/kind $SOURCE_ROOT/build_kind.sh $SOURCE_ROOT/docker
    printf -- '\nCleaned up the artifacts.\n' >>"$LOG_FILE"
}

function buildDockerImage() {
    printf -- '\Build Docker Image \n'
    source $SOURCE_ROOT/setenv.sh

    # Install docker:25 for s390x
    cd $SOURCE_ROOT
    git clone https://github.com/docker-library/docker.git
    cd docker && git checkout ad85990
    curl -s $PATCH_URL/docker.patch | git apply --ignore-whitespace -
    cd 25/cli/
    docker build -t docker-s390x:25-23 .
}

function buildKind() {
    printf -- '\nInstalling Kind \n'
    source $SOURCE_ROOT/setenv.sh

    # Install kind
    cd $SOURCE_ROOT
    wget -O build_kind.sh https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Kind/0.32.0/build_kind.sh

    if [[ $DISTRO == "sles-15.7" ]]; then
        export GOFLAGS="-buildvcs=false"
    fi

    bash build_kind.sh -y
    cd $SOURCE_ROOT/kind/bin/
    chmod +x ./kind
    sudo cp ./kind /usr/local/bin/kind
    kind --version

    printf -- '\Installing cross image\n'  
    # Build cross image
    cd $SOURCE_ROOT
    git clone -b v0.19.0 --depth 1 https://github.com/kubernetes/release.git
    cd release
    curl -s https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Kind/0.32.0/patch/release.patch | git apply --ignore-whitespace -
    export REGISTRY=local
    docker buildx inspect
    cd images/build/cross/
    TARGETPLATFORM=s390x make container

    printf -- '\Installing kindest/node image\n'  
    # Build kindest/node image
    cd $SOURCE_ROOT
    git clone -b v1.36.1 --depth 1 https://github.com/kubernetes/kubernetes.git
    cd kubernetes
    sed -i 's,v1.36.0-go1.26.2-bullseye.0,v1.36.0-go1.26.2-trixie.0,g' build/build-image/cross/VERSION
    docker buildx use default
    KUBE_CROSS_IMAGE=${REGISTRY}/kube-cross-s390x kind build node-image --image kindest/node:v1.35.0
    KUBE_CROSS_IMAGE=${REGISTRY}/kube-cross-s390x kind build node-image --image kindest/node:v1.35.1
    docker tag kindest/node:v1.35.0 ${REGISTRY}/kindest/node:v1.35.0
    docker tag kindest/node:v1.35.1 ${REGISTRY}/kindest/node:v1.35.1

    printf -- "\n Finished building images for kindest/node \n"
}

function buildCurl() {
    printf -- '\n Installing Curl \n'

    cd $SOURCE_ROOT
    sudo yum install -y libpsl-devel openssl-devel autoconf automake libtool
    git clone -b curl-8_6_0 --depth 1 https://github.com/curl/curl.git
    cd curl
    autoreconf -fi
    ./configure --prefix=/usr/local --with-openssl
    make -j$(nproc)
    sudo make install
    export PATH=/usr/local/bin/curl:$PATH
    echo "export PATH=$PATH" > $SOURCE_ROOT/setenv.sh

    printf -- "\n Finished installing Curl \n"
}

function configureAndInstall() {
    printf -- '\nConfiguration and Installation started \n'

    # Install go
    cd $SOURCE_ROOT
    export LOG_FILE="$LOGDIR/configuration-$(date +"%F-%T").log"
    printf -- "\nInstalling Go ... \n" | tee -a "$LOG_FILE"
    export INSTALL_DIR="${SOURCE_ROOT}/${GOLANG_VERSION}"
    export GOROOT=${INSTALL_DIR}
    sudo mkdir -p "${INSTALL_DIR}"
    wget -q $GO_INSTALL_URL
    chmod ugo+r go"$GOLANG_VERSION".linux-s390x.tar.gz
    sudo tar -C "${INSTALL_DIR}" --strip-components=1 -xzf go"$GOLANG_VERSION".linux-s390x.tar.gz
    
    if [[ "${ID}" != "ubuntu" ]]; then
        sudo update-alternatives --install /usr/bin/s390x-linux-gnu-gcc s390x-linux-gnu-gcc /usr/bin/gcc 100
    fi
    
    # Set GOPATH if not already set
    if [[ -z "${GOPATH}" ]]; then
        printf -- "\nSetting default value for GOPATH \n"
        # Check if go directory exists
        if [ ! -d "$SOURCE_ROOT/go" ]; then
            mkdir "$SOURCE_ROOT/go"
        fi
        export GOPATH="$GO_DEFAULT"
    else
        printf -- "\nGOPATH already set : Value : %s \n" "$GOPATH"
        if [ ! -d "$GOPATH" ]; then
            mkdir -p "$GOPATH"
        fi
        export GO_FLAG="CUSTOM"
    fi

    export PATH="$GOROOT/bin:$PATH"
    export PATH=$PATH:/usr/local/bin
    go version

    printenv >>"$LOG_FILE"

    # Exporting Calico ENV to $SOURCE_ROOT/setenv.sh for later use
    cd $SOURCE_ROOT
    cat <<EOF >>setenv.sh
#CALICO ENV
export GOPATH=$GOPATH
export PATH=$PATH
export LOGDIR=$LOGDIR
EOF

    source $SOURCE_ROOT/setenv.sh

    # Clone the Calico repo and apply patches where applicable
    cd $SOURCE_ROOT
    rm -rf $GOPATH/src/github.com/projectcalico/calico
    export CALICO_LOG="$LOGDIR/calico-$(date +"%F-%T").log"
    touch $CALICO_LOG

    printf -- "\nBuilding calico ... \n" | tee -a "$CALICO_LOG"
    git clone -b $PACKAGE_VERSION https://github.com/projectcalico/calico $GOPATH/src/github.com/projectcalico/calico
    cd $GOPATH/src/github.com/projectcalico/calico

    printf -- "\nApplying patch for calico ... \n" | tee -a "$CALICO_LOG"
    curl -s $PATCH_URL/calico.patch | git apply --ignore-whitespace - | tee -a "$CALICO_LOG"

    if [[ $DISTRO == "rhel-8.10" ]]; then
        curl -s $PATCH_URL/cgroup.patch | git apply --ignore-whitespace - | tee -a "$CALICO_LOG"
    fi

    # Build node and felix-test images
    cd $GOPATH/src/github.com/projectcalico/calico/node
    ARCH=s390x make image 2>&1 | tee -a "$CALICO_LOG"

    cd $GOPATH/src/github.com/projectcalico/calico
    ARCH=s390x make -C felix image 2>&1 | tee -a "$CALICO_LOG" #for felix-test

    # Tag docker images
    printf -- "\nTagging images ... \n" | tee -a "$CALICO_LOG"
    docker tag calico/node:latest-s390x quay.io/calico/node:${PACKAGE_VERSION}
}

function runTest() {
    # Execute test cases
    export TEST_FELIX_LOG="$LOGDIR/testFelixLog-$(date +"%F-%T").log"
    export TEST_KC_LOG="$LOGDIR/testKCLog-$(date +"%F-%T").log"
    export TEST_CTL_LOG="$LOGDIR/testCTLLog-$(date +"%F-%T").log"
    export TEST_CNI_LOG="$LOGDIR/testCNILog-$(date +"%F-%T").log"
    export TEST_CONFD_LOG="$LOGDIR/testConfdLog-$(date +"%F-%T").log"
    export TEST_APP_LOG="$LOGDIR/testAppLog-$(date +"%F-%T").log"
    export TEST_NODE_LOG="$LOGDIR/testNodeLog-$(date +"%F-%T").log"
    export TEST_APISERVER_LOG="$LOGDIR/testApiserverLog-$(date +"%F-%T").log"
    export TEST_API_LOG="$LOGDIR/testApiLog-$(date +"%F-%T").log"
    export TEST_TYPHA_LOG="$LOGDIR/testTyphaLog-$(date +"%F-%T").log"
    export TEST_POD2DAEMON_LOG="$LOGDIR/testPod2DaemonLog-$(date +"%F-%T").log"
    export TEST_LIBCALGO_LOG="$LOGDIR/testLibCalGoLog-$(date +"%F-%T").log"

    touch $TEST_FELIX_LOG
    touch $TEST_KC_LOG
    touch $TEST_CTL_LOG
    touch $TEST_CNI_LOG
    touch $TEST_CONFD_LOG
    touch $TEST_APP_LOG
    touch $TEST_NODE_LOG
    touch $TEST_APISERVER_LOG
    touch $TEST_TYPHA_LOG
    touch $TEST_API_LOG
    touch $TEST_POD2DAEMON_LOG
    touch $TEST_LIBCALGO_LOG

    # Build docker:25 - required to build node test_image
    buildDockerImage
    # Build Kind - required by api test cases
    buildKind

    source $SOURCE_ROOT/setenv.sh
    docker pull quay.io/coreos/etcd:v3.5.24-s390x 

    set +e

    cd $GOPATH/src/github.com/projectcalico/calico/node
    ARCH=s390x make test_image 2>&1 | tee -a "$TEST_NODE_LOG"
    ARCH=s390x make test 2>&1 | tee -a "$TEST_NODE_LOG" || true

    cd $GOPATH/src/github.com/projectcalico/calico/felix
    ARCH=s390x GINKGO_ARGS="--repeat=3" make ut 2>&1 | tee -a "$TEST_FELIX_LOG" || true

    cd $GOPATH/src/github.com/projectcalico/calico/kube-controllers
    ARCH=s390x GINKGO_ARGS="--ginkgo.flake-attempts=3" make test 2>&1 | tee -a "$TEST_KC_LOG" || true
    
    cd $GOPATH/src/github.com/projectcalico/calico/calicoctl
    ARCH=s390x make test 2>&1 | tee -a "$TEST_CTL_LOG" || true

    cd $GOPATH/src/github.com/projectcalico/calico/cni-plugin
    ARCH=s390x make test 2>&1 | tee -a "$TEST_CNI_LOG" || true

    cd $GOPATH/src/github.com/projectcalico/calico/confd
    ARCH=s390x GINKGO_ARGS="--ginkgo.flake-attempts=3" make ut 2>&1 | tee -a "$TEST_CONFD_LOG" || true

    cd $GOPATH/src/github.com/projectcalico/calico/app-policy
    ARCH=s390x GINKGO_ARGS="--ginkgo.flake-attempts=3" make ut 2>&1 | tee -a "$TEST_APP_LOG" || true

    cd $GOPATH/src/github.com/projectcalico/calico/apiserver
    ARCH=s390x GINKGO_ARGS="--ginkgo.flake-attempts=3" make test 2>&1 | tee -a "$TEST_APISERVER_LOG" || true

    cd $GOPATH/src/github.com/projectcalico/calico/api
    ARCH=s390x GINKGO_ARGS="--ginkgo.flake-attempts=3" make test 2>&1 | tee -a "$TEST_API_LOG" || true

    cd $GOPATH/src/github.com/projectcalico/calico/typha
    ARCH=s390x GINKGO_ARGS="--ginkgo.flake-attempts=3" make ut 2>&1 | tee -a "$TEST_TYPHA_LOG" || true

    cd $GOPATH/src/github.com/projectcalico/calico/pod2daemon
    ARCH=s390x GINKGO_ARGS="--ginkgo.flake-attempts=3" make test 2>&1 | tee -a "$TEST_POD2DAEMON_LOG" || true

    cd $GOPATH/src/github.com/projectcalico/calico/libcalico-go
    ARCH=s390x GINKGO_ARGS="--ginkgo.flake-attempts=3" make ut 2>&1 | tee -a "$TEST_LIBCALGO_LOG" || true

    printf -- "\n------------------------------------------------------------------------------------------------------------------- \n"
    printf -- "\n Please review results of individual test components."
    printf -- "\n Test results for individual components can be found in their respective repository under report folder."
    printf -- "\n Tests for individual components can be run as follows - for example, node component:"
    printf -- "\n source \$SOURCE_ROOT/setenv.sh"
    printf -- "\n cd \$GOPATH/src/github.com/projectcalico/calico/node"
    printf -- "\n ARCH=s390x CALICOCTL_VER=latest CNI_VER=latest-s390x make st 2>&1 | tee -a \$LOGDIR/testLog-\$(date +"%%F-%%T").log \n"
    printf -- "\n------------------------------------------------------------------------------------------------------------------- \n"

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
    echo "bash  build_calico.sh  [-y install-without-confirmation] [-t install-with-tests]"
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
    printf -- '\n\nFor information on Getting started with Calico visit: \nhttps://github.com/projectcalico/calico \n\n'
    printf -- '***********************************************************************************************************************************\n'
}

logDetails
prepare

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"rhel-8.10" | "rhel-9.6" | "rhel-9.7" | "rhel-9.8")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- "Installing dependencies ... it may take some time.\n"
    sudo yum install -y --allowerasing yum-utils curl git wget tar gcc glibc.s390x make which patch iproute-devel 2>&1 | tee -a "$LOG_FILE"
    export CC=gcc
    if [[ $DISTRO == "rhel-8.10" ]]; then
       buildCurl |& tee -a "$LOG_FILE"
    fi
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"rhel-10.0" | "rhel-10.1" | "rhel-10.2")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- "Installing dependencies ... it may take some time.\n"
    sudo dnf install -y --allowerasing curl git wget tar gcc glibc.s390x make which patch iproute-devel 2>&1 | tee -a "$LOG_FILE"
    export CC=gcc
    configureAndInstall |& tee -a "$LOG_FILE"   
    ;;

"sles-15.7")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- "Installing dependencies ... it may take some time.\n"
    sudo zypper install -y curl git wget tar gcc glibc-devel-static make which patch iproute2 2>&1 | tee -a "$LOG_FILE"
    export CC=gcc
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
    
 "ubuntu-22.04" | "ubuntu-24.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- "Installing dependencies ... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg iproute2 patch git curl tar gcc wget make  2>&1 | tee -a "$LOG_FILE"
    if [[ $DISTRO == "ubuntu-24.04" ]]; then
        sudo apt-get install -y libclang1-18 2>&1 | tee -a "$LOG_FILE"
    else
        sudo apt-get install -y clang 2>&1 | tee -a "$LOG_FILE"
    fi 
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
