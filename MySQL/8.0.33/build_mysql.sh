#!/bin/bash
# © Copyright IBM Corporation 2023
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/MySQL/8.0.33/build_mysql.sh
# Execute build script: bash build_mysql.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="mysql"
PACKAGE_VERSION="8.0.33"
SOURCE_ROOT="$(pwd)"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/MySQL/8.0.33/patch"

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
	rm -rf duktape-2.7.0  duktape-2.7.0.tar.xz openssl-1.1.1k.tar.gz openssl-1.1.1k cmake-3.20.3 cmake-3.20.3.tar.gz
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"
    #Build Duktape 
    cd $SOURCE_ROOT
    if [[ ${DISTRO} == rhel-7\.[8-9] ]] || [[ "$DISTRO" == "sles-12.5" ]]; then
        wget --no-check-certificate https://duktape.org/duktape-2.7.0.tar.xz
    else
        wget https://duktape.org/duktape-2.7.0.tar.xz
    fi
    tar xfJ duktape-2.7.0.tar.xz
    cd duktape-2.7.0
    sed -i '/\/* Durango (Xbox One)/i \/* s390x *\/\n#if defined(__s390x__)\n#define DUK_F_S390X \n#endif' src/duk_config.h
    sed -i '/#elif defined(DUK_F_SPARC32)/i #elif defined(DUK_F_S390X)\n\/* --- s390x --- *\/\n#define DUK_USE_ARCH_STRING "s390x"\n#define DUK_USE_BYTEORDER 3\n#undef DUK_USE_PACKED_TVAL\n#define DUK_F_PACKED_TVAL_PROVIDED'  src/duk_config.h 
    sed -i 's/duk_memcpy_unsafe((void \*) p, (const void \*) ins, (size_t) (ins_end - ins));/duk_memcpy_unsafe((void *) p, (const void *) ins, (size_t) (ins_end - ins) * 4);/' src-input/duk_api_bytecode.c 
    sed -i 's/p += (size_t) (ins_end - ins);/p += (size_t) (ins_end - ins) * 4;/' src-input/duk_api_bytecode.c
    python2 tools/configure.py --output-directory src-duktape
  
    #Download the MySQL source code from Github
    cd $SOURCE_ROOT
    git clone https://github.com/mysql/mysql-server.git
    cd mysql-server
    git checkout mysql-$PACKAGE_VERSION
    wget -O mt-asm.patch $PATCH_URL/mt-asm.patch
    git apply mt-asm.patch
    wget -O NdbHW.patch $PATCH_URL/NdbHW.patch
    git apply NdbHW.patch
    # Copy duktape files in to mysql source
    rm $SOURCE_ROOT/mysql-server/extra/duktape/duktape-2.7.0/src/*
    cp $SOURCE_ROOT/duktape-2.7.0/src-duktape/* $SOURCE_ROOT/mysql-server/extra/duktape/duktape-2.7.0/src/
    mkdir build
    cd build
  	#Configure, build and install MySQL
    if [[ "$DISTRO" =~ rhel-7\.[8-9] ]]; then
	    wget https://boostorg.jfrog.io/artifactory/main/release/1.77.0/source/boost_1_77_0.tar.bz2
        cmake .. -DDOWNLOAD_BOOST=0 -DWITH_BOOST=$SOURCE_ROOT/mysql-server/build -DWITH_SSL=system -DCMAKE_C_COMPILER=/opt/rh/devtoolset-11/root/bin/gcc -DCMAKE_CXX_COMPILER=/opt/rh/devtoolset-11/root/bin/g++	      	
    elif [[ "$DISTRO" == "sles-12.5" ]]; then
        cmake .. -DDOWNLOAD_BOOST=1 -DWITH_BOOST=. -DWITH_SSL=system -DCMAKE_C_COMPILER=/usr/bin/gcc -DCMAKE_CXX_COMPILER=/usr/bin/g++    
    else 
	cmake .. -DDOWNLOAD_BOOST=1 -DWITH_BOOST=. -DWITH_SSL=system
    fi
	
	make
    sudo make install
    
    printf -- "MySQL build completed successfully. \n"
	
  # Run Tests
    runTest 
  # Cleanup
    cleanup
}

function installOpenssl(){
      cd $SOURCE_ROOT
      wget https://www.openssl.org/source/openssl-1.1.1k.tar.gz --no-check-certificate
      tar -xzf openssl-1.1.1k.tar.gz
      cd openssl-1.1.1k
      ./config --prefix=/usr/local --openssldir=/usr/local
      make
      sudo make install

      sudo mkdir -p /usr/local/etc/openssl
      sudo wget https://curl.se/ca/cacert.pem --no-check-certificate -P /usr/local/etc/openssl
}

function buildCmake(){
    cd $SOURCE_ROOT
    wget https://github.com/Kitware/CMake/releases/download/v3.20.3/cmake-3.20.3.tar.gz --no-check-certificate
    tar -xvzf cmake-3.20.3.tar.gz
    cd cmake-3.20.3
    ./bootstrap
    make
    sudo make install
    cmake --version
}

function buildPython2(){
    cd $SOURCE_ROOT
    wget https://www.python.org/ftp/python/2.7.18/Python-2.7.18.tar.xz
    tar -xvf Python-2.7.18.tar.xz
	cd $SOURCE_ROOT/Python-2.7.18
	./configure --prefix=/usr/local --exec-prefix=/usr/local
	make
	sudo make install
	sudo ln -sf /usr/local/bin/python /usr/bin/python2
	python2 -V
}

function runTest() {
	set +e
	
	if [[ "$TESTS" == "true" ]]; then
		printf -- "TEST Flag is set, continue with running test \n"  >> "$LOG_FILE"
		cd $SOURCE_ROOT/mysql-server/build
		export LD_PRELOAD=$SOURCE_ROOT/mysql-server/build/library_output_directory/libprotobuf-lite.so.3.19.4:$LD_PRELOAD	
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
    echo "bash build_mysql.sh  [-d debug] [-y install-without-confirmation] [-t install and run tests]"
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
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"rhel-7.8" | "rhel-7.9")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y bison bzip2 gcc gcc-c++ git hostname ncurses-devel pkgconfig tar wget procps zlib-devel doxygen devtoolset-11-gcc devtoolset-11-gcc-c++ devtoolset-11-binutils net-tools |& tee -a "$LOG_FILE"
	sudo yum install -y xz python2 python-yaml |& tee -a "$LOG_FILE" # for Duktape
    export PATH=/opt/rh/devtoolset-11/root/usr/bin:/usr/local/bin:$PATH
	
    installOpenssl |& tee -a "$LOG_FILE"
    export LDFLAGS="-L/usr/local/lib/ -L/usr/local/lib64/"
    LD_LIBRARY_PATH=/usr/local/lib/:/usr/local/lib64/${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
    export LD_LIBRARY_PATH
    PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}
    export PKG_CONFIG_PATH
    LD_RUN_PATH=/usr/local/lib:/usr/local/lib64${LD_RUN_PATH:+:${LD_RUN_PATH}}
    export LD_RUN_PATH
    export CPPFLAGS="-I/usr/local/include/ -I/usr/local/include/openssl"
    export SSL_CERT_FILE=/usr/local/etc/openssl/cacert.pem
    sudo /usr/sbin/ldconfig /usr/local/lib64

    printf -- "export PATH=\"$PATH\"\n"  >> "${BUILD_ENV}"
    printf -- "export LDFLAGS=\"$LDFLAGS\"\n" >> "${BUILD_ENV}"
    printf -- "export LD_LIBRARY_PATH=\"$LD_LIBRARY_PATH\"\n" >> "${BUILD_ENV}"
    printf -- "export PKG_CONFIG_PATH=\"$PKG_CONFIG_PATH\"\n" >> "${BUILD_ENV}"
    printf -- "export LD_RUN_PATH=\"$LD_RUN_PATH\"\n" >> "${BUILD_ENV}"
    printf -- "export CPPFLAGS=\"$CPPFLAGS\"\n" >> "${BUILD_ENV}"
    printf -- "export SSL_CERT_FILE=\"$SSL_CERT_FILE\"\n" >> "${BUILD_ENV}"

    buildCmake |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;
"rhel-8.6" | "rhel-8.7" | "rhel-8.8")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
	sudo yum install -y bison bzip2 gcc gcc-c++ git hostname ncurses-devel openssl openssl-devel pkgconfig tar procps wget zlib-devel doxygen cmake diffutils rpcgen make libtirpc-devel libarchive gcc-toolset-12-gcc gcc-toolset-12-gcc-c++ gcc-toolset-12-binutils net-tools |& tee -a "$LOG_FILE"
    sudo yum install -y xz python2 python2-pyyaml |& tee -a "$LOG_FILE" # for Duktape
    source /opt/rh/gcc-toolset-12/enable

	configureAndInstall |& tee -a "$LOG_FILE"
    	;;
"rhel-9.0" | "rhel-9.1" | "rhel-9.2")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
	sudo yum install -y bison bzip2 bzip2-devel gcc gcc-c++ git xz xz-devel hostname ncurses ncurses-devel openssl procps openssl-devel pkgconfig tar wget zlib-devel doxygen cmake diffutils rpcgen make libtirpc-devel libarchive tk-devel gdb gdbm-devel sqlite-devel readline-devel libdb-devel libffi-devel libuuid-devel libnsl2-devel net-tools gcc-toolset-12-gcc gcc-toolset-12-gcc-c++ gcc-toolset-12-binutils |& tee -a "$LOG_FILE"
    source /opt/rh/gcc-toolset-12/enable
    
    buildPython2 |& tee -a "$LOG_FILE"
    curl https://bootstrap.pypa.io/pip/2.7/get-pip.py --output get-pip.py 
    sudo python2 get-pip.py |& tee -a "$LOG_FILE" 
    python2 -m pip install --upgrade pip setuptools --force-reinstall
    python2 -m pip install PyYAML |& tee -a "$LOG_FILE" # for Duktape

    configureAndInstall |& tee -a "$LOG_FILE"
    	;;
"sles-12.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
	sudo zypper install -y cmake bison git ncurses-devel pkg-config gawk procps doxygen tar gcc11 gcc11-c++ libtirpc-devel libnghttp2-devel |& tee -a "$LOG_FILE"
    sudo zypper install -y python python2-PyYAML |& tee -a "$LOG_FILE" # for Duktape
	sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-11 11
	sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-11 11
	sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-11 11
	sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-11 11
	sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
	sudo ln -sf /usr/bin/cpp-11 /usr/bin/cpp
	
    installOpenssl |& tee -a "$LOG_FILE"
    export LDFLAGS="-L/usr/local/lib/ -L/usr/local/lib64/"
    LD_LIBRARY_PATH=/usr/local/lib/:/usr/local/lib64/${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
    export LD_LIBRARY_PATH
    PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}
    export PKG_CONFIG_PATH
    LD_RUN_PATH=/usr/local/lib:/usr/local/lib64${LD_RUN_PATH:+:${LD_RUN_PATH}}
    export LD_RUN_PATH
    export CPPFLAGS="-I/usr/local/include/ -I/usr/local/include/openssl"
    export SSL_CERT_FILE=/usr/local/etc/openssl/cacert.pem
    sudo ldconfig /usr/local/lib64

    printf -- "export PATH=\"$PATH\"\n"  >> "${BUILD_ENV}"
    printf -- "export LDFLAGS=\"$LDFLAGS\"\n" >> "${BUILD_ENV}"
    printf -- "export LD_LIBRARY_PATH=\"$LD_LIBRARY_PATH\"\n" >> "${BUILD_ENV}"
    printf -- "export PKG_CONFIG_PATH=\"$PKG_CONFIG_PATH\"\n" >> "${BUILD_ENV}"
    printf -- "export LD_RUN_PATH=\"$LD_RUN_PATH\"\n" >> "${BUILD_ENV}"
    printf -- "export CPPFLAGS=\"$CPPFLAGS\"\n" >> "${BUILD_ENV}"
    printf -- "export SSL_CERT_FILE=\"$SSL_CERT_FILE\"\n" >> "${BUILD_ENV}"

	configureAndInstall |& tee -a "$LOG_FILE"
    	;;
"sles-15.4")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y cmake bison gcc11 gcc11-c++ git hostname ncurses-devel openssl procps openssl-devel pkg-config gawk doxygen libtirpc-devel rpcgen tar wget net-tools-deprecated |& tee -a "$LOG_FILE"
    sudo zypper install -y xz python python2-PyYAML |& tee -a "$LOG_FILE"  # for Duktape
	sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-11 11
	sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-11 11
	sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-11 11
	sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-11 11
	sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
	sudo ln -sf /usr/bin/cpp-11 /usr/bin/cpp
	
    configureAndInstall |& tee -a "$LOG_FILE"
    	;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
