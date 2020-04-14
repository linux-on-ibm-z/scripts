#!/bin/bash
# © Copyright IBM Corporation 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/SonarQube/8.2/build_sonarqube.sh
# Execute build script: bash build_sonarqube.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="sonarqube"
PACKAGE_VERSION="8.2.0.32929"
SCANNER_VERSION="4.2.0.1873"

CURDIR="$(pwd)"
BUILD_DIR="/usr/local"

TESTS="false"
FORCE="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
    mkdir -p "$CURDIR/logs/"
fi

# Need handling for RHEL 6.10 as it doesn't have os-release file
if [ -f "/etc/os-release" ]; then
    source "/etc/os-release"
else
    cat /etc/redhat-release >>"${LOG_FILE}"
    export ID="rhel"
    export VERSION_ID="6.x"
    export PRETTY_NAME="Red Hat Enterprise Linux 6.x"
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
    sudo rm -rf sonar-scanner-cli-${SCANNER_VERSION}-linux.zip sonarqube-${PACKAGE_VERSION}.zip
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

    # Install AdoptOpenJDK
    printf -- 'Configuring AdoptOpenJDK \n'
    cd "$CURDIR"
    sudo wget https://github.com/AdoptOpenJDK/openjdk11-binaries/releases/download/jdk-11.0.4%2B11_openj9-0.15.1/OpenJDK11U-jdk_s390x_linux_openj9_11.0.4_11_openj9-0.15.1.tar.gz
    sudo tar -C /usr/local -xzf OpenJDK11U-jdk_s390x_linux_openj9_11.0.4_11_openj9-0.15.1.tar.gz
    export JAVA_HOME=/usr/local/jdk-11.0.4+11
    export PATH=$JAVA_HOME/bin:$PATH
    java -version |& tee -a "$LOG_FILE"
    printf -- 'AdoptOpenJDK 11 installed\n'

    #Download Sonarqube
    cd "$CURDIR"
    wget https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-${PACKAGE_VERSION}.zip
    unzip sonarqube-${PACKAGE_VERSION}.zip
    wget https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SCANNER_VERSION}-linux.zip
    unzip sonar-scanner-cli-${SCANNER_VERSION}-linux.zip
    printf -- "Download sonarqube success\n"

        if ([[ -z "$(cut -d: -f1 /etc/group | grep sonarqube)" ]]); then
                printf -- '\nCreating group sonarqube\n'
                sudo groupadd sonarqube      # If group is not already created

        fi
        sudo usermod -aG sonarqube $(whoami)

    sudo cp -Rf "$CURDIR"/sonarqube-${PACKAGE_VERSION} "$BUILD_DIR"

    #Give permission to user
    sudo chown $(whoami):sonarqube -R "$BUILD_DIR/sonarqube-${PACKAGE_VERSION}"

    #Run Test
    runTest

    #cleanup
    cleanup

}

function runTest() {

    set +e
    if [[ "$TESTS" == "true" ]]; then
        printf -- 'Running tests \n\n' |& tee -a "$LOG_FILE"
        cd /usr/local/sonarqube-${PACKAGE_VERSION}/lib/
        java -jar sonar-application-${PACKAGE_VERSION}.jar &
        pid=$!
        sleep 15m
        cd "$CURDIR"
        sed -i "40d" "$CURDIR"/sonar-scanner-${SCANNER_VERSION}-linux/bin/sonar-scanner
        sed -i '40 i use_embedded_jre=false' "$CURDIR"/sonar-scanner-${SCANNER_VERSION}-linux/bin/sonar-scanner
        git clone https://github.com/khatilov/sonar-examples.git
        cd "$CURDIR"/sonar-examples/projects/languages/java/sonar-runner/java-sonar-runner-simple/
        "$CURDIR"/sonar-scanner-${SCANNER_VERSION}-linux/bin/sonar-scanner
        curl http://localhost:9000/dashboard/index/java-sonar-runner-simple
        if [[ $(ps -A| grep $pid |wc -l) -ne 0 ]]; then #check whether process is still running
                sudo pkill -P $pid
        fi
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
    echo " build_sonarqube.sh  [-d debug] [-y install-without-confirmation] [-t install and run tests]"
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
    printf -- '\n********************************************************************************************************\n'
    printf -- "\n*Getting Started * \n"
    printf -- "Running sonarqube: \n"
    printf -- "Set Environment variable JAVA_HOME and PATH \n"
    printf -- " export JAVA_HOME=/usr/local/jdk-11.0.4+11 \n"
    printf -- " export PATH=\"\$JAVA_HOME/bin\":\"\$PATH\" \n"
    printf -- "cd /usr/local/sonarqube-$PACKAGE_VERSION/lib/ \n"
    printf -- "java -jar sonar-application-$PACKAGE_VERSION.jar \n\n"
    printf -- "You have successfully started sonarqube.\n"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04" | "ubuntu-19.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y wget git unzip tar curl |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-7.6" | "rhel-7.7" | "rhel-7.8" | "rhel-8.0" | "rhel-8.1")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y git wget unzip tar which curl |& tee -a "$LOG_FILE"
    if [[ "$DISTRO" == "rhel-8.0" ]]; 
        then
        sudo yum install -y procps |& tee -a "$LOG_FILE"
    fi
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-12.4" | "sles-12.5" | "sles-15.1")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y git wget unzip tar which gzip curl |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
