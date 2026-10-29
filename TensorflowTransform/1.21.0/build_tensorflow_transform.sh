#!/bin/bash
# © Copyright IBM Corporation 2025, 2026.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/TensorflowTransform/1.21.0/build_tensorflow_transform.sh
# Execute build script: bash build_tensorflow_transform.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="tensorflow_transform"
PACKAGE_VERSION="1.21.0"
CURDIR="$(pwd)"
SOURCE_ROOT="$(pwd)"
PYTHON_VERSION=""

FORCE="false"
TESTS="false"
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

# Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
    mkdir -p "$CURDIR/logs/"
fi

source "/etc/os-release"

function prepare() {
    if command -v "sudo" >/dev/null; then
        printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
    else
        printf -- 'Sudo : No \n' >>"$LOG_FILE"
        printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n'
        exit 1
    fi

    if [[ "$PYTHON_VERSION" != "3.10" && "$PYTHON_VERSION" != "3.11" && "$PYTHON_VERSION" != "3.12" && "$PYTHON_VERSION" != "3.13" ]]; then
        printf "Python version v$PYTHON_VERSION is not supported, Please use supported version from {3.10, 3.11, 3.12, 3.13} only.\n"
        exit 1
    fi

    if [[ "$FORCE" == "true" ]]; then
        printf -- 'Force attribute provided hence continuing with install without confirmation message' |& tee -a "$LOG_FILE"
    else
        printf -- "\n\nAs part of the installation , dependencies will be installed, \n"
        while true; do
            read -r -p "Do you want to continue (y/n) ? :  " yn
            case $yn in
            [Yy]*)
                printf -- 'User responded with Yes. \n' |& tee -a "$LOG_FILE"
                break
                ;;
            [Nn]*) exit ;;
            *) echo "Please provide confirmation to proceed." ;;
            esac
        done
    fi
}

function cleanup() {
    rm -rf $SOURCE_ROOT/bazel-7.4.1-dist.zip $SOURCE_ROOT/build_bazel.sh $SOURCE_ROOT/build_netty.sh $SOURCE_ROOT/go $SOURCE_ROOT/bazel $SOURCE_ROOT/dist $SOURCE_ROOT/arrow $SOURCE_ROOT/tfx-bsl
    printf -- 'Cleaned up the artifacts\n' | tee -a "$LOG_FILE"
}

function buildBazel() {
    printf -- '\nBuilding bazel..... \n'
    cd $SOURCE_ROOT
	wget -q -O build_bazel.sh "https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Bazel/7.4.1/build_bazel.sh"
    bash build_bazel.sh -y
    sudo cp $SOURCE_ROOT/bazel/output/bazel /usr/local/bin/bazel
    bazel --version
}

function configureAndInstall() {
    printf -- 'Configuration and Installation started \n'

    # Install TensorFlow Transform
    printf -- '\nInstalling %s..... \n' $PACKAGE_NAME

    pip3 install --upgrade pip

    export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python

    # Install Apache Arrow
    printf -- '\nInstalling Apache Arrow...\n'
    cd "$SOURCE_ROOT"
    if [ -d "$CURDIR/arrow" ]; then
        rm -rf "$CURDIR/arrow"
    fi

    printf -- 'Installing C++ library... \n'
    git clone -b apache-arrow-17.0.0 --depth 1 https://github.com/apache/arrow.git
    cd arrow/cpp
    mkdir -p build
    cd build
    cmake -DCMAKE_INSTALL_PREFIX=/usr/local \
          -DCMAKE_INSTALL_LIBDIR=lib \
          -DARROW_PARQUET=ON \
          -DARROW_PYTHON=ON \
          -DARROW_ORC=OFF \
          -DARROW_DATASET=ON \
          -DCMAKE_BUILD_TYPE=Release \
          ..
    make -j$(nproc)
    sudo make install
    sudo ldconfig
    export LD_LIBRARY_PATH=/usr/local/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}

    printf -- 'C++ library installed successfully \n'

    printf -- '\nInstalling pyarrow... \n'
    cd "$SOURCE_ROOT/arrow/python"
    sed -i 's|setuptools>=64|setuptools>=64,<72|' requirements-build.txt
    sed -i 's|cython>=0.29.31|cython>=0.29.31,<3.3|' requirements-build.txt
    pip3 install -r requirements-build.txt
    export PYARROW_WITH_PARQUET=1
    export PYARROW_PARALLEL=$(nproc)
    ARROW_HOME=/usr/local python${PYTHON_VERSION} setup.py build_ext --build-type=release --bundle-arrow-cpp bdist_wheel
    pip3 install dist/*.whl

    printf -- 'Apache Arrow installed successfully \n'

    printf -- '\nInstalling grpcio 1.73.0...\n'
    GRPC_PYTHON_BUILD_SYSTEM_OPENSSL=1 GRPC_PYTHON_BUILD_SYSTEM_ZLIB=1 pip3 install --no-build-isolation 'grpcio==1.73.0'

    printf -- '\nInstalling grpcio-status 1.73.0...\n'
    GRPC_PYTHON_BUILD_SYSTEM_OPENSSL=1 GRPC_PYTHON_BUILD_SYSTEM_ZLIB=1 pip3 install --no-build-isolation 'grpcio-status==1.73.0'

    printf -- '\nInstalling tensorflow-serving-api 2.19.0...\n'
    pip3 install tensorflow-serving-api==2.19.0

    printf -- '\nInstalling apache-beam[gcp]...\n'
    cd "$SOURCE_ROOT"
    PROTOBUF_VER=$(pip3 show protobuf | awk '/^Version:/{print $2}')
    printf "grpcio==1.73.0\ngrpcio-status==1.73.0\nprotobuf==${PROTOBUF_VER}\ncryptography<47\norjson==3.11.9\n" > constraints.txt
    printf "setuptools==79.0.0\n" > build_constraints.txt
    CRC32C_PURE_PYTHON=1 \
    GRPC_PYTHON_BUILD_SYSTEM_OPENSSL=1 \
    GRPC_PYTHON_BUILD_SYSTEM_ZLIB=1 \
        pip3 install \
            --constraint constraints.txt \
            --build-constraint build_constraints.txt \
            'apache-beam[gcp]==2.75.0'
    printf -- 'Apache Beam installed successfully \n'

    # Install tfx-bsl
    printf -- '\nInstalling tfx-bsl...\n'
    cd "$SOURCE_ROOT"
    if [ -d "$CURDIR/tfx-bsl" ]; then
        rm -rf "$CURDIR/tfx-bsl"
    fi
    git clone -b v1.21.0 --depth 1 https://github.com/tensorflow/tfx-bsl.git
    cd tfx-bsl

    sed -i 's/versions.check("7.7.0")/versions.check("7.4.1")/' WORKSPACE

    python${PYTHON_VERSION} setup.py bdist_wheel

    pip3 install --no-deps dist/*.whl
    pip3 install \
        --constraint "$SOURCE_ROOT/constraints.txt" \
        'absl-py<2.0.0,>=0.9' \
        dill \
        'google-api-python-client>=1.7.11' \
        'pandas>=2.0'

    pip3 install --no-deps 'tensorflow-metadata<1.22.0,>=1.21.0'
    printf -- 'tfx-bsl installed successfully \n'

    # Install TensorFlow Transform
    printf -- '\nInstalling TensorFlow Transform...\n'
    cd "$SOURCE_ROOT"
    if [ -d "$CURDIR/transform" ]; then
        rm -rf "$CURDIR/transform"
    fi
    git clone -b v${PACKAGE_VERSION} --depth 1 https://github.com/tensorflow/transform.git
    cd transform

    python${PYTHON_VERSION} setup.py bdist_wheel

    pip3 install --no-deps dist/*.whl

    pip3 install --constraint "$SOURCE_ROOT/constraints.txt" 'pydot<2,>=1.2' 'tf-keras>=2'
    printf -- 'Tensorflow Transform package installed successfully \n'

    # Run Tests
    runTest

    printf -- "\n Installation of %s %s was successful \n\n" "$PACKAGE_NAME" "$PACKAGE_VERSION"
}

function runTest() {
    set +e
    if [[ "$TESTS" == "true" ]]; then
        printf -- "TEST Flag is set, continue with running test \n"

        pip3 install 'pytest>=8.0'
        cd "$SOURCE_ROOT/transform"
        python${PYTHON_VERSION} -m pytest -v tensorflow_transform/ 2>&1 | tee -a "$LOG_FILE"

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
    echo "  bash build_tensorflow_transform.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests] [-p python-version]"
    echo "    -p: use Python version from {3.10, 3.11, 3.12, 3.13}. If omitted, uses"
    echo "        whichever python3 is already the system default. Must match the Python"
    echo "        version TensorFlow was built with."
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
        PYTHON_VERSION=$OPTARG
        ;;
    y)
        FORCE="true"
        ;;
    t)
        TESTS="true"
        ;;
    esac
done

if [[ -z "$PYTHON_VERSION" ]]; then
    if command -v python3 >/dev/null; then
        PYTHON_VERSION="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
    fi
fi

function gettingStarted() {
    printf -- '\n***********************************************************************************************\n'
    printf -- "Getting Started: \n"
    printf -- "To verify, run TensorFlow Transform from command Line : \n"
    printf -- "  $ export LD_LIBRARY_PATH=/usr/local/lib\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}} \n"
    printf -- "  $ export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python  \n"
    printf -- "  $ cd $CURDIR  \n"
    printf -- "  $ python${PYTHON_VERSION}  \n"
    printf -- "   >>> import tensorflow as tf  \n"
    printf -- "   >>> import tensorflow_transform as tft  \n"
    printf -- "   >>> tft.version.__version__  \n"
    printf -- "   '1.21.0'  \n"
    printf -- "   >>> \n\n"

    printf -- "Note:\n"
    printf -- "  - TensorFlow is a pre-requisite and is not built by this script. \n"
    printf -- '*************************************************************************************************\n'
    printf -- '\n'
}

###############################################################################################################

logDetails
prepare # Check Prerequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-22.04" | "ubuntu-24.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    sudo apt-get update
    sudo apt-get install -y build-essential cargo curl git cmake libopenblas-dev libgeos-dev \
        wget pkg-config libhdf5-dev libffi-dev libjpeg-dev libpng-dev libtiff-dev \
        libgrpc-dev libgrpc++-dev libprotobuf-dev protobuf-compiler protobuf-compiler-grpc |& tee -a "$LOG_FILE"
    buildBazel |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
