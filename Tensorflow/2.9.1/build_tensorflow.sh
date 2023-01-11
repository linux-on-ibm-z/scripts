#!/bin/bash
# © Copyright IBM Corporation 2022, 2023.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Tensorflow/2.9.1/build_tensorflow.sh
# Execute build script: bash build_tensorflow.sh    (provide -h for help)
#

set -e  -o pipefail

PACKAGE_NAME="tensorflow"
PACKAGE_VERSION="2.9.1"
CURDIR="$(pwd)"
SOURCE_ROOT="$(pwd)"
USER="$(whoami)"

PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Tensorflow/2.9.1/patch"

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
    rm -rf $SOURCE_ROOT/bazel-5.1.1-dist.zip
    rm -rf $SOURCE_ROOT/tensorflow/build_patch.diff $SOURCE_ROOT/tensorflow/test_patch.diff
    printf -- "Cleaned up the artifacts\n" | tee -a "$LOG_FILE"

}
function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'

	if [[ "${DISTRO}" == "ubuntu-20.04" || "${DISTRO}" == "ubuntu-22.04" ]]; then
		printf -- "Create symlink for python 3 only environment\n" |& tee -a "$LOG_FILE"
		sudo update-alternatives --install /usr/bin/python python /usr/bin/python3 40
	fi

	#Install grpcio
	printf -- "\nInstalling grpcio. . . \n"
	export GRPC_PYTHON_BUILD_SYSTEM_OPENSSL=True
	sudo -E pip3 install grpcio |& tee -a "${LOG_FILE}"

	# Build Bazel
	printf -- '\nBuilding bazel..... \n'
	cd $SOURCE_ROOT
	wget -q https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Bazel/5.1.1/build_bazel.sh
	sed -i 's/apt-get install/DEBIAN_FRONTEND=noninteractive apt-get install/g' build_bazel.sh
	bash build_bazel.sh -y

	export PATH=$SOURCE_ROOT/bazel/output:$PATH
	
	# Build TensorFlow
	printf -- '\nDownload Tensorflow source code..... \n'
	cd $SOURCE_ROOT
	rm -rf tensorflow
	git clone https://github.com/tensorflow/tensorflow
	cd tensorflow
	git checkout v2.9.1
	curl -o build_patch.diff $PATCH_URL/build_patch.diff
	git apply --ignore-whitespace build_patch.diff
	
	if [[ "${DISTRO}" == "ubuntu-18.04" || "${DISTRO}" == "ubuntu-20.04" ]]; then
		sed -i 's/float_t/float/g' tensorflow/stream_executor/tpu/c_api_decl.h
	fi
	
	yes "" | ./configure || true

	#Build Tensorflow
	printf -- '\nBuilding TENSORFLOW..... \n'
	bazel --host_jvm_args="-Xms1024m" --host_jvm_args="-Xmx2048m" build  --define=tensorflow_mkldnn_contraction_kernel=0 --define tflite_with_xnnpack=false //tensorflow/tools/pip_package:build_pip_package
	
	#Build tensorflow_io_gcs_filesystem wheel
	printf -- '\nBuilding tensorflow_io_gcs_filesystem wheel..... \n'
	sudo pip install --upgrade pip
	cd $SOURCE_ROOT
	git clone https://github.com/tensorflow/io.git
	cd io/
	git checkout v0.23.1
	python3 setup.py -q bdist_wheel --project tensorflow_io_gcs_filesystem          
	cd dist
	sudo pip3 install ./tensorflow_io_gcs_filesystem-0.23.1-cp*-cp*-linux_s390x.whl
	
	#Build libclang wheel
	printf -- '\nBuilding libclang wheel..... \n'
	cd $SOURCE_ROOT
	sudo apt-get install -y cmake
	git clone https://github.com/llvm/llvm-project
	cd llvm-project
	git checkout llvmorg-9.0.1
	mkdir -p build
	cd build
	cmake ../llvm -DLLVM_ENABLE_PROJECTS=clang -DBUILD_SHARED_LIBS=OFF -DLLVM_ENABLE_TERMINFO=OFF -DLLVM_TARGETS_TO_BUILD=SystemZ -DCMAKE_BUILD_TYPE=MinSizeRel -DCMAKE_CXX_FLAGS_MINSIZEREL="-Os -DNDEBUG -static-libgcc -static-libstdc++ -s"
	make libclang -j$(nproc)
	cd $SOURCE_ROOT
	git clone https://github.com/sighingnow/libclang.git
	cd libclang
	cp $SOURCE_ROOT/llvm-project/build/lib/libclang.so.9 native/
	cp $SOURCE_ROOT/llvm-project/build/lib/libclang.so native/
	python3 setup.py -q bdist_wheel 
	cd dist
	sudo pip3 install libclang-*-py2.py3-none-any.whl

	#Build and install TensorFlow wheel
	printf -- '\nBuilding and installing Tensorflow wheel..... \n'
	cd $SOURCE_ROOT/tensorflow
	bazel-bin/tensorflow/tools/pip_package/build_pip_package /tmp/tensorflow_wheel

	if [[ "${DISTRO}" == "ubuntu-18.04" ]]; then
		sudo ln -s /usr/include/locale.h /usr/include/xlocale.h
	fi
	sudo pip3 install /tmp/tensorflow_wheel/tensorflow-2.9.1-cp*-linux_s390x.whl

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
		curl -o test_patch.diff $PATCH_URL/test_patch.diff
		git apply --ignore-whitespace test_patch.diff
		bazel --host_jvm_args="-Xms1024m" --host_jvm_args="-Xmx2048m" test --test_tag_filters=-gpu,-tpu,-benchmark-test,-v1only,-no_oss,-oss_serial -k --test_timeout 300,450,1200,3600 --build_tests_only --test_output=errors --define=tensorflow_mkldnn_contraction_kernel=0 --define tflite_with_xnnpack=false  -- //tensorflow/... -//tensorflow/compiler/... -//tensorflow/lite/... -//tensorflow/core/platform/cloud/...
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
	echo "  bash build_tensorflow.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests]"
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
	printf -- "To verify, run TensorFlow from command Line : \n"
	printf -- "  $ cd $SOURCE_ROOT  \n"
	printf -- "  $ python -c \"import tensorflow as tf; print(tf.__version__)\"  \n"
	printf -- "   2.9.1  \n"
	printf -- "Make sure JAVA_HOME is set and bazel binary is in your path in case of test case execution. \n"
	printf -- '*************************************************************************************************\n'
	printf -- '\n'
}

###############################################################################################################

logDetails
prepare #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-18.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo apt-get update
	sudo apt-get install libopenblas-dev wget git unzip zip python3-dev python3-pip openjdk-11-jdk pkg-config libhdf5-dev libssl-dev libblas-dev liblapack-dev gfortran curl -y |& tee -a "${LOG_FILE}"
	wget -q https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Python3/3.10.4/build_python3.sh
	sed -i 's/apt-get install/DEBIAN_FRONTEND=noninteractive apt-get install/g' build_python3.sh
	bash build_python3.sh -y
	sudo apt-get install -y gcc-8 g++-8
   	sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-8 60 --slave /usr/bin/g++ g++ /usr/bin/g++-8
   	sudo update-alternatives --auto gcc
	sudo update-alternatives --install /usr/local/bin/python python /usr/local/bin/python3 40
	sudo ldconfig
	sudo pip3 install --upgrade pip |& tee -a "${LOG_FILE}"
	sudo pip3 install --no-cache-dir numpy==1.22.3 wheel scipy portpicker protobuf==3.13.0 packaging |& tee -a "${LOG_FILE}"
	sudo pip3 install keras_preprocessing --no-deps |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

"ubuntu-20.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo apt-get update
	sudo DEBIAN_FRONTEND=noninteractive apt-get install wget git unzip zip python3-dev python3-pip openjdk-11-jdk pkg-config libhdf5-dev libssl-dev libblas-dev liblapack-dev gfortran curl -y |& tee -a "${LOG_FILE}"
	sudo ldconfig
	sudo pip3 install --upgrade pip |& tee -a "${LOG_FILE}"
	sudo pip3 install --no-cache-dir numpy==1.22.3 wheel scipy==1.6.3 portpicker protobuf==3.13.0 packaging |& tee -a "${LOG_FILE}"
	sudo pip3 install keras_preprocessing --no-deps |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;
	
"ubuntu-22.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo apt-get update
	sudo apt-get install wget git unzip zip python3-dev python3-pip openjdk-11-jdk pkg-config libhdf5-dev libssl-dev libblas-dev liblapack-dev gfortran gcc-9* g++-9* curl -y |& tee -a "${LOG_FILE}"
	sudo ldconfig
	sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-9 60 --slave /usr/bin/g++ g++ /usr/bin/g++-9
	sudo update-alternatives --auto gcc
	sudo pip3 install --upgrade pip |& tee -a "${LOG_FILE}"
	sudo pip3 install --no-cache-dir numpy==1.22.3 wheel scipy==1.7.2 portpicker protobuf==3.13.0 packaging |& tee -a "${LOG_FILE}"
	sudo pip3 install keras_preprocessing --no-deps |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
