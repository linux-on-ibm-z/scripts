#!/usr/bin/env bash
# © Copyright IBM Corporation 2020, 2021
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/RethinkDB/2.4.1/build_rethinkdb.sh
# Execute build script: bash build_rethinkdb.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="rethinkdb"
PACKAGE_VERSION="2.4.1"
CURDIR="$(pwd)"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/RethinkDB/2.4.1/patch"
FORCE="false"
TESTS="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exsists
if [ ! -d "$CURDIR/logs" ]; then
	mkdir -p "$CURDIR/logs"
fi

if [ -f "/etc/os-release" ]; then
	source "/etc/os-release"
fi

function checkPrequisites() {
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

function runTest() {
	set +e
	cd "${CURDIR}"
	if [[ "$TESTS" == "true" ]]; then
		printf -- 'Running test cases for RethinkDB\n'
		cd /"$CURDIR"/rethinkdb
		make -j 4 DEBUG=1
		# Running Unit Tests
		 printf -- "Running Unit tests\n" >> "$LOG_FILE"
		./test/run unit -j 4
		# Running Integration Tests
		 printf -- "Running Integration tests\n" >> "$LOG_FILE"
		./test/run -j 4
		printf -- '\n\n COMPLETED TEST EXECUTION !! \n' |& tee -a "$LOG_FILE"
	fi
	set -e
}


function runTest() {
        set +e
        cd "${CURDIR}"
        if [[ "$TESTS" == "true" ]]; then
                printf -- 'Running test cases for RethinkDB\n'
                cd /"$CURDIR"/rethinkdb
                make -j 4 DEBUG=1
                # Running Unit Tests
                 printf -- "Running Unit tests\n" >> "$LOG_FILE"
                ./test/run unit -j 4
                # Running Integration Tests
                 printf -- "Running Integration tests\n" >> "$LOG_FILE"
                ./test/run -j 4
                printf -- '\n\n COMPLETED TEST EXECUTION !! \n' |& tee -a "$LOG_FILE"
        fi
        set -e
}


function cleanup() {
	if [ -f ${PACKAGE_NAME}-${PACKAGE_VERSION}.tar.gz ]; then
		sudo rm ${PACKAGE_NAME}-${PACKAGE_VERSION}.tar.gz
	fi
}

function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'


	if [[ "$ID" == "ubuntu" ]]; then
        # Install GCC
		cd /"$CURDIR"/
        	mkdir gcc
		cd gcc
		wget https://ftp.gnu.org/gnu/gcc/gcc-5.4.0/gcc-5.4.0.tar.gz
		tar -xzf gcc-5.4.0.tar.gz
		cd gcc-5.4.0/
		./contrib/download_prerequisites
		mkdir objdir
		cd objdir
		../configure --prefix=/opt/gcc --enable-languages=c,c++ --with-arch=zEC12 --with-long-double-128 \
  	   --build=s390x-linux-gnu --host=s390x-linux-gnu --target=s390x-linux-gnu                  \
  	   --enable-threads=posix --with-system-zlib --disable-multilib
		make -j 8
		sudo make install
		sudo ln -sf /opt/gcc/bin/gcc /usr/bin/gcc
		sudo ln -sf /opt/gcc/bin/g++ /usr/bin/g++
		sudo ln -sf /opt/gcc/bin/g++ /usr/bin/c++
		export PATH=/opt/gcc/bin:"$PATH"
		export LD_LIBRARY_PATH=/opt/gcc/lib64:"$LD_LIBRARY_PATH"
		export C_INCLUDE_PATH=/opt/gcc/lib/gcc/s390x-linux-gnu/5.4.0/include
		export CPLUS_INCLUDE_PATH=/opt/gcc/lib/gcc/s390x-linux-gnu/5.4.0/include
		
		
		
		#Install Protobuf 2.6.0
		cd /"$CURDIR"/
		wget https://github.com/google/protobuf/releases/download/v2.6.0/protobuf-2.6.0.tar.gz
		tar zxvf protobuf-2.6.0.tar.gz
		cd protobuf-2.6.0
		sed -i '/elif defined(GOOGLE_PROTOBUF_ARCH_MIPS)/i #elif defined(GOOGLE_PROTOBUF_ARCH_S390)' src/google/protobuf/stubs/atomicops.h
		sed -i '/elif defined(GOOGLE_PROTOBUF_ARCH_MIPS)/i #include <google/protobuf/stubs/atomicops_internals_generic_gcc.h>' src/google/protobuf/stubs/atomicops.h
		sed -i '/#define GOOGLE_PROTOBUF_ARCH_64_BIT 1/a #elif defined(__s390x__)' src/google/protobuf/stubs/platform_macros.h
		sed -i '/#elif defined(__s390x__)/a #define GOOGLE_PROTOBUF_ARCH_S390 1' src/google/protobuf/stubs/platform_macros.h
		sed -i '/#define GOOGLE_PROTOBUF_ARCH_S390/a #define GOOGLE_PROTOBUF_ARCH_64_BIT 1' src/google/protobuf/stubs/platform_macros.h
		./configure
		make
		make check
		sudo make install
		export LD_LIBRARY_PATH=/usr/local/lib
		protoc --version
    fi

	if [[ "$DISTRO" == "sles-15.2" ]]; then
		#Install Python
		cd /"$CURDIR"/
		wget https://www.python.org/ftp/python/2.7.16/Python-2.7.16.tar.xz
		tar -xvf Python-2.7.16.tar.xz
		sudo ln -sfv /usr/include/ncurses/* /usr/include/
		cd Python-2.7.16
		./configure --prefix=/usr/local --exec-prefix=/usr/local
		make
		sudo make install
	fi
	
	if [[ "$DISTRO" = "rhel-8."* ]]; then
		#Install Node v6.17.0
		cd /"$CURDIR"/
		wget https://nodejs.org/dist/v6.17.0/node-v6.17.0-linux-s390x.tar.gz
		tar xvf node-v6.17.0-linux-s390x.tar.gz
		export PATH=$CURDIR/node-v6.17.0-linux-s390x/bin:$PATH
	fi
	
	
	if [[ "$DISTRO" = "sles-15."* ]]; then
		#Install Node v6.11.0
		cd /"$CURDIR"/
		wget https://nodejs.org/dist/v6.11.0/node-v6.11.0-linux-s390x.tar.gz
		tar xvf node-v6.11.0-linux-s390x.tar.gz
		export PATH=$CURDIR/node-v6.11.0-linux-s390x/bin:$PATH	
	fi


	# Download RethinkDB source code
	cd /"$CURDIR"/
	export VPYTHON_BYPASS="manually managed python not supported by chrome operations"
	git clone https://github.com/rethinkdb/rethinkdb
	cd rethinkdb
	git checkout v2.4.1
	
	# For RHEL
	if [[ "$ID" == "rhel" ]]; then
	curl -o v8_rhel.patch $PATCH_URL/v8_rhel.patch 
	patch mk/support/pkg/v8.sh v8_rhel.patch
	fi
	# For SLES
	if [[ "$ID" == "sles" ]]; then
	curl -o v8_sles.patch $PATCH_URL/v8_sles.patch
	patch mk/support/pkg/v8.sh v8_sles.patch
	fi
	# For Ubuntu
	if [[ "$ID" == "ubuntu" ]]; then
	curl -o v8_ubuntu.patch $PATCH_URL/v8_ubuntu.patch
	patch mk/support/pkg/v8.sh v8_ubuntu.patch
	fi
	# Configure and build RethinkDB 
	./configure --allow-fetch
	make -j 4
	
	#  Install RethinkDB
	sudo make install
	
	# Execute Test Cases
	if [[ "$TESTS" == "true" ]]; then
        runTest
	fi
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
	echo "bash build_rethinkdb.sh [-d debug]  [-y install-without-confirmation]  [-t build-with-tests]"
	echo
}

while getopts "h?ydt" opt; do
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

	printf -- "\n\nUsage: \n"
	printf -- "  RethinkDB installed successfully \n"
	printf -- "  Start RethinkDB server using : \n"
	printf -- "    rethinkdb --bind all \n"
	printf -- "  More information can be found here : https://rethinkdb.com/ \n"
	printf -- '\n'
}

###############################################################################################################

logDetails
checkPrequisites #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-18.04" | "ubuntu-20.04" | "ubuntu-20.10")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for RethinkDB from repository \n' |& tee -a "$LOG_FILE"
    sudo apt-get update -y >/dev/null
	sudo  sudo apt-get install -y clang build-essential python libcurl4-openssl-dev libboost-all-dev libncurses5-dev wget m4 libssl-dev git curl  |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"rhel-7.8" | "rhel-7.9")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for RethinkDB from repository \n' |& tee -a "$LOG_FILE"
	sudo  sudo yum groupinstall -y 'Development Tools' |& tee -a "$LOG_FILE"
	sudo   sudo yum install -y python3-devel openssl-devel libcurl-devel wget tar m4 git-core boost-static m4 gcc-c++  ncurses-devel which make ncurses-static zlib-devel zlib-static protobuf protobuf-compiler protobuf-devel |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;
	
"rhel-8.1" | "rhel-8.2" | "rhel-8.3")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for RethinkDB from repository \n' |& tee -a "$LOG_FILE"
	sudo yum groupinstall -y 'Development Tools' |& tee -a "$LOG_FILE"
	sudo yum install -y python3-devel python2 openssl-devel libcurl-devel wget tar m4 git-core boost gcc-c++  ncurses-devel which make ncurses zlib-devel zlib procps protobuf-devel protobuf-compiler |& tee -a "$LOG_FILE"
	sudo ln -s /usr/bin/python2 /usr/bin/python |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"sles-12.5")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for RethinkDB from repository \n' |& tee -a "$LOG_FILE"
	sudo zypper update -y |& tee -a "$LOG_FILE"
	sudo zypper install -y gcc gcc-c++ make libopenssl-devel zlib-devel wget tar patch curl unzip autoconf automake libtool python python-xml python-curses libicu-devel protobuf-devel=2.6.1-7.3.16 libprotobuf-lite9 libprotobuf9 boost-devel termcap curl libcurl-devel git awk  |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;
	
"sles-15.1")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for RethinkDB from repository \n' |& tee -a "$LOG_FILE"
	sudo zypper update -y |& tee -a "$LOG_FILE"
	sudo zypper install -y gcc gcc-c++ make libopenssl-devel zlib-devel wget tar patch curl unzip autoconf automake libtool python3-devel python python-xml python-curses libicu-devel protobuf-devel libprotobuf-lite15 libprotobuf15 boost-devel termcap curl libcurl-devel git bzip2 awk  |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;
	
"sles-15.2")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for RethinkDB from repository \n' |& tee -a "$LOG_FILE"
	sudo zypper update -y |& tee -a "$LOG_FILE"
	sudo zypper install -y  gcc gcc-c++ make libopenssl-devel zlib-devel wget tar patch curl unzip autoconf automake libtool  libicu-devel protobuf-devel libprotobuf-c-devel boost-devel termcap curl libcurl-devel git bzip2 awk gzip xz readline-devel sqlite3-devel tk-devel ncurses-devel gdbm-devel libdb-4_8-devel gdb gawk netcfg libbz2-devel glibc-locale |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "$LOG_FILE"
