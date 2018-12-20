#!/bin/bash
# ©  Copyright IBM Corporation 2018.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Elasticsearch/build_elasticsearch.sh
# Execute build script: bash build_elasticsearch.sh    (provide -h for help)
#
set -e -o pipefail

PACKAGE_NAME="elasticsearch"
PACKAGE_VERSION="6.5.0"
CURDIR="$(pwd)"
REPO_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Elasticsearch/patch"
ES_REPO_URL="https://github.com/elastic/elasticsearch"

LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
NON_ROOT_USER="$(whoami)"
FORCE="false"

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
	rm -rf "${CURDIR}/elasticsearch.yml.diff"
	rm -rf "${CURDIR}/jvm.options.diff"
	rm -rf "${CURDIR}/OpenJDK11-jdk_s390x_linux_hotspot_11_28.tar.gz"
	rm -rf "${CURDIR}/elasticsearch/network_tests.log"
	rm -rf "${CURDIR}/elasticsearch/local_tests.log"
	rm -rf "${CURDIR}/elasticsearch/test_results.log"
	printf -- '\nCleaned up the artifacts\n' >>"$LOG_FILE"
}

function configureAndInstall() {
	printf -- '\nConfiguration and Installation started \n'

	#Installing dependencies
	printf -- 'User responded with Yes. \n'
	printf -- 'Downloading openjdk\n'
	wget 'https://github.com/AdoptOpenJDK/openjdk11-binaries/releases/download/jdk-11%2B28/OpenJDK11-jdk_s390x_linux_hotspot_11_28.tar.gz'
	sudo tar -C /usr/local -xzf OpenJDK11-jdk_s390x_linux_hotspot_11_28.tar.gz
	export PATH=/usr/local/jdk-11+28/bin:$PATH
	java -version |& tee -a "$LOG_FILE"
	printf -- 'Adopt JDK 11 installed\n'

	cd "${CURDIR}"
	#Setting environment variable needed for building
	unset JAVA_TOOL_OPTIONS
	export LANG="en_US.UTF-8"
	export JAVA_TOOL_OPTIONS="-Dfile.encoding=UTF8"
	export JAVA_HOME=/usr/local/jdk-11+28
	export JAVA11_HOME=/usr/local/jdk-11+28
	export _JAVA_OPTIONS="-Xmx10g"

	#Added symlink for PATH
	sudo ln -sf /usr/local/jdk-11+28/bin/java /usr/bin/
	printf -- 'Adding JAVA_HOME to bashrc \n'
	#add JAVA_HOME to ~/.bashrc
	cd "${HOME}"
	if [[ "$(grep -q JAVA_HOME .bashrc)" ]]; then

		printf -- '\nChanging JAVA_HOME\n'
		sed -n 's/^.*\bJAVA_HOME\b.*$/export JAVA_HOME=\/usr\/local\/jdk-9.0.4+11\//p' ~/.bashrc
	else
		echo "export JAVA_HOME=/usr/local/jdk-11+28/" >>.bashrc
	fi

	cd "${CURDIR}"
	# Download and configure ElasticSearch
	printf -- 'Downloading Elasticsearch. Please wait.\n'
	git clone -b v$PACKAGE_VERSION $ES_REPO_URL
	sleep 2

	#Patch Applied for known errors
	cd "${CURDIR}"
	# patch config file
	curl -o jvm.options.diff $REPO_URL/jvm.options.diff
	patch "${CURDIR}/elasticsearch/distribution/src/config/jvm.options" jvm.options.diff

	curl -o elasticsearch.yml.diff $REPO_URL/elasticsearch.yml.diff
	patch "${CURDIR}/elasticsearch/distribution/src/config/elasticsearch.yml" elasticsearch.yml.diff

	printf -- 'Patch applied for files elasticsearch.yml and  jvm.options\n'

	#Build elasticsearch
	printf -- 'Building Elasticsearch \n'
	printf -- 'Build might take some time.Sit back and relax\n'
	cd "${CURDIR}/elasticsearch"
	./gradlew assemble 
	#Verify elasticsearch installation
	if [[ $(grep -q "BUILD FAILED" "$LOG_FILE") ]]; then
		printf -- '\nBuild failed due to some unknown issues.\n'
		exit 1
	fi
	printf -- 'Built Elasticsearch successfully \n\n'
}

function runTest() {
	
	#Setting environment variable needed for testing
	unset JAVA_TOOL_OPTIONS
	export LANG="en_US.UTF-8"
	export JAVA_TOOL_OPTIONS="-Dfile.encoding=UTF8"
	export JAVA_HOME=/usr/local/jdk-11+28
	export JAVA11_HOME=/usr/local/jdk-11+28
	export _JAVA_OPTIONS="-Xmx10g"

	printf -- 'Running test \n'
	cd "${CURDIR}/elasticsearch"
	set +e

	#Run network mode test cases
	printf -- 'Running network mode test cases\n'
	./gradlew test --continue -Dtests.haltonfailure=false -Dtests.es.node.mode=network 2>&1| tee -a network_tests.log

	#Run local mode test cases
	printf -- 'Running local mode test cases\n'
	./gradlew test --continue -Dtests.haltonfailure=false -Dtests.es.node.mode=local 2>&1| tee -a local_tests.log

	cd "${CURDIR}/elasticsearch"
	grep "REPRODUCE" network_tests.log >> test_results.log
	grep "REPRODUCE" local_tests.log >> test_results.log
}
function reviewTest() {

	cd "${CURDIR}/elasticsearch"
	if [ -s test_results.log ]; then
     	if [[ ! $(grep -rni "x-pack:plugin:ml" test_results.log) ]]; then
			printf -- '**********************************************************************************************************\n'
			printf -- '\nUnexpected test failures detected. Tip : Try running them individually and increasing the timeout using the -Dtests.timeoutSuite flag\n'
			printf -- '**********************************************************************************************************\n'
		fi
		if [[ $(grep -rni "x-pack:plugin:ml" test_results.log) ]]; then
			printf -- '****************************************************************************************************************************************\n'
			printf -- '\n Few unit test case failures are observed on s390x as X-Pack plugin is not supported and Machine Learning is not available for s390x.\n'
			printf -- '*****************************************************************************************************************************************\n'

		fi
	else
    	 printf --  '\nCould not run test cases successfully\n'
	fi

}

function startService() {
	printf -- "\n\nstarting service\n"
	cd "${CURDIR}/elasticsearch"
	sudo tar -C /usr/share/ -xf distribution/archives/tar/build/distributions/elasticsearch-"${PACKAGE_VERSION}"-SNAPSHOT.tar.gz
	sudo mv /usr/share/elasticsearch-"${PACKAGE_VERSION}"-SNAPSHOT /usr/share/elasticsearch

	if ([[ -z "$(cut -d: -f1 /etc/group | grep elastic)" ]]); then
		printf -- '\nCreating group elastic\n'
		sudo /usr/sbin/groupadd elastic # If group is not already created

	fi
	sudo chown "$NON_ROOT_USER:elastic" -R /usr/share/elasticsearch

	#To access elastic search from anywhere
	sudo ln -sf /usr/share/elasticsearch/bin/elasticsearch /usr/bin/

	# elasticsearch calls this file internally
	sudo ln -sf /usr/share/elasticsearch/bin/elasticsearch-env /usr/bin/

	#Verify elasticsearch installation
	if command -v "$PACKAGE_NAME" >/dev/null; then
		printf -- "%s installation completed.\n" "$PACKAGE_NAME"
	else
		printf -- "Error while installing %s, exiting with 127 \n" "$PACKAGE_NAME"
		exit 127
	fi

	printf -- 'Service started\n'
}

function installClient() {
	printf -- '\nInstalling curator client\n'
	if [[ "${ID}" == "sles" ]]; then
		sudo zypper install -y python-pip python-devel
	fi

	if [[ "${ID}" == "ubuntu" ]]; then
		sudo apt-get update
		sudo apt-get install -y python-pip
	fi

	if [[ "${ID}" == "rhel" ]]; then
		sudo yum install -y python-setuptools
		sudo easy_install pip
	fi

	sudo -H pip install elasticsearch-curator
	printf -- "\nInstalled Elasticsearch Curator client successfully"



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
		if command -v "$PACKAGE_NAME" >/dev/null; then
			TESTS="true"
			printf -- "%s is detected with version %s .\n" "$PACKAGE_NAME" "$PACKAGE_VERSION" |& tee -a "$LOG_FILE"
			runTest |& tee -a "$LOG_FILE"
			reviewTest |& tee -a "$LOG_FILE"
			exit 0

		else
			TESTS="true"
		fi
		;;
	esac
done

function printSummary() {
	printf -- '\n********************************************************************************************************\n'
	printf -- "\n* Getting Started * \n"
	printf -- '\n\nSet JAVA_HOME to start using elasticsearch right away.'
	printf -- '\nexport JAVA_HOME=/usr/local/jdk-11+28/\n'
	printf -- '\nRestarting the session will apply changes automatically'
	printf -- '\n\nStart Elasticsearch using the following command :   elasticsearch '
	printf -- '\nFor more information on curator client visit https://www.elastic.co/guide/en/elasticsearch/client/curator/current/index.html \n\n'
	printf -- '**********************************************************************************************************\n'

}

logDetails
prepare

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo apt-get update
	sudo apt-get install -y tar patch wget unzip curl maven git make automake autoconf libtool patch libx11-dev libxt-dev pkg-config texinfo locales-all ant hostname |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	startService |& tee -a "$LOG_FILE"
	installClient |& tee -a "$LOG_FILE"
	;;

"rhel-7.4" | "rhel-7.5" | "rhel-7.6")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo yum install -y unzip patch curl which git gcc-c++ make automake autoconf libtool libstdc++-static tar wget patch libXt-devel libX11-devel texinfo ant ant-junit.noarch hostname |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	startService |& tee -a "$LOG_FILE"
	installClient |& tee -a "$LOG_FILE"
	;;

"sles-12.3" | "sles-15")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo zypper --non-interactive install tar patch wget unzip curl which git gcc-c++ patch libtool automake autoconf ccache xorg-x11-proto-devel xorg-x11-devel alsa-devel cups-devel libstdc++6-locale glibc-locale libstdc++-devel libXt-devel libX11-devel texinfo ant ant-junit.noarch make net-tools | tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	startService |& tee -a "$LOG_FILE"
	installClient |& tee -a "$LOG_FILE"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

	#Run test

if [[ "$TESTS" == "true" ]]; then
	printf -- '\nRunning tests\n'
	runTest |& tee -a "$LOG_FILE"
	reviewTest |& tee -a "$LOG_FILE"
fi

cleanup
printSummary |& tee -a "$LOG_FILE"
