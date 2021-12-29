#!/bin/bash
# © Copyright IBM Corporation 2021.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Bazel/4.1.0/build_bazel.sh
# Execute build script: bash build_bazel.sh    (provide -h for help)
#
set -e  -o pipefail

PACKAGE_NAME="bazel"
PACKAGE_VERSION="4.1.0"
CURDIR="$(pwd)"
SOURCE_ROOT="$(pwd)"
USER="$(whoami)"
PATCH="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Bazel/4.1.0/patch"

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
		printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n'
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
	rm -rf $SOURCE_ROOT/netty
	rm -rf $SOURCE_ROOT/netty-tcnative

	printf -- "Cleaned up the artifacts\n" | tee -a "$LOG_FILE"
}

function buildNetty() {
	# Install netty-tcnative 2.0.24
	printf -- '\nBuild netty-tcnative 2.0.24 from source...... \n'
	sudo apt-get update
	sudo apt-get install -y ninja-build cmake perl golang libssl-dev autoconf automake libtool make tar maven default-jdk libapr1-dev

	cd $SOURCE_ROOT
	git clone https://github.com/netty/netty-tcnative.git
	cd netty-tcnative
	git checkout netty-tcnative-parent-2.0.24.Final

	curl -sSL $PATCH/netty-tcnative.patch | git apply || echo "Error: Patch netty tcnative"
	mvn install

	# Install netty 4.1.48 Final
	printf -- '\nBuild netty 4.1.48 from source...... \n'
	cd $SOURCE_ROOT
	git clone https://github.com/netty/netty.git
	cd netty
	git checkout netty-4.1.48.Final
	curl -sSL $PATCH/netty.patch | git apply
	./mvnw clean install -DskipTests
}

function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'

	printf -- 'Create symlink for python 3 only environment\n'
	sudo ln -sf /usr/bin/python3 /usr/bin/python || true

	printf -- 'Set JAVA_HOME\n'
	export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x
	export PATH=$JAVA_HOME/bin:$PATH

	# Download Bazel 4.1.0 distribution archive
	printf -- '\nDownload Bazel 4.1.0 distribution archive..... \n'
	cd $SOURCE_ROOT
	mkdir bazel && cd bazel
	wget https://github.com/bazelbuild/bazel/releases/download/$PACKAGE_VERSION/bazel-$PACKAGE_VERSION-dist.zip
	unzip bazel-$PACKAGE_VERSION-dist.zip
	chmod -R +w .

	printf -- '\nInstall Bazel.... \n'
	curl -sSL $PATCH/bazel.patch | git apply
	curl -o compile.patch $PATCH/compile.patch
	patch --ignore-whitespace $SOURCE_ROOT/bazel/scripts/bootstrap/compile.sh < compile.patch

	buildNetty
	# Copy netty and netty-tcnative jar to respective bazel directory and apply a patch to use them
	printf -- '\nCopy netty and netty-tcnative jar to respective bazel directory and apply a patch to use them......\n'
	cp $SOURCE_ROOT/netty-tcnative/boringssl-static/target/netty-tcnative-boringssl-static-2.0.24.Final-linux-s390_64.jar $SOURCE_ROOT/bazel/third_party/netty_tcnative/netty-tcnative-boringssl-static-2.0.24.Final.jar
	cp $SOURCE_ROOT/netty/all/target/netty-all-4.1.48.Final.jar $SOURCE_ROOT/bazel/third_party/netty/
	cd $SOURCE_ROOT/bazel
	curl -sSL $PATCH/bazel-netty.patch | git apply || echo "Error: Patch Bazel netty"

	bash ./compile.sh
	export PATH=$PATH:$SOURCE_ROOT/bazel/output/

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

		cd $SOURCE_ROOT/bazel
		bazel test --flaky_test_attempts=3 --build_tests_only --copt="-Wimplicit-fallthrough=0" --local_test_jobs=12 --show_progress_rate_limit=5 --terminal_columns=143 --show_timestamps --verbose_failures --keep_going --jobs=32 --test_timeout=1200 -- //src/... //third_party/ijar/...
		printf -- "Tests completed. \n\n"
		printf -- "If you see an unexpected test case failure, you could rerun it the following command:\n\n"
		printf -- "bazel test --flaky_test_attempts=3 --build_tests_only --copt=\"-Wimplicit-fallthrough=0\" --local_test_jobs=12 --show_progress_rate_limit=5 --terminal_columns=143 --show_timestamps --verbose_failures --keep_going --jobs=32 -- //src/<module_name>:<testcase_name>\n\n"
		printf -- "For example,\n"
		printf -- "bazel test --flaky_test_attempts=3 --build_tests_only --copt=\"-Wimplicit-fallthrough=0\" --local_test_jobs=12 --show_progress_rate_limit=5 --terminal_columns=143 --show_timestamps --verbose_failures --keep_going --jobs=32 -- //src/test/cpp/util:md5_test\n"
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
	printf -- "export PATH=$SOURCE_ROOT/bazel/output:'$PATH'\n"
	printf -- "Check the version of Bazel, it should be something like the following:\n"
	printf -- "  $ bazel --version\n"
	printf -- "    bazel 4.1.0 - (@non-git)\n"
	printf -- "The bazel location should be something like the following:\n"
	printf -- "  $ which bazel\n"
	printf -- "    $SOURCE_ROOT/bazel/output/bazel\n"
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
	sudo apt-get install wget curl openjdk-11-jdk unzip patch build-essential zip python3 git -y|& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
