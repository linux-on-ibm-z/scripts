#!/bin/bash
# © Copyright IBM Corporation 2021
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ApacheSpark/3.1.1/build_spark.sh
# Execute build script: bash build_spark.sh    (provide -h for help)

set -e -o pipefail

# Pkg details
PACKAGE_NAME="spark"
PACKAGE_VERSION="3.1.1"

# Staging area
SOURCE_ROOT="$(pwd)"

PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ApacheSpark/3.1.1/patch/"

# JDK 11 URL - AdoptOpenJDK with either Hotspot or OpenJ9 XL JVM
JDK11_URL="https://github.com/AdoptOpenJDK/openjdk11-binaries/releases/download/jdk-11.0.8%2B10/OpenJDK11U-jdk_s390x_linux_hotspot_11.0.8_10.tar.gz"
#JDK11_URL="https://github.com/AdoptOpenJDK/openjdk11-binaries/releases/download/jdk-11.0.8%2B10_openj9-0.21.0/OpenJDK11U-jdk_s390x_linux_openj9_linuxXL_11.0.8_10_openj9-0.21.0.tar.gz"

# JDK 8 URL
JDK8_URL="https://github.com/AdoptOpenJDK/openjdk8-binaries/releases/download/jdk8u265-b01_openj9-0.21.0/OpenJDK8U-jdk_s390x_linux_openj9_linuxXL_8u265b01_openj9-0.21.0.tar.gz"

FORCE="false"
TESTS="false"
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

    # Apply all patches.
    for f in \
        AdaptiveQueryExecSuite \
	CoalesceShufflePartitionsSuite \
	ColumnarBatchSuite \
	EventTimeWatermarkSuite \
	FileBasedDataSourceSuite \
	FileStreamSourceSuite \
	FlatMapGroupsWithStateSuite \
	ReadSchemaSuite \
	SQLQuerySuite \
	SQLQueryTestSuite \
	StateStoreCompatibilitySuite \
	StatsdSinkSuite \
	StreamingAggregationSuite \
	StreamingJoinSuite \
	StreamingStateStoreFormatCompatibilitySuite \
	StreamSuite \
	SubquerySuite
        do
        wget -O - "${PATCH_URL}/${f}.diff" | git apply
        printf -- "Patched ${f} \n" >> "${LOG_FILE}"
    done
}

function ignore_unsupported_test()
{
    cd "${SOURCE_ROOT}/spark"

    # Disable Arrow and ORC tests.
    for f in \
	sql/catalyst/src/test/scala/org/apache/spark/sql/util/ArrowUtilsSuite.scala \
	sql/core/src/test/scala/org/apache/spark/sql/execution/arrow/ArrowConvertersSuite.scala \
	sql/core/src/test/scala/org/apache/spark/sql/execution/arrow/ArrowWriterSuite.scala \
	sql/core/src/test/scala/org/apache/spark/sql/execution/datasources/orc/OrcFilterSuite.scala \
	sql/core/src/test/scala/org/apache/spark/sql/execution/datasources/orc/OrcPartitionDiscoverySuite.scala \
	sql/core/src/test/scala/org/apache/spark/sql/execution/datasources/orc/OrcQuerySuite.scala \
	sql/core/src/test/scala/org/apache/spark/sql/execution/datasources/orc/OrcSourceSuite.scala \
	sql/core/src/test/scala/org/apache/spark/sql/execution/datasources/orc/OrcV1FilterSuite.scala \
	sql/core/src/test/scala/org/apache/spark/sql/execution/datasources/orc/OrcV1SchemaPruningSuite.scala \
	sql/core/src/test/scala/org/apache/spark/sql/execution/datasources/orc/OrcV2SchemaPruningSuite.scala \
	sql/core/src/test/scala/org/apache/spark/sql/execution/python/ExtractPythonUDFsSuite.scala \
	sql/core/src/test/scala/org/apache/spark/sql/execution/vectorized/ArrowColumnVectorSuite.scala \
	sql/hive/src/test/scala/org/apache/spark/sql/hive/orc/HiveOrcPartitionDiscoverySuite.scala \
	sql/hive/src/test/scala/org/apache/spark/sql/hive/orc/HiveOrcQuerySuite.scala \
	sql/hive/src/test/scala/org/apache/spark/sql/hive/orc/HiveOrcSourceSuite.scala \
	sql/hive/src/test/scala/org/apache/spark/sql/hive/orc/OrcHadoopFsRelationSuite.scala \
	sql/hive/src/test/scala/org/apache/spark/sql/hive/orc/OrcReadBenchmark.scala
    do
        mv "${f}" "${f}.orig"
    done
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
    ./build/mvn test -fn -DwildcardSuites=none

    printf -- "Running Scala tests\n" >> "${LOG_FILE}"
    cd "${SOURCE_ROOT}/spark"
    ./build/mvn test -fn -Dtest=none -pl '!sql/hive'

    set -e
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

    # Install JDK8 (required for LevelDB JNI)
    cd "${SOURCE_ROOT}"
    curl -SL -o jdk8.tar.gz "${JDK8_URL}"
    sudo mkdir -p /opt/openjdk/8/
    sudo tar -zxvf jdk8.tar.gz -C /opt/openjdk/8/ --strip-components 1
    printf -- "Install AdoptOpenJDK 8 success\n" >> "${LOG_FILE}"

    # Install JDK11
    cd "${SOURCE_ROOT}"
    sudo mkdir -p /opt/openjdk/11/
    curl -SL -o jdk11.tar.gz "${JDK11_URL}"
    sudo tar -zxvf jdk11.tar.gz -C /opt/openjdk/11/ --strip-components 1
    export JAVA_HOME=/opt/openjdk/11/
    export PATH="${JAVA_HOME}/bin:${PATH}"
    printf -- "export JAVA_HOME=\"${JAVA_HOME}\"\n" >> "${BUILD_ENV}"
    printf -- 'export PATH="${JAVA_HOME}/bin:${PATH}"\n'  >> "${BUILD_ENV}"
    printf -- "Install AdoptOpenJDK 11 success\n" >> "${LOG_FILE}"

    # Install Maven
    cd "${SOURCE_ROOT}"
    wget -O apache-maven-3.6.3.tar.gz "https://www.apache.org/dyn/mirrors/mirrors.cgi?action=download&filename=maven/maven-3/3.6.3/binaries/apache-maven-3.6.3-bin.tar.gz"
    tar -zxvf apache-maven-3.6.3.tar.gz
    export PATH=$PATH:${SOURCE_ROOT}/apache-maven-3.6.3/bin
    printf -- "export PATH=$PATH:%s/apache-maven-3.6.3/bin\n" "${SOURCE_ROOT}" >> "${BUILD_ENV}"
    printf -- "Install Maven success\n" >> "${LOG_FILE}"

    # Build Snappy (required for LevelDB)
    cd "${SOURCE_ROOT}"
    wget https://github.com/google/snappy/releases/download/1.1.3/snappy-1.1.3.tar.gz
    tar -zxvf snappy-1.1.3.tar.gz
    export SNAPPY_HOME="${SOURCE_ROOT}/snappy-1.1.3"
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
    JAVA_HOME="/opt/openjdk/8/" PATH="/opt/openjdk/8/bin/:${PATH}" mvn clean install -P download -Plinux64-s390x -DskipTests
    JAVA_HOME="/opt/openjdk/8/" PATH="/opt/openjdk/8/bin/:${PATH}" jar -xvf "${LEVELDBJNI_HOME}/leveldbjni-linux64-s390x/target/leveldbjni-linux64-s390x-1.8.jar"
    export LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:${SOURCE_ROOT}/leveldbjni/META-INF/native/linux64/s390x"
    printf -- 'export LEVELDB_HOME="%s/leveldb"\n' "${SOURCE_ROOT}"  >> "${BUILD_ENV}"
    printf -- 'export LEVELDBJNI_HOME="%s/leveldbjni"\n' "${SOURCE_ROOT}"  >> "${BUILD_ENV}"
    printf -- 'export LIBRARY_PATH="${SNAPPY_HOME}"\n'  >> "${BUILD_ENV}"
    printf -- 'export C_INCLUDE_PATH="${LIBRARY_PATH}"\n'  >> "${BUILD_ENV}"
    printf -- 'export CPLUS_INCLUDE_PATH="${LIBRARY_PATH}"\n'  >> "${BUILD_ENV}"
    printf -- 'export LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:%s/leveldbjni/META-INF/native/linux64/s390x"\n' "${SOURCE_ROOT}" >> "${BUILD_ENV}"

        # Set up environment for Apache Spark build.
    export MAVEN_OPTS="-Xmx3g -XX:ReservedCodeCacheSize=1024m"
    printf -- 'export MAVEN_OPTS="-Xmx3g -XX:ReservedCodeCacheSize=1024m"\n'  >> "${BUILD_ENV}"

    # Prepare for compile by downloading source code, applying patch and ignoring tests for unsupported components
    cd "${SOURCE_ROOT}"
    git clone -b v"${PACKAGE_VERSION}" https://github.com/apache/spark.git
    printf -- 'Download source code success \n'  >> "${LOG_FILE}"

    apply_patch
    ignore_unsupported_test

    # Build Apache Spark
    ./build/mvn -DskipTests clean package
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
    echo " build_spark.sh  [-d debug] [-y install-without-confirmation] [-t run test cases]"
    echo
}


while getopts "h?dyt" opt; do
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
    esac
done


function gettingStarted() {
    printf -- '\n****************************************************************************************************\n'
    printf -- "\n*Getting Started * \n"
    printf -- "Run following commands to get started: \n"

    printf -- "./spark/bin/spark-shell \n\n"
    printf -- "Note: Environmental Variable needed have been added to setenv.sh\n"
    printf -- "Note: To set the Environmental Variable needed for Spark, please run: source \"${SOURCE_ROOT}/setenv.sh\" \n"
    printf -- "For more help visit https://spark.apache.org/docs/latest/spark-standalone.html"
    printf -- '******************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
    "ubuntu-18.04" | "ubuntu-20.04" | "ubuntu-21.04")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo apt-get update
        sudo apt-get install -y wget tar git libtool autoconf build-essential curl apt-transport-https |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

    "rhel-7.8" | "rhel-7.9" | "rhel-8.1" | "rhel-8.2" | "rhel-8.3")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo yum groupinstall -y 'Development Tools'  |& tee -a "${LOG_FILE}"
        sudo yum install -y wget tar git libtool autoconf make curl python3 |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

    "sles-12.5" | "sles-15.2")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo zypper install -y wget tar git libtool autoconf curl gcc make gcc-c++ zip unzip gzip gawk |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

    *)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "${LOG_FILE}"
        exit 1
        ;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
