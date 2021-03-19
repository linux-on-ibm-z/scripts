#!/bin/bash
# ©  Copyright IBM Corporation 2021.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/HBase/2.3.4/build_hbase.sh
# Execute build script: bash build_hbase.sh    (provide -h for help)
#
set -e -o pipefail

PACKAGE_NAME="hbase"
PACKAGE_VERSION="2.3.4"
CURDIR="$(pwd)"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/HBase/${PACKAGE_VERSION}/patch"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
JAVA_PROVIDED="AdoptJDK8_openj9"
FORCE="false"
BUILD_ENV="$HOME/setenv.sh"


trap cleanup 0 1 2 ERR

# Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
        mkdir -p "$CURDIR/logs/"
fi

if [ -f "/etc/os-release" ]; then
        source "/etc/os-release"
fi

function prepare() {

        if command -v "sudo" >/dev/null; then
                printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
        else
                printf -- 'Sudo : No \n' >>"$LOG_FILE"
                printf -- 'You can install sudo from repository using apt, yum or zypper based on your distro. \n'
                exit 1
        fi

        if [[ "$JAVA_PROVIDED" != "AdoptJDK8_openj9" && "$JAVA_PROVIDED" != "OpenJDK8" ]]; then
                printf "$JAVA_PROVIDED is not supported, Please use valid java from {AdoptJDK8_openj9, OpenJDK8} only"
                exit 1
        fi

        if [[ "$FORCE" == "true" ]]; then
                printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
        else
                printf -- 'As part of the installation, dependencies would be installed/upgraded.\n'

                while true; do
                        read -r -p "Do you want to continue (y/n) ? :  " yn
                        case $yn in
                        [Yy]*)

                                break
                                ;;
                        [Nn]*) exit ;;
                        *) echo "Please provide Correct input to proceed." ;;
                        esac
                done
        fi

        # zero out
        true > "$BUILD_ENV"
}

function cleanup() {
        rm -rf "$CURDIR/adoptjdk.tar.gz"
        rm -rf "$CURDIR/apache-maven-3.3.9-bin.tar.gz"
        rm -rf "$CURDIR/protobuf-2.5.0.tar.gz"
        rm -rf "$CURDIR/gcc-4.9.4.tar.gz"
        rm -rf "$CURDIR/1.2.0.tar.gz"
        printf -- '\nCleaned up the artifacts.\n' >>"$LOG_FILE"
}

function configureAndInstall() {
        printf -- '\nConfiguration and Installation started \n'
        echo "Java provided by user: $JAVA_PROVIDED" >> "$LOG_FILE"

    if [[ "$JAVA_PROVIDED" == "AdoptJDK8_openj9" ]]; then
        # Install AdoptOpenJDK 8 (With OpenJ9)
        cd $CURDIR
        sudo mkdir -p /opt/adopt/java
        curl -SL -o adoptjdk.tar.gz https://github.com/AdoptOpenJDK/openjdk8-binaries/releases/download/jdk8u282-b08_openj9-0.24.0/OpenJDK8U-jdk_s390x_linux_openj9_8u282b08_openj9-0.24.0.tar.gz
        # Everytime new jdk is downloaded, Ensure that --strip valueis correct
        sudo tar -zxf adoptjdk.tar.gz -C /opt/adopt/java --strip-components 1

        export JAVA_HOME=/opt/adopt/java
        printf -- "export JAVA_HOME=/opt/adopt/java\n" >> "$BUILD_ENV"
        printf -- "Installation of AdoptOpenJDK 8 (With OpenJ9) is successful\n" >> "$LOG_FILE"

    elif [[ "$JAVA_PROVIDED" == "OpenJDK8" ]]; then
        if [[ "${ID}" == "ubuntu" ]]; then
                sudo apt-get install -y openjdk-8-jdk
                export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-s390x
                printf -- "export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-s390x\n" >> "$BUILD_ENV"
        elif [[ "${ID}" == "rhel" ]]; then
                sudo yum install -y java-1.8.0-openjdk-devel
                export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk
                printf -- "export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk\n" >> "$BUILD_ENV"
        elif [[ "${ID}" == "sles" ]]; then
                sudo zypper install -y java-1_8_0-openjdk-devel
                export JAVA_HOME=/usr/lib64/jvm/java-1.8.0-openjdk
                printf -- "export JAVA_HOME=/usr/lib64/jvm/java-1.8.0-openjdk\n" >> "$BUILD_ENV"
        fi
        printf -- "Installation of OpenJDK 8 is successful\n" >> "$LOG_FILE"

    else
        printf "$JAVA_PROVIDED is not supported, Please use valid java from {AdoptJDK8_openj9, OpenJDK8} only"
        exit 1
    fi

        export PATH=$JAVA_HOME/bin:$PATH
        printf -- "export PATH=$PATH\n" >> "$BUILD_ENV"
        java -version |& tee -a "$LOG_FILE"

    if [[ "${ID}" == "sles" || "${DISTRO}" == rhel-7* ]]; then
        # Install maven-3.3.9
        cd $CURDIR
        wget https://archive.apache.org/dist/maven/maven-3/3.3.9/binaries/apache-maven-3.3.9-bin.tar.gz
        tar -zxf apache-maven-3.3.9-bin.tar.gz
        export PATH=$CURDIR/apache-maven-3.3.9/bin:$PATH
        printf -- "export PATH=$PATH\n" >> "$BUILD_ENV"
    fi

        # Set maven heap size
        export MAVEN_OPTS="-Xms1024m -Xmx4096m"
        printf -- "export MAVEN_OPTS=\"-Xms1024m -Xmx4096m\"\n" >> "$BUILD_ENV"

        # Install Protobuf 2.5.0 library files
        cd $CURDIR
        wget https://github.com/google/protobuf/releases/download/v2.5.0/protobuf-2.5.0.tar.gz
        tar -zxf protobuf-2.5.0.tar.gz
        cd protobuf-2.5.0
        wget https://raw.githubusercontent.com/protocolbuffers/protobuf/v2.6.0/src/google/protobuf/stubs/atomicops_internals_generic_gcc.h -P src/google/protobuf/stubs/
        curl -sSL $PATCH_URL/src.diff | git apply
        ./configure
        make
        make check
        sudo make install
        mvn install:install-file -DgroupId=com.google.protobuf -DartifactId=protoc -Dversion=2.5.0 -Dclassifier=linux-s390_64 -Dpackaging=exe -Dfile=$CURDIR/protobuf-2.5.0/src/.libs/protoc
        printf -- "Installation of Protobuf 2.5.0 successful\n" >> "$LOG_FILE"

    if [[ "${DISTRO}" == "ubuntu-18.04" ]]; then
        # Set GCC 4.8 as preferred GCC
        sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-4.8 10
        sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-4.8 10
    elif [[ "${ID}" == "ubuntu" || "${DISTRO}" == rhel-8* || "${DISTRO}" == "sles-15.2" ]]; then
        # Install GCC 4.9.4
        cd $CURDIR
        wget http://ftp.gnu.org/gnu/gcc/gcc-4.9.4/gcc-4.9.4.tar.gz
        tar xzf gcc-4.9.4.tar.gz
        cd gcc-4.9.4/
        ./contrib/download_prerequisites
        mkdir build
        cd build/
        ../configure --enable-shared --disable-multilib --enable-threads=posix --with-system-zlib --enable-languages=c,c++
        make -j $(nproc)
        sudo make install
        printf -- "Installation of GCC 4.9.4 successful\n" >> "$LOG_FILE"

        export PATH=/usr/local/bin:$PATH
        printf -- "export PATH=$PATH\n" >> "$BUILD_ENV"
    fi

        # Install Protobuf 3.11.4 library files
        cd $CURDIR
        git clone https://github.com/protocolbuffers/protobuf.git
        cd protobuf
        git checkout v3.11.4
        git submodule update --init --recursive
        ./autogen.sh
        ./configure
        make
        mvn install:install-file -DgroupId=com.google.protobuf -DartifactId=protoc -Dversion=3.11.4 -Dclassifier=linux-s390_64 -Dpackaging=exe -Dfile=$CURDIR/protobuf/src/.libs/protoc
        printf -- "Installation of Protobuf 2.5.0 successful\n" >> "$LOG_FILE"

        # Add library files to LD_LIBRARY_PATH
        export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$CURDIR/protobuf/src/.libs:$CURDIR/protobuf-2.5.0/src/.libs
        printf -- "export LD_LIBRARY_PATH=$LD_LIBRARY_PATH\n" >> "$BUILD_ENV"

        # Download source code and build
        cd $CURDIR
        git clone https://github.com/apache/hbase.git
        cd hbase
        git checkout rel/$PACKAGE_VERSION
        mvn package -DskipTests
        printf -- "Installation of Hbase successful\n" >> "$LOG_FILE"

        # Add Hbase binary to system PATH
        export PATH=$CURDIR/hbase/bin:$PATH
        printf -- "export PATH=$PATH\n" >> "$BUILD_ENV"

        # Download and build jffi 1.2.0
        cd $CURDIR
        wget https://github.com/jnr/jffi/archive/1.2.0.tar.gz
        tar -zxf 1.2.0.tar.gz
        cd jffi-1.2.0/
        # Apply patches
        curl -sSL $PATCH_URL/jni.diff | patch -p1
        curl -sSL $PATCH_URL/libtest.diff | patch -p1
        ant jar

        # Add s390x native jffi library into jruby jar
        mkdir $CURDIR/jar_tmp
        cp ~/.m2/repository/org/jruby/jruby-complete/9.1.17.0/jruby-complete-9.1.17.0.jar $CURDIR/jar_tmp
        cd $CURDIR/jar_tmp
        jar xf jruby-complete-9.1.17.0.jar
        mkdir jni/s390x-Linux
        cp $CURDIR/jffi-1.2.0/build/jni/libjffi-1.2.so jni/s390x-Linux
        jar uf jruby-complete-9.1.17.0.jar jni/s390x-Linux/libjffi-1.2.so
        mv jruby-complete-9.1.17.0.jar ~/.m2/repository/org/jruby/jruby-complete/9.1.17.0/jruby-complete-9.1.17.0.jar
        # Remove the temporary folder
        cd $CURDIR
        rm -rf $CURDIR/jar_tmp

        # Verifying Hbase installation
        if command -v "$PACKAGE_NAME" >/dev/null; then
                printf -- "%s installation completed.\n" "$PACKAGE_NAME"
        else
                printf -- "Error while installing %s, exiting with 127 \n" "$PACKAGE_NAME"
                exit 127
        fi
}

function runTest() {
    # Setting environment variable needed for testing
        source $HOME/setenv.sh

        cd "$CURDIR/hbase"
        set +e
        # Run Hbase test suite
        printf -- '\n Running Hbase test suite.\n'
        mvn test -fn
        printf -- '\n Hbase test suite finished.\n'
        set -e
}


function logDetails() {
        printf -- 'SYSTEM DETAILS\n' >"$LOG_FILE"
        if [ -f "/etc/os-release" ]; then
                cat "/etc/os-release" >>"$LOG_FILE"
        fi

        cat /proc/version >>"$LOG_FILE"
        printf -- "\nDetected %s \n" "$PRETTY_NAME"
        printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" |& tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
        echo
        echo "Usage: "
        echo "bash  build_hbase.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests] [-j Java to be used from {AdoptJDK8_openj9, OpenJDK8}]"
        echo "  default: If no -j specified, AdoptOpenJDK8-Openj9 will be installed"
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
                if command -v "$PACKAGE_NAME" >/dev/null; then
                        TESTS="true"
                        printf -- "%s is detected with version %s .\n" "$PACKAGE_NAME" "$PACKAGE_VERSION" |& tee -a "$LOG_FILE"
                        runTest |& tee -a "$LOG_FILE"
                        exit 0

                else
                        TESTS="true"
                fi
                ;;
        j)
                JAVA_PROVIDED="$OPTARG"
                ;;
        esac
done

function printSummary() {
        printf -- '\n***********************************************************************************************************************************\n'
        printf -- "\n* Getting Started * \n"
        printf -- "Note: Environment Variables needed have been added to $HOME/setenv.sh\n"
        printf -- "Note: To set the Environment Variables needed for Hbase, please run: source $HOME/setenv.sh \n"
        printf -- "\n\nStart Hbase server using the following command: $CURDIR/hbase/bin/start-hbase.sh \n"
        printf -- "Start Hbase shell using the following command: hbase shell \n"
        printf -- "\n\nFor more information on Hbase visit: \nhttps://hbase.apache.org/book.html \n\n"
        printf -- '***********************************************************************************************************************************\n'
}

logDetails
prepare

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-18.04")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo apt-get update
        sudo apt-get install -y git wget maven tar make gcc g++ ant unzip curl patch autoconf automake g++-4.8 gzip libtool zlib1g-dev |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

"ubuntu-20.04" | "ubuntu-20.10")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo apt-get update
        sudo apt-get install -y git wget maven tar make gcc g++ ant unzip curl patch autoconf automake bzip2 gzip libtool zlib1g-dev |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

"rhel-7.8" | "rhel-7.9")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo yum install -y git wget tar make gcc ant unzip hostname gcc-c++ curl patch autoconf automake gzip libtool zlib-devel |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

"rhel-8.1" | "rhel-8.2" | "rhel-8.3")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo yum install -y git wget tar make gcc maven ant unzip hostname gcc-c++ curl patch autoconf automake bzip2 diffutils gzip libtool zlib-devel |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

"sles-12.5" | "sles-15.2")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo zypper install -y git wget tar make gcc ant net-tools gcc-c++ unzip awk curl patch gzip autoconf automake bzip2 gawk libtool zlib-devel | tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

*)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
        exit 1
        ;;
esac

# Run tests
if [[ "$TESTS" == "true" ]]; then
        runTest |& tee -a "$LOG_FILE"
fi

cleanup
printSummary |& tee -a "$LOG_FILE"
