#!/bin/bash
# © Copyright IBM Corporation 2025.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Erlang/27.3/build_erlang.sh
# Execute build script: bash build_erlang.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="erlang"
PACKAGE_VERSION="27.3"
CURDIR="$(pwd)"


TESTS="false"
FORCE="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
JAVA_PROVIDED="OpenJDK11"
BUILD_ENV="$HOME/setenv.sh"

trap cleanup 0 1 2 ERR

#Check if directory exists
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

    if [[ "$JAVA_PROVIDED" != "IBM_Semeru_8" && "$JAVA_PROVIDED" != "IBM_Semeru_11"  && "$JAVA_PROVIDED" != "IBM_Semeru_17" && "$JAVA_PROVIDED" != "IBM_Semeru_21" && "$JAVA_PROVIDED" != "Eclipse_Adoptium_Temurin_11" && "$JAVA_PROVIDED" != "Eclipse_Adoptium_Temurin_17" && "$JAVA_PROVIDED" != "Eclipse_Adoptium_Temurin_21" && "$JAVA_PROVIDED" != "OpenJDK11"  && "$JAVA_PROVIDED" != "OpenJDK17" && "$JAVA_PROVIDED" != "OpenJDK8" && "$JAVA_PROVIDED" != "OpenJDK21" ]];
    then
        printf --  "$JAVA_PROVIDED is not supported, Please use valid java from {IBM_Semeru_8, IBM_Semeru_11, IBM_Semeru_17, IBM_Semeru_21, Eclipse_Adoptium_Temurin_11, Eclipse_Adoptium_Temurin_17, Eclipse_Adoptium_Temurin_21, OpenJDK8, OpenJDK11, OpenJDK17, OpenJDK21} only." |& tee -a "$LOG_FILE"
        exit 1
    fi
    
    DISTRO="$ID-$VERSION_ID"
}

function cleanup() {
    # Remove artifacts

    if [ -f "$CURDIR/otp_src_${PACKAGE_VERSION}.tar.gz" ]; then
        rm -rf "$CURDIR/otp_src_${PACKAGE_VERSION}.tar.gz"
    fi
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

    echo "Java provided by user $JAVA_PROVIDED" >> "$LOG_FILE"

    if [[ "$JAVA_PROVIDED" == "IBM_Semeru_11" ]]; then
        # Install IBM_Semeru_11
        sudo mkdir -p /opt/java

        cd "$SOURCE_ROOT"
        sudo wget -O semeru11.tar.gz https://github.com/ibmruntimes/semeru11-binaries/releases/download/jdk-11.0.26%2B4_openj9-0.49.0/ibm-semeru-open-jdk_s390x_linux_11.0.26_4_openj9-0.49.0.tar.gz
        sudo tar -C /opt/java -xzf semeru11.tar.gz --strip 1
        export JAVA_HOME=/opt/java

        printf -- 'export JAVA_HOME=/opt/java\n'  >> "$BUILD_ENV"
        printf -- 'IBM_Semeru_11 installed\n' >> "$LOG_FILE"
    elif [[ "$JAVA_PROVIDED" == "IBM_Semeru_17" ]]; then
        # Install IBM_Semeru_17
        sudo mkdir -p /opt/java

        cd "$SOURCE_ROOT"
        sudo wget -O semeru17.tar.gz https://github.com/ibmruntimes/semeru17-binaries/releases/download/jdk-17.0.14%2B7_openj9-0.49.0/ibm-semeru-open-jdk_s390x_linux_17.0.14_7_openj9-0.49.0.tar.gz
        sudo tar -C /opt/java -xzf semeru17.tar.gz --strip 1
        export JAVA_HOME=/opt/java

        printf -- 'export JAVA_HOME=/opt/java\n'  >> "$BUILD_ENV"
        printf -- 'IBM_Semeru_17 installed\n' >> "$LOG_FILE"
	elif [[ "$JAVA_PROVIDED" == "IBM_Semeru_8" ]]; then
        # Install IBM_Semeru_8
        sudo mkdir -p /opt/java

        cd "$SOURCE_ROOT"
        sudo wget -O semeru8.tar.gz https://github.com/ibmruntimes/semeru8-binaries/releases/download/jdk8u442-b06_openj9-0.49.0/ibm-semeru-open-jdk_s390x_linux_8u442b06_openj9-0.49.0.tar.gz
        sudo tar -C /opt/java -xzf semeru8.tar.gz --strip 1
        export JAVA_HOME=/opt/java

        printf -- 'export JAVA_HOME=/opt/java\n'  >> "$BUILD_ENV"
        printf -- 'IBM_Semeru_8 installed\n' >> "$LOG_FILE"
    elif [[ "$JAVA_PROVIDED" == "IBM_Semeru_21" ]]; then
        # Install IBM_Semeru_21
        sudo mkdir -p /opt/java

        cd "$SOURCE_ROOT"
        sudo wget -O semeru21.tar.gz https://github.com/ibmruntimes/semeru21-binaries/releases/download/jdk-21.0.6%2B7_openj9-0.49.0/ibm-semeru-open-jdk_s390x_linux_21.0.6_7_openj9-0.49.0.tar.gz
        sudo tar -C /opt/java -xzf semeru21.tar.gz --strip 1
        export JAVA_HOME=/opt/java

        printf -- 'export JAVA_HOME=/opt/java\n'  >> "$BUILD_ENV"
        printf -- 'IBM_Semeru_21 installed\n' >> "$LOG_FILE"
    elif [[ "$JAVA_PROVIDED" == "Eclipse_Adoptium_Temurin_11" ]]; then
        # Install Eclipse_Adoptium_Temurin_11
        sudo mkdir -p /opt/java

        cd "$SOURCE_ROOT"
        sudo wget -O temurin11.tar.gz https://github.com/adoptium/temurin11-binaries/releases/download/jdk-11.0.26%2B4/OpenJDK11U-jdk_s390x_linux_hotspot_11.0.26_4.tar.gz
        sudo tar -C /opt/java -xzf temurin11.tar.gz --strip 1
        export JAVA_HOME=/opt/java

        printf -- 'export JAVA_HOME=/opt/java\n'  >> "$BUILD_ENV"
        printf -- 'Eclipse_Adoptium_Temurin_11 installed\n' >> "$LOG_FILE"
        
    elif [[ "$JAVA_PROVIDED" == "Eclipse_Adoptium_Temurin_17" ]]; then
        # Install Eclipse_Adoptium_Temurin_17
        sudo mkdir -p /opt/java
        cd "$SOURCE_ROOT"
        sudo wget -O temurin17.tar.gz https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.14%2B7/OpenJDK17U-jdk_s390x_linux_hotspot_17.0.14_7.tar.gz
        sudo tar -C /opt/java -xzf temurin17.tar.gz --strip 1
        export JAVA_HOME=/opt/java

        printf -- 'export JAVA_HOME=/opt/java\n'  >> "$BUILD_ENV"
        printf -- 'Eclipse_Adoptium_Temurin_17 installed\n' >> "$LOG_FILE"

     elif [[ "$JAVA_PROVIDED" == "Eclipse_Adoptium_Temurin_21" ]]; then
        # Install Eclipse_Adoptium_Temurin_21
        sudo mkdir -p /opt/java
        cd "$SOURCE_ROOT"
        sudo wget -O temurin21.tar.gz https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.6%2B7/OpenJDK21U-jdk_s390x_linux_hotspot_21.0.6_7.tar.gz
        sudo tar -C /opt/java -xzf temurin21.tar.gz --strip 1
        export JAVA_HOME=/opt/java

        printf -- 'export JAVA_HOME=/opt/java\n'  >> "$BUILD_ENV"
        printf -- 'Eclipse_Adoptium_Temurin_21 installed\n' >> "$LOG_FILE"

    elif [[ "$JAVA_PROVIDED" == "OpenJDK11" ]]; then
        if [[ "$ID" == "rhel" ]]; then
            sudo yum install -y java-11-openjdk-devel   
            export JAVA_HOME=/usr/lib/jvm/java-11-openjdk     
            printf -- 'export JAVA_HOME=/usr/lib/jvm/java-11-openjdk\n'  >> "$BUILD_ENV"   
        elif [[ "$ID" == "sles" ]]; then
            sudo zypper install -y java-11-openjdk-devel
            export JAVA_HOME=/usr/lib64/jvm/java-11-openjdk
            printf -- 'export JAVA_HOME=/usr/lib64/jvm/java-11-openjdk\n'  >> "$BUILD_ENV"
        elif [[ "$ID" == "ubuntu" ]]; then
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-11-jdk
            export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x
            printf -- 'export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x\n'  >> "$BUILD_ENV"
        fi
    elif [[ "$JAVA_PROVIDED" == "OpenJDK17" ]]; then
        if [[ "$ID" == "rhel" ]]; then
            sudo yum install -y java-17-openjdk-devel
            export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
            printf -- 'export JAVA_HOME=/usr/lib/jvm/java-17-openjdk\n'  >> "$BUILD_ENV" 
        elif [[ "$ID" == "sles" ]]; then
            sudo zypper install -y java-17-openjdk java-17-openjdk-devel
            export JAVA_HOME=/usr/lib64/jvm/java-17-openjdk
            printf -- 'export JAVA_HOME=/usr/lib64/jvm/java-17-openjdk\n'  >> "$BUILD_ENV"
        elif [[ "$ID" == "ubuntu" ]]; then
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-17-jdk
            export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-s390x
            printf -- 'export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-s390x\n'  >> "$BUILD_ENV"
        fi
    elif [[ "$JAVA_PROVIDED" == "OpenJDK21" ]]; then
        if [[ "$ID" == "rhel" ]]; then
            sudo yum install -y java-21-openjdk-devel
            export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
            printf -- 'export JAVA_HOME=/usr/lib/jvm/java-21-openjdk\n'  >> "$BUILD_ENV"
	elif [[ "$ID" == "sles" ]]; then
            sudo zypper install -y java-21-openjdk java-21-openjdk-devel
            export JAVA_HOME=/usr/lib64/jvm/java-21-openjdk
            printf -- 'export JAVA_HOME=/usr/lib64/jvm/java-21-openjdk\n'  >> "$BUILD_ENV"    
        elif [[ "$ID" == "ubuntu" ]]; then
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-21-jdk
            export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-s390x
            printf -- 'export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-s390x\n'  >> "$BUILD_ENV"
        fi
    elif [[ "$JAVA_PROVIDED" == "OpenJDK8" ]]; then
        if [[ "$ID" == "rhel" ]]; then
            sudo yum install -y java-1.8.0-openjdk-devel
            export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk
            printf -- 'export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk\n'  >> "$BUILD_ENV" 
        elif [[ "$ID" == "sles" ]]; then
            sudo zypper install -y java-1_8_0-openjdk-devel
            export JAVA_HOME=/usr/lib64/jvm/java-1.8.0-openjdk
            printf -- 'export JAVA_HOME=/usr/lib64/jvm/java-1.8.0-openjdk\n'  >> "$BUILD_ENV"
        elif [[ "$ID" == "ubuntu" ]]; then
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-8-jdk
            export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-s390x
            printf -- 'export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-s390x\n'  >> "$BUILD_ENV"
        fi
    else
        printf --  '$JAVA_PROVIDED is not supported, Please use valid java from {IBM_Semeru_8, IBM_Semeru_11, IBM_Semeru_17, IBM_Semeru_21, Eclipse_Adoptium_Temurin_11, Eclipse_Adoptium_Temurin_17, Eclipse_Adoptium_Temurin_21, OpenJDK8, OpenJDK11, OpenJDK17, OpenJDK21} only' >> "$LOG_FILE"
        exit 1
    fi

    export PATH=$JAVA_HOME/bin:$PATH
    printf -- 'export PATH=$JAVA_HOME/bin:$PATH\n'  >> "$BUILD_ENV"
    java -version
    
    # Download erlang
    cd "$CURDIR"
    wget "https://github.com/erlang/otp/releases/download/OTP-${PACKAGE_VERSION}/otp_src_${PACKAGE_VERSION}.tar.gz"
    tar zxf otp_src_${PACKAGE_VERSION}.tar.gz
    mv otp_src_${PACKAGE_VERSION} erlang
    sudo chmod -Rf 755 erlang
 
    printf -- "Download erlang success\n"


    # Build and install erlang
    cd "$CURDIR"/erlang
    export ERL_TOP=$(pwd)

    ./configure --prefix=/usr

    make -j$(nproc)
    sudo make install
    printf -- "Build and install erlang successfully\n" 

    # Run Test
    runTest

    # Cleanup
    cleanup


    # Verify erlang installation
    if command -v "erl" >/dev/null; then
        printf -- " %s Installation verified.\n" "$PACKAGE_NAME"
    else
        printf -- "Error while installing %s, exiting with 127 \n" "$PACKAGE_NAME"
        exit 127
    fi
}

function runTest() {

    set +e
    if [[ "$TESTS" == "true" ]]; then
        source $BUILD_ENV
        printf -- "Environment PATH : %s \n" "$PATH"
        printf -- 'Running tests \n\n' |& tee -a "$LOG_FILE"
        cd "$CURDIR"/erlang
        make release_tests -j$(nproc)
        cd release/tests/test_server
        printf -- 'Running smoke tests \n\n' 
        $ERL_TOP/bin/erl -s ts install -s ts smoke_test batch -s init stop
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
    echo "bash build_erlang.sh  [-d debug] [-y install-without-confirmation] [-t install and run tests] [-j Java to use from {IBM_Semeru_8, IBM_Semeru_11, IBM_Semeru_17, IBM_Semeru_21, Eclipse_Adoptium_Temurin_11, Eclipse_Adoptium_Temurin_17, Eclipse_Adoptium_Temurin_21, OpenJDK8, OpenJDK11, OpenJDK17, OpenJDK21}]"
    echo "       default: If no -j specified, OpenJDK11 will be installed"
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
    esac
done

function gettingStarted() {
    printf -- '\n********************************************************************************************************\n'
    printf -- "\n*Getting Started * \n"
    printf -- "Running erlang: \n"
    printf -- "erl  \n"
    printf -- "You have successfully started erlang.\n"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare # Check Prerequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"rhel-8.8" | "rhel-8.10" | "rhel-9.2" | "rhel-9.4" | "rhel-9.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y autoconf flex gawk gcc gcc-c++ gzip libxml2-devel libxslt ncurses-devel openssl-devel make tar unixODBC-devel wget |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-15.6")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y autoconf flex gawk gcc gcc-c++ gzip libopenssl-1_1-devel libxml2-devel libxslt-tools ncurses-devel make tar unixODBC-devel wget |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"ubuntu-20.04" | "ubuntu-22.04" | "ubuntu-24.04" | "ubuntu-24.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y curl autoconf fop flex gawk gcc g++ gzip libncurses-dev libssl-dev libxml2-utils make tar unixodbc-dev wget xsltproc pkg-config |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
