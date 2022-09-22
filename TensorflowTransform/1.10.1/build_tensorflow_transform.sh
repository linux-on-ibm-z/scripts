#!/bin/bash
# © Copyright IBM Corporation 2022.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/TensorflowTransform/1.10.1/build_tensorflow_transform.sh
# Execute build script: bash build_tensorflow_transform.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="tensorflow_transform"
PACKAGE_VERSION="1.10.1"
CURDIR="$(pwd)"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Tensorflow-Transform/1.10.1/patch"
TENSORFLOW_INSTALL_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Tensorflow/2.9.1/build_tensorflow.sh"

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

    if [[ "$FORCE" == "true" ]]; then
        printf -- 'Force attribute provided hence continuing with install without confirmation message' |& tee -a "$LOG_FILE"
    else
        # Ask user for prerequisite installation
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
    if [ -f "$CURDIR/cmake-3.21.2.tar.gz" ]; then
        rm "$CURDIR/cmake-3.21.2.tar.gz"
    fi

    if [ -f "$CURDIR/build_tensorflow.sh" ]; then
        rm "$CURDIR/build_tensorflow.sh"
    fi

    printf -- 'Cleaned up the artifacts\n' >>"$LOG_FILE"
}

function configureAndInstall() {
    printf -- 'Configuration and Installation started \n'

    # Install TensorFlow Transform
    printf -- '\nInstalling %s..... \n' '$PACKAGE_NAME'

    # Install TensorFlow
    printf -- 'Installing TensorFlow... \n'

    cd "${CURDIR}"
    wget -O build_tensorflow.sh $TENSORFLOW_INSTALL_URL
    if [[ "${DISTRO}" == "ubuntu-18.04" ]]; then
        # Change python version to 3.9.7
        sed -i "s#3.10.4#3.9.7#" build_tensorflow.sh
    fi
	if [[ "${DISTRO}" == "ubuntu-22.04" ]]; then
        # Build python v3.9.7 from source
        sed -i "271 i sudo apt-get install -y libblas-dev\n\twget -q https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Python3/3.9.7/build_python3.sh\n\tsed -i 's/apt-get install/DEBIAN_FRONTEND=noninteractive apt-get install/g' build_python3.sh\n\tsed -i 's/ubuntu-21.04/ubuntu-22.04/g'  build_python3.sh\n\tbash build_python3.sh -y\n\tsudo update-alternatives --install /usr/local/bin/python python /usr/local/bin/python3 40\n\tsudo ldconfig" build_tensorflow.sh
    fi
    bash build_tensorflow.sh -y

    printf -- 'TensorFlow installed successfully \n'

    if [[ "${DISTRO}" == "ubuntu-18.04" || "${DISTRO}" == "ubuntu-20.04" ]]; then
        # Build CMake 3.21.2
        printf -- 'Installing CMake 3.21.2 ... \n'

        # Check if CMake directory exists
        cd "${CURDIR}"
        if [ -d "$CURDIR/cmake-3.21.2" ]; then
            rm -rf $CURDIR/cmake-3.21.2
        fi

        wget https://github.com/Kitware/CMake/releases/download/v3.21.2/cmake-3.21.2.tar.gz
        tar -xzf cmake-3.21.2.tar.gz
        cd cmake-3.21.2
        ./bootstrap --prefix=/usr
        make
        sudo make install

        printf -- 'CMake installed successfully \n'
    fi

    # Install Apache Arrow
    printf -- 'Installing Apache Arrow... \n'

    # Check if Arrow directory exists
    cd "${CURDIR}"
    if [ -d "$CURDIR/arrow" ]; then
        rm -rf $CURDIR/arrow
    fi

    printf -- 'Installing C++ library... \n'

    git clone https://github.com/apache/arrow.git
    cd arrow
    git checkout apache-arrow-6.0.0
    cd cpp
    mkdir release
    cd release
    cmake -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DARROW_PARQUET=ON \
        -DARROW_PYTHON=ON \
        -DCMAKE_BUILD_TYPE=Release \
        ..
    make -j4
    sudo make install
    export LD_LIBRARY_PATH=/usr/local/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}

    printf -- 'C++ library installed successfully \n'

    printf -- 'Installing pyarrow... \n'

    sudo pip3 install pyarrow==6.0.0

    printf -- 'pyarrow installed successfully \n'
    printf -- 'Apache Arrow installed successfully \n'

    printf -- 'Installing Protobuf... \n'

    # Install compatible Protobuf
    sudo pip3 uninstall protobuf -y
    cd "${CURDIR}"
    git clone https://github.com/protocolbuffers/protobuf.git
    cd protobuf/
    git submodule update --init --recursive
    git checkout v3.19.4
    ./autogen.sh
    CXXFLAGS="-fPIC -g -O2" ./configure --prefix=/usr
    make
    sudo make install
    sudo ldconfig
    cd python/
    sudo python3 setup.py bdist_wheel --cpp_implementation --compile_static_extension
    sudo pip3 install dist/*.whl

    printf -- 'Protobuf installed successfully \n'
    printf -- 'Installing Apache Beam... \n'

    cd "${CURDIR}"
    if [[ "${DISTRO}" == "ubuntu-22.04" ]]; then
        sudo pip3 install maturin
    fi                          
    sudo GRPC_PYTHON_BUILD_SYSTEM_OPENSSL=True pip3 install testresources protobuf==3.19.4 'apache-beam[gcp]'==2.40.0

    printf -- 'Apache Beam installed successfully \n'

    printf -- 'Building Bazel v4.2.2 ... \n'

    cd "${CURDIR}"
    mkdir bazel-4.2.2
    cd bazel-4.2.2
    wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Bazel/4.2.2/build_bazel.sh
    if [[ "${DISTRO}" == "ubuntu-22.04" ]]; then
      sed -i "s/\"ubuntu-20.04\"/\"ubuntu-20.04\" | \"ubuntu-22.04\"/g" build_bazel.sh
      # Patch netty tcnative on Ubuntu 22.04:
      sed -i '80 a \\tcurl -sSL https://github.com/netty/netty-tcnative/commit/05718d27977c6a8865a00c3b0a994331c7963128.patch | git apply || error "Patch netty tcnative openssl 3"' build_bazel.sh
    fi
    bash build_bazel.sh -y
    export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x
    export PATH=$JAVA_HOME/bin:$CURDIR/bazel-4.2.2/bazel/output:$PATH

    printf -- 'Bazel v4.2.2 installed successfully \n'

    printf -- 'Installing tfx-bsl... \n'

    # Check if tfx-bsl directory exists
    cd "${CURDIR}"
    if [ -d "$CURDIR/tfx-bsl" ]; then
        rm -rf $CURDIR/tfx-bsl
    fi

    curl -o tfx-bsl.diff $PATCH_URL/tfx-bsl.diff
    git clone https://github.com/tensorflow/tfx-bsl.git
    cd tfx-bsl
    git checkout v1.10.1
    patch -p1 < ../tfx-bsl.diff

    sudo touch /usr/local/include/immintrin.h
    python3 setup.py bdist_wheel
    sudo pip3 install dist/*.whl

    printf -- 'tfx-bsl installed successfully \n'

    printf -- 'Installing TensorFlow Transform... \n'

    cd "${CURDIR}"
    sudo pip3 install tensorflow-transform==1.10.1

    printf -- 'Tensorflow Transform package installed successfully \n'

    # Run Tests
    runTest

    #Cleanup
    cleanup

    printf -- "\n Installation of %s %s was successful \n\n" $PACKAGE_NAME $PACKAGE_VERSION
}

function runTest() {
    set +e
    if [[ "$TESTS" == "true" ]]; then
        printf -- "TEST Flag is set, continue with running test \n"

        # Check if transform directory exists
        cd "${CURDIR}"
        if [ -d "$CURDIR/transform" ]; then
            rm -rf $CURDIR/transform
        fi

        printf -- 'Downloading source code... \n'

        git clone https://github.com/tensorflow/transform.git
        cd transform
        git checkout v1.10.1

        printf -- 'Applying patches... \n'

        sed -i '352,355d' tensorflow_transform/coders/example_proto_coder_test.py

        printf -- 'Installing Transform package... \n'

        sudo python3 setup.py install

        printf -- 'Running tests... \n'

        python3 -m unittest discover -v -p '*_test.py'

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
    echo "  build_tensorflow_transform.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests]"
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
    printf -- '\n***********************************************************************************************\n'
    printf -- "Getting Started: \n"
    printf -- "To verify, run TensorFlow Transform from command Line : \n"
    printf -- "  $ export LD_LIBRARY_PATH=/usr/local/lib\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}} \n"
    printf -- "  $ cd $CURDIR  \n"
    printf -- "  $ python3  \n"
    printf -- "   >>> import tensorflow as tf  \n"
    printf -- "   >>> import tensorflow_transform as tft  \n"
    printf -- "   >>> tft.version.__version__  \n"
    printf -- "   '1.10.1'  \n"
    printf -- "   >>> \n\n"
    printf -- '*************************************************************************************************\n'
    printf -- '\n'
}

###############################################################################################################

logDetails
prepare # Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-18.04" | "ubuntu-20.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    sudo apt-get update
    sudo apt-get install -y build-essential cargo curl |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"ubuntu-22.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    sudo apt-get update
    sudo apt-get install -y build-essential cargo curl cmake |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
