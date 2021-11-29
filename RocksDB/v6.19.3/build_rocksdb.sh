#!/bin/bash
# ©  Copyright IBM Corporation 2021.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/RocksDB/v6.19.3/build_rocksdb.sh
# Execute build script: bash build_rocksdb.sh    (provide -h for help)
#

set -e -o pipefail

PACKAGE_NAME="rocksdb"
PACKAGE_VERSION="v6.19.3"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/RocksDB/${PACKAGE_VERSION}/patch"
FORCE="false"
TESTS="false"
CURDIR="$(pwd)"
CURPATH="$(echo $PATH)"
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
JAVA_PROVIDED="OpenJDK8"
BUILD_ENV="$HOME/setenv_${PACKAGE_NAME}-${PACKAGE_VERSION}.sh"
PREFIX="/usr/local"

trap cleanup 1 2 ERR

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
        mkdir -p "$CURDIR/logs/"
fi

if [ -f "/etc/os-release" ]; then
        source "/etc/os-release"
fi

function prepare() {
        if command -v "sudo" >/dev/null; then
                printf -- 'Sudo : Yes\n'
        else
                printf -- 'Sudo : No \n'
                printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n'
                exit 1
        fi

        if [[ "$JAVA_PROVIDED" != "SemuruJDK8" && "$JAVA_PROVIDED" != "OpenJDK8" ]]; then
                printf "$JAVA_PROVIDED is not supported, Please use valid java from {SemuruJDK8, OpenJDK8} only\n"
                exit 1
        fi

        if [[ "$FORCE" == "true" ]]; then
                printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "${LOG_FILE}"
        else
                # Ask user for prerequisite installation
                printf -- "\nAs part of the installation, dependencies would be installed/upgraded. \n"
                while true; do
                        read -r -p "Do you want to continue (y/n) ? :  " yn
                        case $yn in
                        [Yy]*)
                                printf -- 'User responded with Yes. \n' |& tee -a "${LOG_FILE}"
                                break
                                ;;
                        [Nn]*) exit ;;
                        *) echo "Please provide confirmation to proceed." ;;
                        esac
                done
        fi

        # zero out
        true > "$BUILD_ENV"
}

function cleanup() {
        cd $CURDIR
        sudo rm -rf semurujdk.tar.gz
        printf -- 'Cleaned up the artifacts\n' >>"${LOG_FILE}"
}

function buildCmake(){
  local ver=3.21.2
  echo "Building cmake $ver"

  cd "$CURDIR"
  URL=https://github.com/Kitware/CMake/releases/download/v${ver}/cmake-${ver}.tar.gz
  curl -sSL $URL | tar xzf - || error "cmake $ver"
  cd cmake-${ver}
  ./bootstrap
  make
  sudo make install
}

buildZstd()
{
  ver=1.4.9
  echo "Building zstd $ver"

  cd "$CURDIR"
  URL=https://github.com/facebook/zstd/releases/download/v${ver}/zstd-${ver}.tar.gz
  curl -sSL $URL | tar xzf - || error "zstd $ver"
  cd zstd-${ver}/lib
  make
  sudo make install
}

function configureAndInstall() {

        printf -- 'Configuration and Installation started \n'

        printf -- "Installing selected JDK: %s\n" "${JAVA_PROVIDED}"
        cd $CURDIR
        if [[ "$JAVA_PROVIDED" == "SemuruJDK8" ]]; then
                # Install IBM Semeru JDK 8
                sudo mkdir -p /opt/semuru/java

                curl -SL -o semurujdk.tar.gz https://github.com/ibmruntimes/semeru8-binaries/releases/download/jdk8u312-b07_openj9-0.29.0/ibm-semeru-open-jdk_s390x_linux_8u312b07_openj9-0.29.0.tar.gz
                # Everytime new jdk is downloaded, Ensure that --strip valueis correct
                sudo tar -zxvf semurujdk.tar.gz -C /opt/semuru/java --strip-components 1

                export JAVA_HOME=/opt/semuru/java

                printf -- "export JAVA_HOME=/opt/semuru/java\n" >> "$BUILD_ENV"
                printf -- "Installation of IBM Semeru JDK 8 is successful\n"

        elif [[ "$JAVA_PROVIDED" == "OpenJDK8" ]]; then
                if [[ "${ID}" == "ubuntu" ]]; then
                        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-8-jdk
                        export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-s390x
                        printf -- "export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-s390x\n" >> "$BUILD_ENV"
                elif [[ "${ID}" == "rhel" ]]; then
                        sudo yum install -y java-1.8.0-openjdk java-1.8.0-openjdk-devel
                        echo "Inside $DISTRO"
                        export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk
                        printf -- "export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk\n" >> "$BUILD_ENV"
                elif [[ "${ID}" == "sles" ]]; then
                        sudo zypper install -y java-1_8_0-openjdk java-1_8_0-openjdk-devel
                        export JAVA_HOME=/usr/lib64/jvm/java-1.8.0-openjdk
                        printf -- "export JAVA_HOME=/usr/lib64/jvm/java-1.8.0-openjdk\n" >> "$BUILD_ENV"
                fi
                printf -- "Installation of OpenJDK 8 is successful\n"
        else
                printf "$JAVA_PROVIDED is not supported, Please use valid java from {SemuruJDK8, OpenJDK8} only"
                exit 1
        fi
        printf -- "export PATH=$JAVA_HOME/bin:$PATH\n" >> "$BUILD_ENV"
        export PATH=$JAVA_HOME/bin:$PATH
        hash -r
        java -version |& tee -a "$LOG_FILE"

        printf -- "Installing gflags 2.0\n"
        cd $CURDIR
        git clone https://github.com/gflags/gflags.git
        cd gflags
        git checkout v2.0
        ./configure --prefix="$PREFIX"
        make
        sudo make install
        sudo ldconfig /usr/local/lib
        printf -- "export LD_LIBRARY_PATH=/usr/local/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}\n" >> "$BUILD_ENV"

        printf -- "Building %s %s\n" "$PACKAGE_NAME" "$PACKAGE_VERSION"
        cd $CURDIR
        git clone https://github.com/facebook/rocksdb.git
        cd rocksdb/
        git checkout $PACKAGE_VERSION
        curl -sSL ${PATCH_URL}/rocksdb.diff | patch -p1 || error "rocksdb.diff"
        curl -sSL https://github.com/facebook/rocksdb/commit/b4326b5273f677f28d5709e0f2ff86cf2d502bb3.patch | git apply --include="table/table_test.cc" - || error "c++-11 patch"

        # Build and install the rocksdb C++ static library
        make -j$(nproc) static_lib
        sudo make install-static

        # Build the rocksdb Java jar
        PORTABLE=1 make -j$(nproc) rocksdbjavastatic
        cp ./java/target/*.jar* ./

        # run tests
        runTest
        
	# Cleanup
        cleanup
        
        printf -- "%s installation completed. Please check the Usage.\n" "$PACKAGE_NAME"
}

function error() { echo "Error: ${*}"; exit 1; }

function runTest() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
	    printf -- "TEST Flag is set, continue with running test \n"
	    cd ${CURDIR}
            printf -- "Preparing for running tests. \n"
            cd ${CURDIR}/rocksdb/
            if [[ "$JAVA_PROVIDED" == "SemuruJDK8" ]]; then
                sed -i 's/-ea -Xcheck:jni/-ea/g' java/Makefile
            fi
            make clean
            # For tests, disable jemalloc and tcmalloc if previously installed.
            # jemalloc causes test failures on both s390x and x86_64.
            ROCKSDB_DISABLE_JEMALLOC=1 ROCKSDB_DISABLE_TCMALLOC=1 make -j$(nproc) all
            ROCKSDB_DISABLE_JEMALLOC=1 ROCKSDB_DISABLE_TCMALLOC=1 make -j$(nproc) J=1 SKIP_FORMAT_BUCK_CHECKS=1 check
            ROCKSDB_DISABLE_JEMALLOC=1 ROCKSDB_DISABLE_TCMALLOC=1 LIB_MODE=shared PORTABLE=1 make -j1 rocksdbjava jtest
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
        printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" |& tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
        echo
        echo "Usage: "
        echo "  build_rocksdb.sh  [-d debug] [-y install-without-confirmation] [-t run-test] [-j Java to use from {OpenJDK8, SemuruJDK8}]"
        echo "  default: If no -j specified, openjdk-8 will be installed"
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
        printf -- "\n* Getting Started * \n"
        printf -- "Note: Environment Variables needed have been added to ${BUILD_ENV}\n"
        printf -- "Note: To set the Environment Variables needed for rocksdb, please run: source ${BUILD_ENV} \n\n"
        printf -- "The rocksdb static library has been installed and is located at $PREFIX/lib/rocksdb.a\n"
        printf -- "The rocksdb java jar files are located at $CURDIR/rocksdb/rocksdbjni-*\n\n"
        printf -- "Visit:\n"
        printf -- " * https://rocksdb.org/\n"
        printf -- " * https://github.com/facebook/rocksdb\n"
        printf -- "for more information.\n"
        printf -- '********************************************************************************************************\n'
}

###############################################################################################################

logDetails
prepare

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-18.04" | "ubuntu-20.04" | "ubuntu-21.04" | "ubuntu-21.10")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo apt-get update |& tee -a "${LOG_FILE}"
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends tzdata |& tee -a "${LOG_FILE}"
        sudo apt-get install -y git patch libsnappy-dev zlib1g-dev libbz2-dev liblz4-dev libzstd-dev g++ make python3 perl cmake curl wget libarchive-dev diffutils openssl gzip file procps |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"rhel-7.8" | "rhel-7.9")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo subscription-manager repos --enable=rhel-7-server-for-system-z-rhscl-rpms || true
        sudo yum install -y git patch snappy snappy-devel zlib zlib-devel bzip2 bzip2-devel lz4-devel devtoolset-8-gcc-c++ devtoolset-8-gcc make python3 perl curl wget libarchive diffutils which openssl openssl-devel gzip file procps |& tee -a "${LOG_FILE}"
        source /opt/rh/devtoolset-8/enable
        buildCmake |& tee -a "${LOG_FILE}"
        buildZstd |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"rhel-8.2" | "rhel-8.4")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo yum install -y git patch snappy snappy-devel zlib zlib-devel bzip2 bzip2-devel lz4-devel libzstd-devel libasan gcc-c++ make python3 perl cmake curl wget libarchive diffutils which openssl openssl-devel gzip file procps |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"sles-12.5")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo zypper install -y git patch libsnappy1 snappy-devel libz1 zlib-devel bzip2 libbz2-devel liblz4-devel libzstd-devel gcc7-c++ make python3 perl curl wget diffutils which openssl openssl-devel awk gzip file procps |& tee -a "${LOG_FILE}"
        sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-7 100
        sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-7 100
        sudo update-alternatives --install /usr/bin/cpp cpp /usr/bin/cpp-7 100
        sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-7 100
        buildCmake |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"sles-15.2" | "sles-15.3")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo zypper install -y git patch libsnappy1 snappy-devel libz1 zlib-devel bzip2 libbz2-devel liblz4-devel libzstd-devel gcc-c++ make python3 perl cmake curl wget diffutils which openssl openssl-devel awk gzip file procps |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

*)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "${LOG_FILE}"
        exit 1

        ;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
