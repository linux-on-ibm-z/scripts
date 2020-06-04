#!/bin/bash
# © Copyright IBM Corporation 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Istio/1.3.6/build_istio.sh
# Execute build script: bash build_istio.sh    (provide -h for help)
#

set -e -o pipefail

PACKAGE_NAME="istio"
PACKAGE_VERSION="1.3.6"
HELM_VERSION="2.9.1"
CURDIR="$(pwd)"
REPO_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Istio/1.3.6/patch"

PROXY_REPO_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/IstioProxy/1.3.6/build_istio_proxy.sh"

HELM_REPO_URL="https://github.com/kubernetes/helm.git"
ISTIO_REPO_URL="https://github.com/istio/istio.git"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
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

function runTest() {
	set +e
	cd "${CURDIR}"
	if [[ "$TESTS" == "true" ]]; then
		printf -- 'Running test cases for istio\n'
		cd $GOPATH/src/istio.io/istio
		sudo env PATH=$PATH make test
		printf -- '\n\n COMPLETED TEST EXECUTION !! \n' |& tee -a "$LOG_FILE"
	fi
	set -e
}

function cleanup() {

	rm -rf "${CURDIR}/glide-v0.13.0-linux-s390x.tar.gz"
	rm -rf "${CURDIR}/src/k8s.io/helm"
	rm -rf "${CURDIR}/init.sh.diff"
	rm -rf "${CURDIR}/init_helm.sh.diff"
	printf -- '\nCleaned up the artifacts\n' >>"$LOG_FILE"
}

function buildHelm() {
	if [ $(command -v helm) ]; then
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

	cd "${CURDIR}"
	#Build Istio Proxy
	#make a call to istio proxy script
	if [ -f "$PROXY_DEBUG_BIN_PATH" ] && [ -f "$PROXY_RELEASE_BIN_PATH" ]; then
		printf -- "Istio Proxy binaries are found at location %s and %s \n" "$PROXY_DEBUG_BIN_PATH" "$PROXY_RELEASE_BIN_PATH" |& tee -a "$LOG_FILE"
	else
		printf -- 'Building Istio Proxy\n' |& tee -a "$LOG_FILE"
		curl -o build_istio_proxy.sh $PROXY_REPO_URL |& tee -a "$LOG_FILE"
		chmod +x build_istio_proxy.sh
		if [[ "$TESTS" == "true" ]]; then
			printf -- 'Test case flag is enabled \n'
			bash build_istio_proxy.sh -yt
		else
			bash build_istio_proxy.sh -y
		fi

		#set a path to binaries
		printf -- 'Istio Proxy installed successfully\n' |& tee -a "$LOG_FILE"
	fi

		#Install Go

		printf -- 'Installing go\n'		
		cd "${CURDIR}"		
		wget https://storage.googleapis.com/golang/go1.13.linux-s390x.tar.gz
		tar -xzf go1.13.linux-s390x.tar.gz
		export PATH=${CURDIR}/go/bin:$PATH
		export GOROOT=${CURDIR}/go
		if [ "${ID}" == "rhel" ] || [ ${ID} == "sles" ]; then
		   sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
		fi
		go version 
		printf -- 'go installed\n'

	

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

	#Build Istio
	printf -- '\nBuilding Istio \n'
	cd $GOPATH/src/istio.io/istio
	sudo env PATH=$PATH make build
	printenv >>"$LOG_FILE"
	printf -- 'Built Istio successfully \n\n'

	# Run Tests
	runTest
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
	echo "  install.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests]"
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

    printf -- "\n* Getting Started * \n"
    printf -- "\n ISTIO BUILD COMPLETED SUCCESSFULLY !!! \n "
    printf -- "\n* To integrate istio with kubernetes, export below variables * \n"
    printf -- "\n export GOPATH=%s""$GOPATH"
    printf -- "\n export GOROOT=%s""$GOROOT"
    printf -- "\n export PATH=\$PATH:\$GOPATH/go/bin:\$GOPATH/bin:\$GOPATH/out/linux_s390x/release:\$GOPATH/linux-s390x \n"
}

logDetails
prepare |& tee -a "$LOG_FILE"
#checkPrequisites #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
	sudo apt-get update
	sudo DEBIAN_FRONTEND=noninteractive apt-get install -y pkg-config zip tar zlib1g-dev unzip git vim tar wget automake autoconf libtool make curl libcurl3-dev bzip2 mercurial patch 
	dependencyInstall
	buildHelm
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"rhel-7.6" | "rhel-7.7")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
	sudo yum install -y wget tar make zip unzip git vim binutils-devel bzip2 which automake autoconf libtool zlib pkgconfig zlib-devel curl bison libcurl-devel mercurial 
	dependencyInstall
	buildHelm
	configureAndInstall |& tee -a "$LOG_FILE"

	;;

"sles-12.4" | "sles-15.1")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
	sudo zypper install -y wget tar make zip unzip git vim binutils-devel bzip2 glibc-devel makeinfo zlib-devel curl which automake autoconf libtool zlib pkg-config libcurl-devel mercurial patch
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
