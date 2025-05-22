#!/bin/bash
# © Copyright IBM Corporation 2025
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ApacheCassandra/5.0.4/build_cassandra.sh
# Execute build script: bash build_cassandra.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="cassandra"
PACKAGE_VERSION="5.0.4"
CURDIR="$(pwd)"
USER="$(whoami)"
FORCE="false"
TESTS="false"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ApacheCassandra/${PACKAGE_VERSION}/patch"

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
    if [[ "$JAVA_PROVIDED" != "Temurin11" && "$JAVA_PROVIDED" != "OpenJDK11" && "$JAVA_PROVIDED" != "OpenJDK17" && "$JAVA_PROVIDED" != "Temurin17" ]]; then
        err "$JAVA_PROVIDED is not supported, only {OpenJDK11, Temurin11, OpenJDK17, Temurin17} are supported"
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
    if [[ "$JAVA_PROVIDED" == "Temurin11" ]]; then
        rm -rf ${CURDIR}/temurin11.tar.gz
    fi
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function build_netty-tcnative() {
    cd "$CURDIR"
    wget -q ${PATCH_URL}/build_netty.sh
    if [[ "$JAVA_PROVIDED" == "Temurin11" ]]; then
        bash build_netty.sh -y -j Temurin11
    elif [[ "$JAVA_PROVIDED" == "Temurin17" ]]; then
        bash build_netty.sh -y -j Temurin17
    elif [[ "$JAVA_PROVIDED" == "OpenJDK17" ]]; then
        bash build_netty.sh -y -j OpenJDK17
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
    elif [[ "$JAVA_PROVIDED" == "Temurin17" ]]; then
        printf -- "\nInstalling Temurin17 Runtime . . . \n"
        cd "$CURDIR"
        wget -O temurin17.tar.gz https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.13%2B11/OpenJDK17U-jdk_s390x_linux_hotspot_17.0.13_11.tar.gz
        tar zxf temurin17.tar.gz
        export JAVA_HOME=$CURDIR/jdk-17.0.13+11
        printf -- "Installation of Temurin17 Runtime is successful\n" >>"$LOG_FILE"
    elif [[ "$JAVA_PROVIDED" == "OpenJDK17" ]]; then
        printf -- "\nInstalling OpenJDK17 Runtime . . . \n"
        cd "$CURDIR"
        if [[ "${ID}" == "ubuntu" ]]; then
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-17-jdk
            export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-s390x
        elif [[ "${ID}" == "rhel" ]]; then
            sudo yum install -y java-17-openjdk-devel
            export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
        elif [[ "${ID}" == "sles" ]]; then
            sudo zypper install -y java-17-openjdk-devel
            export JAVA_HOME=/usr/lib64/jvm/java-17-openjdk
        fi
        printf -- "Installation of OpenJDK17 Runtime is successful\n" >>"$LOG_FILE"
    else
        if [[ "${ID}" == "ubuntu" ]]; then
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-11-jdk
            export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x
        elif [[ "${ID}" == "rhel" ]]; then
            sudo yum install -y java-11-openjdk-devel
            export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
        elif [[ "${ID}" == "sles" ]]; then
            sudo zypper install -y java-11-openjdk-devel
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

    if [[ "$DISTRO" == "ubuntu-24.04" || "$DISTRO" == "ubuntu-24.10" || "$DISTRO" == "ubuntu-25.04" || "$DISTRO" == "rhel-"* || "$DISTRO" == "sles-"* ]]; then
        printf -- "Install python\n" >>"$LOG_FILE"
        wget -q https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Python3/3.11.0/build_python3.sh
	sed -i 's/ubuntu-24.04/ubuntu-25.04/g' build_python3.sh
        bash build_python3.sh -y
    fi
	if [[ "$DISTRO" == "rhel-8."* ]]; then
		cd "$CURDIR"
        wget https://dlcdn.apache.org/maven/maven-3/3.9.9/binaries/apache-maven-3.9.9-bin.tar.gz
        tar -zxf apache-maven-3.9.9-bin.tar.gz
        export PATH=$CURDIR/apache-maven-3.9.9/bin:$PATH
        export MAVEN_OPTS="-Xmx2048m -Xss8m"
    fi
    # Build netty-tcnative
    printf -- "Build netty-tcnative\n" >>"$LOG_FILE"
    build_netty-tcnative

    # Java setup
    java_setup
	if [[ "$DISTRO" == "rhel-8."* ]]; then
		source /opt/rh/gcc-toolset-11/enable
    fi
	
    # Build and install AmazonCorrettoCryptoProvider 2.4.1
    printf -- "Cloning Amazon Corretto Crypto Provider v2.4.1\n" >>"$LOG_FILE"
	cd "$CURDIR"
    git clone --recurse-submodules https://github.com/corretto/amazon-corretto-crypto-provider.git
    cd amazon-corretto-crypto-provider
    git checkout 2.4.1
    echo ">> Building aws-lc native library"
    cd aws-lc
    mkdir -p build
    cd build
	cmake -DCMAKE_BUILD_TYPE=Release \
      -DTARGET_ARCH=s390x \
      -DCMAKE_C_FLAGS="-Wno-string-compare" \
     ..
    make -j"$(nproc)"
    echo ">> Building ACCP JAR with Gradle"
    cd $CURDIR/amazon-corretto-crypto-provider
    ./gradlew build -Pclassifier=linux-s390x -x test
    echo ">> Installing JAR to local Maven repository"
    mvn install:install-file \
    -Dfile=build/lib/AmazonCorrettoCryptoProvider.jar \
    -DgroupId=software.amazon.cryptools \
    -DartifactId=AmazonCorrettoCryptoProvider \
    -Dversion=2.4.1 \
    -Dclassifier=linux-s390_64 \
    -Dpackaging=jar
    export CLASSPATH=$CLASSPATH:$CURDIR/amazon-corretto-crypto-provider/build/lib/AmazonCorrettoCryptoProvider.jar
	echo 'export CLASSPATH=$CLASSPATH:$CURDIR/amazon-corretto-crypto-provider/build/lib/AmazonCorrettoCryptoProvider.jar' >>"$BUILD_ENV"
    printf -- " ACCP v2.4.1 build and install completed for linux-s390_64\n"  >>"$LOG_FILE"
        
    # Build netty
    printf -- "Build netty\n" >>"$LOG_FILE"
    cd "$CURDIR"
    git clone https://github.com/netty/netty.git
    cd netty
    git checkout netty-4.1.119.Final
    sed -i 's/2.0.71/2.0.70/g' pom.xml
    if [[ "$DISTRO" == "rhel"* ]]; then
        mvn install -DskipTests -Dmaven.javadoc.skip=true -Dos.detected.classifier=linux-s390_64-fedora
    elif [[ "$DISTRO" == "sles"* ]]; then
        mvn install -DskipTests -Dmaven.javadoc.skip=true -Dos.detected.classifier=linux-s390_64-suse
    elif [[ "$DISTRO" == "ubuntu"* ]]; then
        mvn install -DskipTests -Dmaven.javadoc.skip=true
    fi

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

    # Set Env
    printf -- "export JAVA_HOME=$JAVA_HOME for $ID  \n" >>"$LOG_FILE"
    java -version

    export LANG="en_US.UTF-8"
    echo 'export LANG="en_US.UTF-8"' >>"$BUILD_ENV"

    export JAVA_TOOL_OPTIONS="-Dfile.encoding=UTF8"
    echo 'export JAVA_TOOL_OPTIONS="-Dfile.encoding=UTF8"' >>"$BUILD_ENV"
    
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
    curl -sSL ${PATCH_URL}/cassandra.patch | git apply

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
        sed -i '468s/?)/?) USING TIMESTAMP 1000/' test/unit/org/apache/cassandra/cql3/ViewPKTest.java
        sed -i '473s/SET/USING TIMESTAMP 2000 SET/' test/unit/org/apache/cassandra/cql3/ViewPKTest.java
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
    echo " bash build_cassandra.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests] [-j java to use [OpenJDK11, Temurin11, OpenJDK17, Temurin17]]"
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
"rhel-8.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    sudo yum install -y curl git which gcc-c++ make automake autoconf libtool libstdc++ tar wget patch words libXt-devel libX11-devel unzip procps gawk maven |& tee -a "$LOG_FILE"
    sudo yum install -y gcc-toolset-11 gcc-toolset-11-gcc gcc-toolset-11-gcc-c++ gcc-toolset-11-libatomic-devel gcc-toolset-11-libstdc++-devel |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"rhel-9.4" | "rhel-9.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    sudo yum install -y curl ant junit ant-junit git which gcc-c++ make automake autoconf libtool libstdc++ tar wget patch words libXt-devel libX11-devel texinfo unzip maven procps gawk |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"sles-15.6")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    sudo zypper install -y gzip curl git which make wget tar zip unzip git gcc gcc-c++ gcc11-c++ gcc11 patch libtool automake autoconf ccache xorg-x11-proto-devel xorg-x11-devel alsa-devel cups-devel libstdc++6-locale glibc-locale libstdc++-devel libXt-devel libX11-devel texinfo python311-devel maven netty-tcnative cmake go |& tee -a "$LOG_FILE"
    sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-11 10
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-11 10
    sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-11 10
    sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-11 10
    sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
    export CC=/usr/bin/gcc
    export CXX=/usr/bin/g++
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"ubuntu-22.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y curl ant ant-optional junit git tar g++ make automake autoconf libtool wget patch libx11-dev libxt-dev pkg-config texinfo locales-all unzip python3-dev maven |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"ubuntu-24.04" | "ubuntu-24.10" | "ubuntu-25.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y curl ant ant-optional junit git tar g++ make automake autoconf libtool wget patch libx11-dev libxt-dev pkg-config texinfo locales-all unzip maven |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
