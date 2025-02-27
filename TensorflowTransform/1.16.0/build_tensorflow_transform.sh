#!/bin/bash
# © Copyright IBM Corporation 2025.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/TensorflowTransform/1.16.0/build_tensorflow_transform.sh
# Execute build script: bash build_tensorflow_transform.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="tensorflow_transform"
PACKAGE_VERSION="1.16.0"
CURDIR="$(pwd)"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/TensorflowTransform/1.16.0/patch"
TENSORFLOW_INSTALL_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Tensorflow/2.18.0/build_tensorflow.sh"
FORCE="false"
TESTS="false"
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
PYTHON_VERSION=3.11
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

    if [[ "$PYTHON_VERSION" != "3.9" && "$PYTHON_VERSION" != "3.10" && "$PYTHON_VERSION" != "3.11" ]]; then
        printf "Python version v$PYTHON_VERSION is not supported, Please use supported version from {3.9, 3.10, 3.11} only.\n"
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
        rm -rf "$CURDIR/cmake-3.21.2.tar.gz"
    fi

    if [ -f "$CURDIR/build_tensorflow.sh" ]; then
        rm -rf "$CURDIR/build_tensorflow.sh"
    fi

    printf -- 'Cleaned up the artifacts\n' >>"$LOG_FILE"
}

function configureAndInstall() {
    printf -- 'Configuration and Installation started \n'

    # Install TensorFlow Transform
    printf -- '\nInstalling %s..... \n' $PACKAGE_NAME

    # Install TensorFlow
    printf -- 'Installing TensorFlow... \n'

    cd "${CURDIR}"
    wget -O build_tensorflow.sh $TENSORFLOW_INSTALL_URL
    bash build_tensorflow.sh -y -p $PYTHON_VERSION
    printf -- 'TensorFlow installed successfully \n'

    if [[ "${DISTRO}" == "ubuntu-20.04" ]]; then
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

    git clone -b apache-arrow-10.0.1 --depth 1 https://github.com/apache/arrow.git
    cd arrow/cpp
    mkdir release
    cd release
    cmake -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DARROW_PARQUET=ON \
        -DARROW_PYTHON=ON \
        -DCMAKE_BUILD_TYPE=Release \
        ..
    make -j$(nproc)
    sudo make install
    export LD_LIBRARY_PATH=/usr/local/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}

    printf -- 'C++ library installed successfully \n'

    printf -- 'Installing pyarrow... \n'

    cd ../../python
    curl -o pyarrow.diff $PATCH_URL/pyarrow.diff
    git apply pyarrow.diff
    export PYARROW_WITH_PARQUET=1
    export PYARROW_PARALLEL=4
    sed -i '2d'  requirements-build.txt
    sed -i '2a oldest-supported-numpy>=0.14; python_version<'\''3.9'\''' requirements-build.txt
    sed -i '3a numpy<2.0.0,>=1.26.0; python_version>='\''3.9'\''' requirements-build.txt
    pip3 install -r requirements-build.txt
    python setup.py build_ext bdist_wheel
    pip3 install dist/*.whl

    printf -- 'pyarrow installed successfully \n'
    printf -- 'Apache Arrow installed successfully \n'

    printf -- 'Installing Apache Beam... \n'

    cd "${CURDIR}"                         
    GRPC_PYTHON_BUILD_SYSTEM_OPENSSL=True pip3 install 'apache-beam[gcp]'==2.60.0

    printf -- 'Apache Beam installed successfully \n'

    printf -- 'Installing tfx-bsl... \n'
    pip3 install --upgrade pip
    sudo update-alternatives --install /usr/local/bin/pip3 pip3 /usr/local/bin/pip${PYTHON_VERSION} 50
    
    # Check if tfx-bsl directory exists
    cd "${CURDIR}"
    if [ -d "$CURDIR/tfx-bsl" ]; then
        rm -rf $CURDIR/tfx-bsl
    fi
    if [[ "${DISTRO}" == "ubuntu-24.04" ]]; then
	sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-11 60
	sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-11 60
    fi
    curl -o tfx-bsl.diff $PATCH_URL/tfx-bsl.diff
    git clone -b v1.16.1 --depth 1 https://github.com/tensorflow/tfx-bsl.git
    cd tfx-bsl
    git apply ../tfx-bsl.diff

    sudo touch /usr/local/include/immintrin.h
    sed -i "179s/.*/            default=\'>=2.16,<2.19\',/" setup.py
    export BAZEL_HTTP_TIMEOUT=300
    python3 setup.py bdist_wheel
    pip3 install dist/*.whl

    printf -- 'tfx-bsl installed successfully \n'

    printf -- 'Installing tf-keras \n'
    pip3 install tf-keras
    
    printf -- 'Installing TensorFlow Transform... \n'
    cd "${CURDIR}"
    git clone -b v${PACKAGE_VERSION} --depth 1 https://github.com/tensorflow/transform.git
    cd transform
    sed -i "55s/.*/            default=\'>=2.16,<2.19\',/" setup.py
    python3 setup.py install --user

    printf -- 'Tensorflow Transform package installed successfully \n'

    # Run Tests
    runTest


    printf -- "\n Installation of %s %s was successful \n\n" $PACKAGE_NAME $PACKAGE_VERSION
}

function runTest() {
    set +e
    if [[ "$TESTS" == "true" ]]; then
        printf -- "TEST Flag is set, continue with running test \n"
        python3 -m unittest discover -v -p '*_test.py'
        printf -- "Tests completed. \n"
        #Cleanup
        cleanup

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
    echo " bash build_tensorflow_transform.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests] [-p python-version]"
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
    printf -- "   '1.16.0'  \n"
    printf -- "   >>> \n\n"
    printf -- '*************************************************************************************************\n'
    printf -- '\n'
}

###############################################################################################################

logDetails
prepare # Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-20.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    sudo apt-get update
    sudo apt-get install -y build-essential cargo curl git libopenblas-dev libgeos-dev |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"ubuntu-22.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    sudo apt-get update
    sudo apt-get install -y build-essential cargo curl git cmake libopenblas-dev libgeos-dev |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"ubuntu-24.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    sudo apt-get update
    sudo apt-get install -y build-essential cargo curl git cmake gcc-11 g++-11 libopenblas-dev libgeos-dev |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
