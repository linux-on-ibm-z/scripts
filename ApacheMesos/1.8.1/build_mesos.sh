#!/bin/bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ApacheMesos/1.8.1/build_mesos.sh
# Execute build script: bash build_mesos.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="mesos"
PACKAGE_VERSION="1.8.1"
CURDIR="$(pwd)"

REPO_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ApacheMesos/1.8.1/patch"

TESTS="false"
FORCE="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

# Check if directory exists
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
    rm -rf "$CURDIR/mesos/"

    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"
    
    # Installing IBM JDK 8 for Ubuntu
    if [[ "$ID" == "ubuntu" ]]  ;then
        cd "$CURDIR"
        wget http://public.dhe.ibm.com/ibmdl/export/pub/systems/cloud/runtimes/java/8.0.5.41/linux/s390x/ibm-java-s390x-sdk-8.0-5.41.bin
        echo -en 'INSTALLER_UI=silent\nUSER_INSTALL_DIR=/opt/java-1.8.0-ibm\nLICENSE_ACCEPTED=TRUE' > installer.properties
        sudo bash ibm-java-s390x-sdk-8.0-5.41.bin -i silent -f installer.properties
    fi

    # Installing Maven
    if [[ "$ID" == "sles" ]] ;then
        cd "$CURDIR"
        wget https://archive.apache.org/dist/maven/maven-3/3.3.9/binaries/apache-maven-3.3.9-bin.tar.gz
        sudo tar zxf apache-maven-3.3.9-bin.tar.gz -C /opt/
        export M2_HOME=/opt/apache-maven-3.3.9
        export PATH=$M2_HOME/bin:$PATH
    fi

    # Installing curl 7.64
    if [ "$DISTRO" == "ubuntu-18.04" ] ;then
        cd "$CURDIR"
        wget https://curl.haxx.se/download/curl-7.64.0.tar.gz
        tar -xzvf curl-7.64.0.tar.gz
        cd curl-7.64.0
        ./configure --disable-shared
        make
        sudo make install
        sudo ldconfig
    fi

    # Setting up Java environment variables
    if [[ "$ID" == "rhel"  ]] ;then
        export JAVA_HOME=/usr/lib/jvm/java-1.8.0-ibm
    fi
    if [[ "$ID" == "sles"  ]] ;then
        export JAVA_HOME=/usr/lib64/jvm/java-1.8.0-ibm
    fi
    if [[ "$ID" == "ubuntu"  ]] ;then
        export JAVA_HOME=/opt/java-1.8.0-ibm
    fi
    export JVM_DIR=$JAVA_HOME/jre/lib/s390x/default
    export JAVA_TEST_LDFLAGS="-L$JVM_DIR -R$JVM_DIR -Wl,-ljvm -ldl"
    export JAVA_JVM_LIBRARY=$JAVA_HOME/jre/lib/s390x/default/libjvm.so
    export PATH=$JAVA_HOME/bin:$PATH

    # Downloading and patching Mesos
    cd "$CURDIR"
    git clone -b ${PACKAGE_VERSION} https://github.com/apache/mesos
    cd "$CURDIR/mesos/3rdparty/"
    git clone -b v1.11.0 https://github.com/grpc/grpc.git grpc-1.11.0
    cd grpc-1.11.0/
    git submodule update --init third_party/cares
    cd ..
    tar zcf grpc-1.11.0.tar.gz --exclude .git grpc-1.11.0
    rm -rf grpc-1.11.0

    cd "$CURDIR/mesos"

    # Patching versions.am file
    sed -i -e 's/1.10.0/1.11.0/g' 3rdparty/versions.am

    # Patching ext_modules.py.in file
    sed -i -e 's/1.10.0/1.11.0/g' src/python/native_common/ext_modules.py.in

    # Patching protobuf-3.5.0.patch file
    curl -o "protobuf-3.5.0.patch"  $REPO_URL/protobuf-3.5.0.patch
    cat protobuf-3.5.0.patch >> 3rdparty/protobuf-3.5.0.patch
    rm protobuf-3.5.0.patch

    # Patching boost-1.65.0.patch file
    if [ "$DISTRO" == "ubuntu-19.04" ] ;then
        curl -o "boost-1.65.0.patch"  $REPO_URL/boost-1.65.0.patch
        cat boost-1.65.0.patch >> 3rdparty/boost-1.65.0.patch
        rm protobuf-3.5.0.patch
    fi

    # Building and installing Mesos
    ./bootstrap
    mkdir build
    cd build
    ../configure
    make
    sudo make install

    printf -- "Built and installed Apache Mesos successfully.\n"

    cleanup
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
    echo " build_mesos.sh  [-d debug] [-y install-without-confirmation] "
    echo
}

while getopts "h?dy" opt; do
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
    printf -- "Running Apache Mesos example on your local machine:\n"
    printf -- "Note: Apache Mesos must be run by a superuser. \n\n"
    printf -- "First run: sudo ldconfig \n\n"
    printf -- "Start master: \n"
    printf -- "mesos-master --ip=<ip-address> --work_dir=/var/lib/mesos  \n\n"
    printf -- "Start slave: \n"
    printf -- "mesos-agent --master=<ip-address>:5050 --work_dir=/var/lib/mesos \n\n"
    printf -- "You have successfully started Apache Mesos.\n\n"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare # Check Prerequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04" | "ubuntu-19.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y autoconf bzip2 curl gcc g++ git libapr1-dev libcurl4-nss-dev libsasl2-dev libssl-dev libsvn-dev libtool make maven patch python-dev python-six tar wget zlib1g-dev |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-7.5" | "rhel-7.6" | "rhel-7.7")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y apr-devel autoconf bzip2 curl cyrus-sasl-devel cyrus-sasl-md5 gcc gcc-c++ git java-1.8.0-ibm-devel libcurl-devel libtool make maven openssl-devel patch python-devel python-six subversion-devel tar wget zlib-devel |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-12.4" | "sles-15" | "sles-15.1")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install --auto-agree-with-licenses -y autoconf bzip2 curl cyrus-sasl-crammd5 cyrus-sasl-devel gcc gcc-c++ git java-1_8_0-ibm-devel libapr1-devel libcurl-devel libopenssl-devel libtool make patch python-devel python-pip python-six subversion-devel tar wget zlib-devel gawk gzip |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
