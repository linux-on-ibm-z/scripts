#!/bin/bash
# © Copyright IBM Corporation 2025
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ApacheSpark/3.5.4/build_spark.sh
# Execute build script: bash build_spark.sh    (provide -h for help)

set -e -o pipefail

# Pkg details
PACKAGE_NAME="spark"
PACKAGE_VERSION="3.5.4"

# Staging area
SOURCE_ROOT="$(pwd)"

PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ApacheSpark/${PACKAGE_VERSION}/patch"

JAVA_PROVIDED="Temurin11"
JDK11_URL="https://github.com/adoptium/temurin11-binaries/releases/download/jdk-11.0.25%2B9/OpenJDK11U-jdk_s390x_linux_hotspot_11.0.25_9.tar.gz"
JDK17_URL="https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.13%2B11/OpenJDK17U-jdk_s390x_linux_hotspot_17.0.13_11.tar.gz"

JDK8_URL="https://github.com/ibmruntimes/semeru8-binaries/releases/download/jdk8u432-b06_openj9-0.48.0/ibm-semeru-open-jdk_s390x_linux_8u432b06_openj9-0.48.0.tar.gz"

FORCE="true"
TESTS="false"
LOG_FILE="${SOURCE_ROOT}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
BUILD_ENV="${SOURCE_ROOT}/setenv.sh"

trap cleanup 0 1 2 ERR

# Check if directory exists
if [ ! -d "${SOURCE_ROOT}/logs/" ]; then
    mkdir -p "${SOURCE_ROOT}/logs/"
fi

# source os-release file
if [ -f "/etc/os-release" ]; then
    source "/etc/os-release"
fi
DISTRO="$ID-$VERSION_ID"

function prepare() {
    if  command -v "sudo" > /dev/null ;
    then
        printf -- 'Sudo : Yes\n' >> "${LOG_FILE}"
    else
        printf -- 'Sudo : No \n' >> "${LOG_FILE}"
        printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n';
        exit 1;
    fi;

    if [[ "$JAVA_PROVIDED" != "Temurin11" && "$JAVA_PROVIDED" != "OpenJDK11"  && "$JAVA_PROVIDED" != "OpenJDK17"  && "$JAVA_PROVIDED" != "Temurin17" ]]; then
        printf "$JAVA_PROVIDED is not supported, Please use valid java from {Temurin11, OpenJDK11, Temurin17, OpenJDK17} only\n"
        exit 1
    fi
    
    if [[ "$FORCE" == "true" ]] ;
    then
        printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "${LOG_FILE}"
    else
        printf -- "\nAs part of the installation , dependencies would be installed/upgraded.\n";

        while true; do
            read -r -p "Do you want to continue (y/n) ? :  " yn
            case $yn in
                [Yy]* ) printf -- 'User responded with Yes. \n' >> "${LOG_FILE}";
                break;;

                [Nn]* ) exit;;

                *)  echo "Please provide confirmation to proceed.";;
            esac
        done
    fi
    # zero out
    true > "${BUILD_ENV}"
}

function cleanup() {
    # Remove artifacts
    rm -f "${SOURCE_ROOT}/apache-maven-3.8.8-bin.tar.gz" "${SOURCE_ROOT}/jdk8.tar.gz" "${SOURCE_ROOT}/snappy-1.1.4.tar.gz"
    rm -rf "${SOURCE_ROOT}/apache-maven-3.8.8"
    rm -rf "${SOURCE_ROOT}/snappy-1.1.4"
    rm -rf "${SOURCE_ROOT}/aircompressor"
    rm -rf "${SOURCE_ROOT}/leveldb"
    printf -- "Cleaned up the artifacts\n" >> "${LOG_FILE}"
}

function buildAndInstallAirCompressor() {
    git clone -b "0.27" --single-branch https://github.com/airlift/aircompressor.git
    cd aircompressor
    curl -sSL "${PATCH_URL}/aircompressor.diff" | git apply -
    PATH="${SOURCE_ROOT}/apache-maven-3.8.8/bin:${PATH}" mvn install -B -V -DskipTests -Dair.check.skip-all
}

function runTests() {
    set +e

    # Fix for TTY related issues when launching the Ammonite REPL in tests.
    ORIG_TERM="$TERM"
    export TERM=vt100

    printf -- "Running tests\n"
    cd "${SOURCE_ROOT}/spark"
    ./build/mvn -B test -fn -pl '!sql/hive'

    export TERM="$ORIG_TERM"

    set -e
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

    # Set LANG to C.UTF-8 so character set related tests will pass
    export LANG="C.UTF-8"
    printf -- "export LANG=\"${LANG}\"\n"  >> "${BUILD_ENV}"

    # Install JDK8 (required for LevelDB JNI)
    cd "${SOURCE_ROOT}"
    curl -SL -o jdk8.tar.gz "${JDK8_URL}"
    sudo mkdir -p /opt/openjdk/8/
    sudo tar -zxf jdk8.tar.gz -C /opt/openjdk/8/ --strip-components 1
    export JAVA_HOME=/opt/openjdk/8
    printf -- "Install AdoptOpenJDK 8 success\n"

    if [[ "$JAVA_PROVIDED" == "Temurin11" ]]; then
        cd "${SOURCE_ROOT}"
        sudo mkdir -p /opt/openjdk/11/
        curl -SL -o jdk11.tar.gz "${JDK11_URL}"
        sudo tar -zxf jdk11.tar.gz -C /opt/openjdk/11/ --strip-components 1
        export JAVA_HOME=/opt/openjdk/11
        printf -- "Installation of Eclipse Adoptium Temurin Runtime (Java 11) is successful\n"
    elif [[ "$JAVA_PROVIDED" == "Temurin17" ]]; then
        cd "${SOURCE_ROOT}"
        sudo mkdir -p /opt/openjdk/17/
        curl -SL -o jdk17.tar.gz "${JDK17_URL}"
        sudo tar -zxf jdk17.tar.gz -C /opt/openjdk/17/ --strip-components 1
        export JAVA_HOME=/opt/openjdk/17
        printf -- "Installation of Eclipse Adoptium Temurin Runtime (Java 17) is successful\n"
    elif [[ "$JAVA_PROVIDED" == "OpenJDK11" ]]; then
        if [[ "${ID}" == "ubuntu" ]]; then
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-11-jdk
            export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x
        elif [[ "${ID}" == "rhel" ]]; then
            sudo yum install -y java-11-openjdk java-11-openjdk-devel
            export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
        elif [[ "${ID}" == "sles" ]]; then
            sudo zypper install -y java-11-openjdk java-11-openjdk-devel
            export JAVA_HOME=/usr/lib64/jvm/java-11-openjdk
        fi
        printf -- "Installation of OpenJDK 11 is successful\n"
    elif [[ "$JAVA_PROVIDED" == "OpenJDK17" ]]; then
        if [[ "${ID}" == "ubuntu" ]]; then
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-17-jdk
            export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-s390x
        elif [[ "${ID}" == "rhel" ]]; then
            sudo yum install -y java-17-openjdk java-17-openjdk-devel
            export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
        elif [[ "${ID}" == "sles" ]]; then
            sudo zypper install -y java-17-openjdk java-17-openjdk-devel
            export JAVA_HOME=/usr/lib64/jvm/java-17-openjdk-17
        fi
        printf -- "Installation of OpenJDK 17 is successful\n"
    else
        printf "$JAVA_PROVIDED is not supported, Please use valid java from {Temurin11, OpenJDK11, Temurin17, OpenJDK17} only"
        exit 1
    fi
    export PATH="${JAVA_HOME}/bin:${PATH}"
    printf -- "export JAVA_HOME=\"${JAVA_HOME}\"\n" >> "${BUILD_ENV}"
    printf -- "export PATH=\"${PATH}\"\n" >> "${BUILD_ENV}"

    # Install Maven 3.8.8 for leveldbjni and aircompressor
    cd "${SOURCE_ROOT}"
    wget https://archive.apache.org/dist/maven/maven-3/3.8.8/binaries/apache-maven-3.8.8-bin.tar.gz
    tar zxf apache-maven-3.8.8-bin.tar.gz

    # Build Snappy (required for LevelDB)
    cd "${SOURCE_ROOT}"
    wget https://github.com/google/snappy/releases/download/1.1.4/snappy-1.1.4.tar.gz
    tar -zxf snappy-1.1.4.tar.gz
    export SNAPPY_HOME="${SOURCE_ROOT}/snappy-1.1.4"
    cd "${SNAPPY_HOME}"
    ./configure --disable-shared --with-pic
    make
    sudo make install
    export LIBRARY_PATH="${SNAPPY_HOME}"

    # Build LevelDB JNI
    cd "${SOURCE_ROOT}"
    git clone -b s390x https://github.com/linux-on-ibm-z/leveldb.git
    git clone -b leveldbjni-1.8-s390x https://github.com/linux-on-ibm-z/leveldbjni.git
    export LEVELDB_HOME="${SOURCE_ROOT}/leveldb"
    export LEVELDBJNI_HOME="${SOURCE_ROOT}/leveldbjni"
    export C_INCLUDE_PATH="${LIBRARY_PATH}"
    export CPLUS_INCLUDE_PATH="${LIBRARY_PATH}"
    cd "${LEVELDB_HOME}"
    git apply "${LEVELDBJNI_HOME}/leveldb.patch"
    make libleveldb.a
    cd "${LEVELDBJNI_HOME}"
    JAVA_HOME="/opt/openjdk/8" PATH="/opt/openjdk/8/bin:${SOURCE_ROOT}/apache-maven-3.8.8/bin:${PATH}" mvn -B clean install -P download -Plinux64-s390x -DskipTests
    JAVA_HOME="/opt/openjdk/8" PATH="/opt/openjdk/8/bin:${SOURCE_ROOT}/apache-maven-3.8.8/bin:${PATH}" jar -xvf "${LEVELDBJNI_HOME}/leveldbjni-linux64-s390x/target/leveldbjni-linux64-s390x-1.8.jar"
    export LD_LIBRARY_PATH="${SOURCE_ROOT}/leveldbjni/META-INF/native/linux64/s390x${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
    printf -- "export LEVELDB_HOME=\"${LEVELDB_HOME}\"\n"  >> "${BUILD_ENV}"
    printf -- "export LEVELDBJNI_HOME=\"${LEVELDBJNI_HOME}\"\n"  >> "${BUILD_ENV}"
    printf -- "export LIBRARY_PATH=\"${LIBRARY_PATH}\"\n"  >> "${BUILD_ENV}"
    printf -- "export C_INCLUDE_PATH=\"${C_INCLUDE_PATH}\"\n"  >> "${BUILD_ENV}"
    printf -- "export CPLUS_INCLUDE_PATH=\"${CPLUS_INCLUDE_PATH}\"\n"  >> "${BUILD_ENV}"
    printf -- "export LD_LIBRARY_PATH=\"${LD_LIBRARY_PATH}\"\n" >> "${BUILD_ENV}"

    cd "${SOURCE_ROOT}"
    buildAndInstallAirCompressor

    cd "${SOURCE_ROOT}"
    git clone -b v"${PACKAGE_VERSION}" --depth 1 https://github.com/apache/spark.git
    printf -- 'Download source code success \n'

    cd "${SOURCE_ROOT}/spark"
    curl -sSL "${PATCH_URL}/spark.diff" | git apply -
    curl -sSL "${PATCH_URL}/disabledTests.diff" | git apply -
    curl -sSL https://patch-diff.githubusercontent.com/raw/apache/spark/pull/49606.patch | git apply -

    # Build Apache Spark
    cd "${SOURCE_ROOT}/spark"
    ./build/mvn -B -DskipTests clean install
    printf -- 'Build Apache Spark success \n'

    if [[ "$TESTS" == "true" ]]; then
        runTests
    fi

    cleanup
}

function logDetails() {
    printf -- '**************************** SYSTEM DETAILS *******************************************\n' >"${LOG_FILE}"

    if [ -f "/etc/os-release" ]; then
        cat "/etc/os-release" >> "${LOG_FILE}"
    fi

    cat /proc/version >>"${LOG_FILE}"
    printf -- '**************************************************************************************\n' >>"${LOG_FILE}"
    printf -- "Detected %s \n" "$PRETTY_NAME"
    printf -- "Request details : PACKAGE NAME= %s, VERSION= %s JDK= %s\n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$JAVA_PROVIDED" |& tee -a "${LOG_FILE}"
}

# Print the usage message
function printHelp() {
    echo
    echo "Usage: "
    echo " bash build_spark.sh  [-d debug] [-y install-without-confirmation] [-t run test cases] [-j Java to use from {Temurin11, OpenJDK11, Temurin17, OpenJDK17}]"
    echo " default: If no -j specified, Temurin11 will be installed"
    echo
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
    printf -- '\n****************************************************************************************************\n'
    printf -- "\n*Getting Started * \n"
    printf -- "Run following commands to get started: \n"
    printf -- "%s/spark/bin/spark-shell \n\n" "${SOURCE_ROOT}"
    printf -- "Note: Environment Variables needed have been added to setenv.sh\n"
    printf -- "Note: To set the Environment Variables needed for Spark, please run: source \"%s/setenv.sh\" \n" "${SOURCE_ROOT}"
    printf -- "For more help visit https://spark.apache.org/docs/latest/spark-standalone.html \n"
    printf -- '******************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites

case "$DISTRO" in
    "ubuntu-22.04" | "ubuntu-24.04")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo apt-get update
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y wget tar git libtool autoconf build-essential curl apt-transport-https cmake python3 procps |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

     "rhel-8.10")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo yum groupinstall -y 'Development Tools'  |& tee -a "${LOG_FILE}"
        sudo yum install -y wget tar git libtool autoconf make curl python3 procps-ng |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;
        
    "rhel-9.4" | "rhel-9.6")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo yum groupinstall -y 'Development Tools'  |& tee -a "${LOG_FILE}"
        sudo yum install -y --allowerasing rpmdevtools wget tar git libtool autoconf make curl python3 flex gcc redhat-rpm-config rpm-build pkgconfig gettext automake gdb bison gcc-c++ binutils procps-ng |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

    "sles-15.6")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo zypper install -y wget tar git libtool autoconf curl gcc make gcc-c++ zip unzip gzip gawk python3 procps |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

    *)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "${LOG_FILE}"
        exit 1
        ;;
esac

gettingStarted |& tee -a "${LOG_FILE}"

# There are TTY related issues when launching the Ammonite REPL in tests so try to reset to sane values.
stty sane || true
