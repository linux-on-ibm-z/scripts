#!/bin/bash
# © Copyright IBM Corporation 2024.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/netty-tcnative/2.0.52/build_netty.sh
# Execute build script: bash build_netty.sh    (provide -h for help)
#

set -e -o pipefail

PACKAGE_NAME="netty-tcnative"
PACKAGE_VERSION="2.0.52"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/BoringSSL/Jan2021/patch"
MAVEN_VERSION="3.6.3"
SOURCE_ROOT="$(pwd)"
USER="$(whoami)"
FORCE="false"
LOG_FILE="${SOURCE_ROOT}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
JAVA_PROVIDED="OpenJDK11"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
    mkdir -p "$SOURCE_ROOT/logs/"
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
        printf "$JAVA_PROVIDED is not supported, Please use valid java from {Semeru11, Temurin11, OpenJDK11} only"
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
    cd $SOURCE_ROOT
    rm -rf apache-maven-${MAVEN_VERSION}-bin.tar.gz go1.18.linux-s390x.tar.gz cmake-3.7.2.tar.gz
    rm -rf ibm-semeru-open-jdk_s390x_linux_11.0.14.1_1_openj9-0.30.1.tar.gz
    rm -rf temurin11.tar.gz
    rm -rf jdk.tar.gz
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"

}
function configureAndInstall() {
    printf -- 'Configuration and Installation started \n'

    # Install JDK 11 and set environment variables
    echo "Java provided by user: $JAVA_PROVIDED" >>"$LOG_FILE"

    if [[ "$JAVA_PROVIDED" == "Semeru11" ]]; then
        # Install Semeru 11
        printf -- "\nInstalling Semeru 11 . . . \n"
        cd $SOURCE_ROOT
        wget https://github.com/ibmruntimes/semeru11-binaries/releases/download/jdk-11.0.14.1%2B1_openj9-0.30.1/ibm-semeru-open-jdk_s390x_linux_11.0.14.1_1_openj9-0.30.1.tar.gz
        tar -xf ibm-semeru-open-jdk_s390x_linux_11.0.14.1_1_openj9-0.30.1.tar.gz
        export JAVA_HOME=$SOURCE_ROOT/jdk-11.0.14.1+1
        printf -- "Installation of Semeru 11 is successful\n" >>"$LOG_FILE"

    elif [[ "$JAVA_PROVIDED" == "Temurin11" ]]; then
        # Install Temurin 11
        printf -- "\nInstalling Temurin 11 . . . \n"
        cd $SOURCE_ROOT
        wget -O temurin11.tar.gz https://github.com/adoptium/temurin11-binaries/releases/download/jdk-11.0.22%2B7/OpenJDK11U-jdk_s390x_linux_hotspot_11.0.22_7.tar.gz
        tar zxf temurin11.tar.gz
        export JAVA_HOME=$SOURCE_ROOT/jdk-11.0.22+7
        printf -- "Installation of Temurin 11 is successful\n" >>"$LOG_FILE"

    else #OpenJDK11
        if [[ "${ID}" == "ubuntu" ]]; then
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-11-jdk
            export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x
        elif [[ "${ID}" == "rhel" ]]; then
            sudo yum install -y java-11-openjdk-devel
            export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
        elif [[ "${ID}" == "sles" ]]; then
            sudo zypper install -y java-11-openjdk java-11-openjdk-devel
            export JAVA_HOME=/usr/lib64/jvm/java-11-openjdk
        fi
        printf -- "Installation of OpenJDK 11 is successful\n" >>"$LOG_FILE"
    fi

    export PATH=$JAVA_HOME/bin:$PATH
    printf -- "Java version is :\n"
    java -version

    # Install ninja (for SLES 12 SP5 and RHEL 7.x)
    if [[ "${DISTRO}" == "rhel-7"* || "$VERSION_ID" == "12.5" ]]; then

        printf -- "\nInstalling ninja . . . \n"
        cd $SOURCE_ROOT
        git clone https://github.com/ninja-build/ninja
        cd ninja
        git checkout v1.8.2
        ./configure.py --bootstrap
        export PATH=$SOURCE_ROOT/ninja:$PATH
    fi

    # Install maven (for SLES and RHEL 7.x)
    if [[ "${DISTRO}" == "rhel-7"* || "$VERSION_ID" == "12.5" ]]; then
    #if [[ "${DISTRO}" == "rhel-7"* || "$ID" == "sles" ]]; then
        printf -- "\nInstalling maven . . . \n"
        cd $SOURCE_ROOT
        wget https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz
        tar -xvzf apache-maven-${MAVEN_VERSION}-bin.tar.gz
        export PATH=$PATH:$SOURCE_ROOT/apache-maven-${MAVEN_VERSION}/bin/
    fi

    # Install GO (for RHEL 7.x and SLES only)
    if [[ "${DISTRO}" == "rhel-7"* || "$VERSION_ID" == "12.5" ]]; then
    #if [[ "$ID" == "sles" || "${DISTRO}" == "rhel-7"* ]]; then
        cd $SOURCE_ROOT
        sudo rm -rf /usr/local/go /usr/bin/go
        wget https://storage.googleapis.com/golang/go1.18.linux-s390x.tar.gz
        sudo tar -C /usr/local -xzf go1.18.linux-s390x.tar.gz
        export PATH=/usr/local/go/bin:$PATH
        export GOROOT=/usr/local/go
        export GOPATH=/usr/local/go/bin
    fi

    # Install cmake 3.7 (for RHEL 7.x and SLES 12 SP5)
    if [[ "${DISTRO}" == "rhel-7"* ]]; then
        cd $SOURCE_ROOT
        wget https://cmake.org/files/v3.7/cmake-3.7.2.tar.gz
        tar xzf cmake-3.7.2.tar.gz
        cd cmake-3.7.2
        ./configure --prefix=/usr/local
        sudo make && sudo make install
    elif [[ "$VERSION_ID" == "12.5" ]]; then
        cd $SOURCE_ROOT
        wget https://cmake.org/files/v3.7/cmake-3.7.2.tar.gz
        tar xzf cmake-3.7.2.tar.gz
        cd cmake-3.7.2
        ./bootstrap --prefix=/usr
        sudo gmake && sudo gmake install
    fi

    # Build netty-tcnative
    cd $SOURCE_ROOT
    git clone https://github.com/netty/netty-tcnative.git
    cd netty-tcnative
    git checkout netty-tcnative-parent-${PACKAGE_VERSION}.Final

    cd $SOURCE_ROOT/netty-tcnative
    printf -- "\nApplying  patch . . . \n"
    # Apply patch
    sed -i '86,86 s/chromium-stable/patch-s390x-Jan2021/g' pom.xml
    sed -i '90,90 s/3a667d10e94186fd503966f5638e134fe9fb4080/d83fd4af80af244ac623b99d8152c2e53287b9ad/g' pom.xml
    sed -i '54,54 s/boringssl.googlesource.com/github.com\/linux-on-ibm-z/g' boringssl-static/pom.xml
    sed -i '55,55 s/chromium-stable/patch-s390x-Jan2021/g' boringssl-static/pom.xml
    sed -i 's/verbose=\"on\"/verbose=\"on\" retries=\"5\"/g' libressl-static/pom.xml

    if [[ "${DISTRO}" == "ubuntu-22.04" || "${DISTRO}" == "ubuntu-23.10" || "${DISTRO}" == "rhel-9"* ]]; then
        curl -o gcc_patch.diff $PATCH_URL/gcc_patch.diff
        cp gcc_patch.diff /tmp/gcc_patch.diff

        sed -i "182i <exec executable=\"git\" failonerror=\"true\" dir=\"\${boringsslSourceDir}\" resolveexecutable=\"true\">" boringssl-static/pom.xml
        sed -i "183i      <arg value=\"apply\" /> " boringssl-static/pom.xml
        sed -i "184i   <arg value=\"/tmp/gcc_patch.diff\" />" boringssl-static/pom.xml
        sed -i "185i   </exec>" boringssl-static/pom.xml

    fi

    ./mvnw clean install

    #Cleanup

    printf -- "\n Installation of netty was sucessfull \n\n"
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
    echo "  bash build_netty.sh  [-d debug] [-y install-without-confirmation] [-j Java to be used from {Semeru11, Temurin11, OpenJDK11}]"
    echo
}

while getopts "h?dyj:" opt; do
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
    esac
done

function gettingStarted() {
    printf -- '\n***********************************************************************************************\n'
    printf -- "Getting Started: \n"
    printf -- "Set LD_LIBRARY_PATH : \n"
    printf -- "  $ export LD_LIBRARY_PATH=$SOURCE_ROOT/netty-tcnative/openssl-dynamic/target/native-build/.libs/:\$LD_LIBRARY_PATH  \n\n"
    printf -- " \n\n"
    printf -- '*************************************************************************************************\n'
    printf -- '\n'
}

###############################################################################################################

logDetails
prepare #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-20.04" | "ubuntu-22.04" | "ubuntu-23.10" | "ubuntu-24.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update -y
    sudo apt-get install -y ninja-build cmake perl golang libssl-dev libapr1-dev autoconf automake libtool make tar git wget maven curl |& tee -a "${LOG_FILE}"
    configureAndInstall |& tee -a "${LOG_FILE}"
    ;;
"rhel-7.8" | "rhel-7.9")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo subscription-manager repos --enable=rhel-7-server-for-system-z-rhscl-rpms || true
    sudo yum install -y perl devtoolset-7-gcc-c++ devtoolset-7-gcc openssl-devel apr-devel autoconf automake libtool make tar git wget |& tee -a "${LOG_FILE}"
    source /opt/rh/devtoolset-7/enable
    configureAndInstall |& tee -a "${LOG_FILE}"
    ;;
"rhel-8."* | "rhel-9."*)
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y ninja-build cmake perl gcc gcc-c++ libarchive openssl-devel apr-devel autoconf automake libtool make tar git wget golang |& tee -a "${LOG_FILE}"
    configureAndInstall |& tee -a "${LOG_FILE}"
    ;;
"sles-12.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y perl libopenssl-devel libapr1-devel autoconf automake libtool make tar git wget gcc7 gcc7-c++ gmake |& tee -a "${LOG_FILE}"
    sudo ln -sf /usr/bin/gcc-7 /usr/bin/gcc
    sudo ln -sf /usr/bin/g++-7 /usr/bin/g++
    sudo ln -sf /usr/bin/gcc /usr/bin/cc
    configureAndInstall |& tee -a "${LOG_FILE}"
    ;;
"sles-15.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y awk ninja cmake perl libopenssl-devel apr-devel autoconf automake libtool make tar git wget gcc gcc-c++ gzip maven go |& tee -a "${LOG_FILE}"
    configureAndInstall |& tee -a "${LOG_FILE}"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
