#!/bin/bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/mesos/build_mesos.sh
# Execute build script: bash build_mesos.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="mesos"
PACKAGE_VERSION="1.7.0"
CURDIR="$(pwd)"
BUILD_DIR="/usr/local"
GRPC_VERSION="1.11.0"

REPO_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Mesos/patch"

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

  
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

    if [[ "$ID" == "rhel"  || "$ID" == "sles" ]] ;then
    cd "$CURDIR"
    wget http://www-us.apache.org/dist/maven/maven-3/3.3.9/binaries/apache-maven-3.3.9-bin.tar.gz
    tar zxvf apache-maven-3.3.9-bin.tar.gz
    export M2_HOME="$CURDIR"/apache-maven-3.3.9
    export PATH="$CURDIR"/apache-maven-3.3.9/bin:$PATH
    fi

    #export variables
     if [[ "$ID" == "rhel"  ]] ;then
    export JAVA_HOME=/usr/lib/jvm/java-1.8.0					# Only for RHEL
    fi
      if [[ "$ID" == "sles"  ]] ;then
    export JAVA_HOME=/usr/lib64/jvm/java-1.8.0					# Only for SLES
    fi

    if [[ "$ID" == "ubuntu"  ]] ;then
    export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk-s390x				# Only for Ubuntu
    fi

    export JAVA_TOOL_OPTIONS='-Xmx2048M'
    export PATH=$JAVA_HOME/bin:$PATH

    #Download mesos
    cd "$CURDIR"
    git clone -b ${PACKAGE_VERSION} https://github.com/apache/mesos 
    
    
    cd "$CURDIR/mesos/3rdparty/"
    git clone -b v$GRPC_VERSION https://github.com/grpc/grpc.git grpc-$GRPC_VERSION
    cd grpc-$GRPC_VERSION/
    git submodule update --init third_party/cares
    cd ../
    tar zcvf grpc-$GRPC_VERSION.tar.gz --exclude .git grpc-$GRPC_VERSION
    rm -rf grpc-$GRPC_VERSION
    

    # Patch versions.am file
	curl -o "versions.am.diff"  $REPO_URL/versions.am.diff
	# replace config file
	patch "${CURDIR}/mesos/3rdparty/versions.am" versions.am.diff
	printf -- 'Patched versions.am \n'

    # Patch ext_modules.py.in file
	curl -o "ext_modules.py.in.diff"  $REPO_URL/ext_modules.py.in.diff
	# replace config file
	patch "${CURDIR}/mesos/src/python/native_common/ext_modules.py.in" ext_modules.py.in.diff
	printf -- 'Patched ext_modules.py.in \n'
    
    # Patch protobuf-3.5.0.patch file
	curl -o "protobuf-3.5.0.patch.diff"  $REPO_URL/protobuf-3.5.0.patch.diff
	# replace config file
	patch "${CURDIR}/mesos/3rdparty/protobuf-3.5.0.patch" protobuf-3.5.0.patch.diff
	printf -- 'Patched protobuf-3.5.0.patch \n'

    
    # Patch mesos.pom.in file
	curl -o "mesos.pom.in.diff"  $REPO_URL/mesos.pom.in.diff
	# replace config file
	patch "${CURDIR}/mesos/src/java/mesos.pom.in" mesos.pom.in.diff
	printf -- 'Patched mesos.pom.in \n'


    #Build and install mesos
    cd "$CURDIR"/mesos
    ./bootstrap
    mkdir build
    cd build
    ../configure
    make
    # Install (Optional)
    sudo make install
    
    sudo chmod -Rf 755 "$CURDIR"/mesos
    sudo cp -Rf "$CURDIR"/mesos "$BUILD_DIR"/mesos
   
    #Give permission to user
	sudo chown -R "$USER" "$BUILD_DIR/mesos"
    
    
    printf -- "Build and install mesos success\n" 

 
    #cleanup
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
    printf -- "\n*Getting Started * \n"
    printf -- "Running mesos: \n\n"
    printf -- "Start master \n"
    printf -- "cd /usr/local/mesos/build \n"
    printf -- "sudo ./bin/mesos-master.sh --ip=<ip_address> --work_dir=/var/lib/mesos  \n\n"
    printf -- "Start slave: \n"
    printf -- "cd /usr/local/mesos/build \n"
    printf -- "sudo ./bin/mesos-agent.sh --master=<ip_address>:5050 --work_dir=/var/lib/mesos \n"
    printf -- "You have successfully started mesos.\n"
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
    sudo apt-get install -y tar wget git build-essential python-dev python-six python-virtualenv openjdk-8-jdk libcurl4-nss-dev libsasl2-dev libsasl2-modules maven libapr1-dev libsvn-dev zlib1g-dev libssl-dev autoconf automake libtool bzip2 unzip libgflags-dev libgtest-dev pkg-config clang libc++-dev patch curl |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-7.3" | "rhel-7.4" | "rhel-7.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y git tar wget java-1.8.0-openjdk-devel gcc gcc-c++ patch libzip-devel zlib-devel libcurl-devel apr apr-util apr-devel subversion subversion-devel cyrus-sasl-md5 cyrus-sasl-devel python-devel which autoconf automake libtool bzip2 unzip openssl openssl-devel gperftools-devel curl |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-12.3")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y wget tar gcc gcc-c++ git patch java-1_8_0-openjdk-devel libzypp-devel libapr1 libapr1-devel subversion subversion-devel cyrus-sasl-devel cyrus-sasl-crammd5 python-devel libclang autoconf automake libtool bzip2 unzip make curl |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-15")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y wget tar gcc gcc-c++ git patch java-1_8_0-openjdk-devel libzypp-devel apr-devel libapr1 subversion subversion-devel cyrus-sasl-devel cyrus-sasl-crammd5 python-devel libclang5 autoconf automake libtool bzip2 unzip python-xml  curl |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
