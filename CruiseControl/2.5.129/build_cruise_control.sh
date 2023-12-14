#!/bin/bash
# © Copyright IBM Corporation 2023.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/CruiseControl/2.5.129/build_cruise_control.sh
# Execute build script: bash build_cruise_control.sh    (provide -h for help)
set -e -o pipefail
PACKAGE_NAME="cruise-control"
PACKAGE_VERSION="2.5.129"
CURDIR="$(pwd)"
FORCE="false"
TESTS="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
BUILD_ENV="$HOME/setenv.sh"
JAVA_PROVIDED="Semeru11"
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
if [[ "$JAVA_PROVIDED" != "Semeru11" && "$JAVA_PROVIDED" != "Temurin11" && "$JAVA_PROVIDED" != "OpenJDK11" ]]; then
        printf "$JAVA_PROVIDED is not supported, Please use valid java from {Semeru11, Temurin11, OpenJDK11} only\n"
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
    rm -f "$CURDIR/adoptjdk.tar.gz"
    printf -- "Cleaned up the artifacts\n"
}
function configureAndInstall() {
    printf -- "Configuration and Installation started \n"
if [[ "$JAVA_PROVIDED" == "Semeru11" ]]; then
        # Installing IBM Semeru Runtime (previously known as AdoptOpenJDK openj9)
        cd "$CURDIR"
        sudo rm -rf /opt/adopt/java
        sudo mkdir -p /opt/adopt/java
curl -SL -o adoptjdk.tar.gz https://github.com/ibmruntimes/semeru11-binaries/releases/download/jdk-11.0.18%2B10_openj9-0.36.1/ibm-semeru-open-jdk_s390x_linux_11.0.18_10_openj9-0.36.1.tar.gz
        # Everytime new jdk is downloaded, Ensure that --strip valueis correct
        sudo tar -zxvf adoptjdk.tar.gz -C /opt/adopt/java --strip-components 1
        export JAVA_HOME=/opt/adopt/java
printf -- "export JAVA_HOME=/opt/adopt/java\n" >> "$BUILD_ENV"
        printf -- "Installation of IBM Semeru Runtime (previously known as AdoptOpenJDK openj9) is successful\n" >> "$LOG_FILE"
elif [[ "$JAVA_PROVIDED" == "Temurin11" ]]; then
        # Installing Eclipse Adoptium Temurin Runtime (previously known as AdoptOpenJDK hotspot)
        cd "$CURDIR"
        sudo rm -rf /opt/adopt/java
        sudo mkdir -p /opt/adopt/java
curl -SL -o adoptjdk.tar.gz https://github.com/adoptium/temurin11-binaries/releases/download/jdk-11.0.18%2B10/OpenJDK11U-jdk_s390x_linux_hotspot_11.0.18_10.tar.gz
        # Everytime new jdk is downloaded, Ensure that --strip valueis correct
        sudo tar -zxvf adoptjdk.tar.gz -C /opt/adopt/java --strip-components 1
        export JAVA_HOME=/opt/adopt/java
printf -- "export JAVA_HOME=/opt/adopt/java\n" >> "$BUILD_ENV"
        printf -- "Installation of Eclipse Adoptium Temurin Runtime (previously known as AdoptOpenJDK hotspot) is successful\n" >> "$LOG_FILE"
elif [[ "$JAVA_PROVIDED" == "OpenJDK11" ]]; then
        if [[ "${ID}" == "ubuntu" ]]; then
                sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-11-jdk
                export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x
                printf -- "export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x\n" >> "$BUILD_ENV"
        elif [[ "${ID}" == "rhel" ]]; then
                sudo yum install -y java-11-openjdk java-11-openjdk-devel
                export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
                printf -- "export JAVA_HOME=/usr/lib/jvm/java-11-openjdk\n" >> "$BUILD_ENV"
        elif [[ "${ID}" == "sles" ]]; then
                sudo zypper install -y java-11-openjdk java-11-openjdk-devel
                export JAVA_HOME=/usr/lib64/jvm/java-11-openjdk
                printf -- "export JAVA_HOME=/usr/lib64/jvm/java-11-openjdk\n" >> "$BUILD_ENV"
        fi
        printf -- "Installation of OpenJDK 11 is successful\n" >> "$LOG_FILE"
    else
        printf "$JAVA_PROVIDED is not supported, Please use valid java from {Semeru11, Temurin11, OpenJDK11} only"
        exit 1
    fi
    printf -- "export PATH=$JAVA_HOME/bin:$PATH\n" >> "$BUILD_ENV"
    export PATH=$JAVA_HOME/bin:$PATH
    java -version
# Download the source code and build the jar files
    printf -- "Download the source code and build the jar files\n"
    cd "$CURDIR"
    git clone https://github.com/linkedin/cruise-control.git
    cd cruise-control
    git checkout ${PACKAGE_VERSION}
    ./gradlew jar
    printf -- "Built Cruise Control Jar successfully.\n"
#Run Tests
    runTest
#Cleanup
    cleanup
}
function runTest() {
    set +e
    if [[ "$TESTS" == "true" ]]; then
        printf -- "TEST Flag is set , Continue with running test \n"
        cd "$CURDIR/cruise-control"
        ./gradlew test --continue
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
    echo " bash build_cruise_control.sh [-d debug][-y install-without-confirmation][-t run-test][-j Java to use from {Semeru11, Temurin11, OpenJDK11}] "
    echo "  default: IBM Semeru Runtime (previously known as AdoptOpenJDK openj9) will be installed"
}
while getopts "h?dytj:" opt; do
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
    j)
        JAVA_PROVIDED="$OPTARG"
        ;;
    esac
done
function gettingStarted() {
    printf -- '\n********************************************************************************************************\n'
    printf -- "\n* Getting Started * \n"
    printf -- "\n Note: Environment Variables(JAVA_HOME) needed have been added to $HOME/setenv.sh\n"
    printf -- "\n Note: To set the Environment Variables needed for Cruise Control, please run: source $HOME/setenv.sh \n"
    printf -- "\n To start Cruise Control server refer: https://github.com/linkedin/cruise-control/tree/2.5.129#quick-start  \n\n"
    printf -- '**********************************************************************************************************\n'
}
logDetails
prepare # Check Prerequisites
DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-20.04" | "ubuntu-22.04" | "ubuntu-23.04" | "ubuntu-23.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y wget tar git curl gzip
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-7.8" | "rhel-7.9" | "rhel-8.6" | "rhel-8.8" | "rhel-8.9")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y wget tar git curl gzip procps-ng
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-9.0" | "rhel-9.2" | "rhel-9.3")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    # Use --allowerasing to allow 'curl' to be installed in case of conflicts with the package 'curl-minimal'
    sudo yum install -y --allowerasing wget tar git curl gzip procps-ng
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-12.5" | "sles-15.4" | "sles-15.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y wget tar git-core curl gzip gawk
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac
gettingStarted |& tee -a "$LOG_FILE"
