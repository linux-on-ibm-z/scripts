#!/bin/bash
# © Copyright IBM Corporation 2021.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ApacheKafka/2.8.0/build_kafka.sh
# Execute build script: bash build_kafka.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="kafka"
PACKAGE_VERSION="2.8.0"
CURDIR="$(pwd)"
SOURCE_ROOT="$(pwd)"
FORCE="false"
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
    rm -rf "$CURDIR/OpenJDK11U-jdk_s390x_linux_openj9_linuxXL_11.0.10_9_openj9-0.24.0.tar.gz"
    rm -rf "$CURDIR/OpenJDK8U-jdk_s390x_linux_openj9_linuxXL_8u282b08_openj9-0.24.0.tar.gz"
    printf -- "Cleaned up the artifacts\n" 
}
function installGCC() {
	set +e
	cd "$CURDIR"
	printf -- "Installing GCC 7 \n"
	printf -- "\nGCC v7.3.0 installed successfully. \n"
	mkdir gcc
	cd gcc
	wget https://ftpmirror.gnu.org/gcc/gcc-7.3.0/gcc-7.3.0.tar.xz
	tar -xf gcc-7.3.0.tar.xz
	cd gcc-7.3.0
	./contrib/download_prerequisites
	mkdir objdir
	cd objdir
	../configure --prefix=/opt/gcc --enable-languages=c,c++ --with-arch=zEC12 --with-long-double-128 \
          --build=s390x-linux-gnu --host=s390x-linux-gnu --target=s390x-linux-gnu                  \
          --enable-threads=posix --with-system-zlib --disable-multilib
	make -j 8
	sudo make install
	sudo ln -sf /opt/gcc/bin/gcc /usr/bin/gcc
	sudo ln -sf /opt/gcc/bin/g++ /usr/bin/g++
	sudo ln -sf /opt/gcc/bin/g++ /usr/bin/c++
	export PATH=/opt/gcc/bin:"$PATH"
	export LD_LIBRARY_PATH=/opt/gcc/lib64:"$LD_LIBRARY_PATH"
	export C_INCLUDE_PATH=/opt/gcc/lib/gcc/s390x-linux-gnu/7.3.0/include
	export CPLUS_INCLUDE_PATH=/opt/gcc/lib/gcc/s390x-linux-gnu/7.3.0/include
	sudo ln -sf /opt/gcc/lib64/libstdc++.so.6.0.24 /lib64/libstdc++.so.6
	sudo ln -sf /opt/gcc/lib64/libatomic.so.1 /lib64/libatomic.so.1
	set -e
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"
    
    # Installing AdoptOpenJDK11 + OpenJ9 with large heap
    printf -- "Installing AdoptOpenJDK11 + OpenJ9 with Large heap \n"
    cd "$CURDIR"
    wget https://github.com/AdoptOpenJDK/openjdk11-binaries/releases/download/jdk-11.0.10%2B9_openj9-0.24.0/OpenJDK11U-jdk_s390x_linux_openj9_linuxXL_11.0.10_9_openj9-0.24.0.tar.gz
    sudo tar zxf OpenJDK11U-jdk_s390x_linux_openj9_linuxXL_11.0.10_9_openj9-0.24.0.tar.gz -C /opt/
    export JAVA_HOME=/opt/jdk-11.0.10+9
    export PATH=$JAVA_HOME/bin:$PATH
    printf -- "export JAVA_HOME=/opt/jdk-11.0.10+9\n" >> "$BUILD_ENV"
    printf -- "export PATH=$JAVA_HOME/bin:$PATH\n" >> "$BUILD_ENV"
    printf -- "Java version is :\n"
    java -version

    # Download the source code and build the jar files
    printf -- "Download the source code and build the jar files\n"
    cd "$CURDIR"
    wget -O scala-2.13.3.patch https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ApacheKafka/2.8.0/patch/scala-2.13.3.patch
    git clone https://github.com/apache/kafka.git
    cd kafka
    git checkout ${PACKAGE_VERSION}
    git apply $CURDIR/scala-2.13.3.patch
    ./gradlew jar
    printf -- "Built Apache Kafka Jar successfully.\n"
    
    printf -- "Building rocksdbjni require java 8: Installing AdoptOpenJDK8 + OpenJ9 with Large heap \n"
    wget https://github.com/AdoptOpenJDK/openjdk8-binaries/releases/download/jdk8u282-b08_openj9-0.24.0/OpenJDK8U-jdk_s390x_linux_openj9_linuxXL_8u282b08_openj9-0.24.0.tar.gz
    sudo tar zxf OpenJDK8U-jdk_s390x_linux_openj9_linuxXL_8u282b08_openj9-0.24.0.tar.gz -C /opt/
    export JAVA_HOME=/opt/jdk8u282-b08
    export PATH=$JAVA_HOME/bin:$PATH
    printf -- "Java version is :\n"
    java -version
    
    # Build and Create rocksdbjni-5.18.4.jar for s390x
    printf -- "Build and Create rocksdbjni-5.18.4.jar for s390x\n"
    cd "$CURDIR"
    git clone https://github.com/facebook/rocksdb.git
    cd rocksdb
    git checkout v5.18.4
    sed -i '1656s/ARCH/MACHINE/g' Makefile
    PORTABLE=1 make shared_lib
    make rocksdbjava
    printf -- "Built rocksdb and created rocksdbjni-5.18.4.jar successfully.\n"
    printf -- "Replace Rocksdbjni jar\n"
    cp $CURDIR/rocksdb/java/target/rocksdbjni-5.18.4-linux64.jar $HOME/.gradle/caches/modules-2/files-2.1/org.rocksdb/rocksdbjni/5.18.4/def7af83920ad2c39eb452f6ef9603777d899ea0/rocksdbjni-5.18.4.jar
    cp $CURDIR/rocksdb/java/target/rocksdbjni-5.18.4-linux64.jar $CURDIR/kafka/streams/examples/build/dependant-libs-2.13.3/rocksdbjni-5.18.4.jar
    cp $CURDIR/rocksdb/java/target/rocksdbjni-5.18.4-linux64.jar $CURDIR/kafka/streams/build/dependant-libs-2.13.3/rocksdbjni-5.18.4.jar
    
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
    echo " build_kafka.sh [-d debug] [-y install-without-confirmation] "
    echo "  default: AdoptJDK 11 with Openj9 Large heap will be installed"
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
    printf -- "\n To start Apache Kafka server refer: https://kafka.apache.org/quickstart#quickstart_startserver  \n\n"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare # Check Prerequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"ubuntu-18.04" | "ubuntu-20.04" | "ubuntu-21.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo apt-get -y install wget tar hostname unzip zlib1g-dev libbz2-dev liblz4-dev libzstd-dev git make gcc-7 g++-7 curl
    sudo rm -rf /usr/bin/gcc /usr/bin/g++ /usr/bin/cc
    sudo ln -sf /usr/bin/gcc-7 /usr/bin/gcc
    sudo ln -sf /usr/bin/g++-7 /usr/bin/g++
    sudo ln -sf /usr/bin/gcc /usr/bin/cc
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"rhel-7.8" | "rhel-7.9")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"

    sudo yum install -y wget tar git hostname unzip procps snappy binutils bzip2 bzip2-devel curl gcc-c++ make which zlib-devel diffutils
    installGCC | tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
    
"rhel-8.2" | "rhel-8.3" | "rhel-8.4")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y wget tar git hostname snappy unzip procps binutils bzip2 bzip2-devel curl gcc-c++ make which zlib-devel diffutils
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
    
"sles-12.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y wget tar unzip snappy-devel libzip2 bzip2 curl gcc7 gcc7-c++ make which zlib-devel git
    sudo ln -sf /usr/bin/gcc-7 /usr/bin/gcc
    sudo ln -sf /usr/bin/g++-7 /usr/bin/g++
    sudo ln -sf /usr/bin/gcc /usr/bin/cc
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"sles-15.2" | "sles-15.3")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y unzip snappy-devel libzip5 bzip2 curl gcc-c++ make which zlib-devel tar wget git gzip gawk
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
