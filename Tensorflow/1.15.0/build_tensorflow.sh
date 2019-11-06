#!/bin/bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Tensorflow/1.15.0/build_tensorflow.sh
# Execute build script: bash build_tensorflow.sh    (provide -h for help)
#

set -e  -o pipefail

PACKAGE_NAME="tensorflow"
PACKAGE_VERSION="1.15.0"
CURDIR="$(pwd)"
SOURCE_ROOT="$(pwd)"
USER="$(whoami)"


FORCE="false"
TESTS="false"
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
   mkdir -p "$CURDIR/logs/"
fi

# Need handling for RHEL 6.10 as it doesn't have os-release file
if [ -f "/etc/os-release" ]; then
	source "/etc/os-release"
else
	cat /etc/redhat-release >>"${LOG_FILE}"
	export ID="rhel"
	export VERSION_ID="6.x"
	export PRETTY_NAME="Red Hat Enterprise Linux 6.x"
fi

function prepare() {
	if command -v "sudo" >/dev/null; then
		printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
	else
		printf -- 'Sudo : No \n' >>"$LOG_FILE"
		printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n'
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
	rm -rf $SOURCE_ROOT/bazel/bazel-0.26.1-dist.zip
	
    printf -- "Cleaned up the artifacts\n" | tee -a "$LOG_FILE"

}
function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'

	# Build Bazel
	printf -- '\nBuilding bazel..... \n' 
	cd $SOURCE_ROOT
	mkdir bazel && cd bazel  
	wget https://github.com/bazelbuild/bazel/releases/download/0.26.1/bazel-0.26.1-dist.zip 
	unzip bazel-0.26.1-dist.zip  
	chmod -R +w .
	
	#Adding fixes and patches to the files
	sed -i "130s/-classpath/-J-Xms1g -J-Xmx1g -classpath/" scripts/bootstrap/compile.sh
	
	
	cd $SOURCE_ROOT/bazel
	env EXTRA_BAZEL_ARGS="--host_javabase=@local_jdk//:jdk" bash ./compile.sh
	export PATH=$PATH:$SOURCE_ROOT/bazel/output/ 
	echo $PATH
	
	# Build TensorFlow
	printf -- '\nBuilding Tensorflow..... \n' 
	cd $SOURCE_ROOT
	rm -rf tensorflow
	git clone https://github.com/linux-on-ibm-z/tensorflow.git
	cd tensorflow 
	git checkout v1.15.0-s390x
	
	export TF_NEED_GCP=0 
	export TF_NEED_HDFS=0 
	export TF_NEED_CUDA=0 
	export TF_NEED_MKL=0 
	export TF_NEED_OPENCL=0 
	export TF_NEED_VERBS=0 
	export TF_NEED_S3=0 
	export TF_NEED_KAFKA=0 
	export TF_NEED_AWS=0 
	export TF_ENABLE_XLA=0
	export PYTHON_BIN_PATH=`which python`
				      
	yes "" | ./configure || true
	
	printf -- '\nBuilding TENSORFLOW..... \n' 
	bazel --host_jvm_args="-Xms512m" --host_jvm_args="-Xmx1024m" build  --define=tensorflow_mkldnn_contraction_kernel=0 //tensorflow/tools/pip_package:build_pip_package
	
	#Build and install TensorFlow wheel
	printf -- '\nBuilding and installing Tensorflow wheel..... \n' 
	cd $SOURCE_ROOT/tensorflow
	bazel-bin/tensorflow/tools/pip_package/build_pip_package /tmp/tensorflow_wheel 
	sudo pip3 install /tmp/tensorflow_wheel/tensorflow-1.15.0-cp*-linux_s390x.whl 

	# Run Tests
	runTest

	#Cleanup
	cleanup

	printf -- "\n Installation of %s %s was sucessfull \n\n" $PACKAGE_NAME $PACKAGE_VERSION
}


function runTest() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- "TEST Flag is set , Continue with running test \n" 
		bazel --host_jvm_args="-Xms1024m" --host_jvm_args="-Xmx2048m" test --define=tensorflow_mkldnn_contraction_kernel=0 --host_javabase="@local_jdk//:jdk" --test_tag_filters=-gpu,-benchmark-test -k   --test_timeout 300,450,1200,3600 --build_tests_only --test_output=errors -- //tensorflow/... -//tensorflow/compiler/... -//tensorflow/lite/... -//tensorflow/core/platform/cloud/... -//tensorflow/java/...

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
	printf -- "  $ /usr/bin/python3  \n"
	printf -- "   >>> import tensorflow as tf  \n"
	printf -- "   >>> tf.enable_eager_execution()  \n"
	printf -- "   >>> tf.add(1, 2).numpy()  \n"
	printf -- "   3  \n"
	printf -- "   >>> hello = tf.constant('Hello, TensorFlow!')  \n"
	printf -- "   >>> hello.numpy()  \n"
	printf -- "   Hello, TensorFlow!'  \n"	
	printf -- "   >>> \n\n"
	printf -- 'Make sure JAVA_HOME is set and bazel binary is in your path in case of test case execution.'
	printf -- '*************************************************************************************************\n'
	printf -- '\n'
}

###############################################################################################################

logDetails
prepare #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04" )
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo apt-get update -y
	sudo apt-get install -y pkg-config zip g++ zlib1g-dev unzip git vim tar wget automake autoconf libtool make curl maven python3-pip python3-virtualenv python3-numpy swig python3-dev libcurl3-dev python3-mock python3-scipy bzip2 libhdf5-dev patch git patch libssl-dev |& tee -a "${LOG_FILE}"
	sudo apt-get install --no-install-recommends -y python3-sklearn   |& tee -a "${LOG_FILE}"
	sudo pip3 install numpy==1.16.2 future wheel backports.weakref portpicker futures==2.2.0 enum34 keras_preprocessing keras_applications h5py tensorflow_estimator==1.15.1 |& tee -a "${LOG_FILE}"

	#Install grpcio
	printf -- "\nInstalling grpcio. . . \n" 
	
	export GRPC_PYTHON_BUILD_SYSTEM_OPENSSL=True
	sudo -E pip3 install grpcio==1.24.3 |& tee -a "${LOG_FILE}"
	
	#Install OpenJDK11
	cd $SOURCE_ROOT
	wget https://github.com/AdoptOpenJDK/openjdk11-binaries/releases/download/jdk-11.0.5%2B10/OpenJDK11U-jdk_s390x_linux_hotspot_11.0.5_10.tar.gz
	tar -xvf OpenJDK11U-jdk_s390x_linux_hotspot_11.0.5_10.tar.gz
	export JAVA_HOME=$SOURCE_ROOT/jdk-11.0.5+10
	export PATH=$JAVA_HOME/bin:$PATH
	
	sudo ln -s /usr/bin/python3 /usr/bin/python
	
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

"ubuntu-18.04" | "ubuntu-19.04" )
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo apt-get update -y
	sudo apt-get install -y pkg-config zip g++ zlib1g-dev unzip git vim tar wget automake autoconf libtool make curl maven openjdk-11-jdk python3-pip python3-virtualenv python3-numpy swig python3-dev libcurl3-dev python3-mock python3-scipy bzip2 libhdf5-dev patch git patch libssl-dev |& tee -a "${LOG_FILE}"
	sudo apt-get install --no-install-recommends  -y python3-sklearn |& tee -a "${LOG_FILE}"
	sudo pip3 install numpy==1.16.2 future wheel backports.weakref portpicker futures enum34 keras_preprocessing keras_applications h5py tensorflow_estimator==1.15.1 |& tee -a "${LOG_FILE}"
	
	
	#Install grpcio
	printf -- "\nInstalling grpcio. . . \n" 
	export GRPC_PYTHON_BUILD_SYSTEM_OPENSSL=True
	sudo -E pip3 install grpcio |& tee -a "${LOG_FILE}"
	
	sudo ln -s /usr/bin/python3 /usr/bin/python
	
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
