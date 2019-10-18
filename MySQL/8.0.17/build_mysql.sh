#!/bin/bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/MySQL/8.0.17/build_mysql.sh
# Execute build script: bash build_mysql.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="mysql"
PACKAGE_VERSION="8.0.17"
SOURCE_ROOT="$(pwd)"

FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
    mkdir -p "$SOURCE_ROOT/logs/"
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
    # Remove artifacts
	cd $SOURCE_ROOT
	rm -rf mysql-server
    	printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function build_gcc() {
	printf -- "Building GCC v5.4.0  \n"
	cd $SOURCE_ROOT
	wget https://ftp.gnu.org/gnu/gcc/gcc-5.4.0/gcc-5.4.0.tar.gz
	tar -xzf gcc-5.4.0.tar.gz
	cd gcc-5.4.0/
	./contrib/download_prerequisites
	mkdir build
	cd build
	../configure --enable-shared --disable-multilib --enable-threads=posix --with-system-zlib --enable-languages=c,c++
	make
	sudo make install
    sudo cp /usr/local/lib64/libstdc* /usr/lib64/
	export PATH=/usr/local/bin:$PATH
	export LD_LIBRARY_PATH=/usr/local/lib64:$LD_LIBRARY_PATH
	printf -- "GCC build completed.\n"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"
	
	#Download the MySQL source code from Github
	cd $SOURCE_ROOT
	git clone git://github.com/mysql/mysql-server.git
	cd mysql-server
	git checkout mysql-8.0.17
	mkdir build
	cd build

	#Configure, build and install MySQL
	
    if [[ "$ID" == "rhel" ]]; then
    		export PATH=/usr/local/bin:$PATH
		export LD_LIBRARY_PATH=/usr/local/lib64:$LD_LIBRARY_PATH
        	cmake .. -DDOWNLOAD_BOOST=1 -DWITH_BOOST=. -DWITH_SSL=system -DCMAKE_C_COMPILER=/usr/local/bin/gcc -DCMAKE_CXX_COMPILER=/usr/local/bin/g++
		make
		sudo make install -e LD_LIBRARY_PATH=/usr/local/lib64/
   else	
		cmake .. -DDOWNLOAD_BOOST=1 -DWITH_BOOST=. -DWITH_SSL=system
		make
		sudo make install    
    fi
    
	printf -- "MySQL build completed successfully. \n"
	
	# Run Tests
    runTest 
}

function runTest() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- "TEST Flag is set, continue with running test \n"  >> "$LOG_FILE"
		cd $SOURCE_ROOT/mysql-server/build
        make test 
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
    echo " build_mysql.sh  [-d debug] [-y install-without-confirmation] [-t install and run tests]"
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
    printf -- '\n********************************************************************************************************\n'
    printf -- "                       Getting Started                \n"
    printf -- " MySQL 8.x installed successfully.       \n"
    printf -- " Information regarding the post-installation steps can be found here : https://dev.mysql.com/doc/refman/5.7/en/postinstallation.html\n"
    printf -- " Starting MySQL Server: \n"
    printf -- " sudo useradd mysql   \n"
    printf -- " sudo groupadd  mysql \n"
    printf -- " cd /usr/local/mysql  \n"
    printf -- " sudo chown -R mysql . \n"
    printf -- " sudo chgrp -R mysql . \n"
    printf -- " nohup sudo bin/mysqld --initialize --user=mysql & \n"
    printf -- " sudo /usr/local/mysql/bin/mysqld_safe --user=mysql & \n"
    printf -- "           You have successfully started MySQL Server.\n"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04" | "ubuntu-19.04")
    	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    	printf -- "Installing dependencies... it may take some time.\n"
   	sudo apt-get update
    	sudo DEBIAN_FRONTEND=noninteractive apt-get install -y bison cmake gcc g++ git hostname libncurses-dev libssl-dev make openssl pkg-config |& tee -a "$LOG_FILE"
    	configureAndInstall |& tee -a "$LOG_FILE"
	;;
"rhel-6.x" | "rhel-7.5" | "rhel-7.6")
    	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    	printf -- "Installing dependencies... it may take some time.\n"
    	sudo yum install -y bison bzip2 gcc gcc-c++ git hostname ncurses-devel openssl openssl-devel pkgconfig tar wget zlib-devel |& tee -a "$LOG_FILE"
	
	#Build gcc v5.4.0
	build_gcc |& tee -a "$LOG_FILE"

	#Install cmake
	cd $SOURCE_ROOT
	wget https://cmake.org/files/v3.5/cmake-3.5.2.tar.gz
	tar -xzf cmake-3.5.2.tar.gz
	cd cmake-3.5.2
	./bootstrap
	make
	sudo make install -e LD_LIBRARY_PATH=/usr/local/lib64/
	
	#Build OpenSSL_1_0_2
	if [ "$VERSION_ID" == "6.x" ]; then
	
		cd $SOURCE_ROOT
		git clone git://github.com/openssl/openssl.git
		cd openssl
		git checkout OpenSSL_1_0_2l
		./config --prefix=/usr --openssldir=/usr/local/openssl shared
		make
		sudo make install
	fi
	configureAndInstall |& tee -a "$LOG_FILE"
	;;
"sles-12.4")
    	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    	printf -- "Installing dependencies... it may take some time.\n"
    	sudo zypper install -y cmake bison gcc gcc7 gcc-c++ gcc7-c++ git ncurses-devel openssl openssl-devel pkg-config gawk |& tee -a "$LOG_FILE"
    	sudo ln -sf /usr/bin/gcc-7 /usr/bin/gcc
        sudo ln -sf /usr/bin/g++-7 /usr/bin/g++
	    sudo ln -sf /usr/bin/gcc /usr/bin/cc
	    sudo ln -sf /usr/bin/g++-7 /usr/bin/c++
        configureAndInstall |& tee -a "$LOG_FILE"
    	;;
"sles-15" | "sles-15.1")
    	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    	printf -- "Installing dependencies... it may take some time.\n"
    	sudo zypper install -y cmake bison gcc gcc-c++ git hostname ncurses-devel openssl openssl-devel pkg-config gawk |& tee -a "$LOG_FILE"
    	configureAndInstall |& tee -a "$LOG_FILE"
    	;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
