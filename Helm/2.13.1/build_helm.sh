#!/bin/bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/helm/build_helm.sh
# Execute build script: bash build_helm.sh    (provide -h for help)
#
set -e -o pipefail

PACKAGE_NAME="helm"
PACKAGE_VERSION="2.13.1"
CURDIR="$PWD"
REPO_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Helm/${PACKAGE_VERSION}/patch"
HELM_REPO_URL="https://github.com/kubernetes/helm.git"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
FORCE="false"
GO_VERSION="1.11.4"
GOPATH="${CURDIR}"
trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
	mkdir -p "$CURDIR/logs/"
fi


# Need handling for RHEL 6.10 as it doesn't have os-release file
if [ -f "/etc/os-release" ]; then
	source "/etc/os-release"
else
	cat /etc/redhat-release |& tee -a "$LOG_FILE"
	export ID="rhel"
	export VERSION_ID="6.x"
	export PRETTY_NAME="Red Hat Enterprise Linux 6.x"
fi
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
		runTest
		exit 0
	fi

	if [[ "$FORCE" == "true" ]]; then
		printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
	else
		
			printf -- 'Following packages are needed before going ahead\n' |& tee -a "$LOG_FILE"
			printf -- 'go version:GO 1.11+\n\n' |& tee -a "$LOG_FILE"
			printf -- 'Build might take some time.Sit back and relax\n' |& tee -a "$LOG_FILE"
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

	rm -rf "${CURDIR}/glide-v0.13.0-linux-s390x.tar.gz"
	rm -rf "${CURDIR}/linux-s390x"
	rm -rf "${CURDIR}/src/k8s.io/helm"
	if [[ "$TESTS" == "true" ]]; then
		sudo rm -rf "${CURDIR}/Makefile.diff"
	fi
	printf -- '\nCleaned up the artifacts\n' >>"$LOG_FILE"
}

function configureAndInstall() {
	printf -- '\nConfiguration and Installation started \n'

	#Installing dependencies
	
		printf -- 'User responded with Yes. \n'
		if command -v "go" >/dev/null; then
				printf -- "Go detected\n"
		else
				printf -- 'Installing go\n'
				cd "${CURDIR}"
				wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Go/build_go.sh
				bash build_go.sh -v $GO_VERSION
				printf -- 'go installed\n'
		fi


	

	#Setting environment variable needed for building
	export GOPATH="${CURDIR}"
	export PATH=$GOPATH/bin:$PATH

	#Install Glide
	cd $GOPATH
	wget https://github.com/Masterminds/glide/releases/download/v0.13.1/glide-v0.13.1-linux-s390x.tar.gz
	tar -xzf glide-v0.13.1-linux-s390x.tar.gz
	export PATH=$GOPATH/linux-s390x:$PATH:$GOPATH/bin
	# #Added symlink for PATH
	# sudo ln -sf $GOPATH/linux-s390x/glide /usr/bin/

  
	# Download and configure helm
	printf -- 'Downloading helm. Please wait.\n'
	mkdir -p $GOPATH/src/k8s.io
	cd $GOPATH/src/k8s.io
	git clone -b v$PACKAGE_VERSION $HELM_REPO_URL
	sleep 2

	# Add patch
	cd "${CURDIR}"
	curl -o Makefile.diff $REPO_URL/Makefile.diff
	patch "$GOPATH/src/k8s.io/helm/Makefile" Makefile.diff 

	#Build helm
	printf -- 'Building helm \n'
	printf -- 'Build might take some time.Sit back and relax\n'
	cd $GOPATH/src/k8s.io/helm
	make bootstrap build

	#Copy binaries to /usr/bin
	sudo cp $GOPATH/src/k8s.io/helm/bin/* /usr/bin
	
	printf -- '\nCopied binaries in /usr/bin\n'

	printenv >>"$LOG_FILE"
	runTest
	cleanup

}
function runTest() {
	
	set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- 'Running tests \n\n' |& tee -a "$LOG_FILE"
		cd "${CURDIR}"
		curl -o Makefile_test.diff $REPO_URL/Makefile_test.diff
		patch "$GOPATH/src/k8s.io/helm/Makefile" Makefile_test.diff
		cd "$GOPATH/src/k8s.io/helm"
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
	echo "  build_helm.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests]"
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
	printf -- "\n*All relevant binaries are created and placed in /usr/bin \n"
	printf -- '\n\nRefer step No. 4 from the receipe ( https://github.com/linux-on-ibm-z/docs/wiki/Building-Helm ) for Tiller installation.'
	printf -- '\n\n**********************************************************************************************************\n'

}

logDetails
prepare

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo apt-get update
	sudo apt-get install -y wget tar git make patch gcc
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"rhel-7.4" | "rhel-7.5" | "rhel-7.6")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo yum install -y wget tar git make patch gcc
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"sles-12.4" | "sles-15")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo zypper install -y  wget tar git make patch gcc
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

printSummary |& tee -a "$LOG_FILE"
