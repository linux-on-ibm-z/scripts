#!/bin/bash
# © Copyright IBM Corporation 2024
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ApacheSpark/3.5.0/build_spark.sh
# Execute build script: bash build_spark.sh    (provide -h for help)

set -e -o pipefail

# Pkg details
PACKAGE_NAME="spark"
PACKAGE_VERSION="3.5.0"

# Staging area
SOURCE_ROOT="$(pwd)"

PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ApacheSpark/3.5.0/patch/spark.diff"

# JDK 11 URL
JAVA_PROVIDED="Temurin11"

JDK11_URL="https://github.com/adoptium/temurin11-binaries/releases/download/jdk-11.0.22%2B7/OpenJDK11U-jdk_s390x_linux_hotspot_11.0.22_7.tar.gz"

# JDK 17 URL
JDK17_URL="https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.10%2B7/OpenJDK17U-jdk_s390x_linux_hotspot_17.0.10_7.tar.gz"

# JDK 8 URL
JDK8_URL="https://github.com/ibmruntimes/semeru8-binaries/releases/download/jdk8u372-b07_openj9-0.38.0/ibm-semeru-open-jdk_s390x_linux_8u372b07_openj9-0.38.0.tar.gz"

FORCE="true"
TESTS="false"
TEMURIN_INSTALLED=false
LOG_FILE="${SOURCE_ROOT}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
BUILD_ENV="${SOURCE_ROOT}/setenv.sh"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "${SOURCE_ROOT}/logs/" ]; then
    mkdir -p "${SOURCE_ROOT}/logs/"
fi

# source os-release file
if [ -f "/etc/os-release" ]; then
    source "/etc/os-release"
fi
DISTRO="$ID-$VERSION_ID"

err() {
    sudo printf -- "\e[31m${1}\e[0m\n" 1>&2
}

function prepare() {
    if  command -v "sudo" > /dev/null ;
    then
        printf -- 'Sudo : Yes\n' >> "${LOG_FILE}"
    else
        printf -- 'Sudo : No \n' >> "${LOG_FILE}"
        printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n';
        exit 1;
    fi;

    if [[ "$JAVA_PROVIDED" != "Temurin11" && "$JAVA_PROVIDED" != "OpenJDK11"  && "$JAVA_PROVIDED" != "OpenJDK17"  && "$JAVA_PROVIDED" != "Temurin17" ]]; then
        if [[ $DISTRO == "sles-12.5" || $DISTRO == "rhel-7.8" || $DISTRO == "rhel-7.9" ]]; then
           printf "$JAVA_PROVIDED is not supported, Please use valid java from {Temurin11, OpenJDK11, Temurin17} only\n"
        else
           printf "$JAVA_PROVIDED is not supported, Please use valid java from {Temurin11, OpenJDK11, Temurin17, OpenJDK17} only\n"
        fi   
        exit 1
    fi
    
    if [[ "$JAVA_PROVIDED" == "OpenJDK17" ]] && [[ $DISTRO == "sles-12.5" || $DISTRO == "rhel-7.8" || $DISTRO == "rhel-7.9" ]]; then
        printf "$JAVA_PROVIDED is not supported, Please use valid java from {Temurin11, OpenJDK11, Temurin17} only\n"
        exit 1
    fi

    if [[ "$FORCE" == "true" ]] ;
    then
        printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "${LOG_FILE}"
    else
        printf -- "\nAs part of the installation , dependencies would be installed/upgraded.\n";

        while true; do
            read -r -p "Do you want to continue (y/n) ? :  " yn
            case $yn in
                [Yy]* ) printf -- 'User responded with Yes. \n' >> "${LOG_FILE}";
                break;;

                [Nn]* ) exit;;

                *)  echo "Please provide confirmation to proceed.";;
            esac
        done
    fi
    # zero out
    true > "${BUILD_ENV}"
}

function apply_patch()
{
    cd "${SOURCE_ROOT}/spark"
    curl -sSL "${PATCH_URL}" | git apply
}

function cleanup() {
    # Remove artifacts
    printf -- "Cleaned up the artifacts\n" >> "${LOG_FILE}"
}

function runTests() {
    set +e

    source "${BUILD_ENV}"

    printf -- "Running Java tests\n" >> "${LOG_FILE}"
    cd "${SOURCE_ROOT}/spark"
    ./build/mvn -B test -fn -DwildcardSuites=none

    cd "${SOURCE_ROOT}/spark"

    printf -- "Running Scala tests\n" >> "${LOG_FILE}"
    ./build/mvn -B test -fn -Dtest=none -pl '!sql/hive'
    set -e
}

function buildGCC() {
    cd "${SOURCE_ROOT}"
    sudo yum install -y hostname tar zip gcc-c++ unzip python3 cmake curl wget gcc vim patch binutils-devel tcl gettext
    GCC_VERSION=9.2.0
    wget https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.gz
    tar -xf gcc-${GCC_VERSION}.tar.gz
    cd gcc-${GCC_VERSION}
    ./contrib/download_prerequisites
    mkdir objdir
    cd objdir
    ../configure --prefix=/opt/gcc --enable-languages=c,c++ --with-arch=zEC12 --with-long-double-128 \
         --build=s390x-linux-gnu --host=s390x-linux-gnu --target=s390x-linux-gnu                  \
         --enable-threads=posix --with-system-zlib --disable-multilib
    make -j $(nproc)
    sudo make install
    sudo ln -sf /opt/gcc/bin/gcc /usr/bin/gcc
    sudo ln -sf /opt/gcc/bin/g++ /usr/bin/g++
    sudo ln -sf /opt/gcc/bin/g++ /usr/bin/c++
    export PATH=/opt/gcc/bin:"$PATH"
    export LD_LIBRARY_PATH=/opt/gcc/lib64:"$LD_LIBRARY_PATH"
    export C_INCLUDE_PATH=/opt/gcc/lib/gcc/s390x-linux-gnu/${GCC_VERSION}/include
    export CPLUS_INCLUDE_PATH=/opt/gcc/lib/gcc/s390x-linux-gnu/${GCC_VERSION}/include
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

    #Build GCC for Rhel 7.x
    if [[ "$DISTRO" == rhel-7* ]]; then
        buildGCC
    fi

    # Install JDK8 (required for LevelDB JNI)
    cd "${SOURCE_ROOT}"
    curl -SL -o jdk8.tar.gz "${JDK8_URL}"
    sudo mkdir -p /opt/openjdk/8/
    sudo tar -zxf jdk8.tar.gz -C /opt/openjdk/8/ --strip-components 1
    export JAVA_HOME=/opt/openjdk/8
    printf -- "Install AdoptOpenJDK 8 success\n" >> "${LOG_FILE}"

    if [[ "$DISTRO" == "ubuntu-20.04" ]] || [[ "$DISTRO" == rhel-[78]* ]] || [[ "$DISTRO" == sles* ]]; then
        # Install Temurin11 (required for ZSTD-JNI)
        cd "${SOURCE_ROOT}"
        sudo mkdir -p /opt/openjdk/11/
        curl -SL -o jdk11.tar.gz "${JDK11_URL}"
        sudo tar -zxf jdk11.tar.gz -C /opt/openjdk/11/ --strip-components 1
        export JAVA_HOME=/opt/openjdk/11
        TEMURIN_INSTALLED="true"
        printf -- "Installation of Eclipse Adoptium Temurin Runtime (Java 11) is successful\n" >> "$LOG_FILE"
    
        # Install ZSTD-JNI library
        cd "${SOURCE_ROOT}"
        git clone -b c1.5.2-5 https://github.com/luben/zstd-jni.git
        cd zstd-jni/
        PATH="/opt/openjdk/11/bin/:${PATH}" ./sbt compile package
        if [[ "$DISTRO" == "ubuntu-20.04" ]]; then
            sudo mkdir /usr/lib64/
            export LD_LIBRARY_PATH=/usr/lib64/:"$LD_LIBRARY_PATH"
        fi
        sudo cp target/classes/linux/s390x/libzstd-jni-1.5.2-5.so /usr/lib64/
            
    fi
    
    if [[ "$JAVA_PROVIDED" == "Temurin11" ]]; then
        # If user selected Temurin11 for distros like Ubuntu 22.04+ and Rhel 9.x
        if [[ "$TEMURIN_INSTALLED" = false ]]; then
            # Install Temurin11
            cd "${SOURCE_ROOT}"
            sudo mkdir -p /opt/openjdk/11/
            curl -SL -o jdk11.tar.gz "${JDK11_URL}"
            sudo tar -zxf jdk11.tar.gz -C /opt/openjdk/11/ --strip-components 1
            export JAVA_HOME=/opt/openjdk/11
            printf -- "Installation of Eclipse Adoptium Temurin Runtime (Java 11) is successful\n" >> "$LOG_FILE"
        fi
    elif [[ "$JAVA_PROVIDED" == "Temurin17" ]]; then
        # Install Temurin17
        cd "${SOURCE_ROOT}"
        sudo mkdir -p /opt/openjdk/17/
        curl -SL -o jdk17.tar.gz "${JDK17_URL}"
        sudo tar -zxf jdk17.tar.gz -C /opt/openjdk/17/ --strip-components 1
        export JAVA_HOME=/opt/openjdk/17
        printf -- "Installation of Eclipse Adoptium Temurin Runtime (Java 17) is successful\n" >> "$LOG_FILE"
    elif [[ "$JAVA_PROVIDED" == "OpenJDK11" ]]; then
        if [[ "${ID}" == "ubuntu" ]]; then
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-11-jdk
            export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x
        elif [[ "${ID}" == "rhel" ]]; then
            sudo yum install -y java-11-openjdk java-11-openjdk-devel
            export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
        elif [[ "${ID}" == "sles" ]]; then
            sudo zypper install -y java-11-openjdk java-11-openjdk-devel
            export JAVA_HOME=/usr/lib64/jvm/java-11-openjdk
        fi
        printf -- "Installation of OpenJDK 11 is successful\n" >> "$LOG_FILE"
    elif [[ "$JAVA_PROVIDED" == "OpenJDK17" ]]; then
        if [[ "${ID}" == "ubuntu" ]]; then
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-17-jdk
            export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-s390x
        elif [[ "${ID}" == "rhel" ]]; then
            sudo yum install -y java-17-openjdk java-17-openjdk-devel
            export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
        elif [[ "${ID}" == "sles" ]]; then
            sudo zypper install -y java-17-openjdk java-17-openjdk-devel
            export JAVA_HOME=/usr/lib64/jvm/java-17-openjdk-17
        fi
        printf -- "Installation of OpenJDK 17 is successful\n" >> "$LOG_FILE"
    else
        printf "$JAVA_PROVIDED is not supported, Please use valid java from {Temurin11, OpenJDK11,Temurin17, OpenJDK17} only"
        exit 1
    fi
    export PATH="${JAVA_HOME}/bin:${PATH}"
    printf -- "export JAVA_HOME=\"${JAVA_HOME}\"\n" >> "${BUILD_ENV}"

    # Install Maven 3.8.8
    cd "${SOURCE_ROOT}"
    wget https://archive.apache.org/dist/maven/maven-3/3.8.8/binaries/apache-maven-3.8.8-bin.tar.gz
    tar zxf apache-maven-3.8.8-bin.tar.gz
    export PATH=$PATH:${SOURCE_ROOT}/apache-maven-3.8.8/bin
    printf -- "export PATH=\"${PATH}\"\n" >> "${BUILD_ENV}"
    printf -- "Install Maven success\n" >> "${LOG_FILE}"

    # Build Snappy (required for LevelDB)
    cd "${SOURCE_ROOT}"
    wget https://github.com/google/snappy/releases/download/1.1.4/snappy-1.1.4.tar.gz
    tar -zxf snappy-1.1.4.tar.gz
    export SNAPPY_HOME="${SOURCE_ROOT}/snappy-1.1.4"
    cd "${SNAPPY_HOME}"
    ./configure --disable-shared --with-pic
    make
    sudo make install
    export LIBRARY_PATH="${SNAPPY_HOME}"

    # Build LevelDB JNI
    cd "${SOURCE_ROOT}"
    git clone -b s390x https://github.com/linux-on-ibm-z/leveldb.git
    git clone -b leveldbjni-1.8-s390x https://github.com/linux-on-ibm-z/leveldbjni.git
    export LEVELDB_HOME="${SOURCE_ROOT}/leveldb"
    export LEVELDBJNI_HOME="${SOURCE_ROOT}/leveldbjni"
    export C_INCLUDE_PATH="${LIBRARY_PATH}"
    export CPLUS_INCLUDE_PATH="${LIBRARY_PATH}"
    cd "${LEVELDB_HOME}"
    git apply "${LEVELDBJNI_HOME}/leveldb.patch"
    make libleveldb.a
    cd "${LEVELDBJNI_HOME}"
    JAVA_HOME="/opt/openjdk/8/" PATH="/opt/openjdk/8/bin/:${PATH}" mvn -B clean install -P download -Plinux64-s390x -DskipTests
    JAVA_HOME="/opt/openjdk/8/" PATH="/opt/openjdk/8/bin/:${PATH}" jar -xvf "${LEVELDBJNI_HOME}/leveldbjni-linux64-s390x/target/leveldbjni-linux64-s390x-1.8.jar"
    export LD_LIBRARY_PATH="${SOURCE_ROOT}/leveldbjni/META-INF/native/linux64/s390x${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
    printf -- "export LEVELDB_HOME=\"${LEVELDB_HOME}\"\n"  >> "${BUILD_ENV}"
    printf -- "export LEVELDBJNI_HOME=\"${LEVELDBJNI_HOME}\"\n"  >> "${BUILD_ENV}"
    printf -- "export LIBRARY_PATH=\"${LIBRARY_PATH}\"\n"  >> "${BUILD_ENV}"
    printf -- "export C_INCLUDE_PATH=\"${C_INCLUDE_PATH}\"\n"  >> "${BUILD_ENV}"
    printf -- "export CPLUS_INCLUDE_PATH=\"${CPLUS_INCLUDE_PATH}\"\n"  >> "${BUILD_ENV}"
    printf -- "export LD_LIBRARY_PATH=\"${LD_LIBRARY_PATH}\"\n" >> "${BUILD_ENV}"

    # Set up environment for Apache Spark build.
    export MAVEN_OPTS="-Xss128m -Xmx3g -XX:ReservedCodeCacheSize=1g"
    export JAVA_OPTS="-Xmx20g"
    export JAVA_TOOL_OPTIONS="-Dfile.encoding=UTF-8"
    printf -- "export MAVEN_OPTS=\"${MAVEN_OPTS}\"\n"  >> "${BUILD_ENV}"

    # Prepare for compile by downloading source code, applying patch and ignoring tests for unsupported components
    cd "${SOURCE_ROOT}"
    git clone -b v"${PACKAGE_VERSION}" https://github.com/apache/spark.git
    printf -- 'Download source code success \n'  >> "${LOG_FILE}"

    apply_patch

    # Build Apache Spark
    ./build/mvn -B -DskipTests clean package
    printf -- 'Build Apache Spark success \n'  >> "${LOG_FILE}"

    if [[ "$TESTS" == "true" ]]; then
        runTests
    fi

    cleanup
}

function logDetails() {
    printf -- '**************************** SYSTEM DETAILS *******************************************\n' >"${LOG_FILE}"

    if [ -f "/etc/os-release" ]; then
        cat "/etc/os-release" >> "${LOG_FILE}"
    fi

    cat /proc/version >>"${LOG_FILE}"
    printf -- '**************************************************************************************\n' >>"${LOG_FILE}"
    printf -- "Detected %s \n" "$PRETTY_NAME"
    printf -- "Request details : PACKAGE NAME= %s, VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" |& tee -a "${LOG_FILE}"
}

# Print the usage message
function printHelp() {
    echo
    echo "Usage: "
    echo " bash build_spark.sh  [-d debug] [-y install-without-confirmation] [-t run test cases] [-j Java to use from {Temurin11, OpenJDK11, Temurin17, OpenJDK17}]"
    echo " default: If no -j specified, Temurin11 will be installed"
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
    printf -- '\n****************************************************************************************************\n'
    printf -- "\n*Getting Started * \n"
    printf -- "Run following commands to get started: \n"

    printf -- "./spark/bin/spark-shell \n\n"
    printf -- "Note: Environmental Variable needed have been added to setenv.sh\n"
    printf -- "Note: To set the Environmental Variable needed for Spark, please run: source \"${SOURCE_ROOT}/setenv.sh\" \n"
    printf -- "For more help visit https://spark.apache.org/docs/latest/spark-standalone.html \n"
    printf -- '******************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites

case "$DISTRO" in
    "ubuntu-20.04" | "ubuntu-22.04" | "ubuntu-23.10")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo apt-get update
        sudo apt-get install -y wget tar git libtool autoconf build-essential curl apt-transport-https cmake|& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

    "rhel-7.8" | "rhel-7.9" | "rhel-8.6" | "rhel-8.8" | "rhel-8.9")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo yum groupinstall -y 'Development Tools'  |& tee -a "${LOG_FILE}"
        sudo yum install -y wget tar git libtool autoconf make curl python3 |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;
        
    "rhel-9.0" | "rhel-9.2" | "rhel-9.3")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo yum groupinstall -y 'Development Tools'  |& tee -a "${LOG_FILE}"
        sudo yum install -y rpmdevtools wget tar git libtool autoconf make curl python3 flex gcc redhat-rpm-config  rpm-build pkgconfig gettext automake gdb bison gcc-c++ binutils |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

    "sles-12.5")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo zypper install -y wget tar git libtool autoconf curl libnghttp2-devel gcc make gcc-c++ zip unzip gzip gawk python36 |& tee -a "${LOG_FILE}"
        sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.6 40
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

    "sles-15.5")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo zypper install -y wget tar git libtool autoconf curl gcc make gcc-c++ zip unzip gzip gawk python3 |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

    *)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "${LOG_FILE}"
        exit 1
        ;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
