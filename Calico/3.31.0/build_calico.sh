#!/bin/bash
# © Copyright IBM Corporation 2025.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)

################################################################################################################################################################
#Script     :   build_calico.sh
#Description:   The script builds Calico version v3.31.0 on Linux on IBM Z for RHEL (8.10, 9.4, 9.6), Ubuntu (22.04, 24.04) and SLES (15 SP6).
#Maintainer :   LoZ Open Source Ecosystem (https://www.ibm.com/community/z/usergroups/opensource)
#Info/Notes :   Please refer to the instructions first for Building Calico mentioned in wiki( https://github.com/linux-on-ibm-z/docs/wiki/Building-Calico-3.x ).
#               Build and Test logs can be found in $SOURCE_ROOT/logs/.
#               By Default, system tests are turned off. To run system tests for Calico, pass argument "-t" to shell script.
#
#Download build script :   wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Calico/3.31.0/build_calico.sh
#Run build script      :   bash build_calico.sh       #(To only build Calico, provide -h for help)
#                          bash build_calico.sh -t    #(To build Calico and run system tests)
#
#################################################################################################################################################################

USER_IN_GROUP_DOCKER=$(id -nGz $USER | tr '\0' '\n' | grep '^docker$' | wc -l)
set -e
set -o pipefail

PACKAGE_NAME="calico"
PACKAGE_VERSION="v3.31.0"
ETCD_VERSION="v3.5.6"
GOLANG_VERSION="go1.24.9.linux-s390x.tar.gz"
GOBUILD_VERSION="1.24.9-llvm18.1.8-k8s1.33.5"
K8S_VERSION="v1.33.3"
FORCE="false"
TESTS="false"
export SOURCE_ROOT=$(pwd)
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Calico/3.31.0/patch"
GO_INSTALL_URL="https://go.dev/dl/${GOLANG_VERSION}"
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
    rm -rf "$SOURCE_ROOT/$GOLANG_VERSION" "$SOURCE_ROOT/etcd-${ETCD_VERSION}-linux-s390x" "$SOURCE_ROOT/etcd-${ETCD_VERSION}-linux-s390x.tar.gz"
    printf -- '\nCleaned up the artifacts.\n' >>"$LOG_FILE"
}

function configureAndInstall() {
    printf -- '\nConfiguration and Installation started \n'

    # Install go
    cd $SOURCE_ROOT
    export LOG_FILE="$LOGDIR/configuration-$(date +"%F-%T").log"
    printf -- "\nInstalling Go ... \n" | tee -a "$LOG_FILE"
    wget -q $GO_INSTALL_URL
    sudo tar -C /usr/local -xzf $GOLANG_VERSION
    sudo ln -sf /usr/local/go/bin/go /usr/bin/
    sudo ln -sf /usr/local/go/bin/gofmt /usr/bin/

    if [[ "${ID}" != "ubuntu" ]]; then
        sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
        printf -- 'Symlink done for gcc \n'
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

    export PATH=/usr/local/go/bin:$PATH
    export PATH=$PATH:/usr/local/bin
    go version
    # Download `etcd ${ETCD_VERSION}`.
    cd $SOURCE_ROOT
    wget -q --no-check-certificate https://github.com/etcd-io/etcd/releases/download/${ETCD_VERSION}/etcd-${ETCD_VERSION}-linux-s390x.tar.gz
    tar xvf etcd-${ETCD_VERSION}-linux-s390x.tar.gz
    sudo cp -f etcd-${ETCD_VERSION}-linux-s390x/etcd /usr/local/bin

    printenv >>"$LOG_FILE"

    # Exporting Calico ENV to $SOURCE_ROOT/setenv.sh for later use
    cd $SOURCE_ROOT
    cat <<EOF >setenv.sh
#CALICO ENV
export GOPATH=$GOPATH
export PATH=$PATH
export LOGDIR=$LOGDIR
EOF

    # Start docker service
    printf -- "Starting docker service\n"
    sudo service docker start
    sleep 20s

    docker pull calico/go-build:${GOBUILD_VERSION}

    cd $SOURCE_ROOT

    # Clone the Calico repo and apply patches where applicable
    rm -rf $GOPATH/src/github.com/projectcalico/calico
    export CALICO_LOG="$LOGDIR/calico-$(date +"%F-%T").log"
    touch $CALICO_LOG
    printf -- "\nBuilding calico ... \n" | tee -a "$CALICO_LOG"
    git clone -b $PACKAGE_VERSION --depth 1 https://github.com/projectcalico/calico $GOPATH/src/github.com/projectcalico/calico
    cd $GOPATH/src/github.com/projectcalico/calico
    printf -- "\nApplying patch for calico ... \n" | tee -a "$CALICO_LOG"
    curl -s $PATCH_URL/calico.patch | git apply --ignore-whitespace - | tee -a "$CALICO_LOG"

    # Build Calico images
    ARCH=s390x SKIP_PROTOBUF=true make image 2>&1 | tee -a "$CALICO_LOG" 
    ARCH=s390x make -C goldmane image 2>&1 | tee -a "$CALICO_LOG"
    ARCH=s390x make -C whisker-backend image 2>&1 | tee -a "$CALICO_LOG"
    ARCH=s390x make -C felix image 2>&1 | tee -a "$CALICO_LOG" #for felix-test

    # Build Calico binaries
    ARCH=s390x make -C api build 2>&1 | tee -a "$CALICO_LOG"
    ARCH=s390x make bin/helm 2>&1 | tee -a "$CALICO_LOG"

    # Tag docker images
    printf -- "\nTagging images ... \n" | tee -a "$CALICO_LOG"
    docker tag calico/node:latest-s390x quay.io/calico/node:${PACKAGE_VERSION}
    docker tag calico/typha:latest-s390x quay.io/calico/typha:${PACKAGE_VERSION}
    docker tag calico/ctl:latest-s390x quay.io/calico/ctl:${PACKAGE_VERSION}
    docker tag calico/cni:latest-s390x quay.io/calico/cni:${PACKAGE_VERSION}
    docker tag calico/apiserver:latest-s390x quay.io/calico/apiserver:${PACKAGE_VERSION}
    docker tag calico/pod2daemon-flexvol:latest-s390x quay.io/calico/pod2daemon-flexvol:${PACKAGE_VERSION}
    docker tag calico/node-driver-registrar:latest-s390x quay.io/calico/node-driver-registrar:${PACKAGE_VERSION}
    docker tag calico/csi:latest-s390x quay.io/calico/csi:${PACKAGE_VERSION}
    docker tag calico/kube-controllers:latest-s390x quay.io/calico/kube-controllers:${PACKAGE_VERSION}
    docker tag calico/dikastes:latest-s390x quay.io/calico/dikastes:${PACKAGE_VERSION}
    docker tag calico/flannel-migration-controller:latest-s390x quay.io/calico/flannel-migration-controller:${PACKAGE_VERSION}
    docker tag calico/key-cert-provisioner:latest-s390x quay.io/calico/key-cert-provisioner:${PACKAGE_VERSION}
    docker tag calico/goldmane:latest-s390x quay.io/calico/goldmane:${PACKAGE_VERSION}
    docker tag calico/whisker-backend:latest-s390x quay.io/calico/whisker-backend:${PACKAGE_VERSION}
}

function runTest() {
    export KUBECTL_LOG="$LOGDIR/kubectl-$(date +"%F-%T").log"
    touch $KUBECTL_LOG
    printf -- "\nBuilding Kubectl Image for s390x ... \n" | tee -a "$KUBECTL_LOG"

    cd $SOURCE_ROOT
    wget --no-check-certificate $PATCH_URL/Dockerfile
    docker build --build-arg TARGETPLATFORM=linux/s390x --build-arg KUBERNETES_RELEASE=$K8S_VERSION -t rancher/kubectl:"$K8S_VERSION" . 2>&1 | tee -a "$KUBECTL_LOG"

    if [ $(docker images "rancher/kubectl:$K8S_VERSION" | wc -l) == 2 ]; then
        echo "Successfully built rancher/kubectl" | tee -a "$KUBECTL_LOG"
    else
        echo "rancher/kubectl Build FAILED, Stopping further build !!! Check logs at $KUBECTL_LOG" | tee -a "$KUBECTL_LOG"
        exit 1
    fi

    export DIND_LOG="$LOGDIR/dind-$(date +"%F-%T").log"
    touch $DIND_LOG
    source "$SOURCE_ROOT/setenv.sh" || true
    printf -- "\nBuilding dind Image for s390x ... \n" | tee -a "$DIND_LOG"
    rm -rf $GOPATH/src/github.com/projectcalico/dind
    git clone https://github.com/projectcalico/dind $GOPATH/src/github.com/projectcalico/dind 2>&1 | tee -a "$DIND_LOG"
    cd $GOPATH/src/github.com/projectcalico/dind
    # Build the dind
    docker build -t calico/dind -f Dockerfile-s390x . 2>&1 | tee -a "$DIND_LOG"

    if [ $(docker images 'calico/dind:latest' | wc -l) == 2 ]; then
        echo "Successfully built calico/dind" | tee -a "$DIND_LOG"
    else
        echo "calico/dind Build FAILED, Stopping further build !!! Check logs at $DIND_LOG" | tee -a "$DIND_LOG"
        exit 1
    fi


    # Copy ETCD artifact to `calico_test`
    cd $GOPATH/src/github.com/projectcalico/calico/node
    mkdir -p calico_test/pkg
    cp $SOURCE_ROOT/etcd-${ETCD_VERSION}-linux-s390x.tar.gz calico_test/pkg

    # Verifying if all images are built/tagged
    export VERIFY_LOG="$LOGDIR/verify-images-$(date +"%F-%T").log"
    touch $VERIFY_LOG
    printf -- "export VERIFY_LOG=$VERIFY_LOG\n" >>"$SOURCE_ROOT/setenv.sh"
    printf -- "\nVerifying if all needed images are successfully built/downloaded ? ... \n" | tee -a "$VERIFY_LOG"
    cd $SOURCE_ROOT
    echo "Required Docker Images: " >>$VERIFY_LOG
    rm -rf docker_images_expected.txt
    rm -rf docker_images.txt

    cat <<EOF >docker_images_expected.txt
calico/dind:latest
calico/node:latest-s390x
quay.io/calico/node:${PACKAGE_VERSION}
calico/cni:latest-s390x
quay.io/calico/cni:${PACKAGE_VERSION}
calico/felix-test:latest-s390x
calico/typha:latest-s390x
quay.io/calico/typha:${PACKAGE_VERSION}
calico/ctl:latest-s390x
quay.io/calico/ctl:${PACKAGE_VERSION}
calico/pod2daemon-flexvol:latest-s390x
quay.io/calico/pod2daemon-flexvol:${PACKAGE_VERSION}
quay.io/calico/node-driver-registrar:${PACKAGE_VERSION}
quay.io/calico/csi:${PACKAGE_VERSION}
calico/apiserver:latest-s390x
quay.io/calico/apiserver:${PACKAGE_VERSION}
calico/kube-controllers:latest-s390x
quay.io/calico/kube-controllers:${PACKAGE_VERSION}
calico/dikastes:latest-s390x
quay.io/calico/dikastes:${PACKAGE_VERSION}
calico/flannel-migration-controller:latest-s390x
quay.io/calico/flannel-migration-controller:${PACKAGE_VERSION}
calico/key-cert-provisioner:latest-s390x
quay.io/calico/key-cert-provisioner:${PACKAGE_VERSION}
calico/goldmane:latest-s390x
quay.io/calico/goldmane:${PACKAGE_VERSION}
calico/whisker-backend:latest-s390x
quay.io/calico/whisker-backend:${PACKAGE_VERSION}
calico/go-build:${GOBUILD_VERSION}
EOF

    cat docker_images_expected.txt >>$VERIFY_LOG
    docker images --format "{{.Repository}}:{{.Tag}}" >docker_images.txt
    echo "" >>$VERIFY_LOG
    echo "" >>$VERIFY_LOG
    echo "Images present: " >>$VERIFY_LOG
    echo "########################################################################" >>$VERIFY_LOG
    echo "########################################################################" >>$VERIFY_LOG
    cat docker_images.txt >>$VERIFY_LOG
    count=0
    while read image; do
        if ! grep -q $image docker_images.txt; then
            echo ""
            echo "$image" | tee -a "$VERIFY_LOG"
            count=$(expr $count + 1)
        fi
    done <docker_images_expected.txt
    if [ "$count" != "0" ]; then
        echo "" | tee -a "$VERIFY_LOG"
        echo "" | tee -a "$VERIFY_LOG"
        echo "Above $count images need to be present. Check $VERIFY_LOG and the logs of above images/modules in $LOGDIR" | tee -a "$VERIFY_LOG"
        echo "CALICO NODE & TESTS BUILD FAILED !!" | tee -a "$VERIFY_LOG"
        exit 1
    else
        echo "" | tee -a "$VERIFY_LOG"
        echo "" | tee -a "$VERIFY_LOG"
        echo "" | tee -a "$VERIFY_LOG"
        echo "###################-----------------------------------------------------------------------------------------------###################" | tee -a "$VERIFY_LOG"
        echo "                                      All docker images are created as expected." | tee -a "$VERIFY_LOG"
        echo ""
        echo "                                  CALICO NODE & TESTS BUILD COMPLETED SUCCESSFULLY !!" | tee -a "$VERIFY_LOG"
        echo "###################-----------------------------------------------------------------------------------------------###################" | tee -a "$VERIFY_LOG"
    fi
    rm -rf docker_images_expected.txt docker_images.txt

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

    set +e

    cd $GOPATH/src/github.com/projectcalico/calico/node
    ARCH=s390x CALICOCTL_VER=latest CNI_VER=latest-s390x make test_image 2>&1 | tee -a "$TEST_NODE_LOG"
    docker tag calico/test:latest-s390x calico/test:latest

    ARCH=s390x CALICOCTL_VER=latest CNI_VER=latest-s390x make st 2>&1 | tee -a "$TEST_NODE_LOG" || true

    cd $GOPATH/src/github.com/projectcalico/calico/felix
    ARCH=s390x make ut 2>&1 | tee "$TEST_FELIX_LOG" || true

    cd $GOPATH/src/github.com/projectcalico/calico/kube-controllers
    ARCH=s390x make test 2>&1 | tee -a "$TEST_KC_LOG" || true

    cd $GOPATH/src/github.com/projectcalico/calico/calicoctl
    ARCH=s390x make test 2>&1 | tee -a "$TEST_CTL_LOG" || true

    cd $GOPATH/src/github.com/projectcalico/calico/cni-plugin
    ARCH=s390x make test 2>&1 | tee -a "$TEST_CNI_LOG" || true

    cd $GOPATH/src/github.com/projectcalico/calico/confd
    ARCH=s390x make test 2>&1 | tee -a "$TEST_CONFD_LOG" || true

    cd $GOPATH/src/github.com/projectcalico/calico/app-policy
    ARCH=s390x make ut 2>&1 | tee -a "$TEST_APP_LOG" || true

    cd $GOPATH/src/github.com/projectcalico/calico/apiserver
    ARCH=s390x make test 2>&1 | tee -a "$TEST_APISERVER_LOG" || true

    cd $GOPATH/src/github.com/projectcalico/calico/api
    ARCH=s390x make test 2>&1 | tee -a "$TEST_API_LOG" || true

    cd $GOPATH/src/github.com/projectcalico/calico/typha
    ARCH=s390x make ut 2>&1 | tee -a "$TEST_TYPHA_LOG" || true

    cd $GOPATH/src/github.com/projectcalico/calico/pod2daemon
    ARCH=s390x make test 2>&1 | tee -a "$TEST_POD2DAEMON_LOG" || true

    cd $GOPATH/src/github.com/projectcalico/calico/libcalico-go
    ARCH=s390x make ut 2>&1 | tee -a "$TEST_LIBCALGO_LOG" || true

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
    printf -- '\n\nFor information on Getting started with Calico visit: \nhttps://github.com/projectcalico/calico \n\n'
    printf -- '***********************************************************************************************************************************\n'
}

logDetails
prepare

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"rhel-8.10" | "rhel-9.4" | "rhel-9.6")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- "Installing dependencies ... it may take some time.\n"
    sudo yum remove -y podman buildah
    sudo yum install -y yum-utils
    sudo yum-config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
    sudo yum install -y --allowerasing curl git wget tar gcc glibc.s390x docker-ce docker-ce-cli containerd.io make which patch iproute-devel 2>&1 | tee -a "$LOG_FILE"
    export CC=gcc
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"sles-15.6")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- "Installing dependencies ... it may take some time.\n"
    sudo zypper install -y curl git wget tar gcc glibc-devel-static make which patch docker containerd docker-buildx iproute2 2>&1 | tee -a "$LOG_FILE"
    export CC=gcc
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
    
 "ubuntu-22.04" | "ubuntu-24.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- "Installing dependencies ... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg iproute2
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo \
        "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" |
        sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    sudo apt-get update
    sudo apt-get install -y patch git curl tar gcc wget make docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin clang 2>&1 | tee -a "$LOG_FILE"
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
