#!/bin/bash
# © Copyright IBM Corporation 2019, 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Snappy-Java/1.1.7/build_snappyjava.sh
# Execute build script: bash build_snappyjava.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="Snappy-Java"
PACKAGE_VERSION="1.1.7"
SOURCE_ROOT="$(pwd)"

FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

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
	if [[ "${ID}" == "rhel" ]]; then	
		rm -rf $SOURCE_ROOT/cmake-3.1.0.tar
		printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
	fi
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

	#Check out the Snappy-Java source code
	cd $SOURCE_ROOT
	git clone https://github.com/xerial/snappy-java.git
	cd snappy-java
	git checkout 1.1.7
	
	make IBM_JDK_7=1 USE_GIT=1 GIT_SNAPPY_BRANCH=1.1.7 GIT_REPO_URL=https://github.com/google/snappy.git 	
	ldd target/snappy-1.1.7-Linux-s390x/libsnappyjava.so 
	
	printf -- "Snappy-Java 1.1.7 installed successfully. \n"   
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
    echo " build_snappyjava.sh  [-d debug] [-y install-without-confirmation] "
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
    printf -- "\n*Getting Started * \n"
    printf -- "\n Set environmanet variables : \n"   
    printf -- "     export PATH=$JAVA_HOME/bin:$PATH"
    printf -- "\n You can now compile java programs.\n"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y openjdk-8-jdk automake autoconf libtool pkg-config git wget tar make patch cmake curl |& tee -a "$LOG_FILE"
    export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-s390x  
    configureAndInstall |& tee -a "$LOG_FILE"
    export PATH=$JAVA_HOME/bin:$PATH
    ;;
"rhel-7.6" | "rhel-7.7" | "rhel-7.8" | "rhel-8.0" | "rhel-8.1")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
	
	if [[ "$DISTRO" == "rhel-8.0" ]]; then
		sudo yum install -y automake which cmake autoconf libtool pkgconfig gcc-c++-8.2.1 libstdc++-static-8.2.1 git wget tar make patch curl java-1.8.0-openjdk java-1.8.0-openjdk-devel |& tee -a "$LOG_FILE"
                export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk
	elif [[ "$DISTRO" == "rhel-8.1" ]]; then
	        sudo yum install -y  automake which autoconf libtool pkgconfig gcc-c++ libstdc++-static git wget tar make patch curl java-1.8.0-ibm.s390x java-1.8.0-ibm-devel.s390x cmake |& tee -a "$LOG_FILE"
		export JAVA_HOME=/etc/alternatives/java_sdk_ibm
        else
		sudo yum install -y  automake which autoconf libtool pkgconfig gcc-c++ libstdc++-static git wget tar make patch curl java-1.8.0-ibm.s390x java-1.8.0-ibm-devel.s390x |& tee -a "$LOG_FILE"
		export JAVA_HOME=/etc/alternatives/java_sdk_ibm

		#Install Cmake 3.1.0 
		cd $SOURCE_ROOT
		wget http://www.cmake.org/files/v3.1/cmake-3.1.0.tar.gz |& tee -a "$LOG_FILE"
		gzip -d cmake-3.1.0.tar.gz |& tee -a "$LOG_FILE"
		tar xvf cmake-3.1.0.tar |& tee -a "$LOG_FILE"
		cd cmake-3.1.0 
		./configure --prefix=/cmake-3.1.0/cmake |& tee -a "$LOG_FILE"
		make && sudo make install |& tee -a "$LOG_FILE"
		export PATH=$SOURCE_ROOT/cmake-3.1.0/bin:$PATH
	fi

	export PATH=$JAVA_HOME/bin:$PATH
	configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-12.4" | "sles-12.5" | "sles-15.1")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y automake autoconf libtool pkg-config gcc-c++ git-core wget tar make patch which curl net-tools cmake |& tee -a "$LOG_FILE"
    sudo zypper install -y --auto-agree-with-licenses java-1_8_0-ibm-devel |& tee -a "$LOG_FILE"
    export JAVA_HOME=/usr/lib64/jvm/java-1_8_0-ibm-1.8.0      
    export PATH=$JAVA_HOME/bin:$PATH
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
