#!/bin/bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)

################################################################################################################################################################
#Script     :   build_Calico.sh
#Description:   The script builds Calico version v3.8.1 on Linux on IBM Z for Rhel(7.5, 7.6), Ubuntu(16.04, 18.04, 19.04) and SLES(12SP4, 15, 15 SP1).
#Maintainer :   LoZ Open Source Ecosystem (https://www.ibm.com/developerworks/community/groups/community/lozopensource) 
#Info/Notes :   Please refer to the instructions first for Building Calico mentioned in wiki( https://github.com/linux-on-ibm-z/docs/wiki/Building-Calico-3.x ).
#               This script doesn't handle Docker installation. Install docker first before proceeding.
#               Build logs can be found in $HOME/Calico_v3.8.1/logs/ . Test logs can be found at $HOME/Calico_v3.8.1/logs/testLog-DATE-TIME.log.
#               By Default, system tests are turned off. To run system tests for Calico, pass argument "-t" to shell script.
#
#
#Download build script :   wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Calico/3.8.1/build_Calico.sh
#Run build script      :   bash build_Calico.sh       #(To only build Calico, provide -h for help)
#                          bash build_Calico.sh -t    #(To build Calico and run system tests)
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
	echo "  build_Calico.sh  [-d debug] [-y build-without-confirmation] [-t build-with-tests]"
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

NAME_PACKAGE="Calico"
VERSION_PACKAGE="v3.8.1"
CALICO_VERSION="3.8.1"
ETCD_VERSION="3.3.7"
GOBUILD_VERSION="0.20"
BIRD_VERSION="0.3.3"

cd $HOME
#Check if directory exists
if [ ! -d "${NAME_PACKAGE}_${VERSION_PACKAGE}" ]; then
   mkdir -p "${NAME_PACKAGE}_${VERSION_PACKAGE}"
fi
export WORKDIR=${HOME}/${NAME_PACKAGE}_${VERSION_PACKAGE}
cd $WORKDIR

if [ ! -d "${WORKDIR}/logs" ]; then
   mkdir -p "${WORKDIR}/logs"
fi
export LOGDIR=${WORKDIR}/logs
#Create configuration log file
export CONF_LOG="${LOGDIR}/configuration-$(date +"%F-%T").log"
touch $CONF_LOG
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Calico/${CALICO_VERSION}/patch"
GO_INSTALL_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Go/1.12.5/build_go.sh"
GO_DEFAULT="$HOME/go"
GO_FLAG="DEFAULT"

if [ -f "/etc/os-release" ]; then
    source "/etc/os-release"
else
    cat /etc/redhat-release >>"${CONF_LOG}"
    ID="rhel"
    VERSION_ID="6.x"
    PRETTY_NAME="Red Hat Enterprise Linux 6.x"
fi

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
"ubuntu-16.04" | "ubuntu-18.04" | "ubuntu-19.04")
	printf -- "Installing %s %s for %s \n" "$NAME_PACKAGE" "$VERSION_PACKAGE" "$DISTRO" | tee -a "$CONF_LOG"
	printf -- "Installing dependencies . . .  it may take some time.\n"
	sudo apt-get update 
	sudo apt-get install -y patch git curl tar gcc wget make 2>&1 | tee -a "$CONF_LOG"
	;;

"rhel-7.5" | "rhel-7.6")
	printf -- "Installing %s %s for %s \n" "$NAME_PACKAGE" "$VERSION_PACKAGE" "$DISTRO" | tee -a "$CONF_LOG"
	printf -- "Installing dependencies . . .  it may take some time.\n"
	sudo yum install -y curl git wget tar gcc glibc-static.s390x make which patch 2>&1 | tee -a "$CONF_LOG"
	export CC=gcc
	;;

"sles-12.4" | "sles-15" | "sles-15.1")
	printf -- "Installing %s %s for %s \n" "$NAME_PACKAGE" "$VERSION_PACKAGE" "$DISTRO" | tee -a "$CONF_LOG"
	printf -- "Installing dependencies . . .  it may take some time.\n"
    sudo zypper install -y curl git wget tar gcc glibc-devel-static make which patch 2>&1 | tee -a "$CONF_LOG"
    export CC=gcc
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" | tee -a "$CONF_LOG"
	exit 1
	;;
esac


printf -- "\nChecking if Docker is already present on the system . . . \n" | tee -a "$CONF_LOG"
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
	printf -- 'Force attribute provided hence continuing with install without confirmation message\n' | tee -a "$CONF_LOG"
else
	# Ask user for prerequisite installation
	printf -- "\nAs part of the installation, Go 1.11.4 will be installed. \n" | tee -a "$CONF_LOG"
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

### 3.1 Install `Go 1.11.4`
printf -- '\nConfiguration and Installation started \n' | tee -a "$CONF_LOG"

# Install go
printf -- "\nInstalling Go . . . \n"  | tee -a "$CONF_LOG"
printf -- "\nDownloading Build Script for Go . . . \n"  | tee -a "$CONF_LOG"
rm -rf build_go.sh
wget -O build_go.sh $GO_INSTALL_URL 2>&1 | tee -a "$CONF_LOG"
bash build_go.sh -v 1.11.4 2>&1 | tee -a "$CONF_LOG"
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


### 3.2 Install `etcd v${ETCD_VERSION}`.
printf -- "\nInstalling etcd v${ETCD_VERSION} . . . \n"  | tee -a "$CONF_LOG"
cd $GOPATH 
mkdir -p $GOPATH/src/github.com/coreos
mkdir -p $GOPATH/etcd_temp
cd $GOPATH/src/github.com/coreos
rm -rf etcd
git clone https://github.com/coreos/etcd 2>&1 | tee -a "$CONF_LOG"
cd etcd
git checkout v${ETCD_VERSION} 2>&1 | tee -a "$CONF_LOG"
export ETCD_DATA_DIR=$GOPATH/etcd_temp
export ETCD_UNSUPPORTED_ARCH=s390x
printf -- "\nBuilding . . . \n"  2>&1 | tee -a "$CONF_LOG"
./build

printenv >> "$CONF_LOG"

#Exporting Calico ENV to $HOME/setenv.sh for later use
cd $HOME
cat << EOF > setenv.sh
#CALICO ENV
export GOPATH=$GOPATH
export PATH=$GOPATH/bin:$PATH
export ETCD_DATA_DIR=$GOPATH/etcd_temp
export ETCD_UNSUPPORTED_ARCH=s390x
export WORKDIR=$WORKDIR
export LOGDIR=$LOGDIR
EOF

#### 4. Build `calicoctl` and  `calico/node` image
export GOBUILD_LOG="${LOGDIR}/go-build-$(date +"%F-%T").log"
touch $GOBUILD_LOG
printf -- "\nBuilding go-build . . . \n"  | tee -a "$GOBUILD_LOG"
### 4.1 Build `go-build`
##This builds a docker image calico/go-build that is used to build other components
rm -rf $GOPATH/src/github.com/projectcalico/go-build
git clone https://github.com/projectcalico/go-build $GOPATH/src/github.com/projectcalico/go-build 2>&1 | tee -a "$GOBUILD_LOG"
cd $GOPATH/src/github.com/projectcalico/go-build
git checkout v${GOBUILD_VERSION} 2>&1 | tee -a "$GOBUILD_LOG"

## Then  build `calico/go-build-s390x` image
ARCH=s390x make image 2>&1 | tee -a "$GOBUILD_LOG"
if grep -Fxq "Successfully tagged calico/go-build:latest-s390x" $GOBUILD_LOG
then
    echo "Successfully built calico/go-build" | tee -a "$GOBUILD_LOG"
else
    echo "go-build FAILED, Stopping further build !!! Check logs at $GOBUILD_LOG" | tee -a "$GOBUILD_LOG"
	exit 1
fi

#docker tag calico/go-build:latest-s390x calico/go-build-s390x:latest 
docker tag calico/go-build:latest-s390x calico/go-build:latest
docker tag calico/go-build:latest-s390x calico/go-build:v${GOBUILD_VERSION}

### 4.2 Build `calicoctl` binary and `calico/ctl` image
export CALICOCTL_LOG="${LOGDIR}/calicoctl-$(date +"%F-%T").log"
touch $CALICOCTL_LOG
printf -- "\nBuilding calicoctl . . . \n"  | tee -a "$CALICOCTL_LOG"
## Download the source code
rm -rf $GOPATH/src/github.com/projectcalico/calicoctl
git clone https://github.com/projectcalico/calicoctl $GOPATH/src/github.com/projectcalico/calicoctl 2>&1 | tee -a "$CALICOCTL_LOG"
cd $GOPATH/src/github.com/projectcalico/calicoctl 
git checkout v${CALICO_VERSION} 2>&1 | tee -a "$CALICOCTL_LOG"

## Build the `calicoctl` binary and `calico/ctl` image
ARCH=s390x make calico/ctl 2>&1 | tee -a "$CALICOCTL_LOG"

if grep -Fxq "Successfully tagged calico/ctl:latest-s390x" $CALICOCTL_LOG
then
    echo "Successfully built calico/ctl" | tee -a "$CALICOCTL_LOG"
else
    echo "calico/ctl Build FAILED, Stopping further build !!! Check logs at $CALICOCTL_LOG" | tee -a "$CALICOCTL_LOG"
	exit 1
fi


### 4.3 Build `bird`
export BIRD_LOG="${LOGDIR}/bird-$(date +"%F-%T").log"
touch $BIRD_LOG
printf -- "\nBuilding bird . . . \n"  | tee -a "$BIRD_LOG"
## Download the source code
sudo rm -rf $GOPATH/src/github.com/projectcalico/bird
git clone https://github.com/projectcalico/bird $GOPATH/src/github.com/projectcalico/bird 2>&1 | tee -a "$BIRD_LOG"
cd $GOPATH/src/github.com/projectcalico/bird 
git checkout v${BIRD_VERSION} 2>&1 | tee -a "$BIRD_LOG"

## Run `build.sh` to build 3 executable files (in `dist/s390x/`)
ARCH=s390x ./build.sh 2>&1 | tee -a "$BIRD_LOG"
if [[ "$(docker images -q birdbuild-s390x:latest 2> /dev/null)" == "" ]]; then
  echo "Bird build FAILED, Stopping further build !!! Check logs at $BIRD_LOG" | tee -a "$BIRD_LOG"
  exit 1
else
  echo "Successfully built bird module." | tee -a "$BIRD_LOG"
fi
## Tag calico/bird image
docker tag birdbuild-s390x:latest calico/bird:v${BIRD_VERSION}-s390x
docker tag birdbuild-s390x:latest calico/bird:latest

                   
### 4.4 Build `Typha`
export TYPHA_LOG="${LOGDIR}/typha-$(date +"%F-%T").log"
touch $TYPHA_LOG
printf -- "\nBuilding typha . . . \n"  | tee -a "$TYPHA_LOG"
## Download the source code
rm -rf $GOPATH/src/github.com/projectcalico/typha
git clone https://github.com/projectcalico/typha $GOPATH/src/github.com/projectcalico/typha 2>&1 | tee -a "$TYPHA_LOG"
cd $GOPATH/src/github.com/projectcalico/typha 
git checkout v${CALICO_VERSION} 2>&1 | tee -a "$TYPHA_LOG"

# Modify `Makefile`, patching Makefile
printf -- "\nDownloading patch for typha Makefile . . . \n"  | tee -a "$TYPHA_LOG"
curl  -o "typha_makefile.diff" $PATCH_URL/typha_makefile.diff 2>&1 | tee -a "$TYPHA_LOG"
printf -- "\nApplying patch to Makefile . . . \n"  | tee -a "$$TYPHA_LOG"
patch --ignore-whitespace Makefile typha_makefile.diff 2>&1 | tee -a "$TYPHA_LOG"
rm -rf typha_makefile.diff

## Build the binaries and docker image for typha
cd $GOPATH/src/github.com/projectcalico/typha
ARCH=s390x make calico/typha 2>&1 | tee -a "$TYPHA_LOG"

if grep -Fxq "Successfully tagged calico/typha:latest-s390x" $TYPHA_LOG
then
    echo "Successfully built calico/typha" | tee -a "$TYPHA_LOG"
else
    echo "calico/typha Build FAILED, Stopping further build !!! Check logs at $TYPHA_LOG" | tee -a "$TYPHA_LOG"
	exit 1
fi

### 4.5 Build `felix`
## To build `felix` it  needs `felixbackend.pb.go` that is generated by a docker image `calico/protoc`. Let's first built this image.
export PROTO_LOG="${LOGDIR}/docker-protobuf-$(date +"%F-%T").log"
touch $PROTO_LOG
printf -- "\nBuilding docker-protobuf . . . \n"  | tee -a "$PROTO_LOG"
rm -rf $GOPATH/src/github.com/projectcalico/docker-protobuf
git clone https://github.com/tigera/docker-protobuf $GOPATH/src/github.com/projectcalico/docker-protobuf 2>&1 | tee -a "$PROTO_LOG"
cd  $GOPATH/src/github.com/projectcalico/docker-protobuf

## Modify `Dockerfile-s390x`, patching the same
printf -- "\nDownloading patch for docker-protobuf Dockerfile-s390x . . . \n"  | tee -a "$PROTO_LOG"
curl  -o "protobuf_dockerfile.diff" $PATCH_URL/protobuf_dockerfile.diff 2>&1 | tee -a "$PROTO_LOG"
printf -- "\nApplying patch to Dockerfile-s390x . . . \n"  | tee -a "$PROTO_LOG"
patch Dockerfile-s390x protobuf_dockerfile.diff 2>&1 | tee -a "$PROTO_LOG"
rm -rf protobuf_dockerfile.diff

## Build and tag docker image `calico/protoc-s390x`
docker build -t calico/protoc-s390x -f Dockerfile-s390x . 2>&1 | tee -a "$PROTO_LOG"
if grep -Fxq "Successfully tagged calico/protoc-s390x:latest" $PROTO_LOG
then
    echo "Successfully built calico/protoc-s390x" | tee -a "$PROTO_LOG"
else
    echo "calico/protoc Build FAILED, Stopping further build !!! Check logs at $PROTO_LOG" | tee -a "$PROTO_LOG"
	exit 1
fi

docker tag calico/protoc-s390x:latest calico/protoc:latest-s390x
docker tag calico/protoc-s390x:latest calico/protoc:v0.1-s390x

### Build `felix`
export FELIX_LOG="${LOGDIR}/felix-$(date +"%F-%T").log"
touch $FELIX_LOG
printf -- "\nBuilding felix . . . \n"  | tee -a "$FELIX_LOG"
rm -rf $GOPATH/src/github.com/projectcalico/felix
git clone https://github.com/projectcalico/felix $GOPATH/src/github.com/projectcalico/felix 2>&1 | tee -a "$FELIX_LOG"
cd $GOPATH/src/github.com/projectcalico/felix
git checkout v${CALICO_VERSION} 2>&1 | tee -a "$FELIX_LOG"

# Modify Makefile, patching the same
printf -- "\nDownloading patch for felix Makefile . . . \n"  | tee -a "$FELIX_LOG"
curl  -o "felix_makefile.diff" $PATCH_URL/felix_makefile.diff 2>&1 | tee -a "$FELIX_LOG"
printf -- "\nApplying patch to Makefile . . . \n"  | tee -a "$FELIX_LOG"
patch Makefile felix_makefile.diff 2>&1 | tee -a "$FELIX_LOG"
rm -rf felix_makefile.diff

## Build the felix binaries
cd $GOPATH/src/github.com/projectcalico/felix

# Create bpf-clang-builder.Dockerfile.s390x file
printf -- "\nDownloading  bpf-clang-builder.Dockerfile.s390x file . . . \n"  | tee -a "$FELIX_LOG"
curl  -o "bpf-clang-builder.Dockerfile.s390x" $PATCH_URL/bpf-clang-builder.Dockerfile.s390x 2>&1 | tee -a "$FELIX_LOG"

cp bpf-clang-builder.Dockerfile.s390x docker-build-images/
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
printf -- "\nBuilding cni-plugin . . . \n"  | tee -a "$CNI_LOG"
## Download the source code
sudo mkdir -p /opt/cni/bin 2>&1 | tee -a "$CNI_LOG"
rm -rf $GOPATH/src/github.com/projectcalico/cni-plugin
git clone https://github.com/projectcalico/cni-plugin.git $GOPATH/src/github.com/projectcalico/cni-plugin 2>&1 | tee -a "$CNI_LOG"
cd $GOPATH/src/github.com/projectcalico/cni-plugin
git checkout v${CALICO_VERSION} 2>&1 | tee -a "$CNI_LOG"

## Build binaries and image
ARCH=s390x make image 2>&1 | tee -a "$CNI_LOG"

if grep -Fxq "Successfully tagged calico/cni:latest-s390x" $CNI_LOG
then
    echo "Successfully built calico/cni-plugin" | tee -a "$CNI_LOG"
else
    echo "calico/cni-plugin Build FAILED, Stopping further build !!! Check logs at $CNI_LOG" | tee -a "$CNI_LOG"
	exit 1
fi

printf -- "\nCopying cni-plugin binaries to /opt/cni/bin . . . \n"  | tee -a "$CNI_LOG"
sudo cp bin/s390x/* /opt/cni/bin 2>&1 | tee -a "$CNI_LOG"
docker tag calico/cni:latest-s390x calico/cni:latest
docker tag calico/cni:latest quay.io/calico/cni-s390x:v${CALICO_VERSION}
docker tag calico/cni:latest-s390x calico/cni:v${CALICO_VERSION}


### 4.7 Build image `calico/node`
export NODE_LOG="${LOGDIR}/node-$(date +"%F-%T").log"
touch $NODE_LOG
printf -- "\nBuilding Calico node . . . \n"  | tee -a "$NODE_LOG"
## Download the source
rm -rf $GOPATH/src/github.com/projectcalico/node
git clone https://github.com/projectcalico/node $GOPATH/src/github.com/projectcalico/node 2>&1 | tee -a "$NODE_LOG"
cd $GOPATH/src/github.com/projectcalico/node
git checkout v${CALICO_VERSION} 2>&1 | tee -a "$NODE_LOG"

# Modify `Makefile`, patching the same
printf -- "\nDownloading patch for node Makefile . . . \n"  | tee -a "$NODE_LOG"
curl  -o "node_makefile.diff" $PATCH_URL/node_makefile.diff 2>&1 | tee -a "$NODE_LOG"
printf -- "\nApplying patch to Makefile . . . \n"  | tee -a "$NODE_LOG"
patch Makefile node_makefile.diff 2>&1 | tee -a "$NODE_LOG"
rm -rf node_makefile.diff


# Modify `Dockerfile.s390x`, patching the same
printf -- "\nDownloading patch for node Dockerfile.s390x . . . \n"  | tee -a "$NODE_LOG"
curl  -o "node_dockerfile.diff" $PATCH_URL/node_dockerfile.diff 2>&1 | tee -a "$NODE_LOG"
printf -- "\nApplying patch to Dockerfile.s390x . . . \n"  | tee -a "$NODE_LOG"
patch Dockerfile.s390x node_dockerfile.diff 2>&1 | tee -a "$NODE_LOG"
rm -rf node_dockerfile.diff

### Build `calico/node`
printf -- "\nCreating filesystem/bin and dist directories for keeping binaries . . . \n"  | tee -a "$NODE_LOG"
cd $GOPATH/src/github.com/projectcalico/node
mkdir -p filesystem/bin
mkdir -p dist
printf -- "\nCopying bird binaries . . . \n"  | tee -a "$NODE_LOG"
cp $GOPATH/src/github.com/projectcalico/bird/dist/s390x/* $GOPATH/src/github.com/projectcalico/node/filesystem/bin 2>&1 | tee -a "$NODE_LOG"
printf -- "\nCopying felix binaries . . . \n"  | tee -a "$NODE_LOG"
cp $GOPATH/src/github.com/projectcalico/felix/bin/calico-felix-s390x $GOPATH/src/github.com/projectcalico/node/filesystem/bin/calico-felix 2>&1 | tee -a "$NODE_LOG"
printf -- "\nCopying calicoctl binaries . . . \n"  | tee -a "$NODE_LOG"
cp $GOPATH/src/github.com/projectcalico/calicoctl/bin/calicoctl-linux-s390x $GOPATH/src/github.com/projectcalico/node/dist/calicoctl 2>&1 | tee -a "$NODE_LOG"

printf -- "\nBuilding calico/node Image . . . \n"  | tee -a "$NODE_LOG"
ARCH=s390x make calico/node 2>&1 | tee -a "$NODE_LOG"

if grep -Fxq "Successfully tagged calico/node:latest-s390x" $NODE_LOG
then
    echo "Successfully built calico/node" | tee -a "$NODE_LOG"
else
    echo "calico/node Build FAILED, Stopping further build !!! Check logs at $NODE_LOG" | tee -a "$NODE_LOG"
	exit 1
fi

docker tag calico/node:latest-s390x quay.io/calico/node-s390x:v${CALICO_VERSION}
docker tag calico/node:latest-s390x calico/node
docker tag calico/node:latest-s390x calico/node:v${CALICO_VERSION}


#### 5. Calico testcases
### 5.1 Build `etcd`
export ETCD_LOG="${LOGDIR}/etcd-$(date +"%F-%T").log"
touch $ETCD_LOG
printf -- "\nBuilding etcd Image . . . \n"  | tee -a "$ETCD_LOG"
rm -rf $GOPATH/src/github.com/projectcalico/etcd
cd $GOPATH/src/github.com/projectcalico/
git clone https://github.com/coreos/etcd 2>&1 | tee -a "$ETCD_LOG"
cd etcd 
git checkout v${ETCD_VERSION} 2>&1 | tee -a "$ETCD_LOG"

## Modify `Dockerfile-release` for s390x
printf -- "\nDownloading patch for etcd Dockerfile-release . . . \n"  | tee -a "$ETCD_LOG"
curl  -o "etcd_dockerfile.diff" $PATCH_URL/etcd_dockerfile.diff 2>&1 | tee -a "$ETCD_LOG"
printf -- "\nApplying patch to Dockerfile-release . . . \n"  | tee -a "$ETCD_LOG"
patch Dockerfile-release etcd_dockerfile.diff 2>&1 | tee -a "$ETCD_LOG"
rm -rf etcd_dockerfile.diff

## Then build etcd and image
./build 2>&1 | tee -a "$ETCD_LOG"
docker build -f Dockerfile-release  -t quay.io/coreos/etcd . 2>&1 | tee -a "$ETCD_LOG"

if grep -Fxq "Successfully tagged quay.io/coreos/etcd:latest" $ETCD_LOG
then
    echo "Successfully built etcd image" | tee -a "$ETCD_LOG"
else
    echo "etcd image Build FAILED, Stopping further build !!! Check logs at $ETCD_LOG" | tee -a "$ETCD_LOG"
	exit 1
fi

cd bin
printf -- "\nCreate a tar file containing etcd, etcdctl binaries . . . \n"  | tee -a "$ETCD_LOG"
tar cvf etcd-v${ETCD_VERSION}-linux-s390x.tar etcd etcdctl 2>&1 | tee -a "$ETCD_LOG"
printf -- "\nCompressing etcd tar file using gzip . . . \n"  | tee -a "$ETCD_LOG"
gzip etcd-v${ETCD_VERSION}-linux-s390x.tar 2>&1 | tee -a "$ETCD_LOG"
docker tag quay.io/coreos/etcd:latest quay.io/coreos/etcd:v${ETCD_VERSION}-s390x
docker tag quay.io/coreos/etcd quay.io/coreos/etcd:v${ETCD_VERSION}

### 5.2 Build `calico/dind`
export DIND_LOG="${LOGDIR}/dind-$(date +"%F-%T").log"
touch $DIND_LOG
printf -- "\nBuilding dind Image for s390x . . . \n"  | tee -a "$DIND_LOG"
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


### 5.3 Build `calico_test`
export TEST_LOG="${LOGDIR}/testLog-$(date +"%F-%T").log"
touch $TEST_LOG
printf -- "\nMaking required changes to node/calico_test for s390x . . . \n"  | tee -a "$TEST_LOG"
cd $GOPATH/src/github.com/projectcalico/node/calico_test/
printf -- "\nCreating directory pkg . . . \n"  | tee -a "$TEST_LOG"
mkdir -p pkg
printf -- "\nCopying etcd tar file to pkg dir in calico_test . . . \n"  | tee -a "$TEST_LOG"
cp $GOPATH/src/github.com/projectcalico/etcd/bin/etcd-v${ETCD_VERSION}-linux-s390x.tar.gz pkg

## Modify `Dockerfile.s390x.calico_test`
printf -- "\nDownloading patch for calico_test Dockerfile.s390x . . . \n"  | tee -a "$TEST_LOG"
curl  -o "calico_test.diff" $PATCH_URL/calico_test.diff 2>&1 | tee -a "$TEST_LOG"
printf -- "\nApplying patch to Dockerfile.s390x.calico_test . . . \n"  | tee -a "$TEST_LOG"
patch Dockerfile.s390x.calico_test calico_test.diff 2>&1 | tee -a "$TEST_LOG"
rm -rf calico_test.diff
sed -i '49 s/^/build-base /' Dockerfile.s390x.calico_test


### 5.4 Run the test cases
## Modify `Dockerfile.s390x` for workload
printf -- "\nMaking required changes to node/workload for s390x . . . \n"  | tee -a "$TEST_LOG"
cd $GOPATH/src/github.com/projectcalico/node/workload
printf -- "\nDownloading patch for workload Dockerfile.s390x . . . \n"  | tee -a "$TEST_LOG"
curl  -o "calico_workload.diff" $PATCH_URL/calico_workload.diff 2>&1 | tee -a "$TEST_LOG"
printf -- "\nApplying patch to Dockerfile.s390x . . . \n"  | tee -a "$TEST_LOG"
patch Dockerfile.s390x calico_workload.diff 2>&1 | tee -a "$TEST_LOG"
rm -rf calico_workload.diff

#Verifying if all images are built/tagged
export VERIFY_LOG="${LOGDIR}/verify-images-$(date +"%F-%T").log"
touch $VERIFY_LOG
printf -- "\nVerifying if all needed images are successfully built/downloaded ? . . . \n"  | tee -a "$VERIFY_LOG"
cd $WORKDIR
echo "Required Docker Images: " >> $VERIFY_LOG
rm -rf docker_images_expected.txt
rm -rf docker_images.txt
cat << 'EOF' > docker_images_expected.txt
calico/dind:latest
quay.io/coreos/etcd:latest
quay.io/coreos/etcd:v3.3.7
quay.io/coreos/etcd:v3.3.7-s390x
calico/node:latest
calico/node:latest-s390x
quay.io/calico/node-s390x:v3.8.1
calico/node:v3.8.1
quay.io/calico/cni-s390x:v3.8.1
calico/cni:latest
calico/cni:latest-s390x
calico/cni:v3.8.1
calico/felix:latest-s390x
calico/protoc-s390x:latest
calico/protoc:v0.1-s390x
calico/typha:latest-s390x
calico/bird:latest
calico/bird:v0.3.3-s390x
birdbuild-s390x:latest
calico/ctl:latest-s390x
calico/go-build:latest
calico/go-build:latest-s390x
calico/go-build:v0.20
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
    printf -- "##############-----------------------------------------------------------------------------------------------############## \n" | tee -a "$TEST_LOG" 
    printf -- "                             TEST Flag is set , Running system tests now. \n" | tee -a "$TEST_LOG" 
    printf -- "                            Testlogs are saved in $TEST_LOG \n" | tee -a "$TEST_LOG" 
    printf -- "##############-----------------------------------------------------------------------------------------------############## \n" | tee -a "$TEST_LOG" 
    cd $GOPATH/src/github.com/projectcalico/node
    ARCH=s390x make st 2>&1 | tee -a "$TEST_LOG"
    if tail -n 30 "$TEST_LOG" | grep -q "OK (SKIP=9)"; then
        printf -- "\n                            All tests have passed !!!\n" | tee -a "$TEST_LOG"
    else
        printf -- "\n                            There are tests case failures!!! \n" | tee -a "$TEST_LOG"
        printf -- "\n                            To rerun Calico tests, run the following commands . . . \n"
        printf -- "\n                            Test logs will be saved in ${LOGDIR}/testLog-DATE-TIME.log  ## \n" | tee -a "$TEST_LOG"
        printf -- "\n------------------------------------------------------------------------------------------------------------------- \n" | tee -a "$TEST_LOG" 
        printf -- "\n                            source \$HOME/setenv.sh \n"
        printf -- "                              cd \$GOPATH/src/github.com/projectcalico/node \n"
        printf -- "                              ARCH=s390x make st 2>&1 | tee -a \$LOGDIR/testLog-\$(date +"%%F-%%T").log \n"
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
	printf -- "                       ARCH=s390x make st 2>&1 | tee -a \$LOGDIR/testLog-\$(date +"%%F-%%T").log \n" | tee -a "$TEST_LOG"
    printf -- "\n------------------------------------------------------------------------------------------------------------------- \n" | tee -a "$TEST_LOG" 

fi
