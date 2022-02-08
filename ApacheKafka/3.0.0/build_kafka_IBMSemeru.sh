#!/bin/bash
# © Copyright IBM Corporation 2021,2022.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ApacheKafka/3.0.0/build_kafka_IBMSemeru.sh
# Execute build script: bash build_kafka_IBMSemeru.sh   (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="kafka"
PACKAGE_VERSION="3.0.0"
CURDIR="$(pwd)"
SOURCE_ROOT="$(pwd)"
FORCE="false"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ApacheKafka/3.0.0/patch"
ROCKSDB_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/RocksDB/v6.19.3"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
BUILD_ENV="$HOME/setenv.sh"

trap cleanup 0 1 2 ERR

# Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
    mkdir -p "$CURDIR/logs/"
fi

source "/etc/os-release"

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
        printf -- "\nAs part of the installation , dependencies would be installed/upgraded.\n"
        while true; do
            read -r -p "Do you want to continue (y/n) ? :  " yn
            case $yn in
            [Yy]*)
                printf -- 'User responded with Yes. \n' >>"$LOG_FILE"
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
    rm -rf "$CURDIR/ibm-semeru-open-jdk_s390x_linux_11.0.13_8_openj9-0.29.0.tar.gz"
    printf -- "Cleaned up the artifacts\n" 
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"
    
    # Installing IBM Semeru Runtime Java 11
    printf -- "Installing IBM Semeru Runtime Java 11 \n"
    cd "$CURDIR"
    wget https://github.com/ibmruntimes/semeru11-binaries/releases/download/jdk-11.0.13%2B8_openj9-0.29.0/ibm-semeru-open-jdk_s390x_linux_11.0.13_8_openj9-0.29.0.tar.gz
    sudo tar zxf ibm-semeru-open-jdk_s390x_linux_11.0.13_8_openj9-0.29.0.tar.gz -C /opt/
    export JAVA_HOME=/opt/jdk-11.0.13+8
    export PATH=$JAVA_HOME/bin:$PATH
    printf -- "Java version is :\n"
    java -version

    # Download the source code and build the jar files
    printf -- "Download the source code and build the jar files\n"
    cd "$CURDIR"
    git clone https://github.com/apache/kafka.git
    cd kafka
    git checkout ${PACKAGE_VERSION}
    curl -sSL $PATCH_URL/IBMSemeru.patch | git apply
    ./gradlew -PscalaOptimizerMode=method jar
    printf -- "Built Apache Kafka Jar successfully.\n"
    
    # Build and Create rocksdbjni-6.19.3.jar for s390x
    printf -- "Build and Create rocksdbjni-6.19.3.jar for s390x\n"
    cd "$CURDIR"
    curl -o build_rocksdb.sh $ROCKSDB_URL/build_rocksdb.sh
    bash build_rocksdb.sh -y
    cp rocksdb/java/target/rocksdbjni-6.19.3-linux64.jar ./rocksdbjni-6.19.3.jar
    printf -- "Built rocksdb and created rocksdbjni-6.19.3.jar successfully.\n"
    printf -- "Replace Rocksdbjni jar\n"
    cd $CURDIR/kafka
    find ./ ~/.gradle/ -name 'rocksdbjni-6.19.3.jar' -print0 | xargs -0 -n1 cp ../rocksdbjni-6.19.3.jar
    # Verify the installed jars have s390x support
    find ./ ~/.gradle/ -name 'rocksdbjni-6.19.3.jar' -print0 | xargs -0 -n1 unzip -l | grep s390x
    printf -- "export JAVA_HOME=/opt/jdk-11.0.13+8\n" > "$BUILD_ENV"
    printf -- "export PATH=$JAVA_HOME/bin:$PATH\n" >> "$BUILD_ENV"

    cleanup
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
    echo "bash build_kafka.sh [-d debug] [-y install-without-confirmation] "
    echo "  default: IBM Semeru Runtime JDK11 will be installed"
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

function gettingStarted() {
    printf -- '\n********************************************************************************************************\n'
    printf -- "\n* Getting Started * \n"
    printf -- "\n Note: Environment Variables(JAVA_HOME) needed have been added to $HOME/setenv.sh\n"
    printf -- "\n Note: To set the Environment Variables needed for Apache Kafka, please run: source $HOME/setenv.sh \n"
    printf -- "\n To run the unit tests of Apache Kafka, please run:"
    printf -- "\n        cd $CURDIR/kafka"
    printf -- "\n        ./gradlew test -PscalaOptimizerMode=method --continue    \n"
    printf -- "\n If any test fails due to timeout, try running it individually\n"
    printf -- "\n If the testing process hangs and stops making progress, it might be helpful to increase the limit of"
    printf -- "\n opening files using command ulimit -n <new_value> and restart the tests\n"
    printf -- "\n You could also try to use forkEvery = 1 gradle option for testing to reduce the number of test case failure\n"
    printf -- "\n To start Apache Kafka server refer: https://kafka.apache.org/quickstart#quickstart_startserver  \n\n"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare # Check Prerequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"ubuntu-18.04" | "ubuntu-20.04" | "ubuntu-21.04" | "ubuntu-21.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo apt-get -y install wget tar git curl unzip
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"rhel-7.8" | "rhel-7.9" | "rhel-8.2" | "rhel-8.4" | "rhel-8.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y wget tar git curl unzip ca-certificates
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"sles-12.5" | "sles-15.3")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y wget tar git curl unzip gzip
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
