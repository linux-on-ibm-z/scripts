#!/bin/bash
# © Copyright IBM Corporation 2020, 2021.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Sysdig/0.26.7/build_sysdig.sh
# Execute build script: bash build_sysdig.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="sysdig"
PACKAGE_VERSION="0.26.7"

export SOURCE_ROOT="$(pwd)"

TEST_USER="$(whoami)"
FORCE="false"
TESTS="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
    mkdir -p "$SOURCE_ROOT/logs/"
fi

source "/etc/os-release"

function prepare() {

    if [[ "$FORCE" == "true" ]]; then
        printf -- 'Force attribute provided hence continuing with install without confirmation message\n' | tee -a "$LOG_FILE"
    else
        printf -- 'As part of the installation, dependencies would be installed/upgraded.\n'
        while true; do
            read -r -p "Do you want to continue (y/n) ? :  " yn
            case $yn in
            [Yy]*)

                break
                ;;
            [Nn]*) exit ;;
            *) echo "Please provide Correct input to proceed." ;;
            esac
        done
    fi
}

function cleanup() {

    rm -rfv "$SOURCE_ROOT"/*.patch
    printf -- '\nCleaned up the artifacts\n'
}

function configureAndInstall() {
    printf -- '\nConfiguration and Installation started \n'

    #Installing dependencies
    printf -- 'User responded with Yes. \n'

    cd "${SOURCE_ROOT}"
    git clone https://github.com/draios/sysdig.git
    cd sysdig
    git checkout "$PACKAGE_VERSION"
    mkdir build
    cd $SOURCE_ROOT/sysdig/build
       
    if [[ $ID == *"ubuntu"* ]]; then
               
                if [ ! -d "/lib/modules/$(uname -r)" ]; then
                sudo mkdir -p /lib/modules/$(uname -r)
                version=version=$(sudo apt-cache policy linux-headers-$(uname -r) | grep Candidate | awk '{print $2}' |  sed 's/...$//')
                echo linux-headers-$version-generic
                sudo ln -s /usr/src/linux-headers-$version-generic /lib/modules/$(uname -r)/build
                fi
    fi
    
    if [[ $ID == *"sles"* ]]; then
            if [ ! -d "/lib/modules/$(uname -r)" ]; then
            sudo mkdir -p /lib/modules/$(uname -r)
            trim=$(sudo zypper info kernel-default-devel | grep Version | cut -d ':' -f 2-)
            version=$(echo $trim | sed 's/..$//')
            echo linux-$version-obj
            sudo ln -s /usr/src/linux-$version-obj/s390x/default /lib/modules/$(uname -r)/build
            fi
    fi

    if [[ $ID == *"rhel"* ]]; then
            if [ ! -d "/lib/modules/$(uname -r)" ]; then
            sudo mkdir -p /lib/modules/$(uname -r)
            version=$(sudo yum info kernel-devel-$(uname -r) | grep Version | awk '{print $3}')
            release=$(sudo yum info kernel-devel-$(uname -r) | grep Release | awk '{print $3}')
            echo $version-$release.s390x
            sudo ln -s /usr/src/kernels/$version-$release.s390x /lib/modules/$(uname -r)/build
             fi
    fi
    cmake .. -DSYSDIG_VERSION=$PACKAGE_VERSION
    make
    sudo make install
    
    cd $SOURCE_ROOT/sysdig/build/driver
    sudo insmod sysdig-probe.ko
    
    runTest
}

function build_gcc() {
    cd $SOURCE_ROOT
    wget http://ftp.gnu.org/gnu/gcc/gcc-5.5.0/gcc-5.5.0.tar.gz
    tar -xzf gcc-5.5.0.tar.gz && cd gcc-5.5.0
    ./contrib/download_prerequisites
    mkdir build && cd build/
    ../configure --disable-multilib --disable-checking --enable-languages=c,c++ --enable-multiarch --enable-shared --enable-threads=posix --without-included-gettext --with-system-zlib --prefix=/usr/local
    make && sudo make install

    if [[ $ID == "rhel-7.8" ]]; then
        sudo mv /usr/bin/gcc /usr/bin/gcc-4.8.5
        sudo mv /usr/bin/g++ /usr/bin/g++-4.8.5
        sudo mv /usr/bin/c++ /usr/bin/c++-4.8.5
        sudo rm /usr/bin/cc
        fi

    sudo update-alternatives --install /usr/bin/cc cc /usr/local/bin/gcc 40
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/local/bin/gcc 40
    sudo update-alternatives --install /usr/bin/g++ g++ /usr/local/bin/g++ 40
    sudo update-alternatives --install /usr/bin/c++ c++ /usr/local/bin/c++ 40
    export CC=/usr/local/bin/s390x-ibm-linux-gnu-gcc
    export CXX=/usr/local/bin/s390x-ibm-linux-gnu-g++
    sudo /sbin/ldconfig
    gcc --version

    sudo cp /usr/local/lib64/libstdc* /usr/lib64/
    export PATH=/usr/local/bin:$PATH
    export LD_LIBRARY_PATH=/usr/local/lib64:$LD_LIBRARY_PATH

    printf -- "GCC build completed.\n"
}

function logDetails() {
    printf -- 'SYSTEM DETAILS\n' >"$LOG_FILE"
    if [ -f "/etc/os-release" ]; then
        cat "/etc/os-release" >>"$LOG_FILE"
    fi

    cat /proc/version >>"$LOG_FILE"
    printf -- "\nDetected %s \n" "$PRETTY_NAME"
    printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" | tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
    echo
    echo "Usage: "
    echo "  install.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests]"
    echo
}

function runTest() {
    set +e

    if [[ "$TESTS" == "true" ]]; then
    # Run tests
    #Check if directory exists
        if [ -d "$SOURCE_ROOT/sysdig" ]; then
        cd $SOURCE_ROOT/sysdig/build/
        make run-unit-tests
        fi
    fi

    set -e

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
        if command -v "$PACKAGE_NAME" >/dev/null; then
            printf -- "%s is detected with version %s .\n" "$PACKAGE_NAME" "$PACKAGE_VERSION" | tee -a "$LOG_FILE"
            TESTS="true"
            runTest
            exit 0

        else

            TESTS="true"
        fi

        ;;
    esac
done

function printSummary() {
    printf -- '\n********************************************************************************************************\n'
    printf -- "\n* Getting Started * \n"
    printf -- '\nRun sysdig --help to see all available options to run sysdig'
    printf -- '\nFor more information on sysdig, please visit https://docs.sysdig.com/?lang=en \n\n'
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-18.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
    sudo apt-get update
    sudo apt-get install -y  wget tar gcc git cmake g++ lua5.1 lua5.1-dev linux-headers-$(uname -r) patch libelf-dev automake kmod
    configureAndInstall | tee -a "$LOG_FILE"
    ;;

"rhel-7.8")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
    sudo yum install -y wget tar gcc git cmake gcc-c++ make lua-devel.s390x bzip2 bzip2-devel kernel-devel-$(uname -r) hostname patch elfutils-libelf-devel.s390x elfutils-libelf-devel-static.s390x glibc-static libstdc++-static automake
    
    #Build gcc v5.5.0
    build_gcc |& tee -a "$LOG_FILE"
    
    configureAndInstall | tee -a "$LOG_FILE"
    ;;
    
"rhel-8.1")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
    sudo yum install -y wget tar git gcc cmake gcc-c++ make lua-devel.s390x bzip2 bzip2-devel kernel-devel-$(uname -r) hostname patch elfutils-libelf-devel.s390x elfutils-libelf-devel-static.s390x glibc-static libstdc++-static automake
    configureAndInstall | tee -a "$LOG_FILE"
    ;;

"sles-12.5" )
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
    sudo zypper install -y which gawk wget tar git gcc cmake gcc-c++ make bzip2 libz1 zlib-devel lua51 lua51-devel kernel-default-devel patch libelf-devel glibc-devel-static automake
    
    #Build gcc v5.5.0
    build_gcc |& tee -a "$LOG_FILE"
    
    installed_kernel=$(uname -r | cut -d '-' -f1,2 )
    kernel=$(sudo zypper se -s kernel-default-devel | grep $installed_kernel )
    if [[ ! $kernel ]]; then
        trim=$(sudo zypper info kernel-default-devel | grep Version | cut -d ':' -f 2-)
        sudo zypper install -y --oldpackage kernel-default-devel=$trim
    fi
    configureAndInstall | tee -a "$LOG_FILE"
    ;;
    
 "sles-15.1")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
    sudo zypper install -y which gawk wget tar git gcc cmake make gcc-c++ lua51 lua51-devel kernel-default-devel patch libelf-devel glibc-devel-static automake
    installed_kernel=$(uname -r | cut -d '-' -f1,2 )
    kernel=$(sudo zypper se -s kernel-default-devel | grep $installed_kernel )
    if [[ ! $kernel ]]; then
        trim=$(sudo zypper info kernel-default-devel | grep Version | cut -d ':' -f 2-)
        sudo zypper install -y --oldpackage kernel-default-devel=$trim
    fi
    configureAndInstall | tee -a "$LOG_FILE"
    ;;

*)
    printf -- "%s not supported \n" "$DISTRO" | tee -a "$LOG_FILE"
    exit 1
    ;;
esac

printSummary | tee -a "$LOG_FILE"
