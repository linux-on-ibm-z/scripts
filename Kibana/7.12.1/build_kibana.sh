#!/bin/bash
# ©  Copyright IBM Corporation 2021.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Kibana/7.12.1/build_kibana.sh
# Execute build script: bash build_kibana.sh    (provide -h for help)
#
set -e -o pipefail

PACKAGE_NAME="kibana"
PACKAGE_VERSION="7.12.1"
NODE_JS_VERSION="14.16.1"

FORCE=false
CURDIR="$(pwd)"
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Kibana/${PACKAGE_VERSION}/patch"
NON_ROOT_USER="$(whoami)"

trap cleanup 1 2 ERR

# Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
   mkdir -p "$CURDIR/logs/"
fi

source "/etc/os-release"

function prepare() {
	if command -v "sudo" > /dev/null; then
		printf -- 'Sudo : Yes\n' >> "$LOG_FILE"
	else
		printf -- 'Sudo : No \n' >> "$LOG_FILE"
		printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n'
		exit 1
	fi

	if [[ "$FORCE" == "true" ]]; then
		printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "${LOG_FILE}"
	else
		# Ask user for prerequisite installation
		printf -- "\nAs part of the installation , dependencies would be installed/upgraded, \n"
		while true; do
			read -r -p "Do you want to continue (y/n) ? :  " yn
			case $yn in
			[Yy]*)
				printf -- 'User responded with Yes. \n' >> "${LOG_FILE}"
				break
				;;
			[Nn]*) exit ;;
			*) echo "Please provide confirmation to proceed." ;;
			esac
		done
	fi
}

function cleanup() {
	sudo rm -rf "${CURDIR}/node-v${NODE_JS_VERSION}-linux-s390x.tar.xz"
	sudo rm -rf "${CURDIR}/linux-s390x-83.gz"
	sudo rm -rf "{$CURDIR}/bazel-4.0.0-dist.zip"
	sudo rm -rf "${CURDIR}/bazelisk"
	sudo rm -rf "${CURDIR}/node-re2"
	sudo rm -rf "{$CURDIR}/build_go.sh"
	printf -- 'Cleaned up the artifacts\n' >>"${LOG_FILE}"
}

function configureAndInstall() {
	printf -- '\nConfiguration and Installation started.\n'

	# Building Bazel from source
	printf -- 'Building Bazel from source.\n'
	cd "${CURDIR}"
	mkdir bazel && cd bazel
	wget https://github.com/bazelbuild/bazel/releases/download/4.0.0/bazel-4.0.0-dist.zip
	unzip bazel-4.0.0-dist.zip
	chmod -R +w .
	curl -sSL https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Bazel/4.0.0/patch/bazel.patch | patch -p1
	bash ./compile.sh
	export PATH=$PATH:${CURDIR}/bazel/output/

	# Download Go binary
	printf -- 'Downloading Go binary.\n'
	cd "${CURDIR}"
	wget -q https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Go/1.16.3/build_go.sh
	bash build_go.sh

	# Building Bazelisk from source
	printf -- 'Building Bazelisk from source.\n'
	cd "${CURDIR}"
	git clone https://github.com/bazelbuild/bazelisk.git
	cd bazelisk
	git checkout v1.7.5
	curl -sSL $PATCH_URL/bazelisk_patch.diff | git apply --ignore-whitespace
	export USE_BAZEL_VERSION=${CURDIR}/bazel/output/bazel
	go build && ./bazelisk build --config=release //:bazelisk-linux-s390x

	# Installing Node.js
	printf -- 'Downloading and installing Node.js.\n'
	cd "${CURDIR}"
	sudo mkdir -p /usr/local/lib/nodejs
	wget https://nodejs.org/dist/v${NODE_JS_VERSION}/node-v${NODE_JS_VERSION}-linux-s390x.tar.xz
	sudo tar xf node-v${NODE_JS_VERSION}-linux-s390x.tar.xz -C /usr/local/lib/nodejs
	export PATH=/usr/local/lib/nodejs/node-v${NODE_JS_VERSION}-linux-s390x/bin:$PATH
	node -v  >> "${LOG_FILE}"

	# Installing Yarn and patch Bazelisk
	printf -- 'Downloading and installing Yarn and patch Bazelisk.\n'
	sudo chmod ugo+w -R /usr/local/lib/nodejs/node-v${NODE_JS_VERSION}-linux-s390x
	npm install -g yarn @bazel/bazelisk@1.7.5
	BAZELISK_DIR=/usr/local/lib/nodejs/node-v${NODE_JS_VERSION}-linux-s390x/lib/node_modules/@bazel/bazelisk
	curl -sSL $PATCH_URL/bazelisk.js.diff | patch $BAZELISK_DIR/bazelisk.js
	cp ${CURDIR}/bazelisk/bazel-out/s390x-opt-*/bin/bazelisk-linux_s390x $BAZELISK_DIR

	# Downloading and installing Kibana and apply patch
	printf -- '\nDownloading and installing Kibana.\n'
	cd "${CURDIR}"
	git clone -b v$PACKAGE_VERSION https://github.com/elastic/kibana.git
	cd kibana
	curl -sSL $PATCH_URL/kibana_patch.diff | git apply

	# Build re2
	cd "${CURDIR}"
	git clone https://github.com/uhop/node-re2.git
	cd node-re2 && git checkout 1.15.4
	git submodule update --init --recursive
	npm install
	gzip -c build/Release/re2.node > "${CURDIR}"/linux-s390x-83.gz
	mkdir -p "${CURDIR}"/kibana/.native_modules/re2/
	cp "${CURDIR}"/linux-s390x-83.gz "${CURDIR}"/kibana/.native_modules/re2/

	# Bootstrap Kibana
	cd "${CURDIR}"/kibana
	yarn kbn bootstrap --oss

	# Building Kibana
	cd "${CURDIR}"/kibana
	export NODE_OPTIONS="--max_old_space_size=4096"
	yarn build --skip-os-packages --oss

	# Installing Kibana
	sudo mkdir /usr/share/kibana/
	sudo tar -xzf target/kibana-oss-"$PACKAGE_VERSION"-SNAPSHOT-linux-s390x.tar.gz -C /usr/share/kibana --strip-components 1
	sudo ln -sf /usr/share/kibana/bin/* /usr/bin/

	if ([[ -z "$(cut -d: -f1 /etc/group | grep elastic)" ]]); then
		printf -- '\nCreating group elastic.\n'
		sudo /usr/sbin/groupadd elastic # If group is not already created
	fi
	sudo chown "$NON_ROOT_USER:elastic" -R /usr/share/kibana

	cd /usr/share/kibana/

	printf -- 'Installed Kibana successfully.\n'
	#Run Tests
	runTest
	# Cleanup
	cleanup

	# Verify kibana installation
	if command -v "$PACKAGE_NAME" >/dev/null; then
		printf -- "%s installation completed. Please check the Usage to start the service.\n" "$PACKAGE_NAME"
	else
		printf -- "Error while installing %s, exiting with 127 \n" "$PACKAGE_NAME"
		exit 127
	fi
}

function runTest() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- "TEST Flag is set, continue with running test \n"  >> "$LOG_FILE"
	cd "${CURDIR}"/kibana
	yarn test:jest 2>&1 | tee -a ${CURDIR}/test_logs

	printf -- '**********************************************************************************************************\n'
	printf -- '\nCompleted test execution !! Test case failures can be ignored as they are seen on x86 also \n'
	printf -- '\nSome test case failures will pass when rerun the tests \n'
	printf -- '\nPlease refer to the building instructions for the complete set of expected failures.\n'
	printf -- '**********************************************************************************************************\n'

	fi
	set -e
	}


function logDetails() {
	printf -- '**************************** SYSTEM DETAILS *************************************************************\n' >"$LOG_FILE"
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
	echo "  build_kibana.sh  [-d debug] [-y install-without-confirmation] [-t test]"
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
	printf -- '\n*********************************************************************************************\n'
	printf -- "Getting Started:\n\n"
	printf -- "Kibana requires an Elasticsearch instance to be running. \n"
	printf -- "Set Kibana home directory:\n"
	printf -- "     export KIBANA_HOME=/usr/share/kibana\n"
	printf -- "Update the Kibana configuration file \$KIBANA_HOME/config/kibana.yml accordingly.\n"
	printf -- "Start Kibana: \n"
	printf -- "     kibana & \n\n"
	printf -- "Access the Kibana UI using the below link: "
	printf -- "https://<Host-IP>:<Port>/    [Default Port = 5601] \n"
	printf -- '*********************************************************************************************\n'
	printf -- '\n'
}

###############################################################################################################

logDetails
prepare

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-18.04" | "ubuntu-20.04")
	printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
	sudo apt-get update
	sudo apt-get install -y curl git g++ gzip make python python3 openjdk-11-jdk unzip zip tar wget patch xz-utils |& tee -a "${LOG_FILE}"
	export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x
	export PATH=$JAVA_HOME/bin:$PATH
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

"rhel-7.8" | "rhel-7.9")
	printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
	sudo yum install -y git devtoolset-7-gcc-c++ devtoolset-7-gcc gzip make python3 java-11-openjdk-devel unzip zip tar wget patch xz |& tee -a "${LOG_FILE}"
	source /opt/rh/devtoolset-7/enable
	export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
	export PATH=$JAVA_HOME/bin:$PATH
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;
"rhel-8.1" | "rhel-8.2"| "rhel-8.3")
	printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
	sudo yum install -y curl git gcc-c++ gzip make python2 python3 java-11-openjdk-devel unzip zip tar wget patch xz |& tee -a "${LOG_FILE}"
	sudo ln -sf /usr/bin/python3 /usr/bin/python
	export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
	export PATH=$JAVA_HOME/bin:$PATH
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

"sles-15.2")
	printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
	sudo zypper install -y curl git gcc-c++ gzip make python python3 java-11-openjdk-devel unzip zip tar wget patch xz which gawk |& tee -a "${LOG_FILE}"
	export JAVA_HOME=/usr/lib64/jvm/java-11-openjdk
	export PATH=$JAVA_HOME/bin:$PATH
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;
*)

	printf -- "%s not supported \n" "$DISTRO" |& tee -a "${LOG_FILE}"
	exit 1
	;;
esac

cleanup
gettingStarted |& tee -a "${LOG_FILE}"
