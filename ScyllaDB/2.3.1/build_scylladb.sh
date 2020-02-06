#!/usr/bin/env bash
# © Copyright IBM Corporation 2019, 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ScyllaDB/2.3.1/build_scylladb.sh
# Execute build script: bash build_scylladb.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="scylladb"
PACKAGE_VERSION="2.3.1"
CURDIR="$(pwd)"

FORCE="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exsists
if [ ! -d "$CURDIR/logs" ]; then
	mkdir -p "$CURDIR/logs"
fi

#Set the Distro ID
if [ -f "/etc/os-release" ]; then
	source "/etc/os-release"
else
	cat /etc/redhat-release >>"${LOG_FILE}"
    export ID="rhel"
    export VERSION_ID="6.x"
    export PRETTY_NAME="Red Hat Enterprise Linux 6.x" 
fi

function checkPrequisites() {
	
	if [ -z "$TARGET" ]; then
		printf "Option -z must be specified with argument z13/z14 .\n"
		exit
	else
		if [ "$TARGET" = "z13" ] || [ "$TARGET" = "z14" ] ; then
			printf -- 'Building ScyllaDB on target %s .\n' "$TARGET" >>"$LOG_FILE"
		else
			printf -- 'Target is unsupported, please set the -z option with the correct argument for target as either z13 or z14 . \n'
			exit 
		fi
	fi

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
		printf -- "\nAs part of the installation , dependencies would be installed/upgraded.\n"
		while true; do
			read -r -p "Do you want to continue (y/n) ? :  " yn
			case $yn in
			[Yy]*)
				printf -- 'User responded with Yes. \n' >>"$LOG_FILE"
				break
				;;
			[Nn]*) exit ;;
			*) echo "Please provide confirmation to proceed." ;;
			esac
		done
	fi


}

function cleanup() {
	
	if [[ "$ID" == "rhel" ]]; 
    	then
		sudo rm -rf "$CURDIR/ninja/v1.7.2.zip"
		sudo rm -rf "$CURDIR/ragel/ragel-6.10.tar.gz"
		sudo rm -rf "$CURDIR/cryptopp/cryptopp565.zip"
		sudo rm -rf "$CURDIR/cmake/cmake-3.12.4.tar.gz"
		sudo rm -rf "$CURDIR/jsoncpp/1.7.7.tar.gz"
	else
		sudo rm -rf "$CURDIR/gcc/gcc-7.4.0.tar.xz"
	fi
		
	sudo rm -rf "$CURDIR/antlr3/3.5.2.tar.gz"
	sudo rm -rf "$CURDIR/boost/boost_1_68_0.tar.gz"
	sudo rm -rf "$CURDIR/thrift/thrift-0.9.3.tar.gz"
	sudo rm -rf "$CURDIR/yaml-cpp/yaml-cpp-0.6.2.tar.gz"	
	
	printf -- 'Cleaned up the artifacts.\n'
}

function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'
		
	#Install Ant
	printf -- 'Installing ant 1.10.6 \n'
	cd "$CURDIR"
	mkdir ant
	cd ant
	wget http://mirrors.estointernet.in/apache/ant/binaries/apache-ant-1.10.6-bin.tar.gz
	tar -xvf apache-ant-1.10.6-bin.tar.gz
	cd apache-ant-1.10.6
	export ANT_HOME=`pwd`
	cd bin
	export PATH=$PATH:`pwd`
	ant -version
		
	#Install antlr
	printf -- 'Installing antlr v3.5.2 \n'
	cd "$CURDIR"
	mkdir antlr3
	cd antlr3
	wget https://github.com/antlr/antlr3/archive/3.5.2.tar.gz
	tar -xzf 3.5.2.tar.gz
	cd antlr3-3.5.2
	sudo cp runtime/Cpp/include/antlr3* /usr/local/include/
	cd antlr-complete
	MAVEN_OPTS="-Xmx4G" mvn
	echo 'java -cp '"$(pwd)"'/target/antlr-complete-3.5.2.jar org.antlr.Tool $@' | sudo tee /usr/local/bin/antlr3
	sudo chmod +x /usr/local/bin/antlr3

	#Install Boost
	printf -- 'Installing Boost v1.68.0  \n'
	cd "$CURDIR"
	mkdir boost
	cd boost
	wget https://dl.bintray.com/boostorg/release/1.68.0/source/boost_1_68_0.tar.gz
	tar -xf boost_1_68_0.tar.gz
	cd boost_1_68_0
	
	sed -i 's/array\.hpp/array_wrapper.hpp/g' boost/numeric/ublas/matrix.hpp
	sed -i 's/array\.hpp/array_wrapper.hpp/g' boost/numeric/ublas/storage.hpp
	
	if [[ "$ID" == "rhel" ]]; 
    	then
		./bootstrap.sh
		sudo ./b2 toolset=gcc variant=release link=static runtime-link=static threading=multi cxxflags="-g -std=c++11" --prefix=/usr/local/ --without-python install
	else
		./bootstrap.sh
		sudo ./b2 toolset=gcc variant=release link=static runtime-link=static threading=multi cxxstd=14 --prefix=/usr/local/ --without-python install
	fi

	#Install Thrift
	printf -- 'Installing Thrift v0.9.3  \n'
	cd "$CURDIR"
	mkdir thrift
	cd thrift
	wget http://archive.apache.org/dist/thrift/0.9.3/thrift-0.9.3.tar.gz
	tar -xzf thrift-0.9.3.tar.gz
	cd thrift-0.9.3
	./configure --without-lua --without-go
	make -j 8
	sudo make install
	
	#Install yaml-cpp
	printf -- 'Installing yaml-cpp v0.6.2  \n'
	cd "$CURDIR"
	mkdir yaml-cpp
	cd yaml-cpp
	wget https://github.com/jbeder/yaml-cpp/archive/yaml-cpp-0.6.2.tar.gz
	tar -xzf yaml-cpp-0.6.2.tar.gz
	mkdir yaml-cpp-yaml-cpp-0.6.2/build
	cd yaml-cpp-yaml-cpp-0.6.2/build
	cmake ..
	make
	sudo make install

	#Build ScyllaDB
	printf -- 'Cloning the repository for v2.3.1 and initializing its submodules \n'
	cd "$CURDIR"
	git clone -b branch-2.3-s390x https://github.com/linux-on-ibm-z/scylla
	cd scylla
	git submodule update --init --recursive

	#Configure and compile ScyllaDB
	printf -- 'Starting the build for ScyllaDB \n'
	export PATH=/usr/local/bin:"$PATH"
	export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig/	
	./configure.py --mode=release --target="$TARGET" --debuginfo 1 --static --static-boost --static-thrift	
	ninja -j 8
	
	if [ "$?" -ne "0" ]; then
		printf -- 'Build  for ScyllaDB failed. Please check the error logs. \n'
		exit 1
	else	
		printf -- 'Build  for ScyllaDB completed successfully. \n'
	fi
	
	# Run Tests
    	runTest 
}

function runTest() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- "TEST Flag is set, continue with running test \n"  >> "$LOG_FILE"
		cd "$CURDIR/scylla"
        	./test.py --mode=release
        	printf -- "Test execution completed. \n" 
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
	echo "  build_scylladb.sh [-z z13/z14 select target for build] [-y install-without-confirmation] [-d debug] [-t test]"
	echo
}

while getopts "h?dyt?z:" opt; do
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
	z)
		export TARGET=$OPTARG	
		;;
	t) 
		TESTS="true"
		;;
	esac
done

function gettingStarted() {

	printf -- "*********************************************************************************************************\n"
	printf -- "\nUsage: \n\n"
	printf -- "*********************************************************************************************************\n"
	printf -- "  ScyllaDB installed successfully. \n"	
	printf -- "  For Ubuntu need to set the environment variables as below: \n      export PATH=/opt/gcc-7.4.0/bin:\"\$PATH\" \n      export LD_LIBRARY_PATH=/opt/gcc-7.4.0/lib64:\"\$LD_LIBRARY_PATH\" \n"	
	printf -- "  Run the following commands to use ScyllaDB :\n"
	printf -- "      $CURDIR/scylla/build/release/scylla --help \n"
	printf -- "  More information can be found here : https://github.com/scylladb/scylla/blob/master/HACKING.md \n"
	printf -- '\n'
}

###############################################################################################################

logDetails
checkPrequisites #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04" )
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for ScyllaDB from repository \n' |& tee -a "$LOG_FILE"
	sudo apt-get update >/dev/null
	sudo apt-get install -y openjdk-8-jdk python libgnutls-dev systemtap-sdt-dev lksctp-tools xfsprogs snappy libyaml-dev maven cmake openssl perl libc-ares-dev libevent-dev libmpfr-dev libmpcdec-dev xz-utils automake gcc git make texinfo wget unzip libtool libssl-dev curl libsystemd-dev libhwloc-dev libaio-dev libsctp-dev libsnappy-dev libpciaccess-dev libxml2-dev xfslibs-dev libgnutls28-dev libiconv-hook-dev mpi-default-dev libbz2-dev python-dev libxslt-dev libjsoncpp-dev cmake ragel python3 python3-pyparsing libprotobuf-dev protobuf-compiler liblz4-dev ninja-build libcrypto++-dev |& tee -a "$LOG_FILE"
	
	#Build GCC 7.4.0
	printf -- 'Building GCC 7.4.0 \n' |& tee -a "$LOG_FILE"	
	cd "$CURDIR"
	mkdir gcc
	cd gcc
	wget https://ftpmirror.gnu.org/gcc/gcc-7.4.0/gcc-7.4.0.tar.xz
	tar -xf gcc-7.4.0.tar.xz
	cd gcc-7.4.0
	./contrib/download_prerequisites
	mkdir objdir
	cd objdir
	../configure --prefix=/opt/gcc-7.4.0 --enable-languages=c,c++ --with-arch=zEC12 --with-long-double-128 --build=s390x-linux-gnu --host=s390x-linux-gnu --target=s390x-linux-gnu --enable-threads=posix --with-system-zlib --disable-multilib
	make -j 8
	sudo make install
	sudo ln -sf /opt/gcc-7.4.0/bin/gcc /usr/bin/gcc
	sudo ln -sf /opt/gcc-7.4.0/bin/g++ /usr/bin/g++
	export PATH=/opt/gcc-7.4.0/bin:"$PATH"
	export LD_LIBRARY_PATH=/opt/gcc-7.4.0/lib64:"$LD_LIBRARY_PATH"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"rhel-7.5")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for ScyllaDB from repository \n' |& tee -a "$LOG_FILE"
	sudo subscription-manager repos --enable=rhel-7-server-for-system-z-rhscl-rpms
	sudo yum install -y java-1.8.0-openjdk-devel python-devel gnutls-devel libaio-devel systemtap-sdt-devel lksctp-tools-devel xfsprogs-devel snappy-devel libyaml-devel maven cmake openssl-devel perl-devel libevent-devel libyaml-devel gmp-devel mpfr-devel libmpcdec xz-devel automake gcc git make texinfo protobuf-devel lz4-devel devtoolset-7 rh-python36 wget libatomic libatomic_ops-devel devtoolset-7-libatomic-devel |& tee -a "$LOG_FILE"
	
	source /opt/rh/rh-python36/enable
	source /opt/rh/devtoolset-7/enable
	
	printf -- 'gcc version \n' 
	gcc -v
	
	sudo ln -sf "$(which python)" /usr/bin/python3
		
	#Install Additional Dependencies
	cd "$CURDIR"
	
	#Pyparsing
	pip install --user pyparsing
	
	#Build Ninja
	printf -- 'Building ninja-1.7.2 \n' |& tee -a "$LOG_FILE"	
	mkdir ninja
	cd ninja
	wget https://github.com/ninja-build/ninja/archive/v1.7.2.zip
	unzip v1.7.2.zip
	cd ninja-1.7.2
	./configure.py --bootstrap
	sudo cp ninja /usr/local/bin
	
	#Build Ragel
	printf -- 'Building ragel-6.10 \n' |& tee -a "$LOG_FILE"	
	cd "$CURDIR"
	mkdir ragel
	cd ragel
	wget http://www.colm.net/files/ragel/ragel-6.10.tar.gz
	tar -xzf ragel-6.10.tar.gz
	cd ragel-6.10
	./configure
	make -j 8
	sudo make install
	
	#Build Crypto++
	printf -- 'Building cryptopp565 \n' |& tee -a "$LOG_FILE"	
	cd "$CURDIR"
	mkdir cryptopp
	cd cryptopp
	wget https://www.cryptopp.com/cryptopp565.zip
	unzip cryptopp565.zip
	CXXFLAGS="-std=c++11 -g -O2" make
	sudo make install
	
	#Build Cmake
	printf -- 'Building cmake v3.12.4 \n' |& tee -a "$LOG_FILE"	
	cd "$CURDIR"
	mkdir cmake
	cd cmake
	wget https://github.com/Kitware/CMake/releases/download/v3.12.4/cmake-3.12.4.tar.gz
	tar -xf cmake-3.12.4.tar.gz
	cd cmake-3.12.4
	./bootstrap
	make
	sudo make install
	
	#Build jsoncpp
	printf -- 'Building jsoncpp v1.7.7 \n' |& tee -a "$LOG_FILE"	
	cd "$CURDIR"
	mkdir jsoncpp
	cd jsoncpp
	wget https://github.com/open-source-parsers/jsoncpp/archive/1.7.7.tar.gz
	tar -xzf 1.7.7.tar.gz
	cd jsoncpp-1.7.7
	mkdir -p build/release
	cd build/release
	cmake ../..
	make -j 8
	sudo make install
	configureAndInstall |& tee -a "$LOG_FILE"
	;;
*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "$LOG_FILE"
