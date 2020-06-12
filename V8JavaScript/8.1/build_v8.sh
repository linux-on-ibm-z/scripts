#!/bin/bash
# © Copyright IBM Corporation 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/V8JavaScript/8.1/build_v8.sh
# Execute build script: bash build_v8.sh    (provide -h for help)


set -e -o pipefail
PACKAGE_NAME="v8"
PACKAGE_VERSION="8.1.307.32"
CURDIR="$(pwd)"

FORCE="false"
TESTS="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
   mkdir -p "$CURDIR/logs/"
fi

source "/etc/os-release"

function prepare() {
    if  command -v "sudo" > /dev/null ;
    then
        printf -- 'Sudo : Yes\n' >> "$LOG_FILE"
    else
        printf -- 'Sudo : No \n' >> "$LOG_FILE"
        printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n';
    exit 1;
    fi;
   
    if [[ "$FORCE" == "true" ]] ;
    then
        printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
    else
        # Ask user for prerequisite installation
        printf -- "\nAs part of the installation , gn and depot will be installed, \n";
        while true; do
		    read -r -p "Do you want to continue (y/n) ? :  " yn
		    case $yn in
  	 		    [Yy]* ) printf -- 'User responded with Yes. \n' >> "$LOG_FILE"; 
	                    break;;
    		    [Nn]* ) exit;;
    		    *) 	echo "Please provide confirmation to proceed.";;
	 	    esac
        done
    fi	
}


function cleanup() {
    # Remove artifacts
    sudo apt-get -y remove git vim wget
    sudo rm -rf $CURDIR/ninja
    printf -- "Cleaned up the artifacts\n" >> "$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"
    # Install Depot_tools
    printf -- "\n\n Installing Depot_tools  \n"
    cd $CURDIR
    git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
    export PATH=$PATH:$CURDIR/depot_tools/
    export VPYTHON_BYPASS="manually managed python not supported by chrome operations"
    
    # Install gn
    printf -- 'Installing gn ..... \n'
    cd $CURDIR
    git clone https://gn.googlesource.com/gn
    cd gn 
    git checkout 8948350
    sed -i -e 's/-Wl,--icf=all//g' ./build/gen.py
    sed -i -e 's/-lpthread/-pthread/g' ./build/gen.py 
    python build/gen.py
    ninja -C out
    export PATH=$CURDIR/gn/out:$PATH        
    
    # Install V8
    cd $CURDIR
    fetch v8
    cd v8/
    git checkout $PACKAGE_VERSION
    gclient sync
    mkdir out/s390x.release
    gn gen out/s390x.release --args='is_component_build=false target_cpu="s390x" v8_target_cpu="s390x" use_goma=false goma_dir="None" v8_enable_backtrace=true v8_enable_disassembler=true v8_enable_object_print=true v8_enable_verify_heap=true'
    ninja -C $CURDIR/v8/out/s390x.release          
    printf -- 'V8 built successfully \n' 

    #Run tests
    runTest
    
    #cleanup
    cleanup

}

#Install GCC and Ninja
function installGCCAndNinja() {
    set +e
    printf -- "Installing GCC 7 \n"
    cd $CURDIR
    mkdir gcc
    cd gcc
    wget https://ftpmirror.gnu.org/gcc/gcc-7.3.0/gcc-7.3.0.tar.xz
    tar -xf gcc-7.3.0.tar.xz
    cd gcc-7.3.0
    ./contrib/download_prerequisites
    mkdir objdir
    cd objdir
    ../configure --prefix=/opt/gcc --enable-languages=c,c++ --with-arch=zEC12 --with-long-double-128 \
       --build=s390x-linux-gnu --host=s390x-linux-gnu --target=s390x-linux-gnu                  \
       --enable-threads=posix --with-system-zlib
    make -j 8
    sudo make install
    sudo ln -sf /opt/gcc/bin/gcc /usr/bin/gcc
    sudo ln -sf /opt/gcc/bin/g++ /usr/bin/g++
    sudo ln -sf /opt/gcc/bin/g++ /usr/bin/c++
    export PATH=/opt/gcc/bin:"$PATH"
    sudo ln -sf /opt/gcc/lib64/libstdc++.so.6.0.24 /usr/lib/s390x-linux-gnu/libstdc++.so.6
    
    # Install Ninja
    cd $CURDIR
    git clone git://github.com/ninja-build/ninja.git && cd ninja
    git checkout v1.8.2
    ./configure.py --bootstrap
    export PATH=/usr/local/bin:$PATH                              
    sudo ln -sf $CURDIR/ninja/ninja /usr/local/bin/ninja     
    ninja --version 
    
    #Install Binutils
    cd $CURDIR
    git clone git://sourceware.org/git/binutils-gdb.git
    cd binutils-gdb
    git checkout tags/binutils-2_30
    ./configure
    make
    sudo make install
    
    set -e
}

#Set ENV
function setENV() {
case "$DISTRO" in
    "ubuntu-16.04")
        cd $HOME
cat << EOF > setenv.sh
        #v8 ENV
        export CURDIR=$CURDIR
        export PATH=$PATH:$CURDIR/depot_tools/
        export VPYTHON_BYPASS="manually managed python not supported by chrome operations"
        export PATH=$CURDIR/gn/out:$PATH
	export PATH=/usr/local/bin:$PATH
	export PATH=/opt/gcc/bin:"$PATH"
	export LD_LIBRARY_PATH=/opt/gcc/lib64:"$LD_LIBRARY_PATH"
	export C_INCLUDE_PATH=/opt/gcc/lib/gcc/s390x-linux-gnu/7.3.0/include
	export CPLUS_INCLUDE_PATH=/opt/gcc/lib/gcc/s390x-linux-gnu/7.3.0/include
        export CC=/usr/bin/gcc
        export CXX=/usr/bin/g++
        export LOGDIR=$LOGDIR
EOF
        ;;
    "ubuntu-18.04")
        cd $HOME
cat << EOF > setenv.sh
        #v8 ENV
        export CURDIR=$CURDIR
        export PATH=$PATH:$CURDIR/depot_tools/
        export VPYTHON_BYPASS="manually managed python not supported by chrome operations"
        export PATH=$CURDIR/gn/out:$PATH
        export LOGDIR=$LOGDIR
EOF
        ;;
esac
}
#Tests function
function runTest() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- "TEST Flag is set, continue with running test \n"
		cd $CURDIR/v8
		tools/run-tests.py --time --progress=dots --outdir=out/s390x.release
		printf -- "Tests completed. \n" |& tee -a "$LOG_FILE"
	fi
	set -e
}
function logDetails() {
    printf -- '**************************** SYSTEM DETAILS *************************************************************\n' >"$LOG_FILE"
    if [ -f "/etc/os-release" ]; then
        cat "/etc/os-release" >> "$LOG_FILE"
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
    echo " install.sh  [-d debug] [-y install-without-confirmation] [-t install and run tests]"
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
    printf -- "\n*Getting Started * \n"
    printf -- "\n Running v8: \n"
    printf -- "\n source \$HOME/setenv.sh \n"
    printf -- "\n \$CURDIR/v8/out/s390x.release/d8  \n"
    printf -- "You have successfully started v8 shell.\n"
    printf -- '**********************************************************************************************************\n'
}
    
logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
    "ubuntu-16.04")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo apt-get update
        sudo -E DEBIAN_FRONTEND=noninteractive apt-get install -y python python3 curl pkg-config libnss3-dev libcups2-dev git vim libglib2.0-dev \
		libpango1.0-dev libgconf2-dev libgnome-keyring-dev libatk1.0-dev libgtk-3-dev wget clang g++ gcc ninja-build gcc-multilib \
		g++-multilib tzdata re2c bison flex texinfo |& tee -a "${LOG_FILE}"
        sudo dpkg-reconfigure --frontend noninteractive tzdata
        installGCCAndNinja |& tee -a "${LOG_FILE}"
        export CC=/usr/bin/gcc
        export CXX=/usr/bin/g++
        export PATH=/usr/local/bin:$PATH
        export LD_LIBRARY_PATH=/opt/gcc/lib64:"$LD_LIBRARY_PATH"
        export C_INCLUDE_PATH=/opt/gcc/lib/gcc/s390x-linux-gnu/7.3.0/include
        export CPLUS_INCLUDE_PATH=/opt/gcc/lib/gcc/s390x-linux-gnu/7.3.0/include
        configureAndInstall |& tee -a "${LOG_FILE}"
        setENV |& tee -a "${LOG_FILE}"
        ;;
    "ubuntu-18.04")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo apt-get update
        sudo -E DEBIAN_FRONTEND=noninteractive apt-get install -y python python3 curl pkg-config libnss3-dev libcups2-dev git vim libglib2.0-dev libpango1.0-dev \
        libgconf2-dev libgnome-keyring-dev libatk1.0-dev libgtk-3-dev wget clang g++ gcc ninja-build gcc-multilib g++-multilib tzdata |& tee -a "${LOG_FILE}"
        sudo dpkg-reconfigure --frontend noninteractive tzdata 
        configureAndInstall |& tee -a "${LOG_FILE}"
        setENV |& tee -a "${LOG_FILE}"
        ;;
    *)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
        exit 1
        ;;
esac
gettingStarted |& tee -a "${LOG_FILE}"
