#!/bin/bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Tensorflow/1.12.0/build_tensorflow.sh
# Execute build script: bash build_tensorflow.sh    (provide -h for help)
#

set -e  -o pipefail

PACKAGE_NAME="tensorflow"
PACKAGE_VERSION="1.12.0"
CURDIR="$(pwd)"
SOURCE_ROOT="$(pwd)"
USER="$(whoami)"


#PATCH_URL
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Tensorflow/1.12.0/patch"


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
	rm -rf $SOURCE_ROOT/bazel/bazel-0.15.0-dist.zip
	
    printf -- "Cleaned up the artifacts\n" | tee -a "$LOG_FILE"

}
function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'

	#Install grpcio
	printf -- "\nInstalling grpcio. . . \n" 
	export GRPC_PYTHON_BUILD_SYSTEM_OPENSSL=True
    	sudo -E pip install grpcio 

	# Build Bazel
	printf -- '\nBuilding bazel..... \n' 
	cd $SOURCE_ROOT
	mkdir bazel && cd bazel  
	wget https://github.com/bazelbuild/bazel/releases/download/0.15.0/bazel-0.15.0-dist.zip 
	unzip bazel-0.15.0-dist.zip  
	chmod -R +w .
	
	#Adding fixes and patches to the files
	fileChanges
	
	
	cd $SOURCE_ROOT/bazel
	bash ./compile.sh 
	export PATH=$PATH:$SOURCE_ROOT/bazel/output/ 
	echo $PATH
	
	# Build TensorFlow
	printf -- '\nBuilding Tensorflow..... \n' 
	cd $SOURCE_ROOT
	rm -rf tensorflow
	git clone https://github.com/linux-on-ibm-z/tensorflow.git 
	cd tensorflow 
	git checkout v1.12.0-s390x 
	
	export TF_NEED_IGNITE=0
	export TF_NEED_GCP=0 
	export TF_NEED_CUDA=0 
	export TF_ENABLE_XLA=0 
	export TF_NEED_GDR=0 
	export TF_NEED_VERBS=0 
	export TF_NEED_MPI=0 
	export TF_NEED_OPENCL_SYCL=0 
	export TF_SET_ANDROID_WORKSPACE=0 
	export TF_NEED_GCP=0 
	export TF_CUDA_CLANG=0 
	export TF_NEED_ROCM=0 
	export PYTHON_BIN_PATH=`which python2`
				      
	yes "" | ./configure || true
	
	printf -- '\nBuilding TENSORFLOW..... \n' 
	bazel --host_jvm_args="-Xms512m" --host_jvm_args="-Xmx1024m" build -c opt //tensorflow/tools/pip_package:build_pip_package 
	
	
	#Build and install TensorFlow wheel
	printf -- '\nBuilding and installing Tensorflow wheel..... \n' 
	cd $SOURCE_ROOT/tensorflow
	bazel-bin/tensorflow/tools/pip_package/build_pip_package /tmp/tensorflow_wheel 
	sudo pip install /tmp/tensorflow_wheel/tensorflow-1.12.0-cp27-cp27mu-linux_s390x.whl 
	

	# Run Tests
	runTest

	#Cleanup
	cleanup

	printf -- "\n Installation of %s %s was sucessfull \n\n" $PACKAGE_NAME $PACKAGE_VERSION
}

function fileChanges(){

	printf -- "\nDownloading patch for compile.sh . . . \n" 
	curl  -o "patch_compile.diff" $PATCH_URL/patch_compile.diff 
	printf -- "\nApplying patch to compile.sh . . . \n"  
	patch $SOURCE_ROOT/bazel/scripts/bootstrap/compile.sh patch_compile.diff 
	rm -rf patch_compile.diff

}

function runTest() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- "TEST Flag is set , Continue with running test \n" 
		bazel --host_jvm_args="-Xms512m" --host_jvm_args="-Xmx1024m" test --test_timeout 300,450,1200,3600 --build_tests_only -- //tensorflow/... -//tensorflow/compiler/... -//tensorflow/core/platform/cloud/... -//tensorflow/contrib/lite/... -//tensorflow/contrib/cloud/... -//tensorflow/java/...  

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
	printf -- "  $ python  \n"
	printf -- "   >>> import tensorflow as tf  \n"
	printf -- "   >>> hello = tf.constant('Hello, TensorFlow!')  \n"
	printf -- "   >>> sess = tf.Session()  \n"
	printf -- "   >>> print(sess.run(hello))  \n"
	printf -- "   	  Hello, TensorFlow!  \n"
	printf -- "   >>> a = tf.constant(10)  \n"
	printf -- "   >>> b = tf.constant(32)  \n"
	printf -- "   >>> print(sess.run(a + b))  \n"
	printf -- "   	  42  \n"	
	printf -- "   >>> \n\n"
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
	sudo apt-get install -y pkg-config zip g++ zlib1g-dev unzip git vim tar wget automake autoconf libtool make curl maven openjdk-8-jdk python-pip python-virtualenv swig python-dev libcurl3-dev python-mock python-scipy bzip2 glibc* python-sklearn python-numpy patch libhdf5-dev libssl-dev golang |& tee -a "${LOG_FILE}"
	sudo pip install wheel backports.weakref portpicker futures grpc enum34 |& tee -a "${LOG_FILE}"
	sudo pip install keras_applications==1.0.5 --no-deps |& tee -a "${LOG_FILE}"
	sudo pip install keras_preprocessing==1.0.3 --no-deps |& tee -a "${LOG_FILE}"
	sudo pip install numpy==1.13.3 keras |& tee -a "${LOG_FILE}"
	
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

"ubuntu-18.04" )
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo apt-get update -y
	sudo apt-get install -y pkg-config zip g++ zlib1g-dev unzip git vim tar wget automake autoconf libtool make curl maven openjdk-8-jdk python-pip python-virtualenv python-numpy swig python-dev libcurl3-dev python-mock python-scipy bzip2 glibc* python-sklearn patch libhdf5-dev libssl-dev golang |& tee -a "${LOG_FILE}"
	sudo pip install wheel backports.weakref portpicker futures grpc enum34 |& tee -a "${LOG_FILE}"
	sudo pip install keras_applications==1.0.5 --no-deps |& tee -a "${LOG_FILE}"
	sudo pip install keras_preprocessing==1.0.3 --no-deps |& tee -a "${LOG_FILE}"

    configureAndInstall |& tee -a "${LOG_FILE}"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
