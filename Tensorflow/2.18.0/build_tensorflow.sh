#!/bin/bash
# © Copyright IBM Corporation 2025.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Tensorflow/2.18.0/build_tensorflow.sh
# Execute build script: bash build_tensorflow.sh    (provide -h for help)
#

set -e  -o pipefail

PACKAGE_NAME="tensorflow"
PACKAGE_VERSION="2.18.0"
CURDIR="$(pwd)"
SOURCE_ROOT="$(pwd)"
USER="$(whoami)"

PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Tensorflow/2.18.0/patch"
ICU_MAJOR_VERSION="69"
ICU_RELEASE="release-${ICU_MAJOR_VERSION}-1"
NUMPY_VERSION="2.0.2"

FORCE="false"
TESTS="false"
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exists
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
        printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n'
        exit 1
    fi

    if [[ -z "$PYTHON_V" ]]; then
        PYTHON_V=3.11
    elif [[ "$PYTHON_V" != "3.9" && "$PYTHON_V" != "3.10" && "$PYTHON_V" != "3.11" && "$PYTHON_V" != "3.12" ]]; then
        printf "Python version v$PYTHON_V is not supported, Please use supported version from {3.9, 3.10, 3.11, 3.12} only.\n"
        exit 1
    fi

    if [[ "$FORCE" == "true" ]]; then
        printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
    else
        # Ask user for prerequisite installation
        printf -- "\nAs part of the installation, dependencies would be installed/upgraded. \n"
        while true; do
            read -r -p "Do you want to continue (y/n) ? :  " yn
            case $yn in
            [Yy]*)
                printf -- 'User responded with Yes. \n' >> "$LOG_FILE"
                break
                ;;
            [Nn]*) exit ;;
            *) echo "Please provide confirmation to proceed." ;;
            esac
        done
    fi
}

function cleanup() {
    # Remove artifacts
    rm -rf $SOURCE_ROOT/bazel-6.5.0-dist.zip
    rm -rf $SOURCE_ROOT/icu/
    rm -rf $SOURCE_ROOT/llvm.sh
    printf -- "Cleaned up the artifacts\n" | tee -a "$LOG_FILE"

}

function installClang() {
    printf -- '\nBuilding clang..... \n'
    if [ -e "/usr/bin/clang" ]; then
        echo "clang already installed."
        return 0
    fi
    cd $SOURCE_ROOT
    sudo apt-get install -y lsb-release software-properties-common gnupg
    wget https://apt.llvm.org/llvm.sh
    chmod +x llvm.sh
    sudo ./llvm.sh 18

    sudo ln -sf /usr/bin/clang-18 /usr/bin/clang
    sudo ln -sf /usr/bin/clang++-18 /usr/bin/clang++
}

function buildBazel() {
    printf -- '\nBuilding bazel..... \n'
    cd $SOURCE_ROOT
    wget -q https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Bazel/6.4.0/build_bazel.sh
    sed -i 's/6.4.0/6.5.0/g' build_bazel.sh
    sed -i 's#Bazel/${PACKAGE_VERSION}/patch#Bazel/6.4.0/patch#g' build_bazel.sh
    sed -i 's/apt-get install/DEBIAN_FRONTEND=noninteractive apt-get install/g' build_bazel.sh
    sed -i 's/23.10/24.04/g' build_bazel.sh
    sed -i 's/git clone https:\/\/github.com\/bazelbuild\/bazel.git/git clone -b $PACKAGE_VERSION --depth 1 https:\/\/github.com\/bazelbuild\/bazel.git/g' build_bazel.sh
    sed -i '170d' build_bazel.sh
    bash build_bazel.sh -y
    sudo cp $SOURCE_ROOT/bazel/output/bazel /usr/local/bin/bazel
}

function buildIcuData() {
    # See third_party/icu/data/BUILD.bazel in the tensorflow repo for more information
    cd $SOURCE_ROOT
    git clone --depth 1 --single-branch --branch "$ICU_RELEASE" https://github.com/unicode-org/icu.git
    cd icu/icu4c/source/
    # create ./filters.json
    cat << 'EOF' > filters.json
{
  "localeFilter": {
    "filterType": "language",
    "includelist": [
      "en"
    ]
  }
}
EOF
    ICU_DATA_FILTER_FILE=filters.json ./runConfigureICU Linux
    make clean && make
    # Workaround makefile issue where not all of the resource files may have been processed
    find data/out/build/ -name '*pool.res' -print0 | xargs -0 touch
    make
    cd data/out/tmp
    LD_LIBRARY_PATH=../../../lib ../../../bin/genccode "icudt${ICU_MAJOR_VERSION}b.dat"
    echo "U_CAPI const void * U_EXPORT2 uprv_getICUData_conversion() { return icudt${ICU_MAJOR_VERSION}b_dat.bytes; }" >> "icudt${ICU_MAJOR_VERSION}b_dat.c"
    cp icudt${ICU_MAJOR_VERSION}b_dat.c icu_conversion_data_big_endian.c
    gzip icu_conversion_data_big_endian.c
    split -a 3 -b 100000 icu_conversion_data_big_endian.c.gz icu_conversion_data_big_endian.c.gz.
}

function setupPython() {
    # Setting up Python
    wget -q https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Python3/$PY_VERSION/build_python3.sh
    sed -i 's/apt-get install/DEBIAN_FRONTEND=noninteractive apt-get install/g' build_python3.sh
 
    if [[ $DISTRO = "ubuntu-24.04" ]]; then
        sed -i 's/ubuntu-20.04/ubuntu-24.04/g' build_python3.sh
    elif [[ $DISTRO = "ubuntu-22.04" && "$PY_VERSION" = "3.9"* ]]; then
        sed -i 's/ubuntu-20.04/ubuntu-22.04/g' build_python3.sh
    fi

    bash build_python3.sh -y
    sudo update-alternatives --install /usr/local/bin/python python /usr/local/bin/python3 40
    printf -- "\n Installation of Python was successful \n\n"
} 

function configureAndInstall() {
    printf -- 'Configuration and Installation started \n'

    # Build ICU data in big-endian format
    printf -- "\nBuilding ICU big-endian data. . . \n"
    buildIcuData |& tee -a "${LOG_FILE}"

    #Build tensorflow_io_gcs_filesystem wheel
    printf -- '\nBuilding tensorflow_io_gcs_filesystem wheel..... \n'
    cd $SOURCE_ROOT
    git clone -b v0.37.1 --depth 1 https://github.com/tensorflow/io.git
    cd io/
    python3 setup.py -q bdist_wheel --project tensorflow_io_gcs_filesystem
    cd dist
    pip3 install ./tensorflow_io_gcs_filesystem-0.37.1-cp*-cp*-linux_s390x.whl

    #Install grpcio
    printf -- "\nInstalling grpcio. . . \n"
    export GRPC_PYTHON_BUILD_SYSTEM_OPENSSL=True
    pip3 install grpcio==1.64.1 |& tee -a "${LOG_FILE}"

    # Build TensorFlow
    printf -- '\nDownload Tensorflow source code..... \n'
    cd $SOURCE_ROOT
    rm -rf tensorflow
    git clone -b v${PACKAGE_VERSION} --depth 1 https://github.com/tensorflow/tensorflow
    cd tensorflow
    rm -rf third_party/tf_runtime/BUILD
    curl -o tf_v${PACKAGE_VERSION}.patch ${PATCH_URL}/tf_v${PACKAGE_VERSION}.patch
    patch -p1 < tf_v${PACKAGE_VERSION}.patch
    rm -f tf_v${PACKAGE_VERSION}.patch

    cp ${SOURCE_ROOT}/icu/icu4c/source/data/out/tmp/icu_conversion_data_big_endian.c.gz.* third_party/icu/data/
 
    export TF_NEED_CLANG=1
    export TF_NEED_OPENCL_SYCL=0
    export TF_NEED_CUDA=0
    export TF_NEED_MKL=0
    export TF_PYTHON_VERSION=$PYTHON_V
    export PYTHON_VERSION=$PY_VERSION
  
    printf -- '\nConfigure..... \n'
    yes "" | ./configure || true

    #Build Tensorflow
    printf -- '\nBuilding TENSORFLOW..... \n'
    TF_SYSTEM_LIBS=boringssl bazel build --copt=-Wno-gnu-offsetof-extensions --define tflite_with_xnnpack=false //tensorflow/tools/pip_package:wheel --repo_env=WHEEL_NAME=tensorflow

    #Install TensorFlow wheel
    printf -- '\nInstalling Tensorflow wheel..... \n'
    cd $SOURCE_ROOT/tensorflow
    pip3 install bazel-bin/tensorflow/tools/pip_package/wheel_house/tensorflow-${PACKAGE_VERSION}-cp*-cp*-linux_s390x.whl

    # Run Tests
    runTest

    #Cleanup
    cleanup

    printf -- "\n Installation of %s %s was successful \n\n" $PACKAGE_NAME $PACKAGE_VERSION
}


function runTest() {
    set +e
    if [[ "$TESTS" == "true" ]]; then
        printf -- "TEST Flag is set , Continue with running test \n"
        cd $SOURCE_ROOT/tensorflow
        TF_SYSTEM_LIBS=boringssl bazel test --copt=-Wno-gnu-offsetof-extensions --define tflite_with_xnnpack=false --test_size_filters=small,medium --build_tests_only --keep_going --test_output=errors --verbose_failures=true --local_test_jobs=HOST_CPUS --test_env=LD_LIBRARY_PATH --test_tag_filters=-no_oss,-oss_excluded,-oss_serial,-gpu,-tpu,-benchmark-test,-v1only --build_tag_filters=-no_oss,-oss_excluded,-oss_serial,-gpu,-tpu,-benchmark-test,-v1only --test_lang_filters=cc,py -- //tensorflow/... -//tensorflow/compiler/tf2tensorrt/... -//tensorflow/core/tpu/... -//tensorflow/lite/... -//tensorflow/tools/toolchains/...

        printf -- "Tests completed. \n"
    fi
    set -e
}

function logDetails() {
    printf -- '**************************** SYSTEM DETAILS *************************************************************\n' >>"$LOG_FILE"
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
    echo "  bash build_tensorflow.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests] [-p python-version]"
    echo
}

while getopts "h?dytp:" opt; do
    case "$opt" in
    h | \?)
        printHelp
        exit 0
        ;;
    d)
        set -x
        ;;
    p)
        PYTHON_V=$OPTARG
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
    printf -- '\n***********************************************************************************************\n'
    printf -- "Getting Started: \n"
    printf -- "To verify, run TensorFlow from command Line : \n"
    printf -- "  $ cd $SOURCE_ROOT  \n"
    printf -- "  $ python -c \"import tensorflow as tf; print(tf.__version__)\"  \n"
    printf -- "   $PACKAGE_VERSION  \n"
    printf -- "Make sure JAVA_HOME is set and bazel binary is in your path in case of test case execution. \n"
    printf -- '*************************************************************************************************\n'
    printf -- '\n'
}

###############################################################################################################

logDetails
prepare #Check Prequisites

case "$PYTHON_V" in

"3.9")
    PY_VERSION=3.9.7
    ;;

"3.10")
    PY_VERSION=3.10.6
    ;;

"3.11")
    PY_VERSION=3.11.4
    ;;

"3.12")
    PY_VERSION=3.12.0
    ;;
esac

DISTRO="$ID-$VERSION_ID"
export SETUPTOOLS_USE_DISTUTILS=stdlib

case "$DISTRO" in
"ubuntu-22.04" | "ubuntu-24.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install wget git unzip zip openjdk-11-jdk pkg-config libhdf5-dev libssl-dev libblas-dev liblapack-dev gfortran curl patchelf libopenblas-dev libatlas-base-dev libapr1-dev -y |& tee -a "${LOG_FILE}"
    installClang |& tee -a "${LOG_FILE}"
    buildBazel |& tee -a "${LOG_FILE}"
    setupPython |& tee -a "${LOG_FILE}"
    sudo ldconfig
    sudo update-alternatives --install /usr/local/bin/pip3 pip3 /usr/local/bin/pip${PYTHON_V} 50
    pip3 install wheel==0.41.3 setuptools==70.0.0 numpy==$NUMPY_VERSION ml-dtypes==0.4.1 h5py==3.13.0 scipy==1.13.1 |& tee -a "${LOG_FILE}"
    configureAndInstall |& tee -a "${LOG_FILE}"
    ;;

*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
