#!/bin/bash
# © Copyright IBM Corporation 2022                                                                                                                                                                                                                                                                                                                                                                                                                                           .
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Falco/0.32.2/build_falco.sh
# Execute build script: bash build_falco.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="falco"
PACKAGE_VERSION="0.32.2"

export SOURCE_ROOT="$(pwd)"

TEST_USER="$(whoami)"
FORCE="false"
FORCE_LUAJIT="false"
TESTS="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
SLES_KERNEL_VERSION=$(uname -r | sed 's/-default//g')

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
    mkdir -p "$SOURCE_ROOT/logs/"
fi

if [ -f "/etc/os-release" ]; then
    source "/etc/os-release"
fi

DISTRO="$ID-$VERSION_ID"

function prepare()
{

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
            *) echo "Please provide correct input to proceed." ;;
            esac
        done
    fi
}

function cleanup() {

    if [[ "${ID}" == "rhel" ]] || [[ "${ID}" == "sles" ]]; then
        rm -rf "${SOURCE_ROOT}/cmake-3.7.2.tar.gz"
    fi
    if [[ "${DISTRO}" == "sles-12.5" ]]; then
        sudo mv "/usr/src/linux-$SLES_KERNEL_VERSION/Makefile.back" "/usr/src/linux-$SLES_KERNEL_VERSION/Makefile"
    fi

    printf -- '\nCleaned up the artifacts\n'
}

function configureAndInstall() {
    printf -- '\nConfiguration and Installation started \n'

    #Installing dependencies
    printf -- 'User responded with Yes. \n'
    printf -- 'Building dependencies\n'

    cd "${SOURCE_ROOT}"
    if [[ "${DISTRO}" != "ubuntu-22.04" ]] || [[ "${DISTRO}" == "sles-12.5" ]] || [[ "${DISTRO}" == "rhel-7."* ]]; then
        printf -- 'Building Go v1.17.12\n'
	cd $SOURCE_ROOT
	wget -q https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Go/1.18.4/build_go.sh 
	bash build_go.sh -y -v 1.17.12 
	export GOPATH=$SOURCE_ROOT 
	export PATH=$GOPATH/bin:$PATH
	go version
	printf -- 'Go installed successfully\n'
    fi
    
    if [[ "${ID}" == "ubuntu" ]] || [[ "${ID}" == "sles" ]]; then
        printf -- 'Building Git v2.27.0\n'
	cd $SOURCE_ROOT/
	wget https://mirrors.edge.kernel.org/pub/software/scm/git/git-2.27.0.tar.gz
	tar -xvf git-2.27.0.tar.gz
	cd git-2.27.0/
	make prefix=/usr/local all
	sudo make prefix=/usr/local install
	export PATH=$PWD:$PATH
	git --version
	printf -- 'Git installed successfully\n'
    fi


    if [[ "${DISTRO}" == "rhel-8."* ]] || [[ "${DISTRO}" == "sles-15."* ]]; then
	printf -- 'Building Protobuf v3.17.3\n'
        cd $SOURCE_ROOT
        git clone https://github.com/protocolbuffers/protobuf.git
        cd protobuf
        git checkout v3.17.3
        git submodule update --init --recursive
        ./autogen.sh
        ./configure
        make -j$(nproc)
        sudo make install
        if [[ "${DISTRO}" == "sles-15."* ]]; then
            sudo ldconfig
        fi
        if [[ ${DISTRO} =~ rhel-8\.[4-6] ]]; then
            LD_LIBRARY_PATH=/usr/local/lib/:/usr/local/lib64/${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
            export LD_LIBRARY_PATH
        fi
        if [[ "${ID}" == "rhel" ]]; then
            sudo ln -s /usr/local/lib/libprotobuf.so.28 /usr/lib64/libprotobuf.so.28
        fi
        protoc --version
        printf -- 'Protobuf installed successfully\n'

        printf -- 'Building gRPC v1.44.0\n'
        cd $SOURCE_ROOT
        git clone --recurse-submodules -b v1.44.0 --depth 1 --shallow-submodules https://github.com/grpc/grpc
        cd grpc 
        mkdir build && cd build
        cmake -DgRPC_INSTALL=true -DgRPC_BUILD_TESTS=OFF \
	      -DgRPC_SSL_PROVIDER=OpenSSL -DgRPC_PROTOBUF_PROVIDER=package \
              -DCMAKE_INSTALL_PREFIX=/usr/local ..
        make -j$(nproc)
        sudo make install
        printf -- 'gRPC installed successfully\n'
    fi
	
    if [[ "${ID}" == "rhel" ]]; then
        if [[ "${VERSION_ID}" == "7.8" ]] || [[ "${VERSION_ID}" == "7.9" ]]; then
            printf -- 'Building GCC 9.4.0\n'
            cd $SOURCE_ROOT
            GCC_VERSION=9.4.0
            wget https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.gz --no-check-certificate
            tar xzf gcc-${GCC_VERSION}.tar.gz
            mkdir obj.gcc-${GCC_VERSION}
            cd gcc-${GCC_VERSION}
            ./contrib/download_prerequisites
            cd ../obj.gcc-${GCC_VERSION}
            ../gcc-${GCC_VERSION}/configure --disable-multilib --enable-languages=c,c++
            make -j $(nproc)
            sudo make install
            export PATH=/usr/local/bin:$PATH
            export CC=/usr/local/bin/gcc
            export CXX=/usr/local/bin/g++
            export LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64:$LD_LIBRARY_PATH	
            printf -- 'gcc installed successfully\n'
        fi
    fi
	
    cd "${SOURCE_ROOT}"
    if [[ "${ID}" == "rhel" ]]; then
        if [[ "${VERSION_ID}" == "7.8" ]] || [[ "${VERSION_ID}" == "7.9" ]]; then
            printf -- 'Building cmake 3.16.3\n'
            cd $SOURCE_ROOT
            wget https://github.com/Kitware/CMake/releases/download/v3.16.3/cmake-3.16.3.tar.gz
            tar -xf cmake-3.16.3.tar.gz
            cd cmake-3.16.3
            ./bootstrap -- -DCMAKE_BUILD_TYPE:STRING=Release
            # In case of error: "/lib64/libstdc++.so.6: version `GLIBCXX_3.4.26' not found" do following 'ln'
            sudo ln -sf /usr/local/lib64/libstdc++.so.6.0.28 /lib64/libstdc++.so.6
            make
            sudo make install
            sudo ln -sf /usr/local/bin/cmake /usr/bin/cmake	
            printf -- 'cmake installed successfully\n'
        fi
    fi

    printf -- '\nDownloading Falco source. \n'
	
    cd $SOURCE_ROOT
    git clone https://github.com/falcosecurity/falco.git
    cd falco
    git checkout ${PACKAGE_VERSION}

    #Applying patch to plugins.cmake file
    wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Falco/0.32.2/patch/plugins.cmake.patch
    git apply plugins.cmake.patch

    printf -- '\nStarting Falco build. \n'
    mkdir -p $SOURCE_ROOT/falco/build
    cd $SOURCE_ROOT/falco/build
    if [[ "${DISTRO}" == "sles-12.5" ]]; then
        sudo cp "/usr/src/linux-$SLES_KERNEL_VERSION/Makefile" "/usr/src/linux-$SLES_KERNEL_VERSION/Makefile.back"
        sudo sed -i 's/-fdump-ipa-clones//g' /usr/src/linux-"$SLES_KERNEL_VERSION"/Makefile
    fi

    if [[ "${DISTRO}" == "ubuntu-18.04" ]] || [[ "${DISTRO}" == "sles-12.5" ]]; then
        CMAKE_FLAGS="-DUSE_BUNDLED_DEPS=ON -DUSE_BUNDLED_CURL=OFF"
    elif [[ "${DISTRO}" == "rhel-7."* ]]; then
        CMAKE_FLAGS="-DUSE_BUNDLED_DEPS=ON"
    else
        CMAKE_FLAGS="-DFALCO_ETC_DIR=/etc/falco -DUSE_BUNDLED_OPENSSL=On -DUSE_BUNDLED_PROTOBUF=Off -DUSE_BUNDLED_GRPC=Off -DUSE_BUNDLED_DEPS=On -DCMAKE_BUILD_TYPE=Release"
    fi
    cmake $CMAKE_FLAGS ../
    
    #Upgrading b64 version
    cd $SOURCE_ROOT/falco/build/falcosecurity-libs-repo/falcosecurity-libs-prefix/src/falcosecurity-libs/cmake/modules
    sed -i 's/v1.4.1/v2.0.0.1/g' b64.cmake
    sed -i 's/0fa93fb9c4fb72cac5a21533e6d611521e4326f42c19cc23f8ded814b0eca071/ce8e578a953a591bd4a6f157eec310b9a4c2e6f10ade2fdda6ae6bafaf798b98/g' b64.cmake
    
    if [[ "${DISTRO}" == "rhel-7."* ]] || [[ "${DISTRO}" == "rhel-8."* ]] || [[ "${DISTRO}" == "sles-15."* ]] || [[ "${DISTRO}" == "ubuntu-20.04" ]] || [[ "${DISTRO}" == "ubuntu-22.04" ]]; then
        sed -i 's+https://github.com/curl/curl/releases/download/curl-7_84_0/curl-7.84.0.tar.bz2+https://github.com/curl/curl/releases/download/curl-7_85_0/curl-7.85.0.tar.bz2+g' curl.cmake
        sed -i 's/702fb26e73190a3bd77071aa146f507b9817cc4dfce218d2ab87f00cd3bc059d/21a7e83628ee96164ac2b36ff6bf99d467c7b0b621c1f7e317d8f0d96011539c/g' curl.cmake
    fi
	
    if [[ "${DISTRO}" == "ubuntu-18.04" ]] || [[ "${DISTRO}" == "sles-12.5" ]] || [[ "${DISTRO}" == "rhel-7."* ]]; then
        sed -i '/libabsl_low_level_hash.a/d' grpc.cmake
        sed -i '/libabsl_cord_internal.a/d' grpc.cmake
        sed -i '/libabsl_cordz_*/d' grpc.cmake
        sed -i '/libabsl_random_internal_*/d' grpc.cmake
        sed -i '/libabsl_random_seed_gen_exception.a/d' grpc.cmake
        sed -i 's/profiling\/libabsl_exponential_biased.a/base\/libabsl_exponential_biased.a/g' grpc.cmake
        sed -i 's/v1.44.0/v1.38.1/g' grpc.cmake
        sed -i 's/v1.44.0/v1.38.1/g' $SOURCE_ROOT/falco/build/grpc-prefix/tmp/grpc-gitclone.cmake
    fi

    cd $SOURCE_ROOT/falco/build/
    make

    if [[ "${ID}" == "rhel" ]] || [[ "${ID}" == "ubuntu" ]]; then
        make package
    fi

    sudo make install
    printf -- '\nFalco build completed successfully. \n'

    printf -- '\nInserting Falco kernel module. \n'
    sudo rmmod falco || true

    cd $SOURCE_ROOT/falco/build
    sudo insmod driver/falco.ko
    printf -- '\nInserted Falco kernel module successfully. \n'

    # Run Tests
    runTest
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
    echo "  bash build_falco.sh  [-d debug] [-y install-without-confirmation] [-t run-tests-after-build] "
    echo
}

function runTest() {
    set +e

    if [[ "$TESTS" == "true" ]]; then
        cd $SOURCE_ROOT/falco/build
        make tests
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
            printf -- "%s is detected in the system. Skipping build and running tests .\n" "$PACKAGE_NAME" | tee -a "$LOG_FILE"
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
    printf -- '\nRun falco --help to see all available options to run falco'
    printf -- '\nFor more information on Falco please visit https://falco.org/docs/ \n\n'
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare

case "$DISTRO" in

"ubuntu-18.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

    sudo apt-get update
    sudo apt-get install -y curl kmod git curl cmake build-essential pkg-config autoconf libz-dev libtool libexpat1-dev libelf-dev libcurl4-openssl-dev libssl-dev libyaml-cpp-dev patch wget rpm linux-headers-$(uname -r) gettext gcc libyaml-cpp-dev libjq-dev libncurses-dev curl libc-ares-dev

    configureAndInstall | tee -a "$LOG_FILE"
    ;;

"ubuntu-20.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
  
    sudo apt-get update
    sudo apt-get install -y git cmake build-essential pkg-config autoconf wget curl patch libtool libelf-dev libz-dev libssl-dev libcurl4-gnutls-dev libexpat1-dev gettext gcc protobuf-compiler-grpc libncurses-dev curl libc-ares-dev libprotobuf-dev protobuf-compiler libjq-dev libgrpc++-dev protobuf-compiler-grpc libyaml-cpp-dev rpm linux-headers-$(uname -r) kmod

    configureAndInstall | tee -a "$LOG_FILE"
    ;;
	
"ubuntu-22.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

    sudo apt-get update
    sudo apt-get install -y git cmake build-essential pkg-config autoconf wget curl patch libtool libelf-dev libz-dev libssl-dev libcurl4-gnutls-dev libexpat1-dev gettext gcc protobuf-compiler-grpc libncurses-dev curl libc-ares-dev libprotobuf-dev protobuf-compiler libjq-dev libgrpc++-dev protobuf-compiler-grpc libyaml-cpp-dev golang-1.18 rpm linux-headers-$(uname -r)
    export PATH=$PATH:/usr/lib/go-1.18/bin
    go version

    configureAndInstall | tee -a "$LOG_FILE"
    ;;

"rhel-7.8" | "rhel-7.9")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

    sudo yum install -y  gcc gcc-c++ git libarchive wget bzip2 perl-FindBin make cmake autoconf automake pkg-config patch libtool elfutils-libelf-devel diffutils which libcurl-devel openssl-devel rpm-build kernel-devel-$(uname -r) kmod
	
    configureAndInstall | tee -a "$LOG_FILE"
    ;;

"rhel-8.4" | "rhel-8.6")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

    sudo yum install -y gcc gcc-c++ git make cmake autoconf automake pkg-config patch ncurses-devel libtool elfutils-libelf-devel diffutils which createrepo libarchive wget curl glibc-static libstdc++-static openssl-devel go rpm-build kmod kernel-devel-$(uname -r)
    go version
    
    configureAndInstall | tee -a "$LOG_FILE"
    ;;

"sles-12.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

    sudo zypper install -y gcc9 gcc9-c++ git-core cmake ncurses-devel libopenssl-devel libcurl-devel protobuf-devel patch which automake autoconf libtool libelf-devel "kernel-default-devel=${SLES_KERNEL_VERSION}" libexpat-devel tcl gettext-tools openssl libcurl-devel tar curl libjq-devel
	
    sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-9 50
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-4.8 20
    sudo update-alternatives --config gcc
    sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-9 50
    sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-4.8 20
    sudo update-alternatives --config g++
    export CC=$(which gcc)
    export CXX=$(which g++)

    configureAndInstall | tee -a "$LOG_FILE"
    ;;

"sles-15.3" | "sles-15.4")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

    sudo zypper install -y gcc gcc-c++ git-core cmake libjq-devel ncurses-devel yaml-cpp-devel libopenssl-devel libcurl-devel c-ares-devel protobuf-devel patch which automake autoconf libtool libelf-devel libexpat-devel tcl-devel gettext-tools tar curl vim wget pkg-config curl glibc-devel-static go1.18 "kernel-default-devel=${SLES_KERNEL_VERSION}" kmod
    go version
	
    configureAndInstall | tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" | tee -a "$LOG_FILE"
    exit 1
    ;;
esac

printSummary | tee -a "$LOG_FILE"
