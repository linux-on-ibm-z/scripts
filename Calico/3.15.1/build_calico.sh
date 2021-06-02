#!/bin/bash
# © Copyright IBM Corporation 2020, 2021.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)

################################################################################################################################################################
#Script     :   build_calico.sh
#Description:   The script builds Calico version v3.15.1 on Linux on IBM Z for RHEL (7.6, 7.7, 7.8 8.1, 8.2), Ubuntu (18.04, 20.04) and SLES (12 SP5, 15 SP1).
#Maintainer :   LoZ Open Source Ecosystem (https://www.ibm.com/developerworks/community/groups/community/lozopensource) 
#Info/Notes :   Please refer to the instructions first for Building Calico mentioned in wiki( https://github.com/linux-on-ibm-z/docs/wiki/Building-Calico-3.x ).
#               This script doesn't handle Docker installation. Install docker first before proceeding.
#               Build logs can be found in $HOME/calico-v3.15.1/logs/ . Test logs can be found at $HOME/calico-v3.15.1/logs/testLog-DATE-TIME.log.
#               By Default, system tests are turned off. To run system tests for Calico, pass argument "-t" to shell script.
#
#Download build script :   wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Calico/3.15.1/build_calico.sh
#Run build script      :   bash build_calico.sh       #(To only build Calico, provide -h for help)
#                          bash build_calico.sh -t    #(To build Calico and run system tests)
#               
################################################################################################################################################################

### 1. Determine if Calico system tests are to be run
set -e
set -o pipefail

FORCE="false"
TESTS="false"

# Print the usage message
function printHelp() {
	echo
	echo "Usage: "
	echo "  build_calico.sh  [-d debug] [-y build-without-confirmation] [-t build-with-tests]"
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

PACKAGE_NAME="calico"
CALICO_VERSION="v3.15.1"
ETCD_VERSION="v3.3.7"
GOLANG_VERSION="1.15.10"

cd $HOME

#Check if directory exists
if [ ! -d "${PACKAGE_NAME}-${CALICO_VERSION}" ]; then
   mkdir -p "${PACKAGE_NAME}-${CALICO_VERSION}"
fi

export WORKDIR=${HOME}/${PACKAGE_NAME}-${CALICO_VERSION}
cd $WORKDIR

if [ ! -d "${WORKDIR}/logs" ]; then
   mkdir -p "${WORKDIR}/logs"
fi

export LOGDIR=${WORKDIR}/logs

#Create configuration log file
export CONF_LOG="${LOGDIR}/configuration-$(date +"%F-%T").log"
touch $CONF_LOG

PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Calico/3.15.1/patch"
GO_INSTALL_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Go/1.16.2/build_go.sh"
GO_DEFAULT="$HOME/go"
GO_FLAG="DEFAULT"

source "/etc/os-release"

if command -v "sudo" >/dev/null; then
    printf -- 'Sudo : Yes\n' >>"$CONF_LOG"
else
    printf -- 'Sudo : No \n' >>"$CONF_LOG"
    printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n'
    exit 1
fi

if [[ "$TESTS" == "true" ]]
then
    printf -- "\n TEST Flag is set , System tests will also run after Calico node build is complete. \n" | tee -a "$CONF_LOG"
else
    printf -- "\n System tests won't run for Calico by default \n" | tee -a "$CONF_LOG"
fi

### 2. Install dependencies
DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-18.04" | "ubuntu-20.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$CALICO_VERSION" "$DISTRO" | tee -a "$CONF_LOG"
	printf -- "Installing dependencies ... it may take some time.\n"
	sudo apt-get update 
	sudo apt-get install -y patch git curl tar gcc wget make clang 2>&1 | tee -a "$CONF_LOG"
	;;

"rhel-7.8" | "rhel-8.1" | "rhel-8.2")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$CALICO_VERSION" "$DISTRO" | tee -a "$CONF_LOG"
	printf -- "Installing dependencies ... it may take some time.\n"
	sudo yum install -y curl git wget tar gcc make which patch 2>&1 | tee -a "$CONF_LOG"
	export CC=gcc
	;;

"sles-12.5" | "sles-15.2")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$CALICO_VERSION" "$DISTRO" | tee -a "$CONF_LOG"
	printf -- "Installing dependencies ... it may take some time.\n"
    sudo zypper install -y curl git wget tar gcc glibc-devel-static make which patch 2>&1 | tee -a "$CONF_LOG"
    export CC=gcc
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" | tee -a "$CONF_LOG"
	exit 1
	;;
esac

printf -- "\nChecking if Docker is already present on the system ... \n" | tee -a "$CONF_LOG"
if [ -x "$(command -v docker)" ]; then
    docker --version | grep "Docker version" | tee -a "$CONF_LOG"
    echo "Docker exists !!" | tee -a "$CONF_LOG"
    docker ps 2>&1 | tee -a "$CONF_LOG"
else
    printf -- "\n Please install and run Docker first !! \n" | tee -a "$CONF_LOG"
    exit 1
fi

#### 3. Install `Go` and  `etcd` as prerequisites
if [[ "$FORCE" == "true" ]]; then
	printf -- '\nForce attribute provided hence continuing with install without confirmation message\n' | tee -a "$CONF_LOG"
else
	# Ask user for prerequisite installation
	printf -- "\nAs part of the installation, Go ${GOLANG_VERSION} will be installed. \n" | tee -a "$CONF_LOG"
	while true; do
		read -r -p "Do you want to continue (y/n) ? :  " yn
		case $yn in
		[Yy]*)
			printf -- 'User responded with Yes. \n' >> "$CONF_LOG"
			break
			;;
		[Nn]*) exit ;;
		*) echo "Please provide confirmation to proceed." ;;
		esac
	done
fi

### 3.1 Install `Go ${GOLANG_VERSION}`
printf -- '\nConfiguration and Installation started \n' | tee -a "$CONF_LOG"

# Install go
printf -- "\nInstalling Go ... \n"  | tee -a "$CONF_LOG"
printf -- "\nDownloading Build Script for Go ... \n"  | tee -a "$CONF_LOG"
rm -rf build_go.sh
wget -O build_go.sh $GO_INSTALL_URL 2>&1 | tee -a "$CONF_LOG"
bash build_go.sh -v ${GOLANG_VERSION} 2>&1 | tee -a "$CONF_LOG"
rm -rf build_go.sh

# Set GOPATH if not already set
if [[ -z "${GOPATH}" ]]; then
	printf -- "\nSetting default value for GOPATH \n"
	#Check if go directory exists
	if [ ! -d "$HOME/go" ]; then
		mkdir "$HOME/go"
	fi
	export GOPATH="${GO_DEFAULT}"
else
	printf -- "\nGOPATH already set : Value : %s \n" "$GOPATH"
    if [ ! -d "$GOPATH" ]; then
        mkdir -p "$GOPATH"
    fi
	export GO_FLAG="CUSTOM"
fi

export PATH=$GOPATH/bin:$PATH

#### 3.2 Install `etcd ${ETCD_VERSION}`.
export ETCD_LOG="${LOGDIR}/etcd-$(date +"%F-%T").log"
touch $ETCD_LOG
printf -- "\nInstalling etcd ${ETCD_VERSION} ... \n"  | tee -a "$ETCD_LOG"
mkdir -p $GOPATH/src/github.com/coreos
cd $GOPATH/src/github.com/coreos
rm -rf etcd
git clone -b ${ETCD_VERSION} https://github.com/coreos/etcd 2>&1 | tee -a "$ETCD_LOG"
cd etcd
export ETCD_UNSUPPORTED_ARCH=s390x
printf -- "\nBuilding ... \n"  2>&1 | tee -a "$ETCD_LOG"

## Modify `Dockerfile-release` for s390x
printf -- "\nDownloading etcd Dockerfile-release.s390x ... \n"  | tee -a "$ETCD_LOG"

curl -o "Dockerfile-release.s390x" $PATCH_URL/Dockerfile-release.s390x
# Create tarball
./build 2>&1 | tee -a "$ETCD_LOG"

tar -zcvf etcd-${ETCD_VERSION}-linux-s390x.tar.gz -C bin etcd etcdctl

## Then build etcd image
BINARYDIR=./bin TAG=quay.io/coreos/etcd ./scripts/build-docker ${ETCD_VERSION} 2>&1 | tee -a "$ETCD_LOG"

if grep -Fxq "Successfully tagged quay.io/coreos/etcd:${ETCD_VERSION}-s390x" $ETCD_LOG
then
    echo "Successfully built etcd image" | tee -a "$ETCD_LOG"
else
    echo "etcd image Build FAILED, Stopping further build !!! Check logs at $ETCD_LOG" | tee -a "$ETCD_LOG"
	exit 1
fi

printenv >> "$CONF_LOG"

#Exporting Calico ENV to $HOME/setenv.sh for later use
cd $HOME
cat << EOF > setenv.sh
#CALICO ENV
export GOPATH=$GOPATH
export PATH=$GOPATH/bin:$PATH
export ETCD_UNSUPPORTED_ARCH=s390x
export WORKDIR=$WORKDIR
export LOGDIR=$LOGDIR
EOF

#### 4. Build `calicoctl` and  `calico/node` image

### 4.1 Build `bpftool`

export BPFTOOL_LOG="${LOGDIR}/bpftool-$(date +"%F-%T").log"
touch $BPFTOOL_LOG
printf -- "\nBuilding bpftool ... \n"  | tee -a "$BPFTOOL_LOG"

rm -rf $GOPATH/src/github.com/projectcalico/bpftool
git clone https://github.com/projectcalico/bpftool $GOPATH/src/github.com/projectcalico/bpftool 2>&1 | tee -a "$BPFTOOL_LOG"
cd $GOPATH/src/github.com/projectcalico/bpftool
printf -- "\nDownloading modified Dockerfile.s390x for bpftool ... \n"  | tee -a "$BPFTOOL_LOG"
curl -o "Dockerfile.s390x" $PATCH_URL/Dockerfile.s390x.bpftool
ARCH=s390x make image 2>&1 | tee -a "$BPFTOOL_LOG"

export GOBUILD_LOG="${LOGDIR}/go-build-$(date +"%F-%T").log"
touch $GOBUILD_LOG
printf -- "\nBuilding go-build ${GOBUILD_VERSION} ... \n"  | tee -a "$GOBUILD_LOG"

### 4.2 Build go-build v0.39
rm -rf $GOPATH/src/github.com/projectcalico/go-build
git clone -b v0.39 https://github.com/projectcalico/go-build $GOPATH/src/github.com/projectcalico/go-build 2>&1 | tee -a "$GOBUILD_LOG"
cd $GOPATH/src/github.com/projectcalico/go-build

printf -- "\nDownloading modified Dockerfile.s390x for go-build ... \n"  | tee -a "$GOBUILD_LOG"
curl -o "Dockerfile.s390x" $PATCH_URL/Dockerfile.s390x.v0.39 2>&1 | tee -a "$GOBUILD_LOG"
printf -- "\nApplying patch for go-build Makefile ... \n"  | tee -a "$GOBUILD_LOG"
curl -s $PATCH_URL/Makefile.diff.go-build | git apply - 2>&1 | tee -a "$GOBUILD_LOG"

## Then build `calico/go-build-s390x:v0.39` image
ARCH=s390x VERSION=v0.39 ARCHIMAGE='$(DEFAULTIMAGE)' make image | tee -a "$GOBUILD_LOG"
if grep -Fxq "Successfully tagged calico/go-build:v0.39" $GOBUILD_LOG
then
    echo "Successfully built calico/go-build:v0.39" | tee -a "$GOBUILD_LOG"
else
    echo "go-build FAILED, Stopping further build !!! Check logs at $GOBUILD_LOG" | tee -a "$GOBUILD_LOG"
	exit 1
fi

### Build go-build v0.40
cd $GOPATH
rm -rf $GOPATH/src/github.com/projectcalico/go-build
git clone -b v0.40 https://github.com/projectcalico/go-build $GOPATH/src/github.com/projectcalico/go-build 2>&1 | tee -a "$GOBUILD_LOG"
cd $GOPATH/src/github.com/projectcalico/go-build
printf -- "\nDownloading modified Dockerfile.s390x for go-build v0.40 ... \n"  | tee -a "$GOBUILD_LOG"
curl -o "Dockerfile.s390x" $PATCH_URL/Dockerfile.s390x.v0.40 2>&1 | tee -a "$GOBUILD_LOG"
printf -- "\nApplying patch for go-build Makefile ... \n"  | tee -a "$GOBUILD_LOG"
curl -s $PATCH_URL/Makefile.diff.go-build | git apply - 2>&1 | tee -a "$GOBUILD_LOG"

## Then build `calico/go-build-s390x:v0.40` image
ARCH=s390x VERSION=v0.40 ARCHIMAGE='$(DEFAULTIMAGE)' make image | tee -a "$GOBUILD_LOG"
if grep -Fxq "Successfully tagged calico/go-build:v0.40" $GOBUILD_LOG
then
    echo "Successfully built calico/go-build:v0.40" | tee -a "$GOBUILD_LOG"
else
    echo "go-build FAILED, Stopping further build !!! Check logs at $GOBUILD_LOG" | tee -a "$GOBUILD_LOG"
    exit 1
fi
#docker pull calico/go-build:${GOBUILD_VERSION}

### 4.3 Build `calicoctl` binary and `calico/ctl` image
export CALICOCTL_LOG="${LOGDIR}/calicoctl-$(date +"%F-%T").log"
touch $CALICOCTL_LOG
printf -- "\nBuilding calicoctl ... \n"  | tee -a "$CALICOCTL_LOG"
## Download the source code
rm -rf $GOPATH/src/github.com/projectcalico/calicoctl
git clone -b ${CALICO_VERSION} https://github.com/projectcalico/calicoctl $GOPATH/src/github.com/projectcalico/calicoctl 2>&1 | tee -a "$CALICOCTL_LOG"
cd $GOPATH/src/github.com/projectcalico/calicoctl

## Build the `calicoctl` binary and `calico/ctl` image
ARCH=s390x make image 2>&1 | tee -a "$CALICOCTL_LOG"

if grep -Fxq "Successfully tagged calico/ctl:latest-s390x" $CALICOCTL_LOG
then
    echo "Successfully built calico/ctl" | tee -a "$CALICOCTL_LOG"
else
    echo "calico/ctl Build FAILED, Stopping further build !!! Check logs at $CALICOCTL_LOG" | tee -a "$CALICOCTL_LOG"
	exit 1
fi

### 4.4 Build `Typha`
export TYPHA_LOG="${LOGDIR}/typha-$(date +"%F-%T").log"
touch $TYPHA_LOG
printf -- "\nBuilding typha ... \n"  | tee -a "$TYPHA_LOG"
## Download the source code
rm -rf $GOPATH/src/github.com/projectcalico/typha
git clone -b ${CALICO_VERSION} https://github.com/projectcalico/typha $GOPATH/src/github.com/projectcalico/typha 2>&1 | tee -a "$TYPHA_LOG"
cd $GOPATH/src/github.com/projectcalico/typha 

# Modify `Makefile`, patching Makefile
printf -- "\nApplying patch to Typha Makefile ... \n"  | tee -a "$TYPHA_LOG"
curl -s $PATCH_URL/Makefile.diff.typha | git apply - | tee -a "$TYPHA_LOG"

## Build the binaries and docker image for typha
cd $GOPATH/src/github.com/projectcalico/typha
ARCH=s390x make GO_BUILD_VER=v0.39 image | tee -a "$TYPHA_LOG"

if grep -Fxq "Successfully tagged calico/typha:latest-s390x" $TYPHA_LOG
then
    echo "Successfully built calico/typha" | tee -a "$TYPHA_LOG"
else
    echo "calico/typha Build FAILED, Stopping further build !!! Check logs at $TYPHA_LOG" | tee -a "$TYPHA_LOG"
	exit 1
fi

### 4.5 Build `Felix`
export FELIX_LOG="${LOGDIR}/felix-$(date +"%F-%T").log"
touch $FELIX_LOG
printf -- "\nBuilding felix ... \n"  | tee -a "$FELIX_LOG"
rm -rf $GOPATH/src/github.com/projectcalico/felix
git clone -b ${CALICO_VERSION} https://github.com/projectcalico/felix $GOPATH/src/github.com/projectcalico/felix 2>&1 | tee -a "$FELIX_LOG"
cd $GOPATH/src/github.com/projectcalico/felix

# Modify Makefile, patching the same
printf -- "\nDownloading Dockerfile.s390x for felix ... \n"  | tee -a "$FELIX_LOG"
curl -o "docker-image/Dockerfile.s390x" $PATCH_URL/Dockerfile.s390x.felix 2>&1 | tee -a "$FELIX_LOG"
printf -- "\Applying patch for felix Makefile ... \n"  | tee -a "$FELIX_LOG"
curl -s $PATCH_URL/Makefile.diff.felix | git apply - 2>&1 | tee -a "$FELIX_LOG"
printf -- "\Applying patch for bpf-gpl Makefile ... \n"  | tee -a "$FELIX_LOG"
curl -s $PATCH_URL/Makefile.diff.bpf-gpl | git apply - 2>&1 | tee -a "$FELIX_LOG"

#Building Felix
ARCH=s390x make image 2>&1 | tee -a "$FELIX_LOG"

if grep -Fxq "Successfully tagged calico/felix:latest-s390x" $FELIX_LOG
then
    echo "Successfully built calico/felix" | tee -a "$FELIX_LOG"
else
    echo "calico/felix Build FAILED, Stopping further build !!! Check logs at $FELIX_LOG" | tee -a "$FELIX_LOG"
	exit 1
fi

### 4.6 Build `cni-plugin` binaries and image
export CNI_LOG="${LOGDIR}/cni-plugin-$(date +"%F-%T").log"
touch $CNI_LOG
printf -- "\nBuilding cni-plugin ... \n"  | tee -a "$CNI_LOG"
## Download the source code
rm -rf $GOPATH/src/github.com/projectcalico/cni-plugin
git clone -b ${CALICO_VERSION} https://github.com/projectcalico/cni-plugin.git $GOPATH/src/github.com/projectcalico/cni-plugin 2>&1 | tee -a "$CNI_LOG"
cd $GOPATH/src/github.com/projectcalico/cni-plugin

## Build binaries and image
ARCH=s390x make image 2>&1 | tee -a "$CNI_LOG"

if grep -Fxq "Successfully tagged calico/cni:latest-s390x" $CNI_LOG
then
    echo "Successfully built calico/cni-plugin" | tee -a "$CNI_LOG"
else
    echo "calico/cni-plugin Build FAILED, Stopping further build !!! Check logs at $CNI_LOG" | tee -a "$CNI_LOG"
	exit 1
fi

### 4.7 Build image `calico/node`
export NODE_LOG="${LOGDIR}/node-$(date +"%F-%T").log"
touch $NODE_LOG
printf -- "\nBuilding Calico node ... \n"  | tee -a "$NODE_LOG"
## Download the source
rm -rf $GOPATH/src/github.com/projectcalico/node
git clone -b ${CALICO_VERSION} https://github.com/projectcalico/node $GOPATH/src/github.com/projectcalico/node 2>&1 | tee -a "$NODE_LOG"
cd $GOPATH/src/github.com/projectcalico/node

printf -- "\nModifying go.mod to point to local felix repository" | tee -a "$NODE_LOG"
go mod edit -replace=github.com/projectcalico/felix=../felix 2>&1 | tee -a "$NODE_LOG"

printf -- "\nDownloading Dockerfile.s390x for node ... \n"  | tee -a "$FELIX_LOG"
curl -o "Dockerfile.s390x" $PATCH_URL/Dockerfile.s390x.node 2>&1 | tee -a "$NODE_LOG"
printf -- "\Applying patch for node Makefile ... \n"  | tee -a "$FELIX_LOG"
curl -s $PATCH_URL/Makefile.diff.node | git apply - 2>&1 | tee -a "$NODE_LOG"

### Build `calico/node`
printf -- "\nCreating filesystem/bin and dist directories for keeping binaries ... \n"  | tee -a "$NODE_LOG"
cd $GOPATH/src/github.com/projectcalico/node
mkdir -p filesystem/bin
mkdir -p dist
printf -- "\nCopying felix binaries ... \n"  | tee -a "$NODE_LOG"
cp $GOPATH/src/github.com/projectcalico/felix/bin/calico-felix-s390x $GOPATH/src/github.com/projectcalico/node/filesystem/bin/calico-felix 2>&1 | tee -a "$NODE_LOG"
printf -- "\nCopying calicoctl binaries ... \n"  | tee -a "$NODE_LOG"
cp $GOPATH/src/github.com/projectcalico/calicoctl/bin/calicoctl-linux-s390x $GOPATH/src/github.com/projectcalico/node/dist/calicoctl 2>&1 | tee -a "$NODE_LOG"

printf -- "\nBuilding calico/node Image ... \n"  | tee -a "$NODE_LOG"
ARCH=s390x EXTRA_DOCKER_ARGS="-v `pwd`/../felix:/go/src/github.com/projectcalico/felix" make image 2>&1 | tee -a "$NODE_LOG"

if grep -Fxq "Successfully tagged calico/node:latest-s390x" $NODE_LOG
then
    echo "Successfully built calico/node" | tee -a "$NODE_LOG"
else
    echo "calico/node Build FAILED, Stopping further build !!! Check logs at $NODE_LOG" | tee -a "$NODE_LOG"
	exit 1
fi

### 4.8 Tag docker images
docker tag calico/node:latest-s390x calico/node:${CALICO_VERSION}
docker tag calico/felix:latest-s390x calico/felix:${CALICO_VERSION}
docker tag calico/typha:latest-s390x calico/typha:${CALICO_VERSION}
docker tag calico/ctl:latest-s390x calico/ctl:${CALICO_VERSION}
docker tag calico/cni:latest-s390x calico/cni:${CALICO_VERSION}

#### 5. Calico testcases

### 5.1 Build `calico/dind`
export DIND_LOG="${LOGDIR}/dind-$(date +"%F-%T").log"
touch $DIND_LOG
printf -- "\nBuilding dind Image for s390x ... \n"  | tee -a "$DIND_LOG"
rm -rf $GOPATH/src/github.com/projectcalico/dind
git clone https://github.com/projectcalico/dind $GOPATH/src/github.com/projectcalico/dind 2>&1 | tee -a "$DIND_LOG"
cd $GOPATH/src/github.com/projectcalico/dind
## Build the dind
docker build -t calico/dind -f Dockerfile-s390x . 2>&1 | tee -a "$DIND_LOG"

if grep -Fxq "Successfully tagged calico/dind:latest" $DIND_LOG
then
    echo "Successfully built calico/dind" | tee -a "$DIND_LOG"
else
    echo "calico/dind Build FAILED, Stopping further build !!! Check logs at $DIND_LOG" | tee -a "$DIND_LOG"
	exit 1
fi

### 5.2 Build `calico_test`
export TEST_LOG="${LOGDIR}/testLog-$(date +"%F-%T").log"
touch $TEST_LOG
cd $GOPATH/src/github.com/projectcalico/node

mkdir -p calico_test/pkg
cp $GOPATH/src/github.com/coreos/etcd/etcd-${ETCD_VERSION}-linux-s390x.tar.gz calico_test/pkg

printf -- "\nApplying patch to Dockerfile.s390x.calico_test ... \n"  | tee -a "$TEST_LOG"
curl -s $PATCH_URL/Dockerfile.s390x.calico_test.diff | git apply - 2>&1 | tee -a "$TEST_LOG"

printf -- "\nApplying patch to workload Dockerfile.s390x ... \n"  | tee -a "$TEST_LOG"
curl -s $PATCH_URL/Dockerfile.s390x.workload.diff | git apply - 2>&1 | tee -a "$TEST_LOG"

### 5.3 Run the test cases
#Verifying if all images are built/tagged
export VERIFY_LOG="${LOGDIR}/verify-images-$(date +"%F-%T").log"
touch $VERIFY_LOG
printf -- "\nVerifying if all needed images are successfully built/downloaded ? ... \n"  | tee -a "$VERIFY_LOG"
cd $WORKDIR
echo "Required Docker Images: " >> $VERIFY_LOG
rm -rf docker_images_expected.txt
rm -rf docker_images.txt

cat <<EOF > docker_images_expected.txt
calico/dind:latest
quay.io/coreos/etcd:${ETCD_VERSION}-s390x
calico/node:latest-s390x
calico/node:${CALICO_VERSION}
calico/cni:latest-s390x
calico/cni:${CALICO_VERSION}
calico/felix:latest-s390x
calico/felix:${CALICO_VERSION}
calico/typha:latest-s390x
calico/typha:${CALICO_VERSION}
calico/ctl:latest-s390x
calico/ctl:${CALICO_VERSION}
calico/go-build:v0.39
calico/go-build:v0.40
EOF

cat docker_images_expected.txt >> $VERIFY_LOG
docker images --format "{{.Repository}}:{{.Tag}}" > docker_images.txt
echo "" >> $VERIFY_LOG
echo "" >> $VERIFY_LOG
echo "Images present: " >> $VERIFY_LOG
echo "########################################################################" >> $VERIFY_LOG
echo "########################################################################" >> $VERIFY_LOG
cat docker_images_expected.txt >> $VERIFY_LOG
count=0
while read image; do
  if ! grep -q $image docker_images.txt; then
  echo ""
  echo "$image" | tee -a "$VERIFY_LOG"
  count=`expr $count + 1`
  fi
done < docker_images_expected.txt
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
##########################################################################################################################################################
##########################################################################################################################################################
#                                              CALICO NODE & TESTS BUILD COMPLETED SUCCESSFULLY                                                          #
##########################################################################################################################################################
##########################################################################################################################################################

## 5.5 Execute test cases(Optional)
#Will only run if arg "-t" is passed to shell script
if [[ "$TESTS" == "true" ]]
then
	set +e
    printf -- "##############-----------------------------------------------------------------------------------------------############## \n" | tee -a "$TEST_LOG" 
    printf -- "                             TEST Flag is set , Running system tests now. \n" | tee -a "$TEST_LOG" 
    printf -- "                            Testlogs are saved in $TEST_LOG \n" | tee -a "$TEST_LOG" 
    printf -- "##############-----------------------------------------------------------------------------------------------############## \n" | tee -a "$TEST_LOG" 
    cd $GOPATH/src/github.com/projectcalico/node
    ARCH=s390x CALICOCTL_VER=latest-s390x CNI_VER=latest-s390x EXTRA_DOCKER_ARGS="-v `pwd`/../felix:/go/src/github.com/projectcalico/felix" make st 2>&1 | tee -a "$TEST_LOG"
    if tail -n 30 "$TEST_LOG" | grep -q "OK (SKIP=9)"; then
        printf -- "\n                            All tests have passed !!!\n" | tee -a "$TEST_LOG"
    else
        printf -- "\n                            There are tests case failures!!! \n" | tee -a "$TEST_LOG"
        printf -- "\n                            To rerun Calico tests, run the following commands ... \n"
        printf -- "\n                            Test logs will be saved in ${LOGDIR}/testLog-DATE-TIME.log  ## \n" | tee -a "$TEST_LOG"
        printf -- "\n------------------------------------------------------------------------------------------------------------------- \n" | tee -a "$TEST_LOG" 
        printf -- "\n                            source \$HOME/setenv.sh \n"
        printf -- "                              cd \$GOPATH/src/github.com/projectcalico/node \n"
		printf -- "                              ARCH=s390x CALICOCTL_VER=latest-s390x CNI_VER=latest-s390x EXTRA_DOCKER_ARGS=\"-v `pwd`/../felix:/go/src/github.com/projectcalico/felix\" make st 2>&1 | tee -a \$LOGDIR/testLog-\$(date +"%%F-%%T").log \n"
        printf -- "\n------------------------------------------------------------------------------------------------------------------- \n" | tee -a "$TEST_LOG" 
    fi   
else
    set +x
    cd $GOPATH
    printf -- "\n------------------------------------------------------------------------------------------------------------------- \n" | tee -a "$TEST_LOG" 
    printf -- "       System tests won't run for Calico by default as \"-t\" was not passed to this script in beginning. \n" | tee -a "$TEST_LOG" 
    printf -- "\n------------------------------------------------------------------------------------------------------------------- \n" | tee -a "$TEST_LOG" 
    printf -- " \n" | tee -a "$TEST_LOG" 
    printf -- " \n" | tee -a "$TEST_LOG" 
    printf -- "                        To run Calico system tests, run the following commands now: \n" | tee -a "$TEST_LOG"
    printf -- "                        Test logs are saved in ${LOGDIR}/testLog-DATE-TIME.log  ## \n" | tee -a "$TEST_LOG" 
    printf -- "\n------------------------------------------------------------------------------------------------------------------- \n" | tee -a "$TEST_LOG" 
	printf -- "                       source \$HOME/setenv.sh \n" | tee -a "$TEST_LOG" 
    printf -- "                       cd \$GOPATH/src/github.com/projectcalico/node \n" | tee -a "$TEST_LOG" 
	printf -- "                       ARCH=s390x CALICOCTL_VER=latest-s390x CNI_VER=latest-s390x EXTRA_DOCKER_ARGS=\"-v `pwd`/../felix:/go/src/github.com/projectcalico/felix\" make st 2>&1 | tee -a \$LOGDIR/testLog-\$(date +"%%F-%%T").log \n"
    printf -- "\n------------------------------------------------------------------------------------------------------------------- \n" | tee -a "$TEST_LOG" 
fi
