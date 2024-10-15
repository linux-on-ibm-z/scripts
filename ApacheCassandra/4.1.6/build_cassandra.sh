#!/bin/bash
# © Copyright IBM Corporation 2024
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ApacheCassandra/4.1.6/build_cassandra.sh
# Execute build script: bash build_cassandra.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="cassandra"
PACKAGE_VERSION="4.1.6"
CURDIR="$(pwd)"
USER="$(whoami)"
FORCE="false"
TESTS="false"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ApacheCassandra/4.1.6/patch"

JAVA_PROVIDED="Temurin11"
BUILD_ENV="$CURDIR/setenv.sh"

trap cleanup 0 1 2 ERR

source "/etc/os-release"
DISTRO="$ID-$VERSION_ID"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-${DISTRO}-$(date +"%F-%T").log"

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
        printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n'
        exit 1
    fi

    printf -- "JAVA_PROVIDED=$JAVA_PROVIDED \n" >>"$LOG_FILE"
    if [[ "$JAVA_PROVIDED" != "Temurin11" && "$JAVA_PROVIDED" != "OpenJDK11" ]]; then
        err "$JAVA_PROVIDED is not supported, only {Temurin11, OpenJDK11} are supported"
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

function cleanup() {
    # Remove artifacts
    rm -rf ${CURDIR}/build_netty.sh ${CURDIR}/Chronicle-Bytes
    if [[ "$VERSION_ID" == "12.5" ]]; then
        rm -rf ${CURDIR}/Python-3.7.4.tgz
    fi
    if [[ "$JAVA_PROVIDED" == "Temurin11" ]]; then
        rm -rf ${CURDIR}/temurin11.tar.gz
    fi
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function build_netty-tcnative() {
    cd "$CURDIR"
    wget -q https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ApacheCassandra/4.1.6/patch/build_netty.sh
    if [[ "$JAVA_PROVIDED" == "Temurin11" ]]; then
        bash build_netty.sh -y -j Temurin11
    else
        bash build_netty.sh -y -j OpenJDK11
    fi
}

function java_setup() {
    echo "Java provided by user: $JAVA_PROVIDED" >>"$LOG_FILE"

    if [[ "$JAVA_PROVIDED" == "Temurin11" ]]; then
        printf -- "\nInstalling Temurin11 Runtime . . . \n"
        cd "$CURDIR"
        wget -O temurin11.tar.gz https://github.com/adoptium/temurin11-binaries/releases/download/jdk-11.0.22%2B7/OpenJDK11U-jdk_s390x_linux_hotspot_11.0.22_7.tar.gz
        tar zxf temurin11.tar.gz
        export JAVA_HOME=$CURDIR/jdk-11.0.22+7
        printf -- "Installation of Temurin11 Runtime is successful\n" >>"$LOG_FILE"
    else
        if [[ "${ID}" == "ubuntu" ]]; then
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-11-jdk
            export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x
        elif [[ "${ID}" == "rhel" ]]; then
            sudo yum install -y java-11-openjdk-devel
            export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
        elif [[ "${ID}" == "sles" ]]; then
            sudo zypper install -y java-11-openjdk
            export JAVA_HOME=/usr/lib64/jvm/java-11-openjdk
        fi
        printf -- "Installation of  OpenJDK11 is successful\n" >>"$LOG_FILE"
    fi

    export PATH=$JAVA_HOME/bin:$PATH
    java -version
    echo "export JAVA_HOME=$JAVA_HOME" >>"$BUILD_ENV"
    echo 'export PATH=$JAVA_HOME/bin:$PATH' >>"$BUILD_ENV"

}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"
    #DISTRO="$ID-$VERSION_ID"

    # Build netty-tcnative
    printf -- "Build netty-tcnative\n" >>"$LOG_FILE"
    build_netty-tcnative

    # Java setup
    java_setup

    # Install maven (for SLES 12.5)
    if [[ "$VERSION_ID" == "12.5" ]]; then
        printf -- "\nInstalling maven\n"
        cd "$CURDIR"
        wget https://archive.apache.org/dist/maven/maven-3/3.6.3/binaries/apache-maven-3.6.3-bin.tar.gz
        tar -xvzf apache-maven-3.6.3-bin.tar.gz
        export PATH=$PATH:$CURDIR/apache-maven-3.6.3/bin/
    fi

    # Build netty
    printf -- "Build netty\n" >>"$LOG_FILE"
    cd "$CURDIR"
    git clone https://github.com/netty/netty.git
    cd netty
    git checkout netty-4.1.58.Final
    curl -sSL https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ApacheCassandra/4.1.6/patch/netty.patch | git apply
    mvn -T 1C install -DskipTests -Dmaven.javadoc.skip=true

    # Build Chronicle-bytes
    printf -- "Build Chronicle-bytes\n" >>"$LOG_FILE"
    cd "$CURDIR"
    git clone https://github.com/OpenHFT/Chronicle-Bytes
    cd Chronicle-Bytes
    git checkout chronicle-bytes-2.20.111
    curl -sSL https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ApacheCassandra/4.1.6/patch/bytes.patch | git apply
    mvn -T 1C install -DskipTests -Dmaven.javadoc.skip=true

    # Install Ant
    if [[ "$DISTRO" == "rhel-8"* || "$ID" == "sles" ]]; then
        printf -- "Installing ant\n" >>"$LOG_FILE"
        cd "$CURDIR"
        export ANT_HOME=/opt/ant
        echo 'export ANT_HOME=/opt/ant' >>"$BUILD_ENV"
        sudo mkdir -p "$ANT_HOME"
        curl -SL -o ant.tar.gz https://archive.apache.org/dist/ant/binaries/apache-ant-1.10.4-bin.tar.gz
        sudo tar -xvf ant.tar.gz -C "$ANT_HOME" --strip-components=1
        export PATH=$ANT_HOME/bin:$PATH

        echo 'export PATH=$ANT_HOME/bin:$PATH' >>"$BUILD_ENV"
        printf -- "Installed Ant \n" >>"$LOG_FILE"
    fi

    # Install Python3.7 (Only SLES 12.5)
    if [[ "$VERSION_ID" == "12.5" ]]; then
        printf -- "Build openssl 1.1.1q for sles12.5\n" >>"$LOG_FILE"
        wget https://www.openssl.org/source/openssl-1.1.1q.tar.gz --no-check-certificate
        tar -xzf openssl-1.1.1q.tar.gz
        cd openssl-1.1.1q
        ./config --prefix=/usr/local --openssldir=/usr/local
        make
        sudo make install
        sudo ldconfig /usr/local/lib64
        export PATH=/usr/local/bin:$PATH

        export LDFLAGS="-L/usr/local/lib/ -L/usr/local/lib64/"
        export LD_LIBRARY_PATH="/usr/local/lib/:/usr/local/lib64/"
        export CPPFLAGS="-I/usr/local/include/ -I/usr/local/include/openssl"

        printf -- "Build python3 for sles12.5\n" >>"$LOG_FILE"
        cd "$CURDIR"
        wget https://www.python.org/ftp/python/3.11.2/Python-3.11.2.tgz
        tar -xzf Python-3.11.2.tgz
        cd Python-3.11.2
        ./configure
        make -j$(nproc)
        sudo make install
    fi

    # Set Env
    printf -- "export JAVA_HOME=$JAVA_HOME for $ID  \n" >>"$LOG_FILE"
    java -version

    export LANG="en_US.UTF-8"
    echo 'export LANG="en_US.UTF-8"' >>"$BUILD_ENV"

    export JAVA_TOOL_OPTIONS="-Dfile.encoding=UTF8"
    echo 'export JAVA_TOOL_OPTIONS="-Dfile.encoding=UTF8"' >>"$BUILD_ENV"

    export CASSANDRA_USE_JDK11=true
    echo 'export CASSANDRA_USE_JDK11=true' >>"$BUILD_ENV"
    
    # set LD_LIBRARY_PATH
    export LD_LIBRARY_PATH=$CURDIR/netty-tcnative/boringssl-static/target/native-jar-work/META-INF/native/:$CURDIR/netty/transport-native-epoll/target/classes/META-INF/native/

    echo "export LD_LIBRARY_PATH=$LD_LIBRARY_PATH" >>"$BUILD_ENV"
    sudo ldconfig
    sudo ldconfig /usr/local/lib64

    # Download source code
    printf -- "Build cassandra\n" >>"$LOG_FILE"
    cd "$CURDIR"
    git clone https://github.com/apache/cassandra.git
    cd cassandra
    git checkout cassandra-"${PACKAGE_VERSION}"

    # Apply patch
    curl -sSL https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ApacheCassandra/4.1.6/patch/cassandra.patch | git apply

    # Use JVM default for stack size
    sed -i "/Xss/d" build.xml
    sed -i "/Xss/d" conf/jvm-server.options

    # Build Apache Cassandra
    ANT_OPTS="-Xms4G -Xmx4G" ant
    printf -- 'Build Apache Cassandra success \n' >>"$LOG_FILE"

    # Run Tests
    runTest

    # Copy cassandra to /usr/local/, It is here to make sure that copy happens after the test run
    sudo cp -r "$CURDIR/cassandra" "/usr/local/"
    sudo chown -R "$USER" "/usr/local/cassandra"
    export PATH=/usr/local/cassandra/bin:$PATH
    echo 'export PATH=/usr/local/cassandra/bin:$PATH ' >>"$BUILD_ENV"

    #cleanup
    cleanup
}

function runTest() {
    set +e
    if [[ "$TESTS" == "true" ]]; then
        printf -- "TEST Flag is set, continue with running test \n" >>"$LOG_FILE"
        cd $CURDIR/cassandra
        echo "key_cache_size_in_mb: 12" >> "$CURDIR/cassandra/test/conf/cassandra.yaml"
        sed -i '/name="test.timeout"/ s/value.*/value="1000000" \/>/' "$CURDIR/cassandra/build.xml"
        ANT_OPTS="-Xms4G -Xmx4G" ant test
        printf -- "Tests completed. \n"
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
    printf -- "Request details : PACKAGE NAME= %s , VERSION= %s with JAVA= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$JAVA_PROVIDED" |& tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
    echo
    echo "Usage: "
    echo " bash build_cassandra.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests] [-j java to use [Temurin11, OpenJDK11]]"
    echo " Default java is Temurin11 (previously known as AdoptOpenJDK hotspot)"
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
    printf -- "export LD_LIBRARY_PATH=$CURDIR/netty-tcnative/boringssl-static/target/native-jar-work/META-INF/native/:$CURDIR/netty/transport-native-epoll/target/classes/META-INF/native/ \n"
    printf -- "sudo ldconfig \n"
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
"ubuntu-20.04" | "ubuntu-22.04" | "ubuntu-24.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y curl ant ant-optional junit git tar g++ make automake autoconf libtool wget patch libx11-dev libxt-dev pkg-config texinfo locales-all unzip python3-dev maven |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"rhel-8.8" | "rhel-8.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    sudo yum install -y curl git which gcc-c++ make automake autoconf libtool libstdc++ tar wget patch words libXt-devel libX11-devel unzip python39-devel procps gawk maven |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"rhel-9.2" | "rhel-9.4")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    sudo yum install -y curl ant junit ant-junit git which gcc-c++ make automake autoconf libtool libstdc++ tar wget patch words libXt-devel libX11-devel texinfo unzip python3-devel maven procps gawk |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"sles-12.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    sudo zypper install -y curl git which make wget tar zip unzip words gcc7 gcc7-c++ patch libtool automake autoconf ccache xorg-x11-proto-devel xorg-x11-devel alsa-devel cups-devel libffi48-devel libstdc++6-locale glibc-locale libstdc++-devel libXt-devel libX11-devel texinfo gawk gdbm-devel libbz2-devel libdb-4_8-devel libopenssl-devel libuuid-devel readline-devel xz-devel zlib-devel libffi48-devel |& tee -a "$LOG_FILE"
    sudo ln -sf /usr/bin/gcc-7 /usr/bin/gcc
    sudo ln -sf /usr/bin/g++-7 /usr/bin/g++
    sudo ln -sf /usr/bin/gcc /usr/bin/cc
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"sles-15.5" | "sles-15.6")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    sudo zypper install -y gzip curl git which make wget tar zip unzip gcc-c++ patch libtool automake autoconf ccache xorg-x11-proto-devel xorg-x11-devel alsa-devel cups-devel libstdc++6-locale glibc-locale libstdc++-devel libXt-devel libX11-devel texinfo python3-devel maven |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
