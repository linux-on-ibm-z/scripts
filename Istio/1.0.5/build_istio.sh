#!/bin/bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Istio/1.0.5/build_istio.sh
# Execute build script: bash build_istio.sh    (provide -h for help)
#

set -e -o pipefail

PACKAGE_NAME="istio"
PACKAGE_VERSION="1.0.5"
GO_VERSION="1.10.5"
HELM_VERSION="2.9.1"
CURDIR="$(pwd)"
REPO_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Istio/1.0.5/patch"
PROXY_REPO_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/IstioProxy/1.0.5/build_istio_proxy.sh"
HELM_REPO_URL="https://github.com/kubernetes/helm.git"
ISTIO_REPO_URL="https://github.com/istio/istio.git"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
TEST_USER="$(whoami)"
FORCE="false"
GOPATH="$CURDIR"
HELM_BIN_PATH="/usr/bin/helm"
PROXY_DEBUG_BIN_PATH="$CURDIR/proxy/debug/envoy"
PROXY_RELEASE_BIN_PATH="$CURDIR/proxy/release/envoy"
trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
	mkdir -p "$CURDIR/logs/"
fi

#
if [ -f "/etc/os-release" ]; then
	source "/etc/os-release"
fi

function prepare() {

	if [[ "${TEST_USER}" != "root" ]]; then
		printf -- 'Cannot run istio as non-root . Please switch to superuser \n'
		exit 1
	fi

	if [[ "$FORCE" == "true" ]]; then
		printf -- 'Force attribute provided hence continuing with install without confirmation message\n'
	else
		if [[ "${ID}" != "ubuntu" ]]; then
			printf -- '\nFollowing packages are needed before going ahead\n'
			printf -- 'Istio Proxy version: $PACKAGE_VERSION\n'
			printf -- 'Helm version: 2.9.1  \n'
			printf -- '\nBuild might take some time, please have patience . \n'
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
	fi
}

function cleanup() {

	rm -rf "${CURDIR}/glide-v0.13.0-linux-s390x.tar.gz"
	rm -rf "${CURDIR}/linux-s390x"
	rm -rf "${CURDIR}/src/k8s.io/helm"
	rm -rf "${CURDIR}/init.sh.diff"
	rm -rf "${CURDIR}/init_helm.sh.diff"
	rm -rf "${CURDIR}/swapper_safe.go.diff"
	rm -rf "${CURDIR}/swapper_unsafe.go.diff"
	rm -rf "${CURDIR}/swapper_unsafe_14.go.diff"
	rm -rf "${CURDIR}/swapper_unsafe_15.go.diff"

	printf -- '\nCleaned up the artifacts\n' >>"$LOG_FILE"
}

function buildHelm() {
	if [ $(command -v helm) ]
	then
        printf -- "helm detected skipping helm installation \n" |& tee -a "$LOG_FILE"
	else
	#Setting environment variable needed for building
	export GOPATH="${CURDIR}"
	export PATH=$GOPATH/bin:$PATH

	#Install Glide
	cd $GOPATH
	wget https://github.com/Masterminds/glide/releases/download/v0.13.0/glide-v0.13.0-linux-s390x.tar.gz
	tar -xzf glide-v0.13.0-linux-s390x.tar.gz
	export PATH=$GOPATH/linux-s390x:$PATH
  
	# Download and configure helm
	printf -- 'Downloading helm. Please wait.\n'
	mkdir -p $GOPATH/src/k8s.io
	cd $GOPATH/src/k8s.io
	git clone -b v$HELM_VERSION $HELM_REPO_URL
	sleep 2

	#Build helm
	printf -- 'Building helm \n'
	printf -- 'Build might take some time.Sit back and relax\n'
	cd $GOPATH/src/k8s.io/helm
	make bootstrap build

	#Copy binaries to /usr/bin
	sudo cp $GOPATH/src/k8s.io/helm/bin/* /usr/bin
	
	printf -- '\nCopied binaries in /usr/bin\n'
	printf -- 'helm installed\n' |& tee -a "$LOG_FILE"
	fi
}

#Installing dependencies
function dependencyInstall() {
	printf -- 'Building dependencies\n' |& tee -a "$LOG_FILE"
	cd "${CURDIR}"
	export PATH=$PATH:$GOPATH/bin


	#Install Go
	wget "https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Go/build_go.sh"
	bash build_go.sh -v "${GO_VERSION}"
	export PATH="${CURDIR}/go/bin:$PATH"
	export GOROOT="/usr/local/go"

	cd "${CURDIR}"
	#Build Istio Proxy
	#make a call to istio proxy script
	if [ -f "$PROXY_DEBUG_BIN_PATH" ] && [ -f "$PROXY_RELEASE_BIN_PATH" ]
	then
        printf -- "Istio Proxy binaries are found at location $PROXY_DEBUG_BIN_PATH and $PROXY_RELEASE_BIN_PATH \n" |& tee -a "$LOG_FILE"
	else
        printf -- 'Building Istio Proxy\n' |& tee -a "$LOG_FILE"
		curl -o build_istio_proxy.sh $PROXY_REPO_URL |& tee -a "$LOG_FILE"
		chmod +x build_istio_proxy.sh
		bash build_istio_proxy.sh -y
		#set a path to binaries
		printf -- 'Istio Proxy installed successfully\n' |& tee -a "$LOG_FILE"
	fi

}


function configureAndInstall() {
	printf -- '\nConfiguration and Installation started \n'
	#Installing dependencies
	printf -- 'User responded with Yes. \n'

	cd "${CURDIR}" 

	# Download and configure Istio
	printf -- '\nDownloading Istio. Please wait.\n'
	mkdir -p $GOPATH/src/istio.io && cd $GOPATH/src/istio.io  
	git clone $ISTIO_REPO_URL
	cd istio
	git checkout $PACKAGE_VERSION

	#Patch to be applied here (6 patches)
	#Patch for setting Path for release and debug envoy binaries
	cd "${CURDIR}"
	curl -o init.sh.diff $REPO_URL/init.sh.diff
	sed -i "s|<path-to-envoy-debug-binary/envoy>|${PROXY_DEBUG_BIN_PATH}|" init.sh.diff
	sed -i "s|<path-to-envoy-release-binary/envoy>|${PROXY_RELEASE_BIN_PATH}|" init.sh.diff
	patch "$GOPATH/src/istio.io/istio/bin/init.sh" init.sh.diff

	#Patch to setting Path for helm binary
	curl -o init_helm.sh.diff $REPO_URL/init_helm.sh.diff
	sed -i "s|<path-to-Helm-binary/helm>|${HELM_BIN_PATH}|" init_helm.sh.diff
	patch "$GOPATH/src/istio.io/istio/bin/init_helm.sh" init_helm.sh.diff

	#Additional patches
	curl -o swapper_safe.go.diff $REPO_URL/swapper_safe.go.diff
	patch "$GOPATH/src/istio.io/istio/vendor/go4.org/reflectutil/swapper_safe.go" swapper_safe.go.diff

	curl -o swapper_unsafe.go.diff $REPO_URL/swapper_unsafe.go.diff
	patch "$GOPATH/src/istio.io/istio/vendor/go4.org/reflectutil/swapper_unsafe.go" swapper_unsafe.go.diff

	curl -o swapper_unsafe_14.go.diff $REPO_URL/swapper_unsafe_14.go.diff
	patch "$GOPATH/src/istio.io/istio/vendor/go4.org/reflectutil/swapper_unsafe_14.go" swapper_unsafe_14.go.diff

	curl -o swapper_unsafe_15.go.diff $REPO_URL/swapper_unsafe_15.go.diff
	patch "$GOPATH/src/istio.io/istio/vendor/go4.org/reflectutil/swapper_unsafe_15.go" swapper_unsafe_15.go.diff


	#Build Istio
	printf -- '\nBuilding Istio \n'
	cd $GOPATH/src/istio.io/istio
	make build
	printenv >>"$LOG_FILE"
	printf -- 'Built Istio successfully \n\n'

	# Run Tests
	# runTest feature not available
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
	echo "  install.sh  [-d debug] [-y install-without-confirmation]"
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
	esac
done

function printSummary() {

	printf -- "\n* Getting Started * \n"
	printf -- '\nPlease refer to Step 3 from Build instructions to run test cases'
	printf -- "\nNote: kubernetes is needed to run test cases \n\n"
}

logDetails
prepare |& tee -a "$LOG_FILE"
#checkPrequisites #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
	apt-get update  
	apt-get install -y pkg-config zip gcc g++ tar zlib1g-dev unzip git vim tar wget automake autoconf libtool make curl openjdk-8-jdk libcurl3-dev bzip2 mercurial
	dependencyInstall
	buildHelm
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

 "ubuntu-18.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
	apt-get update  
	apt-get install -y pkg-config zip gcc g++ zlib1g-dev unzip git vim tar wget automake autoconf libtool make curl openjdk-8-jdk libcurl3-dev bzip2 mercurial
	dependencyInstall
	buildHelm
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"rhel-7.4" | "rhel-7.5" | "rhel-7.6")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
	sudo yum install -y wget tar make zip unzip git vim gcc gcc-c++ binutils-devel bzip2 which java-1.8.0-openjdk java-1.8.0-openjdk-devel automake autoconf libtool zlib pkgconfig zlib-devel curl bison libcurl-devel mercurial
	dependencyInstall
	buildHelm
	configureAndInstall |& tee -a "$LOG_FILE"

	;;

"sles-12.3" | "sles-15")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
	zypper install -y wget tar make zip unzip git vim gcc gcc-c++ binutils-devel bzip2 glibc-devel makeinfo zlib-devel curl which java-1_8_0-openjdk-devel automake autoconf libtool zlib pkg-config libcurl-devel mercurial
	dependencyInstall
	buildHelm
	configureAndInstall |& tee -a "$LOG_FILE"

	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

# Print Summary
printSummary |& tee -a "$LOG_FILE"
