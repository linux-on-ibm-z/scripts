#!/bin/bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ApacheSpark/2.3.2/build_spark.sh
# Execute build script: bash build_apachespark.sh    (provide -h for help)



set -e -o pipefail

PACKAGE_NAME="spark"
PACKAGE_VERSION="2.3.2"
CURDIR="$(pwd)"
CONF_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ApacheSpark/2.3.2/patch/"


FORCE="false"
TESTS="false"
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
    cat /etc/redhat-release >> "${LOG_FILE}"
    export ID="rhel"
    export VERSION_ID="6.x"
    export PRETTY_NAME="Red Hat Enterprise Linux 6.x"
fi


function prepare() {
    if  command -v "sudo" > /dev/null ;
    then
        printf -- 'Sudo : Yes\n' >> "$LOG_FILE"
    else
        printf -- 'Sudo : No \n' >> "$LOG_FILE"
        printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n';
    exit 1;
    fi;

    if [[ "$FORCE" == "true" ]] ;
    then
        printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
    else
        # Ask user for prerequisite installation
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
}


function cleanup() {
    # Remove artifacts
    rm -rf "${CURDIR}/Platform.diff"
    rm -rf "${CURDIR}/OffHeapColumnVector.diff"
    rm -rf "${CURDIR}/OnHeapColumnVector.diff"
    rm -rf "${CURDIR}/StatsdSinkSuite.diff"

    printf -- "Cleaned up the artifacts\n" >> "$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

    cd "$CURDIR"

    if [[ "$ID" == "sles" ]]; then
        # Install Maven
        cd "$CURDIR"
        wget http://mirrors.estointernet.in/apache/maven/maven-3/3.6.1/binaries/apache-maven-3.6.1-bin.tar.gz
        tar -xvf apache-maven-3.6.1-bin.tar.gz
        export PATH=$PATH:$CURDIR/apache-maven-3.6.1/bin
    fi

    # Install AdoptOpenJDK 8 (With OpenJ9)
                cd "$CURDIR"
                wget https://github.com/AdoptOpenJDK/openjdk8-binaries/releases/download/jdk8u202-b08_openj9-0.12.1/OpenJDK8U-jdk_s390x_linux_openj9_8u202b08_openj9-0.12.1.tar.gz
                tar -xvf OpenJDK8U-jdk_s390x_linux_openj9_8u202b08_openj9-0.12.1.tar.gz
                printf -- "install AdoptOpenJDK 8 (With OpenJ9) success\n" >> "$LOG_FILE"
                export JAVA_HOME=$CURDIR/jdk8u202-b08/
                export PATH=$JAVA_HOME/bin:$PATH
                printf -- 'export JAVA_HOME for "$ID"  \n'  >> "$LOG_FILE"

                #Build LevelDB JNI

                cd "$CURDIR"
                wget https://github.com/google/snappy/releases/download/1.1.3/snappy-1.1.3.tar.gz
                tar -zxvf  snappy-1.1.3.tar.gz
                export SNAPPY_HOME=`pwd`/snappy-1.1.3
                cd ${SNAPPY_HOME}
                ./configure --disable-shared --with-pic
                make

                cd "$CURDIR"
                git clone -b s390x https://github.com/linux-on-ibm-z/leveldb.git
                git clone -b leveldbjni-1.8-s390x https://github.com/linux-on-ibm-z/leveldbjni.git
                export LEVELDB_HOME=`pwd`/leveldb
                export LEVELDBJNI_HOME=`pwd`/leveldbjni
                export LIBRARY_PATH=${SNAPPY_HOME}
                export C_INCLUDE_PATH=${LIBRARY_PATH}
                export CPLUS_INCLUDE_PATH=${LIBRARY_PATH}
                cd ${LEVELDB_HOME}
                git apply ${LEVELDBJNI_HOME}/leveldb.patch
                make libleveldb.a
                cd ${LEVELDBJNI_HOME}
                mvn clean install -P download -Plinux64-s390x -DskipTests
                jar -xvf ${LEVELDBJNI_HOME}/leveldbjni-linux64-s390x/target/leveldbjni-linux64-s390x-1.8.jar
                export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$CURDIR/leveldbjni/META-INF/native/linux64/s390x

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
                export MAVEN_OPTS="-Xmx2g -XX:ReservedCodeCacheSize=512m"
                ulimit -s unlimited
                ulimit -n 999999




    # Download  source code
    cd "$CURDIR"
    git clone -b v"${PACKAGE_VERSION}" https://github.com/apache/spark.git

    printf -- 'Download source code success \n'  >> "$LOG_FILE"

    cd "$CURDIR"

    # Patch Platform.java file
        curl -o "Platform.diff"  $CONF_URL/Platform.diff
        # replace config file
        patch "${CURDIR}/spark/common/unsafe/src/main/java/org/apache/spark/unsafe/Platform.java" Platform.diff
        printf -- 'Platform.java \n'  >> "$LOG_FILE"

    # Patch OffHeapColumnVector.diff
        curl -o "OffHeapColumnVector.diff"  $CONF_URL/OffHeapColumnVector.diff
        # replace config file
        patch "${CURDIR}/spark/sql/core/src/main/java/org/apache/spark/sql/execution/vectorized/OffHeapColumnVector.java" OffHeapColumnVector.diff
        printf -- 'Patched OffHeapColumnVector \n'  >> "$LOG_FILE"


    # Patch OnHeapColumnVector.diff
        curl -o "OnHeapColumnVector.diff"  $CONF_URL/OnHeapColumnVector.diff
        # replace config file
        patch "${CURDIR}/spark/sql/core/src/main/java/org/apache/spark/sql/execution/vectorized/OnHeapColumnVector.java" OnHeapColumnVector.diff
        printf -- 'Patched OnHeapColumnVector \n'  >> "$LOG_FILE"


    # Patch StatsdSinkSuite.diff file
        curl -o "StatsdSinkSuite.diff"  $CONF_URL/StatsdSinkSuite.diff
        # replace config file
        patch "${CURDIR}/spark/core/src/test/scala/org/apache/spark/metrics/sink/StatsdSinkSuite.scala" StatsdSinkSuite.diff
        printf -- 'Patched StatsdSinkSuite \n'   >> "$LOG_FILE"


    # Build Apache Spark
    cd "$CURDIR/spark"
    git diff
    mv sql/core/src/test/scala/org/apache/spark/sql/execution/arrow/ArrowConvertersSuite.scala sql/core/src/test/scala/org/apache/spark/sql/execution/arrow/ArrowConvertersSuite.scala.orig
mv sql/core/src/test/scala/org/apache/spark/sql/execution/vectorized/ColumnarBatchSuite.scala sql/core/src/test/scala/org/apache/spark/sql/execution/vectorized/ColumnarBatchSuite.scala.orig
mv sql/core/src/test/scala/org/apache/spark/sql/execution/vectorized/ArrowColumnVectorSuite.scala sql/core/src/test/scala/org/apache/spark/sql/execution/vectorized/ArrowColumnVectorSuite.scala.orig
mv sql/core/src/test/scala/org/apache/spark/sql/execution/arrow/ArrowWriterSuite.scala sql/core/src/test/scala/org/apache/spark/sql/execution/arrow/ArrowWriterSuite.scala.orig
mv sql/core/src/test/scala/org/apache/spark/sql/execution/arrow/ArrowUtilsSuite.scala sql/core/src/test/scala/org/apache/spark/sql/execution/arrow/ArrowUtilsSuite.scala.orig
mv sql/hive/src/test/scala/org/apache/spark/sql/hive/orc/HiveOrcFilterSuite.scala sql/hive/src/test/scala/org/apache/spark/sql/hive/orc/HiveOrcFilterSuite.scala.orig
mv sql/hive/src/test/scala/org/apache/spark/sql/hive/orc/HiveOrcQuerySuite.scala sql/hive/src/test/scala/org/apache/spark/sql/hive/orc/HiveOrcQuerySuite.scala.orig
mv sql/hive/src/test/scala/org/apache/spark/sql/hive/orc/OrcHadoopFsRelationSuite.scala sql/hive/src/test/scala/org/apache/spark/sql/hive/orc/OrcHadoopFsRelationSuite.scala.orig
mv sql/hive/src/test/scala/org/apache/spark/sql/hive/orc/HiveOrcPartitionDiscoverySuite.scala sql/hive/src/test/scala/org/apache/spark/sql/hive/orc/HiveOrcPartitionDiscoverySuite.scala.orig
mv sql/hive/src/test/scala/org/apache/spark/sql/hive/orc/HiveOrcSourceSuite.scala sql/hive/src/test/scala/org/apache/spark/sql/hive/orc/HiveOrcSourceSuite.scala.orig
mv sql/hive/src/test/scala/org/apache/spark/sql/hive/orc/OrcReadBenchmark.scala sql/hive/src/test/scala/org/apache/spark/sql/hive/orc/OrcReadBenchmark.scala.orig
    ./build/mvn -DskipTests clean package

    printf -- 'Build Apache Spark success \n'  >> "$LOG_FILE"




#Exporting Spark ENV to $HOME/setenv.sh for later use
cd $HOME
cat << EOF > setenv.sh
#SPARK ENV
export PATH=$PATH:$CURDIR/apache-maven-3.6.1/bin
export JAVA_HOME=$CURDIR/jdk8u202-b08/
export PATH=$JAVA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$CURDIR/leveldbjni/META-INF/native/linux64/s390x
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/$CURDIR/zstd-jni/target/classes/linux/s390x/
EOF

    #cleanup
    cleanup

}

function logDetails() {
    printf -- '**************************** SYSTEM DETAILS *************************************************************\n' >"$LOG_FILE"
    if [ -f "/etc/os-release" ]; then
        cat "/etc/os-release" >> "$LOG_FILE"
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
    echo " build_spark.sh  [-d debug] [-y install-without-confirmation] [-t install and run tests]"
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
        TESTS="false"
        ;;
    esac
done


function gettingStarted() {
    printf -- '\n********************************************************************************************************\n'
    printf -- "\n*Getting Started * \n"
    printf -- "Run following commands to get started: \n"

    printf -- "./spark/bin/spark-shell \n\n"
    printf -- "Note: Environmental Variable needed have already been added to $HOME/setenv.sh\n"
    printf -- "Note: To set the Environmental Variable needed for Spark, please run: source $HOME/setenv.sh \n"
    printf -- "For more help visit https://spark.apache.org/docs/latest/spark-standalone.html"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
    "ubuntu-16.04" | "ubuntu-18.04" | "ubuntu-19.04")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo apt-get update
        sudo apt-get install -y wget tar git libtool autoconf build-essential maven |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;
    "rhel-7.4" | "rhel-7.5" | "rhel-7.6")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo yum groupinstall -y 'Development Tools'  |& tee -a "$LOG_FILE"
        sudo yum install -y maven wget tar git libtool autoconf make patch curl  |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;
    "sles-12.4" | "sles-15")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo zypper install -y patch curl wget tar git libtool autoconf gcc make  gcc-c++ zip unzip |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

    *)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
        exit 1
        ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
