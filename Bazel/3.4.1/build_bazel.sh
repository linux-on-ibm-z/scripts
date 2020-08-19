#!/bin/bash
# © Copyright IBM Corporation 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Bazel/3.4.1/build_bazel.sh
# Execute build script: bash build_bazel.sh    (provide -h for help)
#
set -e  -o pipefail

PACKAGE_NAME="bazel"
PACKAGE_VERSION="3.4.1"
CURDIR="$(pwd)"
SOURCE_ROOT="$(pwd)"
USER="$(whoami)"


FORCE="false"
TESTS="false"
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exists
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
		printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n'
		exit 1
	fi

	if [[ "$FORCE" == "true" ]]; then
		printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
	else
		# Ask user for prerequisite installation
		printf -- "\nAs part of the installation, dependencies would be installed/upgraded. \n"
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

function cleanup() {
    # Remove artifacts
	rm -rf $SOURCE_ROOT/bazel
    rm -rf $SOURCE_ROOT/bazel-fork
	
    printf -- "Cleaned up the artifacts\n" | tee -a "$LOG_FILE"

}
function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'
	
	printf -- 'Create symlink for python 3 only environment\n'
	sudo ln -sf /usr/bin/python3 /usr/bin/python || true
	
	# Download Bazel 3.4.1 distribution archive 
    printf -- '\nDownload Bazel 3.4.1 distribution archive..... \n' 
    cd $SOURCE_ROOT   
    mkdir bazel && cd bazel  
    wget https://github.com/bazelbuild/bazel/releases/download/3.4.1/bazel-3.4.1-dist.zip
    unzip bazel-3.4.1-dist.zip 
    chmod -R +w .

    # Bootstrap Bazel
    printf -- '\nBootstrap Bazel.... \n' 
    env EXTRA_BAZEL_ARGS="--host_javabase=@local_jdk//:jdk" bash ./compile.sh
    export PATH=$PATH:$SOURCE_ROOT/bazel/output/

    # Install Bazel
    printf -- '\nInstall Bazel, build a distribution archive......\n'
    cd $SOURCE_ROOT
    mkdir bazel-fork && cd bazel-fork
    git clone https://github.com/linux-on-ibm-z/bazel.git
    cd bazel
    git checkout v3.4.1-s390x
    bazel build --host_javabase=@local_jdk//:jdk //:bazel-distfile

    # Compile the bazel binary
    printf -- '\nCompile the bazel binary.......\n'
    cd $SOURCE_ROOT
    mkdir bazel-s390x && cd bazel-s390x
    unzip $SOURCE_ROOT/bazel-fork/bazel/bazel-bin/bazel-distfile.zip
    env EXTRA_BAZEL_ARGS="--host_javabase=@local_jdk//:jdk" bash ./compile.sh
    export PATH=$SOURCE_ROOT/bazel-s390x/output:$PATH

    # Run Tests
	runTest

	#Cleanup
	cleanup

	printf -- "\n Installation of %s %s was successful \n\n" $PACKAGE_NAME $PACKAGE_VERSION
}

function runTest() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- "TEST Flag is set , Continue with running test \n" 
		
		cd $SOURCE_ROOT/bazel-s390x
		bazel test --flaky_test_attempts=3 --build_tests_only --local_test_jobs=12 --show_progress_rate_limit=5 --terminal_columns=143 --show_timestamps --verbose_failures --keep_going --jobs=32 --host_javabase=@local_jdk//:jdk --test_timeout=1200 -- //src/... //third_party/ijar/...
		printf -- "Tests completed. \n"
	fi
	set -e
}

function logDetails() {
	printf -- '**************************** SYSTEM DETAILS *************************************************************\n' >>"$LOG_FILE"
	if [ -f "/etc/os-release" ]; then
		cat "/etc/os-release" >>"$LOG_FILE"
	fi

	cat /proc/version >>"$LOG_FILE"
	printf -- '*********************************************************************************************************\n' >>"$LOG_FILE"

	printf -- "Detected %s \n" "$PRETTY_NAME"
	printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" |& tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
	echo
	echo "Usage: "
	echo "  bash build_bazel.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests]"
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

function gettingStarted() {
	printf -- '\n***********************************************************************************************\n'
	printf -- "Getting Started: \n"
    printf -- "Make sure bazel binary is in your path\n"
    printf -- "export PATH=$SOURCE_ROOT/bazel-s390x/output:'$PATH'\n"
    printf -- "Check the version of Bazel, it should be something like the following:\n"
    printf -- "  $ bazel --version\n"
    printf -- "    bazel 3.4.1- (@non-git)\n"
    printf -- "The bazel location should be something like the following:\n"
    printf -- "  $ which bazel\n" 
    printf -- "    $SOURCE_ROOT/bazel-s390x/output/bazel\n"
}

###############################################################################################################

logDetails
prepare #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in

"ubuntu-18.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo apt-get update
    sudo apt-get install wget curl openjdk-11-jdk unzip patch build-essential zip python3 git libapr1 -y|& tee -a "${LOG_FILE}"	
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
