#!/bin/bash
# © Copyright IBM Corporation 2021.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)

################################################################################################################################################################
#Script     :   build_soauth.sh
#Description:   The script builds and test Strimzi Kafka OAuth version v0.8.1 on Linux on IBM Z for RHEL (7.8, 7.9, 8.2, 8.3, 8.4),
#               Ubuntu (18.04, 20.04, 21.04) and SLES (12 SP5, 15 SP2, 15 SP3).
#Notes: Docker must be installed before running this script!
################################################################################################################################################################

set -e
set -o pipefail

PACKAGE_NAME="strimzi-kafka-oauth"
PACKAGE_VERSION="0.8.1"
ARQUILLIAN_CUBE_VERSION="1.18.2"
KEYCLOAK_VERSION="13.0.1"
HYDRA_VERSION="v1.8.5"
GOLANG_VERSION="1.16.5"
JAVA_PROVIDED="OpenJDK11"
FORCE="false"
TESTS="false"
CURDIR="$(pwd)"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/strimzi-kafka-oauth/0.8.1/patch"
GO_INSTALL_URL="https://golang.org/dl/go1.16.5.linux-s390x.tar.gz"
GO_DEFAULT="$CURDIR/go"
GO_FLAG="DEFAULT"
LOGDIR="$CURDIR/logs"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

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
        printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n'
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
    rm -rf "${CURDIR}/go1.16.5.linux-s390x.tar.gz"
    printf -- '\nCleaned up the artifacts.\n' >>"$LOG_FILE"
}

function configureAndInstall() {
    printf -- '\nConfiguration and Installation started \n'
    # Install go
    cd "$CURDIR"
    export LOG_FILE="$LOGDIR/configuration-$(date +"%F-%T").log"
    openj9_set=false

    if [[ "$JAVA_PROVIDED" == "AdoptJDK11_openj9" ]]; then
        # Install AdoptOpenJDK 11 (With OpenJ9)
        cd "$CURDIR"
        sudo mkdir -p /opt/adopt/java

        curl -SL -o adoptjdk.tar.gz https://github.com/AdoptOpenJDK/openjdk11-binaries/releases/download/jdk-11.0.8%2B10_openj9-0.21.0/OpenJDK11U-jdk_s390x_linux_openj9_11.0.8_10_openj9-0.21.0.tar.gz
        # Everytime new jdk is downloaded, Ensure that --strip valueis correct
        sudo tar -zxvf adoptjdk.tar.gz -C /opt/adopt/java --strip-components 1

        export JAVA_HOME=/opt/adopt/java
        openj9_set=true

        printf -- "Installation of AdoptOpenJDK 11 (With OpenJ9) is successful\n" >>"$LOG_FILE"
    fi

    # Build components using JDK11
    DISTRO="$ID-$VERSION_ID"
    case "$DISTRO" in
    "ubuntu-18.04" | "ubuntu-20.04" | "ubuntu-21.04")
        if [ "$openj9_set" = false ]; then
            export JAVA_HOME="/usr/lib/jvm/java-11-openjdk-s390x"
        fi
        ;;

    "rhel-7.8" | "rhel-7.9")
        if [ "$openj9_set" = false ]; then
            export JAVA_HOME="/usr/lib/jvm/java-11-openjdk-11.0.12.0.7-0.el7_9.s390x"
        fi
        export M2_HOME=$CURDIR/apache-maven-3.8.1
        export PATH=$M2_HOME/bin:$PATH
        export LD_LIBRARY_PATH=${CURDIR}/jffi-jffi-1.2.23/build/jni/${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
        ;;

    "rhel-8.2" | "rhel-8.3" | "rhel-8.4")
        if [ "$openj9_set" = false ]; then
            export JAVA_HOME="/usr/lib/jvm/java-11-openjdk-11.0.12.0.7-0.el8_4.s390x"
        fi
        export M2_HOME=$CURDIR/apache-maven-3.8.1
        export PATH=$M2_HOME/bin:$PATH
        export LD_LIBRARY_PATH=${CURDIR}/jffi-jffi-1.2.23/build/jni/${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
        ;;

    "sles-12.5" | "sles-15.2" | "sles-15.3")
        if [ "$openj9_set" = false ]; then
            export JAVA_HOME="/usr/lib64/jvm/java-11-openjdk-11"
        fi
        export M2_HOME=$CURDIR/apache-maven-3.8.1
        export PATH=$M2_HOME/bin:$PATH
        export LD_LIBRARY_PATH=${CURDIR}/jffi-jffi-1.2.23/build/jni/${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
        ;;

    *) ;;
    esac

    echo "JAVA_HOME set to $JAVA_HOME"
    export PATH=$JAVA_HOME/bin:$PATH:/usr/local/bin

    # Build strimzi-kafka-oauth
    printf -- "\nBuilding strimzi-kafka-oauth ... \n" | tee -a "$LOG_FILE"
    cd "$CURDIR"
    git clone -b ${PACKAGE_VERSION} https://github.com/strimzi/strimzi-kafka-oauth.git 2>&1 | tee -a "$LOG_FILE"
    cd strimzi-kafka-oauth
    mvn clean install 2>&1 | tee -a "$LOG_FILE"

    ## Validate build
    FILE=$CURDIR/strimzi-kafka-oauth/oauth-server/target/kafka-oauth-server-0.8.1.jar
    if [ -f "$FILE" ]; then
        echo "strimzi-kafka-oauth server built successfully - Jars available in respective target folders."
    else
        echo "strimzi-kafka-oauth failed to build. Please investigate log for failures."
    fi

}

function runTest() {
    set +e

    if command -v "docker" >/dev/null; then
        printf -- 'Docker is installed for this user : Continuing... \n' >>"$LOG_FILE"
        if [ "$(docker images | grep 0.23.0-kafka-2.8.0 | awk '{print $1}')" == "strimzi/kafka" ]; then
            printf -- 'Kafka image is available for this user : Continuing... \n' >>"$LOG_FILE"
        else
            printf -- 'Kafka image is missing - please install Strimzi Kafka Operator before proceeding with tests - see https://ibm.ent.box.com/file/847680789196 \n'
            exit 1
        fi
    else
        printf -- 'Docker installed? : No \n' >>"$LOG_FILE"
        printf -- 'Please install Docker before proceeding with test. \n'
        exit 1
    fi

    printf -- "\nInstalling Go ... \n" | tee -a "$LOG_FILE"
    wget $GO_INSTALL_URL
    sudo tar -C /usr/local -xzf go1.16.5.linux-s390x.tar.gz

    # Set GOPATH if not already set
    if [[ -z "${GOPATH}" ]]; then
        printf -- "\nSetting default value for GOPATH \n"
        # Check if go directory exists
        if [ ! -d "$CURDIR/go" ]; then
            mkdir "$CURDIR/go"
        fi
        export GOPATH="${GO_DEFAULT}"
    else
        printf -- "\nGOPATH already set : Value : %s \n" "$GOPATH"
        if [ ! -d "$GOPATH" ]; then
            mkdir -p "$GOPATH"
        fi
        export GO_FLAG="CUSTOM"
    fi

    # Run tests using JDK8 as per CI
    DISTRO="$ID-$VERSION_ID"
    case "$DISTRO" in
    "ubuntu-18.04" | "ubuntu-20.04" | "ubuntu-21.04")
        export JAVA_HOME="/usr/lib/jvm/java-8-openjdk-s390x"
        ;;

    "rhel-7.8" | "rhel-7.9")
        export JAVA_HOME="/usr/lib/jvm/java-1.8.0-openjdk-1.8.0.302.b08-0.el7_9.s390x"
        export M2_HOME=$CURDIR/apache-maven-3.8.1
        export PATH=$M2_HOME/bin:$PATH
        export LD_LIBRARY_PATH=${CURDIR}/jffi-jffi-1.2.23/build/jni/${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
        sudo ln /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
        ;;

    "rhel-8.2" | "rhel-8.3" | "rhel-8.4")
        export JAVA_HOME="/usr/lib/jvm/java-1.8.0-openjdk-1.8.0.302.b08-0.el8_4.s390x"
        export M2_HOME=$CURDIR/apache-maven-3.8.1
        export PATH=$M2_HOME/bin:$PATH
        export LD_LIBRARY_PATH=${CURDIR}/jffi-jffi-1.2.23/build/jni/${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
        sudo ln /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
        ;;

    "sles-12.5" | "sles-15.2" | "sles-15.3")
        export JAVA_HOME="/usr/lib64/jvm/java-1.8.0-openjdk-1.8.0"
        export M2_HOME=$CURDIR/apache-maven-3.8.1
        export PATH=$M2_HOME/bin:$PATH
        export LD_LIBRARY_PATH=${CURDIR}/jffi-jffi-1.2.23/build/jni/${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
        sudo ln /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
        ;;

    *) ;;
    esac

    export PATH=/usr/local/go/bin:$PATH
    export PATH=$JAVA_HOME/bin:$PATH:/usr/local/bin
    echo "JAVA_HOME for test is set to $JAVA_HOME"

    if [[ "$TESTS" == "true" ]]; then

        cd "$CURDIR/strimzi-kafka-oauth"

        # Run tests
        printf -- "\nRunning strimzi-kafka-oauth test suites ... \n" | tee -a "$LOG_FILE"
        mvn test 2>&1 | tee -a "$LOG_FILE"

        # Build arquillian-cube.
        printf -- "\nBuilding Arquillian Cube ${ARQUILLIAN_CUBE_VERSION} ... \n" | tee -a "$LOG_FILE"
        cd "$CURDIR"
        git clone -b ${ARQUILLIAN_CUBE_VERSION} https://github.com/arquillian/arquillian-cube.git 2>&1 | tee -a "$LOG_FILE"
        cd arquillian-cube/
        ## Apply the patch
        curl -s $PATCH_URL/arquillian.patch | git apply - 2>&1 | tee -a "$LOG_FILE"
        mvn clean install -Dmaven.test.skip=true 2>&1 | tee -a "$LOG_FILE"

        # Build s390x compatible quay.io/keycloak/keycloak container.
        cd "$CURDIR"
        printf -- "\nBuilding Keycloak container ... \n" | tee -a "$LOG_FILE"
        git clone -b ${KEYCLOAK_VERSION} https://github.com/keycloak/keycloak-containers.git 2>&1 | tee -a "$LOG_FILE"
        cd keycloak-containers/server/
        docker build -t quay.io/keycloak/keycloak:13.0.1 . 2>&1 | tee -a "$LOG_FILE"

        # Build s390x compatible oryd/hydra container.
        cd "$CURDIR"
        printf -- "\nBuilding oryd/hydra container ... \n" | tee -a "$LOG_FILE"
        git clone -b ${HYDRA_VERSION} https://github.com/ory/hydra.git 2>&1 | tee -a "$LOG_FILE"
        cd hydra/
        GO111MODULE=on make install-stable 2>&1 | tee -a "$LOG_FILE"
        docker build -t oryd/hydra:v1.8.5 -f .docker/Dockerfile-build . 2>&1 | tee -a "$LOG_FILE"

        # Backup /etc/hosts file
        printf -- "\nBacking up /etc/hosts file ... \n" | tee -a "$LOG_FILE"
        sudo cp /etc/hosts /etc/hosts.original
        sudo /bin/su -c "echo '127.0.0.1            keycloak
127.0.0.1            hydra
127.0.0.1            hydra-jwt
127.0.0.1            kafka' >> /etc/hosts"

        cd "$CURDIR/strimzi-kafka-oauth"
        # Run integration tests
        docker tag strimzi/kafka:0.23.0-kafka-2.8.0 quay.io/strimzi/kafka:0.23.0-kafka-2.8.0
        printf -- "\nRunning strimzi-kafka-oauth integration tests ... \n" | tee -a "$LOG_FILE"
        curl -s $PATCH_URL/hydra.patch | git apply - 2>&1 | tee -a "$LOG_FILE"
        mvn -e -V -B clean install -f testsuite -Pcustom -Dkafka.docker.image=strimzi-oauth-testsuite/kafka:2.8.0 -Ddockerfile.build.pullNewerImage=false | tee -a "$LOG_FILE"
        printf -- "Tests completed. \n"

        # Restore /etc/hosts file
        printf -- "\nRestoring /etc/hosts file ... \n" | tee -a "$LOG_FILE"
        sudo mv /etc/hosts.original /etc/hosts
    fi
    set -e
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
    echo "bash  build_souath.sh  [-y install-without-confirmation] [-t install-with-tests] [-j Java to use {AdoptJDK11_openj9}"
    echo
}

while getopts "h?dyj:t" opt; do
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
    j)
        JAVA_PROVIDED="$OPTARG"
        ;;
    t)
        if [ -f $CURDIR/strimzi-kafka-oauth/oauth-server/target/kafka-oauth-server-0.8.1.jar ]; then
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
    printf -- '\n\nFor information on Getting started with strimzi-kafka-oauth visit: \nhttps://github.com/strimzi/strimzi-kafka-oauth \n\n'
    printf -- '***********************************************************************************************************************************\n'
}

logDetails
prepare

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-18.04" | "ubuntu-20.04" | "ubuntu-21.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- "Installing dependencies ... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y gcc make wget git openjdk-11-jdk-headless openjdk-8-jdk-headless maven libjffi-jni clang curl 2>&1 | tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"rhel-7.8" | "rhel-7.9" | "rhel-8.2" | "rhel-8.3" | "rhel-8.4")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- "Installing dependencies ... it may take some time.\n"
    sudo yum install -y gcc make wget git java-1.8.0-openjdk-devel java-11-openjdk java-11-openjdk-devel clang ant curl 2>&1 | tee -a "$LOG_FILE"
    cd "$CURDIR"
    wget https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.8.1/apache-maven-3.8.1-bin.tar.gz
    tar -xvzf apache-maven-3.8.1-bin.tar.gz
    rm apache-maven-3.8.1-bin.tar.gz
    cd "$CURDIR"
    wget https://github.com/jnr/jffi/archive/jffi-1.2.23.tar.gz
    tar -xzvf jffi-1.2.23.tar.gz
    cd jffi-jffi-1.2.23
    ant
    rm "$CURDIR"/jffi-1.2.23.tar.gz
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"sles-12.5" | "sles-15.2" | "sles-15.3")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- "Installing dependencies ... it may take some time.\n"
    sudo zypper install -y gcc make wget git java-1_8_0-openjdk-devel java-11-openjdk java-11-openjdk-devel ant curl 2>&1 | tee -a "$LOG_FILE"
    cd "$CURDIR"
    wget https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.8.1/apache-maven-3.8.1-bin.tar.gz
    tar -xvzf apache-maven-3.8.1-bin.tar.gz
    rm apache-maven-3.8.1-bin.tar.gz
    cd "$CURDIR"
    wget https://github.com/jnr/jffi/archive/jffi-1.2.23.tar.gz
    tar -xzvf jffi-1.2.23.tar.gz
    cd jffi-jffi-1.2.23
    export JAVA_HOME="/usr/lib64/jvm/java-1.8.0-openjdk-1.8.0"
    export PATH=$JAVA_HOME/bin:$PATH
    ant
    rm "$CURDIR"/jffi-1.2.23.tar.gz
    configureAndInstall |& tee -a "$LOG_FILE"
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
