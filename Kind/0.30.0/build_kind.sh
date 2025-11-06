#!/bin/bash
# © Copyright IBM Corporation 2025
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: curl -sSLO https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Kind/0.30.0/build_kind.sh
# Execute build script: bash build_kind.sh    (provide -h for help)
#
USER_IN_GROUP_DOCKER=$(id -nGz $USER | tr '\0' '\n' | grep '^docker$' | wc -l)
set -e
set -o pipefail

PACKAGE_NAME="kind"
PACKAGE_VERSION="v0.30.0"
FORCE="false"
export SOURCE_ROOT=$(pwd)
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Kind/0.30.0/patch"
GO_DEFAULT="$SOURCE_ROOT/go"
GO_FLAG="DEFAULT"
LOGDIR="$SOURCE_ROOT/logs"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

# Check if directory exists
if [ ! -d "logs" ]; then
	mkdir -p "logs"
fi

if [ -f "/etc/os-release" ]; then
	source "/etc/os-release"
fi

function prepare() {
	if command -v "sudo" >/dev/null; then
		printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
	else
		printf -- 'Sudo : No \n' >>"$LOG_FILE"
		printf -- 'You can install sudo from repository using apt, yum or zypper based on your distro.. \n'
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
		# Ask user for prerequisite installation
		printf -- "\nAs part of the installation , some dependencies will be installed, \n"
		while true; do
			read -r -p "Do you want to continue (y/n) ? :  " yn
			case $yn in
			[Yy]*)
				printf -- 'User responded with Yes. \n' >> "$LOG_FILE"
				break
				;;
			[Nn]*) exit ;;
			*) echo "Please provide confirmation to proceed." ;;
			esac
		done
	fi
}

function configureAndInstall() {
    printf -- '\nConfiguration and Installation started \n'

    # Start docker service
    printf -- "Starting docker service\n"
    sudo service docker start
    sleep 20s

    cd "$SOURCE_ROOT"
    #Check if kind directory exists
    if [ -d "$SOURCE_ROOT/kind" ]; then
	  sudo rm -rf "$SOURCE_ROOT/kind"
    fi

    git clone -b "${PACKAGE_VERSION}" https://github.com/kubernetes-sigs/kind.git
    cd kind
    printf -- "\nBuilding kind binary ... \n"
    make build
    printf -- 'Build kind success \n'
    export PATH=${SOURCE_ROOT}/kind/bin:$PATH
    kind version
    printf -- "\nApplying patch for kind ... \n"
    curl -sSL $PATCH_URL/kind.patch | git apply --ignore-whitespace -
    make -C images/base quick
    make -C images/kindnetd TAG=v20250512-df8de77b quick
    make -C images/local-path-provisioner TAG=v20250214-acbabc1a quick

    # Run tests
    runTest
    
}

function runTest() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- "TEST Flag is set, continue with running test \n"

		# Test build
		make test
    		make unit
    		make integration
		printf -- "Tests completed. \n"

	fi
	set -e
}

function logDetails() {
	printf -- '**************************** SYSTEM DETAILS *************************************************************\n' >"$LOG_FILE"
	if [ -f "/etc/os-release" ]; then
		cat "/etc/os-release" >>"$LOG_FILE"
	else
		cat "/etc/redhat-release" >>"${LOG_FILE}"
	fi

	cat /proc/version >>"$LOG_FILE"
	printf -- '*********************************************************************************************************\n' >>"$LOG_FILE"

	printf -- "Detected %s \n" "$PRETTY_NAME"
	printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" |& tee -a "$LOG_FILE"
}

function printHelp() {
	echo "Usage: "
	echo "  bash build_kind.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests]"
	echo "Note: With tests, the build may take up to an additional 15 mins."
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
		printf -- "\nBuilding with tests may take up to an additional 15 mins.\n"
		;;
	esac
done

function gettingStarted() {
	printf -- '\n***************************************************************************************\n'
	printf -- "Getting Started: \n"
 	printf -- "Run following command to check kind version: \n"
	printf -- "kind version \n"
 	printf -- "Refer the verification step in the Build Instructions for creating a cluster\n"
 	printf -- "For more help visit https://kind.sigs.k8s.io/docs/user/quick-start/#installation\n"
	printf -- '***************************************************************************************\n'
	printf -- '\n'
}

###############################################################################################################

logDetails
prepare #Check Prerequisite

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"rhel-8.10" | "rhel-9.4" | "rhel-9.6")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- "Installing dependencies ... it may take some time.\n"
    sudo yum remove -y podman buildah
    sudo yum install -y yum-utils
    sudo yum-config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
    sudo yum install -y curl git wget make tar gcc glibc.s390x docker-ce docker-ce-cli containerd.io make which patch iproute-devel 2>&1 | tee -a "$LOG_FILE"
    export CC=gcc
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"sles-15.6" | "sles-15.7")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- "Installing dependencies ... it may take some time.\n"
    sudo zypper install -y curl git make wget tar gcc glibc-devel-static make which patch docker containerd docker-buildx iproute2 2>&1 | tee -a "$LOG_FILE"
    export CC=gcc
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
    
"ubuntu-22.04" | "ubuntu-24.04" | "ubuntu-25.04")
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
    sudo apt-get install -y patch git make curl tar gcc wget make docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin clang 2>&1 | tee -a "$LOG_FILE"
    export CC=gcc
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
