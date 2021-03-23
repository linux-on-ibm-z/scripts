#!/bin/bash
# © Copyright IBM Corporation 2021
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/MySQL/8.0.23/build_mysql.sh
# Execute build script: bash build_mysql.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="mysql"
PACKAGE_VERSION="8.0.23"
SOURCE_ROOT="$(pwd)"

FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
BUILD_ENV="$HOME/setenv.sh"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
    mkdir -p "$SOURCE_ROOT/logs/"
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
	printf -- "Building GCC v7.3.0  \n"
	cd $SOURCE_ROOT
	wget ftp://gcc.gnu.org/pub/gcc/releases/gcc-7.3.0/gcc-7.3.0.tar.gz
	tar -xzf gcc-7.3.0.tar.gz
	cd gcc-7.3.0/

	./contrib/download_prerequisites
	mkdir build
	cd build
	../configure --enable-shared --disable-multilib --enable-threads=posix --with-system-zlib --enable-languages=c,c++
	make
	sudo make install
  sudo cp /usr/local/lib64/libstdc* /usr/lib64/
	export PATH=/usr/local/bin:$PATH
	export LD_LIBRARY_PATH=/usr/local/lib64:$LD_LIBRARY_PATH
	# Add env variables to setenv file
	printf -- "export PATH=/usr/local/bin:$PATH\n" >> "$BUILD_ENV"
	printf -- "export LD_LIBRARY_PATH=/usr/local/lib64:$LD_LIBRARY_PATH\n" >> "$BUILD_ENV"
	printf -- "GCC build completed.\n"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"
	
	#Download the MySQL source code from Github
	cd $SOURCE_ROOT
	git clone git://github.com/mysql/mysql-server.git
	cd mysql-server
	git checkout mysql-$PACKAGE_VERSION
	mkdir build
	cd build

	#Configure, build and install MySQL
	echo "BUILDING DBOOST"
    	if [[ "$ID" == "rhel" ]]; then
	        export PATH=/usr/local/bin:$PATH
		      export LD_LIBRARY_PATH=/usr/local/lib64:$LD_LIBRARY_PATH
		      if [[ "$DISTRO" == "rhel-8.1" || "$DISTRO" == "rhel-8.2" || "$DISTRO" == "rhel-8.3" ]]; then
			      cmake .. -DDOWNLOAD_BOOST=1 -DWITH_BOOST=. -DWITH_SSL=system -DCMAKE_C_COMPILER=/usr/bin/gcc -DCMAKE_CXX_COMPILER=/usr/bin/g++	
			      make
			      sudo make install
		      else
			      export PATH=/usr/local/bin:$PATH
			      export LD_LIBRARY_PATH=/usr/local/lib64:$LD_LIBRARY_PATH
			      wget https://dl.bintray.com/boostorg/release/1.73.0/source/boost_1_73_0.tar.gz
            cmake .. -DDOWNLOAD_BOOST=1 -DWITH_BOOST=. -DWITH_SSL=system -DCMAKE_C_COMPILER=/usr/local/bin/gcc -DCMAKE_CXX_COMPILER=/usr/local/bin/g++
			      make
			      sudo make install -e LD_LIBRARY_PATH=/usr/local/lib64/
		       fi	
   	else	
		cmake .. -DDOWNLOAD_BOOST=1 -DWITH_BOOST=. -DWITH_SSL=system
		make
		sudo make install    
    fi
    
	printf -- "MySQL build completed successfully. \n"
	
  # Run Tests
    runTest 
  # Cleanup
    cleanup
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
    printf -- " Information regarding the post-installation steps can be found here : https://dev.mysql.com/doc/refman/8.0/en/postinstallation.html\n"  
    printf -- " Starting MySQL Server: \n"
    printf -- " sudo useradd mysql   \n"
    printf -- " sudo groupadd mysql \n"
    printf -- " cd /usr/local/mysql  \n"
    printf -- " sudo mkdir mysql-files \n"
    printf -- " sudo chown mysql:mysql mysql-files \n"
    printf -- " sudo chmod 750 mysql-files \n"
    printf -- " sudo bin/mysqld --initialize --user=mysql \n"
    printf -- " sudo bin/mysqld_safe --user=mysql & \n"
    printf -- "           You have successfully started MySQL Server.\n"
    printf -- " Note: In case of RHEL (7.x), Env variables can be set by running command source $HOME/setenv.sh \n"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"ubuntu-18.04")
    	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    	printf -- "Installing dependencies... it may take some time.\n"
   		sudo apt-get update
		sudo apt-get install -y bison cmake gcc g++ git hostname libncurses-dev libssl-dev make openssl pkg-config doxygen |& tee -a "$LOG_FILE"
		configureAndInstall |& tee -a "$LOG_FILE"

	;;
"rhel-7.8" | "rhel-7.9")
    	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    	printf -- "Installing dependencies... it may take some time.\n"
    	sudo yum install -y bison bzip2 gcc gcc-c++ git hostname ncurses-devel openssl openssl-devel pkgconfig tar wget zlib-devel doxygen |& tee -a "$LOG_FILE"
	
	#Build gcc v7.3.0
	build_gcc |& tee -a "$LOG_FILE"

	#Install cmake
	cd $SOURCE_ROOT
	wget https://cmake.org/files/v3.5/cmake-3.5.2.tar.gz
	tar -xzf cmake-3.5.2.tar.gz
	cd cmake-3.5.2
	./bootstrap
	make
	sudo make install -e LD_LIBRARY_PATH=/usr/local/lib64/
	
	configureAndInstall |& tee -a "$LOG_FILE"
	;;
"rhel-8.1" | "rhel-8.2" | "rhel-8.3")
    	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    	printf -- "Installing dependencies... it may take some time.\n"
    	sudo yum install -y bison bzip2 gcc gcc-c++ git hostname ncurses-devel openssl openssl-devel pkgconfig tar wget zlib-devel doxygen cmake diffutils rpcgen make libtirpc-devel |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;
"sles-12.5")
    	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    	printf -- "Installing dependencies... it may take some time.\n"
	sudo zypper install -y cmake bison gcc gcc-c++ git ncurses-devel openssl openssl-devel pkg-config gawk doxygen tar
    	
	#Build gcc v7.3.0
	build_gcc |& tee -a "$LOG_FILE"

	#Create symbolic link to gcc v5.4.0
	sudo ln -sf /usr/local/bin/gcc /usr/bin/gcc
	sudo ln -sf /usr/local/bin/g++ /usr/bin/g++
	sudo ln -sf /usr/bin/gcc /usr/bin/cc
	sudo ln -sf /usr/local/bin/g++ /usr/bin/c++

	configureAndInstall |& tee -a "$LOG_FILE"
    	;;
"sles-15.2")
    	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    	printf -- "Installing dependencies... it may take some time.\n"
    	sudo zypper install -y cmake bison gcc gcc-c++ git hostname ncurses-devel openssl openssl-devel pkg-config gawk doxygen|& tee -a "$LOG_FILE"
    	configureAndInstall |& tee -a "$LOG_FILE"
    	;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
