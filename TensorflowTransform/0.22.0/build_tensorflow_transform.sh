#!/bin/bash
# © Copyright IBM Corporation 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/TensorflowTransform/0.22.0/build_tensorflow_transform.sh
# Execute build script: bash build_tensorflow_transform.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="tensorflow_transform"
PACKAGE_VERSION="0.22.0"
CURDIR="$(pwd)"

PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/TensorflowTransform/0.22.0/patch/tft.patch"
TENSORFLOW_INSTALL_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Tensorflow/2.2.0/build_tensorflow.sh"

ARROW_VERSION="0.16.0"

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
		printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n'
		exit 1
	fi

	if [[ "$FORCE" == "true" ]]; then
		printf -- 'Force attribute provided hence continuing with install without confirmation message' |& tee -a "$LOG_FILE"
	else
		# Ask user for prerequisite installation
		printf -- "\n\nAs part of the installation , Apache Arrow "${ARROW_VERSION}" will be installed, \n"
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
	if [ -f "$CURDIR/cmake-3.16.3.tar.gz" ]; then
		rm "$CURDIR/cmake-3.16.3.tar.gz"
	fi

	if [ -f "$CURDIR/build_tensorflow.sh" ]; then
		rm "$CURDIR/build_tensorflow.sh"
	fi

	if [ -f "$CURDIR/transform/tft.patch" ]; then
		rm "$CURDIR/transform/tft.patch"
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
	bash build_tensorflow.sh -y


	export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x
	export PATH=$JAVA_HOME/bin:$PATH:$CURDIR/bazel/output/
	

	printf -- 'TensorFlow installed successfully \n'

	# Build CMake 3.16.3 for Ubuntu 18.04
	if [[ "$DISTRO" == "ubuntu-18.04" ]]; then
		printf -- 'Installing CMake 3.16.3 ... \n'
		
		# Check if CMake directory exists
		cd "${CURDIR}"
		if [ -d "$CURDIR/cmake-3.16.3" ]; then
			rm -rf $CURDIR/cmake-3.16.3
		fi

		wget -O cmake-3.16.3.tar.gz https://cmake.org/files/v3.16/cmake-3.16.3.tar.gz
		tar -xzf cmake-3.16.3.tar.gz
		cd cmake-3.16.3
		./bootstrap --prefix=/usr
		make
		sudo make install

		printf -- 'CMake installed successfully \n'
	fi

	# Install Apache Arrow
	printf -- 'Installing Apache Arrow... \n'

	export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
	export ARROW_BUILD_TYPE='release'
	export PYARROW_WITH_PARQUET=1

	# Check if Arrow directory exists
	cd "${CURDIR}"
	if [ -d "$CURDIR/arrow" ]; then
		rm -rf $CURDIR/arrow
	fi

	printf -- 'Installing C++ library... \n'

	git clone https://github.com/apache/arrow.git
	cd arrow
	git checkout apache-arrow-0.16.0
	mkdir -p cpp/release
	cd cpp/release
	cmake -DCMAKE_INSTALL_PREFIX=/usr/local \
	  -DCMAKE_INSTALL_LIBDIR=lib \
	  -DARROW_PARQUET=ON \
	  -DARROW_PYTHON=ON \
	  -DCMAKE_BUILD_TYPE=Release \
	  ..
	make -j4
	sudo make install

	printf -- 'C++ library installed successfully \n'

	printf -- 'Installing pyarrow... \n'

	if [[ "$DISTRO" == "ubuntu-18.04" ]]; then
		sudo pip3 uninstall -y enum34 || printf -- 'enum34 already uninstalled \n'
	fi
	sudo pip3 install 'avro-python3==1.9.1' 'setuptools>=41.0.0' 'Cython>=0.29' 'httplib2<0.18.0,>=0.8' 'tensorflow-serving-api==2.2.0'
	cd $CURDIR/arrow/python
	python setup.py build_ext --build-type=$ARROW_BUILD_TYPE --bundle-arrow-cpp bdist_wheel
	sudo pip3 install dist/*.whl

	printf -- 'pyarrow installed successfully \n'
	printf -- 'Apache Arrow installed successfully \n'

	printf -- 'Installing tfx-bsl... \n'

	# Check if tfx-bsl directory exists
	cd "${CURDIR}"
	if [ -d "$CURDIR/tfx-bsl" ]; then
		rm -rf $CURDIR/tfx-bsl
	fi

	git clone https://github.com/tensorflow/tfx-bsl.git
	cd tfx-bsl
	git checkout v0.22.1
	./configure.sh
	bazel run -c opt tfx_bsl:build_pip_package
	sudo pip3 install dist/*.whl

	printf -- 'tfx-bsl installed successfully \n'

	printf -- 'Building TensorFlow Transform... \n'

	# Check if transform directory exists
	cd "${CURDIR}"
	if [ -d "$CURDIR/transform" ]; then
		rm -rf $CURDIR/transform
	fi

	git clone https://github.com/tensorflow/transform.git
	cd transform
	git checkout v0.22.0

	printf -- 'Applying patches... \n'

	curl -o tft.patch $PATCH_URL
	git apply --ignore-whitespace tft.patch

	printf -- 'Installing Transform package... \n'

	sudo python3 setup.py install

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

		cd "${CURDIR}/transform"
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
	printf -- "  $ cd $CURDIR  \n"
	printf -- "  $ /usr/bin/python3  \n"
	printf -- "   >>> import tensorflow as tf  \n"
	printf -- "   >>> import tensorflow_transform as tft  \n"
	printf -- "   >>> tft.version.__version__  \n"
	printf -- "   '0.22.0'  \n"
	printf -- "   >>> \n\n"
	printf -- '*************************************************************************************************\n'
	printf -- '\n'
}

###############################################################################################################


logDetails
prepare # Check Prequisites


DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-18.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	sudo apt-get update
	sudo apt-get install -y wget build-essential libffi-dev libjemalloc-dev libboost-dev libboost-filesystem-dev libboost-system-dev libboost-regex-dev autoconf flex bison |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"ubuntu-20.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	sudo apt-get update
	sudo apt-get install -y wget build-essential cmake libffi-dev libjemalloc-dev libboost-dev libboost-filesystem-dev libboost-system-dev libboost-regex-dev autoconf flex bison |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "$LOG_FILE"
