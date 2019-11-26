#!/bin/bash
# ©  Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Elasticsearch/7.4.1/build_elasticsearch.sh
# Execute build script: bash build_elasticsearch.sh    (provide -h for help)
#
set -e -o pipefail

PACKAGE_NAME="elasticsearch"
PACKAGE_VERSION="7.4.1"
CURDIR="$(pwd)"
REPO_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Elasticsearch/${PACKAGE_VERSION}/patch"
ES_REPO_URL="https://github.com/elastic/elasticsearch"

LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
NON_ROOT_USER="$(whoami)"
FORCE="false"

trap cleanup 0 1 2 ERR

# Check if directory exists
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
        rm -rf "${CURDIR}/OpenJDK12U-jdk_s390x_linux_hotspot_12.0.2_10.tar.gz"
        printf -- '\nCleaned up the artifacts.\n' >>"$LOG_FILE"
}

function configureAndInstall() {
        printf -- '\nConfiguration and Installation started \n'

        #Installing dependencies
        printf -- 'User responded with Yes. \n'
        printf -- 'Downloading OpenJDK 12 with HotSpot. \n'

        wget https://github.com/AdoptOpenJDK/openjdk12-binaries/releases/download/jdk-12.0.2%2B10/OpenJDK12U-jdk_s390x_linux_hotspot_12.0.2_10.tar.gz
        sudo tar -C /usr/local -xzf OpenJDK12U-jdk_s390x_linux_hotspot_12.0.2_10.tar.gz
        export PATH=/usr/local/jdk-12.0.2+10/bin:$PATH
        java -version |& tee -a "$LOG_FILE"
        printf -- 'OpenJDK 12 with HotSpot installed\n'

        cd "${CURDIR}"
        # Setting environment variable needed for building
        export JAVA_HOME=/usr/local/jdk-12.0.2+10
        export JAVA12_HOME=/usr/local/jdk-12.0.2+10
        # Adding symlink for PATH
        sudo ln -sf /usr/local/jdk-12.0.2+10/bin/java /usr/bin/
        printf -- 'Adding JAVA_HOME to .bashrc \n'

        # Adding JAVA_HOME to ~/.bashrc
        cd "${HOME}"
        if [[ "$(grep -q JAVA_HOME .bashrc)" ]]; then
                printf -- '\nChanging JAVA_HOME\n'
                sed -n 's/^.*\bJAVA_HOME\b.*$/export JAVA_HOME=\/usr\/local\/jdk-12.0.2+10\//p' ~/.bashrc
        else
                echo "export JAVA_HOME=/usr/local/jdk-12.0.2+10/" >>.bashrc
        fi

        cd "${CURDIR}"
        # Download and configure ElasticSearch
        printf -- 'Downloading Elasticsearch. Please wait.\n'
        git clone -b v$PACKAGE_VERSION $ES_REPO_URL

        # Applying patches
        cd "${CURDIR}/elasticsearch"
        # patch config file
        curl -o patch_gradle.diff $REPO_URL/patch_gradle.diff
        patch ${CURDIR}/elasticsearch/distribution/archives/build.gradle patch_gradle.diff
        
        # Building Elasticsearch
        printf -- 'Building Elasticsearch \n'
        printf -- 'Build might take some time. Sit back and relax\n'
        ./gradlew -p distribution/archives/oss-linux-tar assemble --parallel

        # Verifying Elasticsearch installation
        if [[ $(grep -q "BUILD FAILED" "$LOG_FILE") ]]; then
                printf -- '\nBuild failed due to some unknown issues.\n'
                exit 1
        fi
        printf -- 'Built Elasticsearch successfully. \n\n'
}

function runTest() {

        # Setting environment variable needed for testing
        export JAVA_HOME=/usr/local/jdk-12.0.2+10
        export JAVA12_HOME=/usr/local/jdk-12.0.2+10

        cd "${CURDIR}/elasticsearch"
        set +e

        # Run Elasticsearch test suite
        printf -- '\n Running Elasticsearch test suite.\n'
        ./gradlew --continue test -Dtests.haltonfailure=false -Dtests.jvm.argline="-Xss2m" | tee -a ${CURDIR}/logs/test_results.log

        printf -- '***********************************************************************************************************************************'
        printf -- '\n Some X-Pack test cases will fail as X-Pack plugins are not supported on s390x, such as Machine Learning features.\n'
        printf -- '***********************************************************************************************************************************\n'
}


function startService() {
        printf -- "\n\nInstalling Elasticsearch and starting service\n"

        cd "${CURDIR}/elasticsearch"
        sudo mkdir /usr/share/elasticsearch
        sudo tar -xzf distribution/archives/oss-linux-tar/build/distributions/elasticsearch-oss-"${PACKAGE_VERSION}"-SNAPSHOT-linux-s390x.tar.gz -C /usr/share/elasticsearch --strip-components 1
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

        printf -- 'Service started\n'
}

function installClient() {
        printf -- '\nInstalling Elasticsearch Curator client\n'
        if [[ "${ID}" == "sles" ]]; then
                sudo zypper install -y python-devel python-setuptools
                sudo easy_install pip
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
        printf -- '\nexport JAVA_HOME=/usr/local/jdk-12.0.2+10/\n'
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
        startService |& tee -a "$LOG_FILE"
        installClient |& tee -a "$LOG_FILE"
        ;;

"rhel-7.5" | "rhel-7.6" | "rhel-7.7")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo yum install -y curl git gzip tar wget patch |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        startService |& tee -a "$LOG_FILE"
        installClient |& tee -a "$LOG_FILE"
        ;;

"sles-12.4")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo zypper install -y curl git gzip tar wget patch | tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        startService |& tee -a "$LOG_FILE"
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
