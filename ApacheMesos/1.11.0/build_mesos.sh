#!/bin/bash
# © Copyright IBM Corporation 2021, 2023.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ApacheMesos/1.11.0/build_mesos.sh
# Execute build script: bash build_mesos.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="mesos"
PACKAGE_VERSION="1.11.0"
CURDIR="$(pwd)"
SOURCE_ROOT="$(pwd)"
JAVA_FLAV="ibmsdk"

PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ApacheMesos/1.11.0/patch"

TESTS="false"
FORCE="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

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
        printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n'
        exit 1
    fi
    if [[ "$JAVA_FLAV" != "openjdk" && "$JAVA_FLAV" != "ibmsdk" && "$JAVA_FLAV" != "adoptjdk" ]]; then
                printf "$JAVA_FLAV is not supported, Please use valid java from {openjdk, ibmsdk, adoptjdk} only"
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
	rm -rf "$CURDIR/apache-maven-3.3.9-bin.tar.gz"
	rm -rf "$CURDIR/curl-7.64.0.tar.gz"
    printf -- "Cleaned up the artifacts\n" 
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"
    
    # Installing IBM SDK 8 for Ubuntu
    if [[ "$ID" == "ubuntu" && "$JAVA_FLAV" == "ibmsdk" ]]  ;then
    	printf -- "Installing IBM SDK 8 for Ubuntu \n"
        cd "$CURDIR"
        wget https://public.dhe.ibm.com/ibmdl/export/pub/systems/cloud/runtimes/java/8.0.7.16/linux/s390x/ibm-java-s390x-sdk-8.0-7.16.bin
        echo -en 'INSTALLER_UI=silent\nUSER_INSTALL_DIR=/opt/java-1.8.0-ibm\nLICENSE_ACCEPTED=TRUE' > installer.properties
        sudo bash ibm-java-s390x-sdk-8.0-7.16.bin -i silent -f installer.properties
	export JAVA_HOME=/opt/java-1.8.0-ibm
    fi
    
    # Installing AdoptOpenJDK8 + OpenJ9
    if [[ "$JAVA_FLAV" == "adoptjdk" ]]  ;then
    	printf -- "Installing AdoptOpenJDK8 + OpenJ9 \n"
        cd "$CURDIR"
        wget https://github.com/AdoptOpenJDK/openjdk8-binaries/releases/download/jdk8u275-b01_openj9-0.23.0/OpenJDK8U-jdk_s390x_linux_openj9_8u275b01_openj9-0.23.0.tar.gz
        sudo tar zxf OpenJDK8U-jdk_s390x_linux_openj9_8u275b01_openj9-0.23.0.tar.gz -C /opt/
        export JAVA_HOME=/opt/jdk8u275-b01
        export JAVA_TOOL_OPTIONS='-Xmx2048M'
        export PATH=$JAVA_HOME/bin:$PATH
    fi

    # Installing Maven
    if [[ "$ID" == "sles" ]] ;then
    	printf -- "Installing Maven for SLES \n"
        cd "$CURDIR"
        wget https://archive.apache.org/dist/maven/maven-3/3.3.9/binaries/apache-maven-3.3.9-bin.tar.gz
        sudo tar zxf apache-maven-3.3.9-bin.tar.gz -C /opt/
        export M2_HOME=/opt/apache-maven-3.3.9
        export PATH=$M2_HOME/bin:$PATH
    fi

    # Installing curl 7.64
    if [ "$DISTRO" == "ubuntu-18.04" ] ;then
    	printf -- "Installing curl 7.64 for ubuntu-18.04 \n"
        cd "$CURDIR"
        wget https://curl.haxx.se/download/curl-7.64.0.tar.gz
        tar -xzvf curl-7.64.0.tar.gz
        cd curl-7.64.0
        ./configure --disable-shared
        make
        sudo make install
        sudo ldconfig
    fi
	
    if [[ "$JAVA_FLAV" == "openjdk" ]]; then
	    export JAVA_TOOL_OPTIONS='-Xmx2048M'
    elif [[ "$JAVA_FLAV" == "ibmsdk" ]]; then
	    export JVM_DIR=$JAVA_HOME/jre/lib/s390x/default
	    export JAVA_TEST_LDFLAGS="-L$JVM_DIR -R$JVM_DIR -Wl,-ljvm -ldl"
	    export JAVA_JVM_LIBRARY=$JAVA_HOME/jre/lib/s390x/default/libjvm.so
    fi
	
    export PATH=$JAVA_HOME/bin:$PATH
    printf -- "Java version is :\n"
    java -version

    # Downloading and patching Mesos
    printf -- "Downloading and patching Mesos\n"
    cd "$CURDIR"
    git clone -b ${PACKAGE_VERSION} https://github.com/apache/mesos
    cd "$CURDIR/mesos/3rdparty/"
    git clone -b v1.11.0 https://github.com/grpc/grpc.git grpc-1.11.0
    cd grpc-1.11.0/
    git submodule update --init third_party/cares
    cd ..
    tar zcf grpc-1.11.0.tar.gz --exclude .git grpc-1.11.0
    rm -rf grpc-1.11.0
    if [ "$DISTRO" == "ubuntu-20.04" ] || [ "$DISTRO" == "ubuntu-20.10" ]; then
        curl -o "grpc-1.11.0.patch"  $PATCH_URL/grpc-1.11.0.patch
    fi

    cd "$CURDIR/mesos"

    # Patching versions.am file
    printf -- "Patching versions.am file\n"
    sed -i -e 's/1.10.0/1.11.0/g' 3rdparty/versions.am

    # Patching ext_modules.py.in file
    printf -- "Patching ext_modules.py.in file\n"
    sed -i -e 's/1.10.0/1.11.0/g' src/python/native_common/ext_modules.py.in

    # Patching protobuf-3.5.0.patch file
    printf -- "Patching protobuf-3.5.0.patch file\n"
    curl -o "protobuf-3.5.0.patch"  $PATCH_URL/protobuf-3.5.0.patch
    cat protobuf-3.5.0.patch >> 3rdparty/protobuf-3.5.0.patch
    rm protobuf-3.5.0.patch

    # Patching boost-1.65.0.patch file
    if [ "$DISTRO" == "ubuntu-20.04" ] || [ "$DISTRO" == "ubuntu-20.10" ] || [ "$DISTRO" == "rhel-8.1" ] || [ "$DISTRO" == "rhel-8.2" ] || [ "$DISTRO" == "rhel-8.3" ]; then
        printf -- "Patching boost-1.65.0.patch file\n"
	    curl -o "boost-1.65.0.patch"  $PATCH_URL/boost-1.65.0.patch
        cat boost-1.65.0.patch >> 3rdparty/boost-1.65.0.patch
        rm boost-1.65.0.patch
    fi

    # Building and installing Mesos
    printf -- "Building and installing Mesos\n"
    ./bootstrap
    mkdir build
    cd build
    ../configure
    make
    sudo make install
    
    sudo cp -r $SOURCE_ROOT/mesos /usr/share

    printf -- "Built and installed Apache Mesos successfully.\n"

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
    echo
    echo "Usage: Builds using IBM_SDK java by default."
    echo " build_mesos.sh [-d debug] [-y install-without-confirmation] [-j Java to be used from {openjdk, ibmsdk, adoptjdk}] "
    echo "  default: If no -j specified, IBM Java 8 SDK will be installed"
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
	JAVA_FLAV="$OPTARG"
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
    printf -- "sudo mesos-master --ip=<ip-address> --work_dir=/var/lib/mesos  \n\n"
    printf -- "Start slave: \n"
    printf -- "sudo mesos-agent --master=<ip-address>:5050 --work_dir=/var/lib/mesos \n\n"
    printf -- "You have successfully started Apache Mesos.\n\n"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare # Check Prerequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"ubuntu-18.04" | "ubuntu-20.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
	if [[ "$JAVA_FLAV" == "openjdk" ]]; then
		printf -- "\nOpenJDK dependencies\n" |& tee -a "$LOG_FILE"
		sudo apt-get install -y autoconf bzip2 curl gcc g++ git libapr1-dev libcurl4-nss-dev libsasl2-dev libssl-dev libsvn-dev libtool make maven openjdk-8-jdk patch python-dev python-six tar wget zlib1g-dev |& tee -a "$LOG_FILE"
	        export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk-s390x
	elif [[ "$JAVA_FLAV" == "ibmsdk" ]]; then
		printf -- "\nIBMSDK dependencies\n" |& tee -a "$LOG_FILE"
		sudo apt-get install -y autoconf bzip2 curl gcc g++ git libapr1-dev libcurl4-nss-dev libsasl2-dev libssl-dev libsvn-dev libtool make maven patch python-dev python-six tar wget zlib1g-dev |& tee -a "$LOG_FILE"
	elif [[ "$JAVA_FLAV" == "adoptjdk" ]]; then
	        printf -- "\nAdoptJDK dependencies\n" |& tee -a "$LOG_FILE"
                sudo apt-get install -y autoconf bzip2 curl gcc g++ git libapr1-dev libcurl4-nss-dev libsasl2-dev libssl-dev libsvn-dev libtool make maven patch python-dev python-six tar wget zlib1g-dev |& tee -a "$LOG_FILE"
	fi
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"ubuntu-20.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
	if [[ "$JAVA_FLAV" == "openjdk" ]]; then
		printf -- "\nOpenJDK dependencies\n" |& tee -a "$LOG_FILE"
		sudo apt-get install -y autoconf bzip2 curl gcc-9 g++-9 git libapr1-dev libcurl4-nss-dev libsasl2-dev libssl-dev libsvn-dev libtool make maven openjdk-8-jdk patch python-dev python-six tar wget zlib1g-dev |& tee -a "$LOG_FILE"
                export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk-s390x
		sudo ln -s /usr/bin/gcc-9 /usr/bin/gcc
                sudo ln -s /usr/bin/g++-9 /usr/bin/g++
	elif [[ "$JAVA_FLAV" == "ibmsdk" ]]; then
		printf -- "\nIBMSDK dependencies\n" |& tee -a "$LOG_FILE"
		sudo apt-get install -y autoconf bzip2 curl gcc-9 g++-9 git libapr1-dev libcurl4-nss-dev libsasl2-dev libssl-dev libsvn-dev libtool make maven patch python-dev python-six tar wget zlib1g-dev |& tee -a "$LOG_FILE"
                sudo ln -s /usr/bin/gcc-9 /usr/bin/gcc
                sudo ln -s /usr/bin/g++-9 /usr/bin/g++
	elif [[ "$JAVA_FLAV" == "adoptjdk" ]]; then
	        printf -- "\nAdoptJDK dependencies\n" |& tee -a "$LOG_FILE"
		sudo apt-get install -y autoconf bzip2 curl gcc-9 g++-9 git libapr1-dev libcurl4-nss-dev libsasl2-dev libssl-dev libsvn-dev libtool make maven patch python-dev python-six tar wget zlib1g-dev |& tee -a "$LOG_FILE"
                sudo ln -s /usr/bin/gcc-9 /usr/bin/gcc
                sudo ln -s /usr/bin/g++-9 /usr/bin/g++
	fi
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-7.8" | "rhel-7.9")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
	if [[ "$JAVA_FLAV" == "openjdk" ]]; then
		printf -- "\nOpenJDK dependencies\n" |& tee -a "$LOG_FILE"
		sudo yum install -y apr-devel autoconf bzip2 curl cyrus-sasl-devel cyrus-sasl-md5 gcc gcc-c++ git java-1.8.0-openjdk-devel libcurl-devel libtool make maven openssl-devel patch python-devel python-six subversion-devel tar wget zlib-devel |& tee -a "$LOG_FILE"
	        export JAVA_HOME=/usr/lib/jvm/java-1.8.0
	elif [[ "$JAVA_FLAV" == "ibmsdk" ]]; then
		printf -- "\nIBMSDK dependencies\n" |& tee -a "$LOG_FILE"
		sudo yum install -y apr-devel autoconf bzip2 curl cyrus-sasl-devel cyrus-sasl-md5 gcc gcc-c++ git java-1.8.0-ibm-devel libcurl-devel libtool make maven openssl-devel patch python-devel python-six subversion-devel tar wget zlib-devel |& tee -a "$LOG_FILE"
	        export JAVA_HOME=/usr/lib/jvm/java-1.8.0-ibm
	elif [[ "$JAVA_FLAV" == "adoptjdk" ]]; then
	        printf -- "\nAdoptJDK dependencies\n" |& tee -a "$LOG_FILE"
		sudo yum install -y apr-devel autoconf bzip2 curl cyrus-sasl-devel cyrus-sasl-md5 gcc gcc-c++ git libcurl-devel libtool make maven openssl-devel patch python-devel python-six subversion-devel tar wget zlib-devel |& tee -a "$LOG_FILE"
	fi
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-8.1" | "rhel-8.2" | "rhel-8.3")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
         if [[ "$JAVA_FLAV" == "openjdk" ]]; then
	         printf -- "\nOpenJDK dependencies\n" |& tee -a "$LOG_FILE"
                 sudo yum install -y apr-devel autoconf bzip2 curl cyrus-sasl-devel cyrus-sasl-md5 gcc gcc-c++ git java-1.8.0-openjdk-devel libcurl-devel libtool make maven openssl-devel patch python2-devel python2-six subversion-devel tar wget zlib-devel |& tee -a "$LOG_FILE"
                 export JAVA_HOME=/usr/lib/jvm/java-1.8.0
	 elif [[ "$JAVA_FLAV" == "ibmsdk" ]]; then
		printf -- "\nIBMSDK dependencies\n" |& tee -a "$LOG_FILE"
                sudo yum install -y apr-devel autoconf bzip2 curl cyrus-sasl-devel cyrus-sasl-md5 gcc gcc-c++ git java-1.8.0-ibm-devel libcurl-devel libtool make maven openssl-devel patch python2-devel python2-six subversion-devel tar wget zlib-devel |& tee -a "$LOG_FILE"
                export JAVA_HOME=/usr/lib/jvm/java-1.8.0-ibm
	 elif [[ "$JAVA_FLAV" == "adoptjdk" ]]; then
	        printf -- "\nAdoptJDK dependencies\n" |& tee -a "$LOG_FILE"
		sudo yum install -y apr-devel autoconf bzip2 curl cyrus-sasl-devel cyrus-sasl-md5 gcc gcc-c++ git libcurl-devel libtool make maven openssl-devel patch python2-devel python2-six subversion-devel tar wget zlib-devel |& tee -a "$LOG_FILE"
	 fi
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-12.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
	if [[ "$JAVA_FLAV" == "openjdk" ]]; then
		printf -- "\nOpenJDK dependencies\n" |& tee -a "$LOG_FILE"
		sudo zypper install --auto-agree-with-licenses -y autoconf which bzip2 curl libnghttp2-devel cyrus-sasl-crammd5 cyrus-sasl-devel gcc gcc-c++ git java-1_8_0-openjdk-devel libapr1-devel libcurl-devel libopenssl-devel libtool make patch python-devel python-pip python-xml python-six subversion-devel tar wget zlib-devel gawk gzip |& tee -a "$LOG_FILE"
	        export JAVA_HOME=/usr/lib64/jvm/java-1.8.0
	elif [[ "$JAVA_FLAV" == "ibmsdk" ]]; then
	        printf -- "\nIBMSDK dependencies\n" |& tee -a "$LOG_FILE"
		sudo zypper install --auto-agree-with-licenses -y autoconf bzip2 curl libnghttp2-devel cyrus-sasl-crammd5 cyrus-sasl-devel gcc gcc-c++ git java-1_8_0-ibm-devel libapr1-devel libcurl-devel libopenssl-devel libtool make patch python-devel python-pip python-six subversion-devel tar wget zlib-devel gawk gzip which |& tee -a "$LOG_FILE"
	        export JAVA_HOME=/usr/lib64/jvm/java-1.8.0-ibm
	elif [[ "$JAVA_FLAV" == "adoptjdk" ]]; then
	        printf -- "\nAdoptJDK dependencies\n" |& tee -a "$LOG_FILE"
		sudo zypper install --auto-agree-with-licenses -y autoconf bzip2 curl libnghttp2-devel cyrus-sasl-crammd5 cyrus-sasl-devel gcc gcc-c++ git java-1_8_0-ibm-devel libapr1-devel libcurl-devel libopenssl-devel libtool make patch python-devel python-pip python-six subversion-devel tar wget zlib-devel gawk gzip |& tee -a "$LOG_FILE"
	fi
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-15.2")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
	if [[ "$JAVA_FLAV" == "openjdk" ]]; then
		printf -- "\nOpenJDK dependencies\n" |& tee -a "$LOG_FILE"
		sudo zypper install --auto-agree-with-licenses -y autoconf bzip2 curl cyrus-sasl-crammd5 cyrus-sasl-devel gcc gcc-c++ git java-1_8_0-openjdk-devel libapr1-devel libcurl-devel libopenssl-devel libtool make patch python-devel python-xml python3-pip python3-six subversion-devel tar wget zlib-devel gawk gzip |& tee -a "$LOG_FILE"
	        export JAVA_HOME=/usr/lib64/jvm/java-1.8.0
	elif [[ "$JAVA_FLAV" == "ibmsdk" ]]; then
	        printf -- "\nIBMSDK dependencies\n" |& tee -a "$LOG_FILE"
		sudo zypper install --auto-agree-with-licenses -y autoconf bzip2 curl cyrus-sasl-crammd5 cyrus-sasl-devel gcc gcc-c++ git java-1_8_0-ibm-devel libapr1-devel libcurl-devel libopenssl-devel libtool make patch python-devel python-xml python3-pip python3-six subversion-devel tar wget zlib-devel gawk gzip |& tee -a "$LOG_FILE"
	        export JAVA_HOME=/usr/lib64/jvm/java-1.8.0-ibm
	elif [[ "$JAVA_FLAV" == "adoptjdk" ]]; then
	        printf -- "\nAdoptJDK dependencies\n" |& tee -a "$LOG_FILE"
		sudo zypper install --auto-agree-with-licenses -y autoconf bzip2 curl cyrus-sasl-crammd5 cyrus-sasl-devel gcc gcc-c++ git libapr1-devel libcurl-devel libopenssl-devel libtool make patch python-devel python-xml python3-pip python3-six subversion-devel tar wget zlib-devel gawk gzip |& tee -a "$LOG_FILE"	
	fi
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
