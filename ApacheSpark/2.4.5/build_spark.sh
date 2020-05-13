#!/bin/bash
# © Copyright IBM Corporation 2020
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ApacheSpark/2.4.5/build_spark.sh
# Execute build script: bash build_apachespark.sh    (provide -h for help)
#
# Note: Sometimes `zstd-jni` build fails intermittently, In that case please clean the source and re-run the script.

set -e -o pipefail

# Pkg details
PACKAGE_NAME="spark"
PACKAGE_VERSION="2.4.5"

# Staging area
CURDIR="$(pwd)"

PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ApacheSpark/2.4.5/patch/"

FORCE="false"
TESTS="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
JAVA_PROVIDED="AdoptJDK"
BUILD_ENV="$HOME/setenv.sh"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
    mkdir -p "$CURDIR/logs/"
fi

# source os-release file
if [ -f "/etc/os-release" ]; then
    source "/etc/os-release"
fi

err() {
    sudo printf -- "\e[31m${1}\e[0m\n" 1>&2
}

function prepare() {
    if  command -v "sudo" > /dev/null ;
    then
        printf -- 'Sudo : Yes\n' >> "$LOG_FILE"
    else
        printf -- 'Sudo : No \n' >> "$LOG_FILE"
        printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n';
        exit 1;
    fi;

    if [[ "$JAVA_PROVIDED" != "AdoptJDK" && "$JAVA_PROVIDED" != "IBM" ]]
    then
        err "$JAVA_PROVIDED is not supported, Please use valid java from {AdoptJDK, IBM} only"
        exit 1
    fi

    if [[ "$FORCE" == "true" ]] ;
    then
        printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
    else
        printf -- "\nAs part of the installation , dependencies would be installed/upgraded.\n";

        while true; do
            read -r -p "Do you want to continue (y/n) ? :  " yn
            case $yn in
                [Yy]* ) printf -- 'User responded with Yes. \n' >> "$LOG_FILE";
                break;;

                [Nn]* ) exit;;

                *)  echo "Please provide confirmation to proceed.";;
            esac
        done
    fi
    # zero out
    true > "$BUILD_ENV"
}

function apply_patch()
{
    cd "$CURDIR"/spark
    # Patch StatsdSinkSuite.diff file
    wget -O - $PATCH_URL/StatsdSinkSuite.diff | git apply
    printf -- 'Patched StatsdSinkSuite \n'   >> "$LOG_FILE"

    # Patch Murmur3_x86_32Suite.diff
    wget -O - $PATCH_URL/Murmur3_x86_32Suite.diff | git apply
    printf -- 'Patched Murmur3_x86_32Suite \n'  >> "$LOG_FILE"

    # Patch UnsafeMapSuite.diff
    wget -O - $PATCH_URL/UnsafeMapSuite.diff | git apply
    printf -- 'Patched UnsafeMapSuite \n'  >> "$LOG_FILE"

    # Patch EventTimeWatermarkSuite.diff
    wget -O - $PATCH_URL/EventTimeWatermarkSuite.diff | git apply
    printf -- 'Patched EventTimeWatermarkSuite \n'  >> "$LOG_FILE"

    # Patch RecordBinaryComparator.diff
    wget -O - $PATCH_URL/RecordBinaryComparator.diff | git apply
    printf -- 'Patched RecordBinaryComparator.diff \n'  >> "$LOG_FILE"
}

function ignore_irrelevant_test()
{
    cd "$CURDIR/spark"
    git diff
    mv sql/core/src/test/scala/org/apache/spark/sql/execution/arrow/ArrowConvertersSuite.scala \
    sql/core/src/test/scala/org/apache/spark/sql/execution/arrow/ArrowConvertersSuite.scala.orig

    mv sql/core/src/test/scala/org/apache/spark/sql/execution/vectorized/ColumnarBatchSuite.scala \
    sql/core/src/test/scala/org/apache/spark/sql/execution/vectorized/ColumnarBatchSuite.scala.orig

    mv sql/core/src/test/scala/org/apache/spark/sql/execution/vectorized/ArrowColumnVectorSuite.scala \
    sql/core/src/test/scala/org/apache/spark/sql/execution/vectorized/ArrowColumnVectorSuite.scala.orig

    mv sql/core/src/test/scala/org/apache/spark/sql/execution/arrow/ArrowWriterSuite.scala \
    sql/core/src/test/scala/org/apache/spark/sql/execution/arrow/ArrowWriterSuite.scala.orig

    mv sql/core/src/test/scala/org/apache/spark/sql/execution/arrow/ArrowUtilsSuite.scala \
    sql/core/src/test/scala/org/apache/spark/sql/execution/arrow/ArrowUtilsSuite.scala.orig

    mv sql/hive/src/test/scala/org/apache/spark/sql/hive/orc/HiveOrcFilterSuite.scala \
    sql/hive/src/test/scala/org/apache/spark/sql/hive/orc/HiveOrcFilterSuite.scala.orig

    mv sql/hive/src/test/scala/org/apache/spark/sql/hive/orc/HiveOrcQuerySuite.scala  \
    sql/hive/src/test/scala/org/apache/spark/sql/hive/orc/HiveOrcQuerySuite.scala.orig

    mv sql/hive/src/test/scala/org/apache/spark/sql/hive/orc/OrcHadoopFsRelationSuite.scala \
    sql/hive/src/test/scala/org/apache/spark/sql/hive/orc/OrcHadoopFsRelationSuite.scala.orig

    mv sql/hive/src/test/scala/org/apache/spark/sql/hive/orc/HiveOrcPartitionDiscoverySuite.scala \
    sql/hive/src/test/scala/org/apache/spark/sql/hive/orc/HiveOrcPartitionDiscoverySuite.scala.orig

    mv sql/hive/src/test/scala/org/apache/spark/sql/hive/orc/HiveOrcSourceSuite.scala \
    sql/hive/src/test/scala/org/apache/spark/sql/hive/orc/HiveOrcSourceSuite.scala.orig

    mv sql/hive/src/test/scala/org/apache/spark/sql/hive/orc/OrcReadBenchmark.scala \
    sql/hive/src/test/scala/org/apache/spark/sql/hive/orc/OrcReadBenchmark.scala.orig

    mv sql/core/src/test/scala/org/apache/spark/sql/execution/python/ExtractPythonUDFsSuite.scala \
    sql/core/src/test/scala/org/apache/spark/sql/execution/python/ExtractPythonUDFsSuite.scala.orig
}

function cleanup() {
# Remove artifacts
    printf -- "Cleaned up the artifacts\n" >> "$LOG_FILE"
}

function runTests() {
    set +e

    source $HOME/setenv.sh

    printf -- "Running Java tests\n" >> "$LOG_FILE"
    cd $CURDIR/spark
    ./build/mvn test -fn -DwildcardSuites=none

    printf -- "Running Scala tests\n" >> "$LOG_FILE"
    cd $SOURCE_ROOT/spark
    ./build/mvn test -fn -Dtest=none

    set -e
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

    cd "$CURDIR"
    if [[ "$ID" == "sles" ]]; then
        # Install Maven
        cd "$CURDIR"
        wget http://mirrors.estointernet.in/apache/maven/maven-3/3.6.3/binaries/apache-maven-3.6.3-bin.tar.gz
        tar -xvf apache-maven-3.6.3-bin.tar.gz

        export PATH=$PATH:$CURDIR/apache-maven-3.6.3/bin
        printf -- "export PATH=$PATH:%s/apache-maven-3.6.3/bin\n" "$CURDIR" >> "$BUILD_ENV"
    fi

    echo "Java provided by user $JAVA_PROVIDED" >> "$LOG_FILE"
    if [[ "$JAVA_PROVIDED" == "AdoptJDK" ]]; then
        # Install AdoptOpenJDK 8 (With OpenJ9)
        cd "$CURDIR"
        sudo mkdir -p /opt/adopt/java

        curl -SL -o adoptjdk.tar.gz https://github.com/AdoptOpenJDK/openjdk8-binaries/releases/download/jdk8u242-b08_openj9-0.18.1/OpenJDK8U-jdk_s390x_linux_openj9_8u242b08_openj9-0.18.1.tar.gz
        # Everytime new jdk is downloaded, Ensure that --strip valueis correct
        sudo tar -zxvf adoptjdk.tar.gz -C /opt/adopt/java --strip-components 1

        export JAVA_HOME=/opt/adopt/java

        printf -- " export JAVA_HOME=/opt/adopt/java\n" >> "$BUILD_ENV"
        printf -- "Install AdoptOpenJDK 8 (With OpenJ9) success\n" >> "$LOG_FILE"
    elif [[ "$JAVA_PROVIDED" == "IBM" ]]; then
        cd "$CURDIR"

        # installation fails if java exists already, check it here
        # TODO : Can we avoid the hardcoding
        # TODO : make it interactive
        if [ -x /opt/ibm/java/bin/java ]
        then
            err "IBM java sdk is installed, uninstall it to proceed\n"
            exit 1
        fi

        curl -SLO http://public.dhe.ibm.com/ibmdl/export/pub/systems/cloud/runtimes/java/8.0.6.7/linux/s390x/ibm-java-s390x-sdk-8.0-6.7.bin	
		chmod +x ibm-java-s390x-sdk-8.0-6.7.bin

        wget https://raw.githubusercontent.com/zos-spark/scala-workbench/master/files/installer.properties.java
        tail -n +3 installer.properties.java | tee installer.properties
        cat installer.properties

        sudo ./ibm-java-s390x-sdk-8.0-6.7.bin -r installer.properties

        export JAVA_HOME=/opt/ibm/java
        export HADOOP_USER_NAME="hadoop"

        printf -- "export JAVA_HOME=/opt/ibm/java\n" >> "$BUILD_ENV"
        printf -- "export HADOOP_USER_NAME=\"hadoop\"\n" >> "$BUILD_ENV"
    else
        err "$JAVA_PROVIDED is not supported, Please use valid java from {AdoptJDK, IBM} only"
        exit 1
    fi

    export PATH=$JAVA_HOME/bin:$PATH
    printf -- 'export PATH=$JAVA_HOME/bin:$PATH\n'  >> "$BUILD_ENV"
    printf -- 'export JAVA_HOME for "$ID"  \n'  >> "$LOG_FILE"

    #Build LevelDB JNI
    cd "$CURDIR"
    wget https://github.com/google/snappy/releases/download/1.1.3/snappy-1.1.3.tar.gz
    tar -zxvf  snappy-1.1.3.tar.gz
    export SNAPPY_HOME=`pwd`/snappy-1.1.3
    cd ${SNAPPY_HOME}
    ./configure --disable-shared --with-pic
    make
    sudo make install
    export LIBRARY_PATH=${SNAPPY_HOME}

    cd "$CURDIR"
    git clone -b s390x https://github.com/linux-on-ibm-z/leveldb.git
    git clone -b leveldbjni-1.8-s390x https://github.com/linux-on-ibm-z/leveldbjni.git
    export LEVELDB_HOME=`pwd`/leveldb
    export LEVELDBJNI_HOME=`pwd`/leveldbjni
    export C_INCLUDE_PATH=${LIBRARY_PATH}
    export CPLUS_INCLUDE_PATH=${LIBRARY_PATH}

    cd ${LEVELDB_HOME}
    git apply ${LEVELDBJNI_HOME}/leveldb.patch
    make libleveldb.a
    cd ${LEVELDBJNI_HOME}
    mvn clean install -P download -Plinux64-s390x -DskipTests
    jar -xvf ${LEVELDBJNI_HOME}/leveldbjni-linux64-s390x/target/leveldbjni-linux64-s390x-1.8.jar
    export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$CURDIR/leveldbjni/META-INF/native/linux64/s390x

    printf -- 'export LEVELDB_HOME=`pwd`/leveldb\n'  >> "$BUILD_ENV"
    printf -- 'export LEVELDBJNI_HOME=`pwd`/leveldbjni\n'  >> "$BUILD_ENV"
    printf -- 'export LIBRARY_PATH=${SNAPPY_HOME}\n'  >> "$BUILD_ENV"
    printf -- 'export C_INCLUDE_PATH=${LIBRARY_PATH}\n'  >> "$BUILD_ENV"
    printf -- 'export CPLUS_INCLUDE_PATH=${LIBRARY_PATH}\n'  >> "$BUILD_ENV"
    printf -- "export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:%s/leveldbjni/META-INF/native/linux64/s390x\n" "$CURDIR" >> "$BUILD_ENV"
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"

    #Build ZSTD JNI
    if [[ "$ID" == "rhel" ]]; then
        curl https://bintray.com/sbt/rpm/rpm | sudo tee /etc/yum.repos.d/bintray-sbt-rpm.repo
        sudo yum install -y sbt
    fi

    if [[ "$ID" == "sles" ]]; then
        cd "$CURDIR"
        wget https://piccolo.link/sbt-1.2.8.zip
        unzip sbt-1.2.8.zip
        export PATH=$PATH:$CURDIR/sbt/bin/
    fi

    if [[ "$ID" == "ubuntu" ]]; then
        echo "deb https://dl.bintray.com/sbt/debian /" | sudo tee -a /etc/apt/sources.list.d/sbt.list
        sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 2EE0EA64E40A89B84B2DF73499E82A75642AC823
        sudo apt-get update
        sudo apt-get install sbt
    fi

    cd "$CURDIR"
    git clone https://github.com/luben/zstd-jni.git
    cd zstd-jni
    git checkout v1.3.8-2
    sbt compile test package

    export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/$CURDIR/zstd-jni/target/classes/linux/s390x/
    export MAVEN_OPTS="-Xmx3g -XX:ReservedCodeCacheSize=1024m"
    ulimit -s unlimited
    ulimit -n 999999

    printf -- "export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:%s/zstd-jni/target/classes/linux/s390x/\n" "$CURDIR" >> "$BUILD_ENV"
    printf -- 'export MAVEN_OPTS="-Xmx3g -XX:ReservedCodeCacheSize=1024m"\n'  >> "$BUILD_ENV"
    printf -- 'ulimit -s unlimited\n'  >> "$BUILD_ENV"
    printf -- 'ulimit -n 999999\n'  >> "$BUILD_ENV"

# Prepare for compile by downloading source code, applying patch and ignoring irrelevant test
    cd "$CURDIR"
    git clone -b v"${PACKAGE_VERSION}" https://github.com/apache/spark.git
    printf -- 'Download source code success \n'  >> "$LOG_FILE"

    apply_patch
    ignore_irrelevant_test

# Build Apache Spark
    ./build/mvn -DskipTests clean package
    printf -- 'Build Apache Spark success \n'  >> "$LOG_FILE"

    if [[ "$TESTS" == "true" ]]; then
        runTests
    fi

    cleanup
}

function logDetails() {
    printf -- '**************************** SYSTEM DETAILS *******************************************\n' >"$LOG_FILE"

    if [ -f "/etc/os-release" ]; then
        cat "/etc/os-release" >> "$LOG_FILE"
    fi

    cat /proc/version >>"$LOG_FILE"
    printf -- '**************************************************************************************\n' >>"$LOG_FILE"
    printf -- "Detected %s \n" "$PRETTY_NAME"
    printf -- "Request details : PACKAGE NAME= %s, VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" |& tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
    echo
    echo "Usage: "
    echo " build_spark.sh  [-d debug] [-y install-without-confirmation] [-j Java to use from {AdoptJDK, IBM}] [-t run test cases]"
    echo "       default: If no -j specified, AdoptJDK will be installed"
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
    printf -- "Note: Environmental Variable needed have been added to $HOME/setenv.sh\n"
    printf -- "Note: To set the Environmental Variable needed for Spark, please run: source $HOME/setenv.sh \n"
    printf -- "For more help visit https://spark.apache.org/docs/latest/spark-standalone.html"
    printf -- '******************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
    "ubuntu-16.04" | "ubuntu-18.04")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo apt-get update
        sudo apt-get install -y wget tar git libtool autoconf build-essential maven curl apt-transport-https |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

    "rhel-7.6" | "rhel-7.7" | "rhel-8.1")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo yum groupinstall -y 'Development Tools'  |& tee -a "$LOG_FILE"
        sudo yum install -y maven wget tar git libtool autoconf make curl  |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

    "sles-12.4" | "sles-12.5" | "sles-15.1")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo zypper install -y wget tar git libtool autoconf curl gcc make gcc-c++ zip unzip gzip gawk |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

    *)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
        exit 1
        ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
