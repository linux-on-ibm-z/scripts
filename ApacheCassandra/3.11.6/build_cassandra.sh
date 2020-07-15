#!/bin/bash
# © Copyright IBM Corporation 2020
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ApacheCassandra/3.11.6/build_cassandra.sh
# Execute build script: bash build_cassandra.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="cassandra"
PACKAGE_VERSION="3.11.6"
CURDIR="$(pwd)"
USER="$(whoami)"

FORCE="false"
TESTS="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

JAVA_PROVIDED="adoptjdk"
BUILD_ENV="$CURDIR/setenv.sh"

trap cleanup 0 1 2 ERR

source "/etc/os-release"

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
    mkdir -p "$CURDIR/logs/"
fi

function err() {
    sudo printf -- "\e[31m${1}\e[0m\n" 1>&2
}

function prepare() {
    if command -v "sudo" >/dev/null; then
        printf -- 'sudo : Yes\n' >>"$LOG_FILE"
    else
        printf -- 'sudo : No \n' >>"$LOG_FILE"
        printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n'
        exit 1
    fi

    printf -- "JAVA_PROVIDED=$JAVA_PROVIDED" >>"$LOG_FILE"
    if [[ "$JAVA_PROVIDED" != "adoptjdk" && "$JAVA_PROVIDED" != "openjdk" ]]; then
        err "$JAVA_PROVIDED is not supported, Supported are {adoptjdk, openjdk} only"
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

    # clean slate
    true >"$BUILD_ENV"
}

function setup_java() {

    if [[ "$JAVA_PROVIDED" == "adoptjdk" ]]; then
        # Install AdoptOpenJDK 8 (With Hotspot)
        cd "$CURDIR"
        export JAVA_HOME=/opt/jdk
        echo 'export JAVA_HOME=/opt/jdk' >>"$BUILD_ENV"
        sudo mkdir -p $JAVA_HOME
        curl -SL -o jdk.tar.gz https://github.com/AdoptOpenJDK/openjdk8-binaries/releases/download/jdk8u202-b08/OpenJDK8U-jdk_s390x_linux_hotspot_8u202b08.tar.gz
        sudo tar -xzf jdk.tar.gz -C $JAVA_HOME --strip-components=1

        printf -- "Install AdoptOpenJDK 8 (With Hotspot) success\n" >>"$LOG_FILE"
        printf -- "export JAVA_HOME=$JAVA_HOME for $ID  \n" >>"$LOG_FILE"

    else

        if [[ "$ID" == "rhel" ]]; then
            sudo yum install -y java-1.8.0-openjdk-devel.s390x
        elif [[ "$ID" == "sles" ]]; then
            sudo zypper install -y java-1_8_0-openjdk-devel
        else # Ubuntu
            sudo apt-get install -y openjdk-8-jre openjdk-8-jdk
        fi

        export JAVA_HOME="$(readlink -f /etc/alternatives/javac | sed 's:/bin/javac::')"
        echo "export JAVA_HOME=$JAVA_HOME" >>"$BUILD_ENV"
        printf -- "export JAVA_HOME=$JAVA_HOME for $ID  \n" >>"$LOG_FILE"

    fi

    export PATH=$JAVA_HOME/bin:$PATH
    echo 'export PATH=$JAVA_HOME/bin:$PATH' >>"$BUILD_ENV"
}

function cleanup() {
    # Remove artifacts
    rm -rf "${CURDIR}/jdk.tar.gz"
    rm -rf "${CURDIR}/jna"
    rm -rf "${CURDIR}/ant.tar.gz"
    rm -rf "${CURDIR}/libffi-3.2.1.tar.gz"

    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

    # Install Ant, required for el8 as it does not ship ant, junit, ant-junit
    cd "$CURDIR"
    DISTRO="$ID-$VERSION_ID"
    if [[ "$DISTRO" == "rhel-8.2" || "$DISTRO" == "rhel-8.1" ]]; then
        export ANT_HOME=/opt/ant
        echo 'export ANT_HOME=/opt/ant' >>"$BUILD_ENV"
        sudo mkdir -p "$ANT_HOME"

        curl -SL -o ant.tar.gz https://archive.apache.org/dist/ant/binaries/apache-ant-1.10.4-bin.tar.gz
        sudo tar -xvf ant.tar.gz -C "$ANT_HOME" --strip-components=1

        export PATH=$ANT_HOME/bin:$PATH
        echo 'export PATH=$ANT_HOME/bin:$PATH' >>"$BUILD_ENV"
    fi
    printf -- "Install Ant success\n" >>"$LOG_FILE"

    #Install libffi to resolve missing libffi.so.6 library issue.
    printf -- "Install libffi library\n" >>"$LOG_FILE"
    if [[ "$DISTRO" == "ubuntu-20.04" || "$ID" == "sles" ]]; then        
        cd "$CURDIR"
        wget ftp://sourceware.org/pub/libffi/libffi-3.2.1.tar.gz
        tar xvfz libffi-3.2.1.tar.gz
        cd libffi-3.2.1
        ./configure --prefix=/usr/local
        make
        sudo make install
        if [[ "$DISTRO" == "ubuntu-20.04" ]]; then
            export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
            echo 'export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH' >>"$BUILD_ENV"
        else
            export LD_LIBRARY_PATH=/usr/local/lib64:$LD_LIBRARY_PATH
            echo 'export LD_LIBRARY_PATH=/usr/local/lib64:$LD_LIBRARY_PATH' >>"$BUILD_ENV"
        fi    
    fi

    cd "$CURDIR"
    # Don't use a pipe here like | or |& as it runs in a subshell and exports are not visible as a result
    setup_java

    export LANG="en_US.UTF-8"
    echo 'export LANG="en_US.UTF-8"' >>"$BUILD_ENV"

    export JAVA_TOOL_OPTIONS="-Dfile.encoding=UTF8"
    echo 'export JAVA_TOOL_OPTIONS="-Dfile.encoding=UTF8"' >>"$BUILD_ENV"

    export ANT_OPTS="-Xms4G -Xmx4G"
    echo 'export ANT_OPTS="-Xms4G -Xmx4G"' >>"$BUILD_ENV"

    java -version

    # Download  source code
    cd "$CURDIR"
    git clone -b cassandra-"${PACKAGE_VERSION}" https://github.com/apache/cassandra.git

    printf -- 'Download source code success \n' >>"$LOG_FILE"

    cd "$CURDIR/cassandra"

    # Apply patches
    sed -i 's/Xss256k/Xss32m/g' build.xml conf/jvm.options

    
    # Build Apache Cassandra
    cd "$CURDIR/cassandra"
    ant

    printf -- 'Build Apache Cassandra success \n' >>"$LOG_FILE"

    # Replace Snappy-Java
    cd "$CURDIR/cassandra"
    rm lib/snappy-java-1.1.1.7.jar
    wget -O lib/snappy-java-1.1.2.6.jar https://repo1.maven.org/maven2/org/xerial/snappy/snappy-java/1.1.2.6/snappy-java-1.1.2.6.jar

    printf -- 'Replace Snappy-Java success \n' >>"$LOG_FILE"

    # Build and replace JNA
    cd "$CURDIR"
    git clone -b 4.2.2 https://github.com/java-native-access/jna.git

    cd "$CURDIR"/jna
    ant native jar
    rm "$CURDIR/cassandra/lib/jna-4.2.2.jar"
    cp build/jna.jar "$CURDIR/cassandra/lib/jna-4.2.2.jar"

    printf -- 'Build and replace JNA success \n'

    # Run Tests
    runTest

    # Copy cassandra to /usr/local/, It is here to make sure that copy happens after the test run
    sudo cp -r "$CURDIR/cassandra" "/usr/local/"
    sudo chown -R "$USER" "/usr/local/cassandra"
    export PATH=/usr/local/cassandra/bin:$PATH

    #cleanup
    cleanup
}

function runTest() {
    set +e +o pipefail
    if [[ "$TESTS" == "true" ]]; then
        printf -- "TEST Flag is set, continue with running test \n" >>"$LOG_FILE"
        cd $CURDIR/cassandra
        echo "key_cache_size_in_mb: 12" >> "${CURDIR}/cassandra/test/conf/cassandra.yaml"
        sed -i '/name="test.timeout"/ s/value.*/value="900000" \/>/' "${CURDIR}/cassandra/build.xml"
        ant test
        printf -- "Tests completed. \n"
    fi
    set -e -o pipefail
}

function logDetails() {
    printf -- '**************************** SYSTEM DETAILS *************************************************************\n' >"$LOG_FILE"
    if [ -f "/etc/os-release" ]; then
        cat "/etc/os-release" >>"$LOG_FILE"
    fi

    cat /proc/version >>"$LOG_FILE"
    printf -- '*********************************************************************************************************\n' >>"$LOG_FILE"
    printf -- "Detected %s \n" "$PRETTY_NAME"
    printf -- "Request details : PACKAGE NAME= %s , VERSION= %s with JAVA= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$JAVA_PROVIDED" |& tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
    echo
    echo "Usage: "
    echo " build_cassandra.sh  [-d debug] [-y install dependencies assume yes] [-t install and run tests] [-j java to use [adoptjdk, openjdk]]"
    echo "       default java is adoptjdk(for all except sles) or openjdk ( for sles) "
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
    printf -- '\n********************************************************************************************************\n'
    printf -- "\n*Getting Started * \n"
    printf -- "Run following command to get started: \n"

    printf -- "source ~/setenv.sh \n"
    printf -- "Start cassandra server: \n"
    printf -- "cassandra  -f\n\n"

    printf -- "Open Command line in another terminal using command :\n"
    printf -- "cqlsh\n"
    printf -- "For more help visit https://cassandra.apache.org/doc/latest/getting_started/index.html\n"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04" | "ubuntu-20.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y curl ant ant-optional junit git tar g++ make automake autoconf libtool wget patch libx11-dev libxt-dev pkg-config texinfo locales-all unzip python |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-7.8" | "rhel-7.6" | "rhel-7.7")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y ant junit ant-junit curl git which gcc-c++ make automake autoconf libtool libstdc++-static tar wget patch words libXt-devel libX11-devel texinfo unzip python |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"rhel-8.2" | "rhel-8.1")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y langpacks-en_GB.noarch curl git which gcc-c++ make automake autoconf libtool libstdc++-static tar wget patch words libXt-devel libX11-devel texinfo unzip python3-devel python3-setuptools |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"sles-12.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y ant ant-junit junit curl git which make wget tar zip unzip words gcc-c++ patch libtool automake autoconf ccache xorg-x11-proto-devel xorg-x11-devel alsa-devel cups-devel libffi48-devel libstdc++6-locale glibc-locale libstdc++-devel libXt-devel libX11-devel texinfo python |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"sles-15.1")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y ant junit ant-junit gzip curl git which make wget tar zip unzip gcc-c++ patch libtool automake autoconf ccache xorg-x11-proto-devel xorg-x11-devel alsa-devel cups-devel libffi-devel libstdc++6-locale glibc-locale libstdc++-devel libXt-devel libX11-devel texinfo python |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
