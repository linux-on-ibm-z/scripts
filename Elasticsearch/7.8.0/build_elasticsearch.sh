#!/bin/bash
# ©  Copyright IBM Corporation 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Elasticsearch/7.8.0/build_elasticsearch.sh
# Execute build script: bash build_elasticsearch.sh    (provide -h for help)
#
set -e -o pipefail

PACKAGE_NAME="elasticsearch"
PACKAGE_VERSION="7.8.0"
CURDIR="$(pwd)"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Elasticsearch/${PACKAGE_VERSION}/patch"
ES_REPO_URL="https://github.com/elastic/elasticsearch"

LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
NON_ROOT_USER="$(whoami)"
FORCE="false"

trap cleanup 0 1 2 ERR

# Check if directory exists
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
        rm -rf "${CURDIR}/OpenJDK14U-jdk_s390x_linux_hotspot_14.0.1_7.tar.gz"
	rm -rf "${CURDIR}/OpenJDK11U-jdk_s390x_linux_hotspot_11.0.7_10.tar.gz"
        printf -- '\nCleaned up the artifacts.\n' >>"$LOG_FILE"
}

function configureAndInstall() {
        printf -- '\nConfiguration and Installation started \n'

        #Installing dependencies
        printf -- 'User responded with Yes. \n'
        printf -- 'Downloading OpenJDK 14 with HotSpot. \n'

        wget https://github.com/AdoptOpenJDK/openjdk14-binaries/releases/download/jdk-14.0.1%2B7/OpenJDK14U-jdk_s390x_linux_hotspot_14.0.1_7.tar.gz
        sudo tar -C /usr/local -xzf OpenJDK14U-jdk_s390x_linux_hotspot_14.0.1_7.tar.gz
        export PATH=/usr/local/jdk-14.0.1+7/bin:$PATH
        java -version |& tee -a "$LOG_FILE"
        printf -- 'OpenJDK 14 with HotSpot installed\n'

        cd "${CURDIR}"
        # Setting environment variable needed for building
        export JAVA_HOME=/usr/local/jdk-14.0.1+7
        export JAVA14_HOME=/usr/local/jdk-14.0.1+7
        # Adding symlink for PATH
        sudo ln -sf /usr/local/jdk-14.0.1+7/bin/java /usr/bin/
        printf -- 'Adding JAVA_HOME to .bashrc \n'

        # Adding JAVA_HOME to ~/.bashrc
        cd "${HOME}"
        if [[ "$(grep -q JAVA_HOME .bashrc)" ]]; then
                printf -- '\nChanging JAVA_HOME\n'
                sed -n 's/^.*\bJAVA_HOME\b.*$/export JAVA_HOME=\/usr\/local\/jdk-14.0.1+7\//p' ~/.bashrc
        else
                echo "export JAVA_HOME=/usr/local/jdk-14.0.1+7/" >>.bashrc
        fi

        cd "${CURDIR}"
        # Download and configure ElasticSearch
        printf -- 'Downloading Elasticsearch. Please wait.\n'
        git clone -b v$PACKAGE_VERSION $ES_REPO_URL

        # Download required files and apply patch
        cd "${CURDIR}/elasticsearch"
	wget $PATCH_URL/build.gradle -P ${CURDIR}/elasticsearch/distribution/archives/linux-s390x-tar
        wget $PATCH_URL/build.gradle -P ${CURDIR}/elasticsearch/distribution/archives/oss-linux-s390x-tar
	wget $PATCH_URL/build.gradle -P ${CURDIR}/elasticsearch/distribution/packages/s390x-deb
	wget $PATCH_URL/build.gradle -P ${CURDIR}/elasticsearch/distribution/packages/s390x-oss-deb
	wget $PATCH_URL/build.gradle -P ${CURDIR}/elasticsearch/distribution/packages/s390x-oss-rpm
	wget $PATCH_URL/build.gradle -P ${CURDIR}/elasticsearch/distribution/packages/s390x-rpm
	wget $PATCH_URL/build.gradle -P ${CURDIR}/elasticsearch/distribution/docker/docker-s390x-export
	wget $PATCH_URL/build.gradle -P ${CURDIR}/elasticsearch/distribution/docker/oss-docker-s390x-export
	wget $PATCH_URL/docker_build_context_build.gradle -P ${CURDIR}/elasticsearch/distribution/docker/docker-s390x-build-context
	mv ${CURDIR}/elasticsearch/distribution/docker/docker-s390x-build-context/docker_build_context_build.gradle ${CURDIR}/elasticsearch/distribution/docker/docker-s390x-build-context/build.gradle
	wget $PATCH_URL/oss_docker_build_context_build.gradle -P ${CURDIR}/elasticsearch/distribution/docker/oss-docker-s390x-build-context
    	mv ${CURDIR}/elasticsearch/distribution/docker/oss-docker-s390x-build-context/oss_docker_build_context_build.gradle ${CURDIR}/elasticsearch/distribution/docker/oss-docker-s390x-build-context/build.gradle
        wget -O - $PATCH_URL/diff.patch | git apply
        
        # Building Elasticsearch
        printf -- 'Building Elasticsearch \n'
        printf -- 'Build might take some time. Sit back and relax\n'
		./gradlew :distribution:archives:oss-linux-s390x-tar:assemble --parallel

        # Verifying Elasticsearch installation
        if [[ $(grep -q "BUILD FAILED" "$LOG_FILE") ]]; then
                printf -- '\nBuild failed due to some unknown issues.\n'
                exit 1
        fi
        printf -- 'Built Elasticsearch successfully. \n\n'
        
        printf -- 'Creating distributions as deb, rpm and docker: \n\n'
  	./gradlew :distribution:packages:s390x-oss-deb:assemble
 	printf -- 'Created deb distribution. \n\n'
  	./gradlew :distribution:packages:s390x-oss-rpm:assemble
	printf -- 'Created rpm distribution. \n\n'
  	./gradlew :distribution:docker:oss-docker-s390x-build-context:assemble
  	printf -- 'Created docker distribution. \n\n'
      
	printf -- "\n\nInstalling Elasticsearch\n"

        cd "${CURDIR}/elasticsearch"
        sudo mkdir /usr/share/elasticsearch
        sudo tar -xzf distribution/archives/oss-linux-s390x-tar/build/distributions/elasticsearch-oss-"${PACKAGE_VERSION}"-SNAPSHOT-linux-s390x.tar.gz -C /usr/share/elasticsearch --strip-components 1
	sudo ln -sf /usr/share/elasticsearch/bin/* /usr/bin/

        if ([[ -z "$(cut -d: -f1 /etc/group | grep elastic)" ]]); then
                printf -- '\nCreating group elastic.\n'
                sudo /usr/sbin/groupadd elastic # If group is not already created
        fi
        sudo chown "$NON_ROOT_USER:elastic" -R /usr/share/elasticsearch

        # Verifying Elasticsearch installation
        if command -v "$PACKAGE_NAME" >/dev/null; then
                printf -- "%s installation completed.\n" "$PACKAGE_NAME"
        else
                printf -- "Error while installing %s, exiting with 127 \n" "$PACKAGE_NAME"
                exit 127
        fi
}

function runTest() {
        # Setting environment variable needed for testing
	set -x
	#export LANG="en_US.UTF-8"
	export JAVA_TOOL_OPTIONS="-Dfile.encoding=UTF8"
	export JAVA_HOME=/usr/local/jdk-14.0.1+7
        export JAVA14_HOME=/usr/local/jdk-14.0.1+7
	export PATH=$JAVA_HOME/bin:$PATH
	cd "${CURDIR}"
        wget https://github.com/AdoptOpenJDK/openjdk11-binaries/releases/download/jdk-11.0.7%2B10/OpenJDK11U-jdk_s390x_linux_hotspot_11.0.7_10.tar.gz
        sudo tar -C /usr/local -xzf OpenJDK11U-jdk_s390x_linux_hotspot_11.0.7_10.tar.gz
        printf -- 'OpenJDK 11 with HotSpot installed for testing\n'

        export JAVA11_HOME=/usr/local/jdk-11.0.7+10
        export RUNTIME_JAVA_HOME=/usr/local/jdk-11.0.7+10

        cd "${CURDIR}/elasticsearch"
	set +e
        # Run Elasticsearch test suite
        printf -- '\n Running Elasticsearch test suite.\n'
        ./gradlew --continue test -Dtests.haltonfailure=false -Dtests.jvm.argline="-Xss2m" |& tee -a ${CURDIR}/logs/test_results.log

        printf -- '***********************************************************************************************************************************'
        printf -- '\n Some X-Pack test cases will fail as X-Pack plugins are not supported on s390x, such as Machine Learning features.\n'
        printf -- '***********************************************************************************************************************************\n'
	set -e
}

function installClient() {
        printf -- '\nInstalling Elasticsearch Curator client\n'
        if [[ "${ID}" == "sles" ]]; then
          sudo zypper install -y python3 python3-pip
        fi

        if [[ "${ID}" == "ubuntu" ]]; then
          sudo apt-get update
          sudo apt-get install -y python3-pip
        fi

        if [[ "${ID}" == "rhel" ]]; then
          sudo yum install -y python3-devel
        fi

        if [[ "${ID}" == "sles" ]]; then
          sudo -H env PATH=$PATH pip3 install elasticsearch-curator
        else
          sudo -H pip3 install elasticsearch-curator
        fi
		# Verifying Elasticsearch installation
        if command -v curator >/dev/null; then
                printf -- "\nInstalled Elasticsearch Curator client successfully\n"
        else
                printf -- "\nError occured in installation of Curator client\n"
                exit 127
        fi
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
                        exit 0

                else
                        TESTS="true"
                fi
                ;;
        esac
done

function printSummary() {
        printf -- '\n***********************************************************************************************************************************\n'
        printf -- "\n* Getting Started * \n"
        printf -- '\nSet JAVA_HOME to start using Elasticsearch right away:'
        printf -- '\nexport JAVA_HOME=/usr/local/jdk-14.0.1+7/\n'
        printf -- '\nRestarting the session will apply changes automatically.'
        printf -- '\n\nStart Elasticsearch using the following command: elasticsearch '
        printf -- '\n\nFor more information on curator client visit: \nhttps://www.elastic.co/guide/en/elasticsearch/client/curator/current/index.html \n\n'
        printf -- '***********************************************************************************************************************************\n'
}

logDetails
prepare

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo apt-get update
        sudo apt-get install -y curl git gzip tar wget patch locales |& tee -a "$LOG_FILE"
        sudo locale-gen en_US.UTF-8
        configureAndInstall |& tee -a "$LOG_FILE"
        installClient |& tee -a "$LOG_FILE"
        ;;

"rhel-7.6" | "rhel-7.7" | "rhel-7.8" | "rhel-8.1" | "rhel-8.2")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo yum install -y curl git gzip tar wget patch |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        installClient |& tee -a "$LOG_FILE"
        ;;

"sles-12.5")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo zypper install -y curl git gzip tar wget patch | tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        installClient |& tee -a "$LOG_FILE"
        ;;

*)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
        exit 1
        ;;
esac

# Run tests
if [[ "$TESTS" == "true" ]]; then
        runTest |& tee -a "$LOG_FILE"
fi

cleanup
printSummary |& tee -a "$LOG_FILE"
