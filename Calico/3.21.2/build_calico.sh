#!/bin/bash
# © Copyright IBM Corporation 2022.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)

################################################################################################################################################################
#Script     :   build_calico.sh
#Description:   The script builds Calico version v3.21.2 on Linux on IBM Z for RHEL (7.8, 7.9, 8.2, 8.4, 8.5), Ubuntu (18.04, 20.04) and SLES (12 SP5, 15 SP3).
#Maintainer :   LoZ Open Source Ecosystem (https://www.ibm.com/community/z/usergroups/opensource)
#Info/Notes :   Please refer to the instructions first for Building Calico mentioned in wiki( https://github.com/linux-on-ibm-z/docs/wiki/Building-Calico-3.x ).
#               This script doesn't handle Docker installation. Install docker first before proceeding.
#               Build and Test logs can be found in $CURDIR/logs/.
#               By Default, system tests are turned off. To run system tests for Calico, pass argument "-t" to shell script.
#
#Download build script :   wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Calico/3.21.2/build_calico.sh
#Run build script      :   bash build_calico.sh       #(To only build Calico, provide -h for help)
#                          bash build_calico.sh -t    #(To build Calico and run system tests)
#
################################################################################################################################################################

set -e
set -o pipefail

PACKAGE_NAME="calico"
PACKAGE_VERSION="v3.21.2"
ETCD_VERSION="v3.3.7"
GOLANG_VERSION="go1.15.2.linux-s390x.tar.gz"
FORCE="false"
TESTS="false"
CURDIR="$(pwd)"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Calico/3.21.2/patch"
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
    rm -rf "${CURDIR}/${GOLANG_VERSION}"
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

    export PATH=/usr/local/go/bin:$PATH
    export PATH=$PATH:/usr/local/bin

    # Install `etcd ${ETCD_VERSION}`.
    export ETCD_LOG="${LOGDIR}/etcd-$(date +"%F-%T").log"
    touch $ETCD_LOG
    printf -- "\nInstalling etcd ${ETCD_VERSION} ... \n" | tee -a "$ETCD_LOG"
    mkdir -p $GOPATH/src/github.com/coreos
    cd $GOPATH/src/github.com/coreos
    rm -rf etcd
    git clone -b ${ETCD_VERSION} https://github.com/coreos/etcd 2>&1 | tee -a "$ETCD_LOG"
    cd etcd
    export ETCD_UNSUPPORTED_ARCH=s390x
    printf -- "\nBuilding ... \n" 2>&1 | tee -a "$ETCD_LOG"

    # Modify `Dockerfile-release` for s390x
    printf -- "\nDownloading etcd Dockerfile-release.s390x ... \n" | tee -a "$ETCD_LOG"

    curl -o "Dockerfile-release.s390x" $PATCH_URL/Dockerfile-release.s390x
    # Create tarball
    ./build 2>&1 | tee -a "$ETCD_LOG"

    tar -zcvf etcd-${ETCD_VERSION}-linux-s390x.tar.gz -C bin etcd etcdctl

    # Then build etcd image
    BINARYDIR=./bin TAG=quay.io/coreos/etcd ./scripts/build-docker ${ETCD_VERSION} 2>&1 | tee -a "$ETCD_LOG"

    if grep -Fxq "Successfully tagged quay.io/coreos/etcd:${ETCD_VERSION}-s390x" $ETCD_LOG; then
        echo "Successfully built etcd image" | tee -a "$ETCD_LOG"
    else
        echo "etcd image Build FAILED, Stopping further build !!! Check logs at $ETCD_LOG" | tee -a "$ETCD_LOG"
        exit 1
    fi

    printenv >>"$LOG_FILE"

    # Exporting Calico ENV to $CURDIR/setenv.sh for later use
    cd $CURDIR
    cat <<EOF >setenv.sh
#CALICO ENV
export GOPATH=$GOPATH
export PATH=$GOPATH/bin:$PATH
export ETCD_UNSUPPORTED_ARCH=s390x
export LOGDIR=$LOGDIR
EOF

    # Build `bpftool`
    export BPFTOOL_LOG="${LOGDIR}/bpftool-$(date +"%F-%T").log"
    touch $BPFTOOL_LOG
    printf -- "\nBuilding bpftool ... \n" | tee -a "$BPFTOOL_LOG"

    rm -rf $GOPATH/src/github.com/projectcalico/bpftool
    git clone https://github.com/projectcalico/bpftool $GOPATH/src/github.com/projectcalico/bpftool 2>&1 | tee -a "$BPFTOOL_LOG"
    cd $GOPATH/src/github.com/projectcalico/bpftool
    ARCH=s390x VERSION=v5.3 ARCHIMAGE='$(DEFAULTIMAGE)' make image 2>&1 | tee -a "$BPFTOOL_LOG"
    docker tag calico/bpftool:v5.3 calico/bpftool:v5.3-s390x

    export GOBUILD_LOG="${LOGDIR}/go-build-$(date +"%F-%T").log"
    touch $GOBUILD_LOG
    printf -- "\nBuilding go-build ${GOBUILD_VERSION} ... \n" | tee -a "$GOBUILD_LOG"

    # Build go-build v0.59
    rm -rf $GOPATH/src/github.com/projectcalico/go-build
    git clone -b v0.59 https://github.com/projectcalico/go-build $GOPATH/src/github.com/projectcalico/go-build 2>&1 | tee -a "$GOBUILD_LOG"
    cd $GOPATH/src/github.com/projectcalico/go-build
    printf -- "\nApplying patch for go-build Makefile ... \n" | tee -a "$GOBUILD_LOG"
    curl -s $PATCH_URL/go-build.patch | git apply - 2>&1 | tee -a "$GOBUILD_LOG"
    # Then build `calico/go-build-s390x:v0.59` image
    ARCH=s390x VERSION=v0.59 ARCHIMAGE='$(DEFAULTIMAGE)' make image | tee -a "$GOBUILD_LOG"
    if grep -Fxq "Successfully tagged calico/go-build:v0.59" $GOBUILD_LOG; then
        echo "Successfully built calico/go-build:v0.59" | tee -a "$GOBUILD_LOG"
    else
        echo "go-build FAILED, Stopping further build !!! Check logs at $GOBUILD_LOG" | tee -a "$GOBUILD_LOG"
        exit 1
    fi

    # Build Protobuf
    mkdir $GOPATH/tmp
    cd $GOPATH/tmp && wget https://raw.githubusercontent.com/projectcalico/docker-protobuf/master/Dockerfile-s390x
    docker build -t calico/protoc:v0.1-s390x -f Dockerfile-s390x .
    cd $GOPATH
    rm -rf $GOPATH/tmp

    # Clone the repos and apply patches where applicable
    rm -rf $GOPATH/src/github.com/projectcalico/libcalico-go
    rm -rf $GOPATH/src/github.com/projectcalico/confd
    rm -rf $GOPATH/src/github.com/projectcalico/felix
    rm -rf $GOPATH/src/github.com/projectcalico/typha
    rm -rf $GOPATH/src/github.com/projectcalico/kube-controllers
    rm -rf $GOPATH/src/github.com/projectcalico/calicoctl
    rm -rf $GOPATH/src/github.com/projectcalico/app-policy
    rm -rf $GOPATH/src/github.com/projectcalico/pod2daemon
    rm -rf $GOPATH/src/github.com/projectcalico/node
    rm -rf $GOPATH/src/github.com/projectcalico/cni-plugin
    rm -rf $GOPATH/src/github.com/projectcalico/calico
    git clone -b $PACKAGE_VERSION https://github.com/projectcalico/libcalico-go $GOPATH/src/github.com/projectcalico/libcalico-go
    git clone -b release-v3.21 https://github.com/projectcalico/confd $GOPATH/src/github.com/projectcalico/confd

    export CALICOCTL_LOG="${LOGDIR}/calicoctl-$(date +"%F-%T").log"
    touch $CALICOCTL_LOG
    printf -- "\nBuilding calicoctl ... \n" | tee -a "$CALICOCTL_LOG"
    git clone -b $PACKAGE_VERSION https://github.com/projectcalico/calicoctl $GOPATH/src/github.com/projectcalico/calicoctl
    cd $GOPATH/src/github.com/projectcalico/calicoctl
    printf -- "\Applying patch for calicoctl ... \n" | tee -a "$CALICOCTL_LOG"
    curl -s $PATCH_URL/calicoctl.patch | git apply - 2>&1 | tee -a "$CALICOCTL_LOG"
    ARCH=s390x EXTRA_DOCKER_ARGS="-v $(pwd)/../:/go/src/github.com/projectcalico" make image 2>&1 | tee -a "$CALICOCTL_LOG"

    export TYPHA_LOG="${LOGDIR}/typha-$(date +"%F-%T").log"
    touch $TYPHA_LOG
    printf -- "\nBuilding typha ... \n" | tee -a "$TYPHA_LOG"
    git clone -b $PACKAGE_VERSION https://github.com/projectcalico/typha $GOPATH/src/github.com/projectcalico/typha
    cd $GOPATH/src/github.com/projectcalico/typha
    printf -- "\Applying patch for typha ... \n" | tee -a "$TYPHA_LOG"
    curl -s $PATCH_URL/typha.patch | git apply - 2>&1 | tee -a "$TYPHA_LOG"
    ARCH=s390x EXTRA_DOCKER_ARGS="-v $(pwd)/../:/go/src/github.com/projectcalico" make image 2>&1 | tee -a "$TYPHA_LOG"

    export FELIX_LOG="${LOGDIR}/felix-$(date +"%F-%T").log"
    touch $FELIX_LOG
    printf -- "\nBuilding felix ... \n" | tee -a "$FELIX_LOG"
    git clone -b $PACKAGE_VERSION https://github.com/projectcalico/felix $GOPATH/src/github.com/projectcalico/felix
    cd $GOPATH/src/github.com/projectcalico/felix
    printf -- "\Applying patch for felix ... \n" | tee -a "$FELIX_LOG"
    curl -s $PATCH_URL/felix.patch | git apply - 2>&1 | tee -a "$FELIX_LOG"
    wget $PATCH_URL/Dockerfile.test.s390x -P $GOPATH/src/github.com/projectcalico/felix/fv
    cp $GOPATH/src/github.com/projectcalico/felix/fv/Dockerfile.wgtool.amd64 $GOPATH/src/github.com/projectcalico/felix/fv/Dockerfile.wgtool.s390x
    ARCH=s390x EXTRA_DOCKER_ARGS="-v $(pwd)/../:/go/src/github.com/projectcalico" make image 2>&1 | tee -a "$FELIX_LOG"

    export CNI_LOG="${LOGDIR}/cni-$(date +"%F-%T").log"
    touch $CNI_LOG
    printf -- "\nBuilding cni-plugin ... \n" | tee -a "$CNI_LOG"
    git clone -b $PACKAGE_VERSION https://github.com/projectcalico/cni-plugin.git $GOPATH/src/github.com/projectcalico/cni-plugin
    cd $GOPATH/src/github.com/projectcalico/cni-plugin
    printf -- "\Applying patch for cni-plugin ... \n" | tee -a "$CNI_LOG"
    curl -s $PATCH_URL/cni.patch | git apply - 2>&1 | tee -a "$CNI_LOG"
    ARCH=s390x CALICOCTL_VER=latest CNI_VER=latest-s390x EXTRA_DOCKER_ARGS="-v $(pwd)/../:/go/src/github.com/projectcalico" make image 2>&1 | tee -a "$CNI_LOG"

    export NODE_LOG="${LOGDIR}/node-$(date +"%F-%T").log"
    touch $NODE_LOG
    printf -- "\nBuilding node ... \n" | tee -a "$NODE_LOG"
    git clone -b $PACKAGE_VERSION https://github.com/projectcalico/node.git $GOPATH/src/github.com/projectcalico/node
    cd $GOPATH/src/github.com/projectcalico/node
    printf -- "\Applying patch for node ... \n" | tee -a "$NODE_LOG"
    curl -s $PATCH_URL/node.patch | git apply - 2>&1 | tee -a "$NODE_LOG"
    mkdir -p filesystem/bin
    mkdir -p dist
    cp ../felix/bin/calico-felix-s390x ./filesystem/bin/calico-felix
    cp ../calicoctl/bin/calicoctl-linux-s390x ./dist/calicoctl
    ARCH=s390x CALICOCTL_VER=latest CNI_VER=latest-s390x EXTRA_DOCKER_ARGS="-v $(pwd)/../:/go/src/github.com/projectcalico" make image 2>&1 | tee -a "$NODE_LOG"

    export KCTL_LOG="${LOGDIR}/kctl-$(date +"%F-%T").log"
    touch $KCTL_LOG
    printf -- "\nBuilding kube-controllers ... \n" | tee -a "$KCTL_LOG"
    git clone -b $PACKAGE_VERSION https://github.com/projectcalico/kube-controllers $GOPATH/src/github.com/projectcalico/kube-controllers
    cd $GOPATH/src/github.com/projectcalico/kube-controllers
    ARCH=s390x CALICOCTL_VER=latest CNI_VER=latest-s390x EXTRA_DOCKER_ARGS="-v $(pwd)/../:/go/src/github.com/projectcalico" make image 2>&1 | tee -a "$KCTL_LOG"
    
    export APISERVER_LOG="${LOGDIR}/apiserver-$(date +"%F-%T").log"
    touch $APISERVER_LOG
    printf -- "\nBuilding apiserver ... \n" | tee -a "$APISERVER_LOG"
    git clone -b $PACKAGE_VERSION https://github.com/projectcalico/apiserver $GOPATH/src/github.com/projectcalico/apiserver
    cd $GOPATH/src/github.com/projectcalico/apiserver
    curl -s $PATCH_URL/apiserver.patch | git apply - 2>&1 | tee -a "$APISERVER_LOG"
    cp docker-image/Dockerfile.amd64 docker-image/Dockerfile.s390x
    ARCH=s390x CALICOCTL_VER=latest CNI_VER=latest-s390x EXTRA_DOCKER_ARGS="-v $(pwd)/../:/go/src/github.com/projectcalico" make image 2>&1 | tee -a "$APISERVER_LOG"

    export APP_POLICY_LOG="${LOGDIR}/app-policy-$(date +"%F-%T").log"
    touch $APP_POLICY_LOG
    printf -- "\nBuilding app-policy ... \n" | tee -a "$APP_POLICY_LOG"
    git clone -b $PACKAGE_VERSION https://github.com/projectcalico/app-policy $GOPATH/src/github.com/projectcalico/app-policy
    cd $GOPATH/src/github.com/projectcalico/app-policy
    printf -- "\Applying patch for app-policy ... \n" | tee -a "$APP_POLICY_LOG"
    curl -s $PATCH_URL/app-policy.patch | git apply - 2>&1 | tee -a "$APP_POLICY_LOG"
    ARCH=s390x CALICOCTL_VER=latest CNI_VER=latest-s390x EXTRA_DOCKER_ARGS="-v $(pwd)/../:/go/src/github.com/projectcalico" make image 2>&1 | tee -a "$APP_POLICY_LOG"

    export POD_LOG="${LOGDIR}/pod-$(date +"%F-%T").log"
    touch $POD_LOG
    printf -- "\nBuilding pod2daeon ... \n" | tee -a "$POD_LOG"
    sudo rm -rf $GOPATH/src/github.com/projectcalico/pod2daemon
    git clone -b $PACKAGE_VERSION https://github.com/projectcalico/pod2daemon $GOPATH/src/github.com/projectcalico/pod2daemon
    cd $GOPATH/src/github.com/projectcalico/pod2daemon
    curl -s $PATCH_URL/pod2daemon.patch | git apply - 2>&1 | tee -a "$POD_LOG"
    ARCH=s390x CALICOCTL_VER=latest CNI_VER=latest-s390x EXTRA_DOCKER_ARGS="-v $(pwd)/../:/go/src/github.com/projectcalico" make image 2>&1 | tee -a "$POD_LOG"
    docker tag calico/pod2daemon-flexvol:latest-s390x calico/pod2daemon:latest-s390x

    export API_LOG="${LOGDIR}/api-$(date +"%F-%T").log"
    touch $API_LOG
    printf -- "\nBuilding api ... \n" | tee -a "$API_LOG"
    git clone -b release-v3.21 https://github.com/projectcalico/api $GOPATH/src/github.com/projectcalico/api
    cd $GOPATH/src/github.com/projectcalico/api
    ARCH=s390x CALICOCTL_VER=latest CNI_VER=latest-s390x EXTRA_DOCKER_ARGS="-v $(pwd)/../:/go/src/github.com/projectcalico" make build 2>&1 | tee -a "$API_LOG"
    
    #Changing the docker tags
    sed -i '806s/docker/-docker/' $GOPATH/src/github.com/projectcalico/typha/Makefile.common
    sed -i '806s/docker/-docker/' $GOPATH/src/github.com/projectcalico/kube-controllers/Makefile.common
    sed -i '806s/docker/-docker/' $GOPATH/src/github.com/projectcalico/calicoctl/Makefile.common
    sed -i '806s/docker/-docker/' $GOPATH/src/github.com/projectcalico/cni-plugin/Makefile.common
    sed -i '806s/docker/-docker/' $GOPATH/src/github.com/projectcalico/app-policy/Makefile.common
    sed -i '806s/docker/-docker/' $GOPATH/src/github.com/projectcalico/pod2daemon/Makefile.common
    sed -i '806s/docker/-docker/' $GOPATH/src/github.com/projectcalico/node/Makefile.common

    export CALICO_LOG="${LOGDIR}/calico-$(date +"%F-%T").log"
    touch $CALICO_LOG
    printf -- "\nBuilding calico ... \n" | tee -a "$CALICO_LOG"
    git clone -b $PACKAGE_VERSION https://github.com/projectcalico/calico $GOPATH/src/github.com/projectcalico/calico
    cd $GOPATH/src/github.com/projectcalico/calico
    printf -- "\Applying patch for calico ... \n" | tee -a "$CALICO_LOG"
    curl -s $PATCH_URL/calico.patch | git apply - 2>&1 | tee -a "$CALICO_LOG"
	
    # Build dev-images
    ARCH=s390x CALICOCTL_VER=latest CNI_VER=latest-s390x EXTRA_DOCKER_ARGS="-v $(pwd)/../:/go/src/github.com/projectcalico" make dev-image 2>&1 | tee -a "$CALICO_LOG"

    # Tag docker images
    docker tag calico/node:latest-s390x calico/node:${PACKAGE_VERSION}
    docker tag calico/felix:latest-s390x calico/felix:${PACKAGE_VERSION}
    docker tag calico/typha:latest-s390x calico/typha:master-s390x
    docker tag calico/typha:latest-s390x calico/typha:${PACKAGE_VERSION}
    docker tag calico/ctl:latest-s390x calico/ctl:${PACKAGE_VERSION}
    docker tag calico/cni:latest-s390x calico/cni:${PACKAGE_VERSION}
    docker tag calico/apiserver:latest-s390x docker.io/calico/apiserver:${PACKAGE_VERSION}
}

function runTest() {
    export DIND_LOG="${LOGDIR}/dind-$(date +"%F-%T").log"
    touch $DIND_LOG
    source "${CURDIR}/setenv.sh"
    printf -- "\nBuilding dind Image for s390x ... \n" | tee -a "$DIND_LOG"
    rm -rf $GOPATH/src/github.com/projectcalico/dind
    git clone https://github.com/projectcalico/dind $GOPATH/src/github.com/projectcalico/dind 2>&1 | tee -a "$DIND_LOG"
    cd $GOPATH/src/github.com/projectcalico/dind
    # Build the dind
    docker build -t calico/dind -f Dockerfile-s390x . 2>&1 | tee -a "$DIND_LOG"

    if grep -Fxq "Successfully tagged calico/dind:latest" $DIND_LOG; then
        echo "Successfully built calico/dind" | tee -a "$DIND_LOG"
    else
        echo "calico/dind Build FAILED, Stopping further build !!! Check logs at $DIND_LOG" | tee -a "$DIND_LOG"
        exit 1
    fi

    # Build `calico_test`
    export TEST_LOG="${LOGDIR}/testLog-$(date +"%F-%T").log"
    touch $TEST_LOG
    cd $GOPATH/src/github.com/projectcalico/node

    mkdir -p calico_test/pkg
    cp $GOPATH/src/github.com/coreos/etcd/etcd-${ETCD_VERSION}-linux-s390x.tar.gz calico_test/pkg

    # Verifying if all images are built/tagged
    export VERIFY_LOG="${LOGDIR}/verify-images-$(date +"%F-%T").log"
    touch $VERIFY_LOG
    printf -- "\nVerifying if all needed images are successfully built/downloaded ? ... \n" | tee -a "$VERIFY_LOG"
    cd $CURDIR
    echo "Required Docker Images: " >>$VERIFY_LOG
    rm -rf docker_images_expected.txt
    rm -rf docker_images.txt

    cat <<EOF >docker_images_expected.txt
calico/dind:latest
quay.io/coreos/etcd:${ETCD_VERSION}-s390x
calico/node:latest-s390x
calico/node:${PACKAGE_VERSION}
calico/cni:latest-s390x
calico/cni:${PACKAGE_VERSION}
calico/felix:latest-s390x
calico/felix:${PACKAGE_VERSION}
calico/typha:latest-s390x
calico/typha:${PACKAGE_VERSION}
calico/ctl:latest-s390x
calico/ctl:${PACKAGE_VERSION}
calico/go-build:v0.59
EOF

    cat docker_images_expected.txt >>$VERIFY_LOG
    docker images --format "{{.Repository}}:{{.Tag}}" >docker_images.txt
    echo "" >>$VERIFY_LOG
    echo "" >>$VERIFY_LOG
    echo "Images present: " >>$VERIFY_LOG
    echo "########################################################################" >>$VERIFY_LOG
    echo "########################################################################" >>$VERIFY_LOG
    cat docker_images_expected.txt >>$VERIFY_LOG
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
    export TEST_FELIX_LOG="${LOGDIR}/testFelixLog-$(date +"%F-%T").log"
    export TEST_KC_LOG="${LOGDIR}/testKCLog-$(date +"%F-%T").log"
    export TEST_CTL_LOG="${LOGDIR}/testCTLLog-$(date +"%F-%T").log"
    export TEST_CNI_LOG="${LOGDIR}/testCNILog-$(date +"%F-%T").log"
    export TEST_APP_LOG="${LOGDIR}/testAppLog-$(date +"%F-%T").log"
    export TEST_NODE_LOG="${LOGDIR}/testNodeLog-$(date +"%F-%T").log"
    export TEST_APISERVER_LOG="${LOGDIR}/testApiserverLog-$(date +"%F-%T").log"
    
    touch $TEST_FELIX_LOG
    touch $TEST_KC_LOG
    touch $TEST_CTL_LOG
    touch $TEST_CNI_LOG
    touch $TEST_APP_LOG
    touch $TEST_NODE_LOG
    touch $TEST_LOG
    touch $TEST_APISERVER_LOG

    set +e

    cd $GOPATH/src/github.com/projectcalico/node
    ARCH=s390x CALICOCTL_VER=latest CNI_VER=latest-s390x EXTRA_DOCKER_ARGS="-v $(pwd)/../:/go/src/github.com/projectcalico" make test_image 2>&1 | tee -a "$TEST_NODE_LOG"
    docker tag calico/test:latest-s390x calico/test:latest
    ARCH=s390x CALICOCTL_VER=latest CNI_VER=latest-s390x EXTRA_DOCKER_ARGS="-v $(pwd)/../:/go/src/github.com/projectcalico" make st 2>&1 | tee -a "$TEST_NODE_LOG"

    cd $GOPATH/src/github.com/projectcalico/felix
    ARCH=s390x CALICOCTL_VER=latest CNI_VER=latest-s390x EXTRA_DOCKER_ARGS="-v $(pwd)/../:/go/src/github.com/projectcalico" make ut 2>&1 | tee "$TEST_FELIX_LOG"

    cd $GOPATH/src/github.com/projectcalico/kube-controllers
    ARCH=s390x CALICOCTL_VER=latest CNI_VER=latest-s390x EXTRA_DOCKER_ARGS="-v $(pwd)/../:/go/src/github.com/projectcalico" make test 2>&1 | tee -a "$TEST_KC_LOG"

    cd $GOPATH/src/github.com/projectcalico/calicoctl
    ARCH=s390x CALICOCTL_VER=latest CNI_VER=latest-s390x EXTRA_DOCKER_ARGS="-v $(pwd)/../:/go/src/github.com/projectcalico" make test 2>&1 | tee -a "$TEST_CTL_LOG"

    cd $GOPATH/src/github.com/projectcalico/cni-plugin
    ARCH=s390x CALICOCTL_VER=latest CNI_VER=latest-s390x EXTRA_DOCKER_ARGS="-v $(pwd)/../:/go/src/github.com/projectcalico" make test 2>&1 | tee -a "$TEST_CNI_LOG"

    cd $GOPATH/src/github.com/projectcalico/app-policy
    ARCH=s390x CALICOCTL_VER=latest CNI_VER=latest-s390x EXTRA_DOCKER_ARGS="-v $(pwd)/../:/go/src/github.com/projectcalico" make test 2>&1 | tee -a "$TEST_APP_LOG"
    
    cd $GOPATH/src/github.com/projectcalico/apiserver
    ARCH=s390x CALICOCTL_VER=latest CNI_VER=latest-s390x EXTRA_DOCKER_ARGS="-v $(pwd)/../:/go/src/github.com/projectcalico" make test 2>&1 | tee -a "$TEST_APISERVER_LOG"
    

    printf -- "\n------------------------------------------------------------------------------------------------------------------- \n"
    printf -- "\n Please review results of individual test components."
    printf -- "\n Test results for individual components can be found in their respective repository under report folder."
    printf -- "\n Tests for individual components can be run as follows - for example, node component:"
    printf -- "\n source \$CURDIR/setenv.sh"
    printf -- "\n cd \$GOPATH/src/github.com/projectcalico/node"
    printf -- "\n ARCH=s390x CALICOCTL_VER=latest-s390x CNI_VER=latest-s390x EXTRA_DOCKER_ARGS=\"-v $(pwd)/../felix:/go/src/github.com/projectcalico/felix\" make st 2>&1 | tee -a \$LOGDIR/testLog-\$(date +"%%F-%%T").log \n"
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
"ubuntu-18.04" | "ubuntu-20.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- "Installing dependencies ... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y patch git curl tar gcc wget make clang 2>&1 | tee -a "$LOG_FILE"
    sudo wget -O /usr/local/bin/yq.v2 https://github.com/mikefarah/yq/releases/download/2.4.1/yq_linux_s390x
    sudo chmod 755 /usr/local/bin/yq.v2
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"rhel-7.8" | "rhel-7.9" | "rhel-8.2" | "rhel-8.4" | "rhel-8.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- "Installing dependencies ... it may take some time.\n"
    sudo yum install -y curl git wget tar gcc glibc-static.s390x make which patch 2>&1 | tee -a "$LOG_FILE"
    sudo wget -O /usr/local/bin/yq.v2 https://github.com/mikefarah/yq/releases/download/2.4.1/yq_linux_s390x
    sudo chmod 755 /usr/local/bin/yq.v2
    export CC=gcc
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"sles-12.5" | "sles-15.3")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- "Installing dependencies ... it may take some time.\n"
    sudo zypper install -y curl git wget tar gcc glibc-devel-static make which patch 2>&1 | tee -a "$LOG_FILE"
    sudo wget -O /usr/local/bin/yq.v2 https://github.com/mikefarah/yq/releases/download/2.4.1/yq_linux_s390x
    sudo chmod 755 /usr/local/bin/yq.v2
    export CC=gcc
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
