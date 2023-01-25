#!/bin/bash
# © Copyright IBM Corporation 2023.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Couchbase/7.1.1/build_couchbase.sh
# Execute build script: bash build_couchbase.sh  (provide -h for help)
#

set -e -o pipefail

PACKAGE_NAME="couchbase"
PACKAGE_VERSION="7.1.1"
DATE_AND_TIME="$(date +"%F-%T")"
SOURCE_ROOT=$(pwd)
LOG_FILE="$SOURCE_ROOT/${PACKAGE_NAME}-${PACKAGE_VERSION}-${DATE_AND_TIME}.log"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Couchbase/7.1.1/patch"
TESTS="false"
HAS_PREFIX="false"
CB_PREFIX="$SOURCE_ROOT/couchbase/install"

if [ -f "/etc/os-release" ]; then
  source "/etc/os-release"
else
  printf -- "/etc/os-release file not found. Platform is not supported.\n"
  exit 1
fi

DISTRO=$(echo $(echo $ID | sed 's/sles/suse/g')$VERSION_ID | sed -E -e 's/(rhel[[:digit:]]|suse[[:digit:]]{2}).*/\1/g')

PRESERVE_ENVARS=~/.bash_profile

CACHE_DIRECTORY=~/.cbdepscache

mkdir -p $SOURCE_ROOT/patch
mkdir -p $CACHE_DIRECTORY

function prepareUB20() {
    printf -- "Installing dependencies from repository.\n"
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive TZ=America/Toronto apt-get install -y \
        autoconf automake autotools-dev binutils-dev bison ccache cmake curl flex \
        git libssl-dev ncurses-dev ninja-build python python3 \
        python3-httplib2 python3-six pkg-config re2c texinfo tzdata unzip wget \
        g++-10 gcc-10 gcc-10-multilib g++-10-multilib libglib2.0-dev libtool

    sudo ln -sf /usr/bin/python2 /usr/bin/python
    echo "export LANG=en_US.UTF-8" >> $PRESERVE_ENVARS
    echo "export CC=gcc" >> $PRESERVE_ENVARS
    echo "export CXX=g++" >> $PRESERVE_ENVARS

    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-9 9
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-10 10
    sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-10 10
}

function prepareUB18() {
    printf -- "Installing dependencies from repository.\n"
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive TZ=America/Toronto apt-get install -y \
        autoconf automake autotools-dev binutils-dev bison ccache cmake curl flex \
        git libssl-dev ncurses-dev ninja-build python python3 \
        python3-httplib2 python3-six pkg-config re2c texinfo tzdata unzip wget \
        libtool libglib2.0-dev

    sudo apt-get update >/dev/null
    sudo apt-get install -y software-properties-common
    sudo add-apt-repository -y ppa:ubuntu-toolchain-r/test
    sudo apt-get update >/dev/null
    sudo apt-get install -y --no-install-recommends gcc-10 g++-10 gcc-10-multilib g++-10-multilib

    sudo ln -sf /usr/bin/python2 /usr/bin/python
    echo "export LANG=en_US.UTF-8" >> $PRESERVE_ENVARS
    echo "export CC=gcc" >> $PRESERVE_ENVARS
    echo "export CXX=g++" >> $PRESERVE_ENVARS

    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-7 9
    sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-7 9
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-10 10
    sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-10 10
}

function prepareRHEL8() {
    source $PRESERVE_ENVARS
    printf -- "Installing dependencies from repository.\n"
    sudo subscription-manager repos --enable codeready-builder-for-rhel-8-s390x-rpms
    sudo subscription-manager repos --enable rhel-8-for-s390x-appstream-rpms
    sudo yum install -y gcc-toolset-10 gcc-toolset-10-gcc gcc-toolset-10-gcc-c++ gcc-toolset-10-libatomic-devel
    sudo ln -sf /opt/rh/gcc-toolset-10/root/usr/bin/gcc /usr/local/bin/gcc
    sudo ln -sf /opt/rh/gcc-toolset-10/root/usr/bin/g++ /usr/local/bin/g++
    sudo yum install -y atk-devel autoconf automake binutils-devel bison bzip2 \
        cmake cups-devel flex git gnome-keyring libcurl-devel \
        libev-devel libtool make ncurses-devel ninja-build openssl-devel openssl-perl \
        python2 python3 python3-devel python3-httplib2 tar texinfo unzip wget which xz xz-devel glib2-devel

    sudo ln -sf /usr/bin/python2 /usr/bin/python
    echo 'export CC=/opt/rh/gcc-toolset-10/root/usr/bin/gcc' >> $PRESERVE_ENVARS
    echo 'export CXX=/opt/rh/gcc-toolset-10/root/usr/bin/g++' >> $PRESERVE_ENVARS
    echo "export LANG=en_US.UTF-8" >> $PRESERVE_ENVARS
}

function prepareRHEL7() {
    source $PRESERVE_ENVARS
    printf -- "Installing dependencies from repository.\n"
    sudo subscription-manager repos --enable=rhel-7-server-for-system-z-rhscl-rpms
    sudo yum install -y gcc gcc-c++ libatomic atk-devel autoconf automake bison bzip2 perl-CPAN perl-devel \
    ca-certificates cmake cups-devel flex gnome-keyring libcurl-devel libtool make ncurses-devel python2 python3 \
    python3-devel tar texinfo unzip wget which xmlto xz xz-devel zlib-devel gettext

    sudo pip3 install six httplib2
    sudo ln -sf /usr/bin/python2 /usr/bin/python

    echo "export LANG=en_US.UTF-8" >> $PRESERVE_ENVARS
}


function prepareSUSE12() {
    set +e
    sudo zypper remove -y libstdc++6-pp-gcc11-11.2.1+git610-1.7.1.s390x
    set -e

    sudo zypper install -y asciidoc autoconf automake bison cmake \
        cups-libs flex gcc10-c++ gcc10 libstdc++6-devel-gcc10 libstdc++6-pp-gcc10 git-core glib2-devel libatk-1_0-0 libgtk-3-0 \
        libgconfmm-2_6-1 liblzma5 libncurses6 ncurses-devel \
        libopenssl1_1 libopenssl-1_1-devel libpango-1_0-0 \
        libtirpc-devel libtool libxml2-tools libxslt-tools libz1 make makedepend \
        ninja openssl-1_1 patch pkg-config python re2c ruby \
        sqlite3 tar texinfo unixODBC wget which xinetd xmlto zlib-devel xz glibc-locale python36 python36-pip

    pip install httplib2 --upgrade
    pip install six

    sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-10 10
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-10 10
    sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-10 10
    sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-10 10
    sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.6 10
    sudo update-alternatives --set python3 /usr/bin/python3.6
    sudo update-alternatives --display python3
    python3 -V

    echo 'export CC=/usr/bin/gcc' >> $PRESERVE_ENVARS
    echo 'export CXX=/usr/bin/g++' >> $PRESERVE_ENVARS
    echo "export LANG=en_US.UTF-8" >> $PRESERVE_ENVARS
}

function prepareSUSE15() {
    sudo zypper install -y asciidoc autoconf automake cmake curl flex \
        gcc gcc-c++ gcc10-c++-10.3.0+git1587 gcc10-10.3.0+git1587 git-core glib2 glib2-devel glibc-locale \
        libopenssl-devel libncurses6 \
        libtirpc-devel libtool libxml2-tools libxslt-tools \
        make makedepend ncurses-devel ninja patch pkg-config \
        python python-xml python3-httplib2 re2c ruby sqlite3 tar \
        unixODBC wget which xinetd xmlto python3-pip

    pip3 install pyparsing

    sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-10 10
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-10 10
    sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-10 10
    sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-10 10
    sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc

    echo 'export CC=/usr/bin/gcc' >> $PRESERVE_ENVARS
    echo 'export CXX=/usr/bin/g++' >> $PRESERVE_ENVARS
    echo "export LANG=en_US.UTF-8" >> $PRESERVE_ENVARS
}

#For RHEL 7.x only
function installGCC() {
    source $PRESERVE_ENVARS
    printf -- "Start building GCC.\n"
    GCC_VERSION=($(gcc --version))
    if [ -f /usr/bin/s390x-linux-gnu-gcc-10 ]; then
        printf -- "GCC-10 already exists. Nothing to do. \n"
        return 0
    fi

    cd $SOURCE_ROOT
    ver=10.3.0
    wget http://ftp.mirrorservice.org/sites/sourceware.org/pub/gcc/releases/gcc-${ver}/gcc-${ver}.tar.gz
    tar xzf gcc-${ver}.tar.gz
    cd gcc-${ver}
    ./contrib/download_prerequisites
    mkdir -p build-gcc
    cd build-gcc
    ../configure -v --with-pkgversion='Couchbase 10.3.0' --with-bugurl=file:///usr/share/doc/gcc-10/README.Bugs --enable-languages=c,c++ --prefix=/usr --with-gcc-major-version-only --program-suffix=-10 --program-prefix=s390x-linux-gnu- --enable-shared --enable-linker-build-id --libexecdir=/usr/lib --without-included-gettext --enable-threads=posix --libdir=/usr/lib --enable-nls --enable-bootstrap --enable-clocale=gnu --enable-libstdcxx-debug --enable-libstdcxx-time=yes --with-default-libstdcxx-abi=new --enable-gnu-unique-object --disable-libquadmath --disable-libquadmath-support --enable-plugin --enable-default-pie --with-system-zlib --enable-libphobos-checking=release --with-target-system-zlib=auto --enable-objc-gc=auto --disable-werror --with-arch=zEC12 --with-long-double-128 --disable-multilib --enable-checking=release --build=s390x-linux-gnu --host=s390x-linux-gnu --target=s390x-linux-gnu --with-build-config=bootstrap-lto-lean --enable-link-mutex --enable-__cxa_atexit
    make -j$(nproc)
    sudo make install
    sudo rm -f /usr/bin/gcc
    sudo rm -f /usr/bin/g++
    echo "export CC=/usr/bin/s390x-linux-gnu-gcc-10" >> $PRESERVE_ENVARS
    echo "export CXX=/usr/bin/s390x-linux-gnu-g++-10" >> $PRESERVE_ENVARS
    sudo ln -sf /usr/bin/s390x-linux-gnu-gcc-10 /usr/bin/s390x-linux-gnu-gcc
    sudo ln -sf /usr/bin/s390x-linux-gnu-g++-10 /usr/bin/s390x-linux-gnu-g++
    sudo ln -sf /usr/bin/s390x-linux-gnu-gcc-10 /usr/bin/gcc
    sudo ln -sf /usr/bin/s390x-linux-gnu-g++-10 /usr/bin/g++

    printf -- "Finished building GCC.\n"
}

#For RHEL 7.x only
function installGit() {
    source $PRESERVE_ENVARS
    printf -- "Start building Git.\n"
    if command -v "git" >/dev/null; then
    GIT_VERSION=($(git --version))
        if [ ${GIT_VERSION[2]} == 2.10.1 ]; then
            printf -- "Git already exists.\n"
            return 0
        fi
    fi

    cd $SOURCE_ROOT
    rm -rdf git-2.10.1
    wget https://github.com/git/git/archive/v2.10.1.tar.gz -O git.tar.gz
    tar -zxf git.tar.gz
    cd git-2.10.1
    make configure
    ./configure --prefix=/usr
    make -j$(nproc)
    sudo make install

    printf -- "Finished building Git.\n"
}

#For RHEL 7.x only
function installNinja() {
    source $PRESERVE_ENVARS
    printf -- "Start building Ninja.\n"
    if command -v "ninja" >/dev/null; then
        if [ `ninja --version` == 1.8.2 ]; then
            printf -- "Ninja already exists.\n"
            return 0
        fi
    fi

    cd $SOURCE_ROOT
    rm -rfd ninja
    git clone https://github.com/ninja-build/ninja
    cd ninja
    git checkout v1.8.2
    ./configure.py --bootstrap
    sudo cp ninja /usr/bin

    printf -- "Finished building Ninja.\n"
}

function installGo() {
    source $PRESERVE_ENVARS
    printf -- "Start building golang.\n"
    if command -v "go" >/dev/null; then
        printf -- "Golang already exists.\n"
        return 0
    fi

    cd $SOURCE_ROOT
    wget https://golang.org/dl/go1.18.8.linux-s390x.tar.gz
    chmod ugo+r go1.18.8.linux-s390x.tar.gz
    sudo tar -C /usr/local -xzf go1.18.8.linux-s390x.tar.gz
    echo "export PATH=/usr/local/go/bin:$PATH" >> $PRESERVE_ENVARS
    export PATH=/usr/local/go/bin:$PATH
    echo "export GOPATH=$(go env GOPATH)" >> $PRESERVE_ENVARS
    go version

    printf -- "Finished building golang.\n"
}

function installCmake() {
    source $PRESERVE_ENVARS
    printf -- "Start building CMake.\n"
    if command -v "cmake" >/dev/null; then
    CMAKE_VERSION=($(cmake --version))
        if [ ${CMAKE_VERSION[2]} == 3.24.2 ]; then
            printf -- "Cmake already exists.\n"
            return 0
        fi
    fi

    cd $SOURCE_ROOT
    rm -rdf cmake-3.24.2
    wget https://cmake.org/files/v3.24/cmake-3.24.2.tar.gz
    tar -xzf cmake-3.24.2.tar.gz
    cd cmake-3.24.2
    ./bootstrap --prefix=/usr
    make -j$(nproc)
    sudo make install
    hash -r

    printf -- "Finished building CMake.\n"
}

function installRepoTool() {
    source $PRESERVE_ENVARS
    printf -- "Start getting repo .\n"
    if [ -f  /usr/bin/repo ]; then
        printf -- "Repo already exists. Nothing to do. \n"
        return 0
    fi

    cd $SOURCE_ROOT
    curl https://storage.googleapis.com/git-repo-downloads/repo >repo
    chmod a+x repo
    sudo mv repo /usr/bin

    printf -- "Finished getting repo .\n"
}

function installGflags() {
    source $PRESERVE_ENVARS
    printf -- "Start building gflags .\n"
    if [ -d  $SOURCE_ROOT/gflags-2.2.2 ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    cd $SOURCE_ROOT
    version=2.2.2
    wget https://github.com/gflags/gflags/archive/refs/tags/v$version.tar.gz
    tar xzf v$version.tar.gz
    cd gflags-$version
    mkdir build && cd build
    cmake -D BUILD_SHARED_LIBS=ON ..
    make -j$(nproc)
    sudo make install

    printf -- "Finished building gflags .\n"
}

function buildBenchmark() {
    source $PRESERVE_ENVARS
    NAME_BENCHMARK=benchmark
    VERSION_BENCHMARK=v1.6.0
    BUILD_BENCHMARK=cb1
    PACKAGE_BENCHMARK=$NAME_BENCHMARK-$DISTRO-s390x-$VERSION_BENCHMARK-$BUILD_BENCHMARK

    printf -- "Start building %s .\n" "$PACKAGE_BENCHMARK"
    if [ -d  $SOURCE_ROOT/$NAME_BENCHMARK ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    cd $SOURCE_ROOT
    git clone https://github.com/couchbasedeps/benchmark.git
    cd benchmark
    git checkout $VERSION_BENCHMARK
    cmake -D CMAKE_INSTALL_PREFIX=$(pwd)/_build -D CMAKE_BUILD_TYPE=RelWithDebInfo -D CMAKE_INSTALL_LIBDIR=lib -D CMAKE_CXX_STANDARD=17 -D CMAKE_CXX_STANDARD_REQUIRED=ON -D BUILD_SHARED_LIBS=OFF -D BENCHMARK_ENABLE_TESTING=OFF -D BENCHMARK_ENABLE_GTEST_TESTS=OFF -D BENCHMARK_ENABLE_INSTALL=ON -D BENCHMARK_DOWNLOAD_DEPENDENCIES=OFF
    cmake --build . --target install
    cmake -E remove_directory ./_build/lib/pkgconfig
    cd _build
    # Packaging build files
    tar -czvf $PACKAGE_BENCHMARK.tgz *
    MD5_BENCHMARK=($(md5sum $PACKAGE_BENCHMARK.tgz))
    echo $MD5_BENCHMARK >$PACKAGE_BENCHMARK.md5
    # Copy the package to destination
    cp $PACKAGE_BENCHMARK.* $CACHE_DIRECTORY

    printf -- "Finished building %s .\n" "$PACKAGE_BENCHMARK"
}

function buildBoost() {
    source $PRESERVE_ENVARS
    NAME_BOOST=boost
    VERSION_BOOST=1.74.0
    BUILD_BOOST=cb1
    PACKAGE_BOOST=$NAME_BOOST-$DISTRO-s390x-$VERSION_BOOST-$BUILD_BOOST

    printf -- "Start building %s .\n" "$PACKAGE_BOOST"
    if [ -d  $SOURCE_ROOT/boost_1_74_0 ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    sudo ldconfig /usr/local/lib64 /usr/local/lib
    cd $SOURCE_ROOT
    TOOLSET=gcc
    URL=https://boostorg.jfrog.io/artifactory/main/release/$VERSION_BOOST/source/boost_1_74_0.tar.gz
    curl -sSL $URL | tar xzf -
    cd boost_1_74_0
    sed -i 's/array\.hpp/array_wrapper.hpp/g' boost/numeric/ublas/matrix.hpp
    sed -i 's/array\.hpp/array_wrapper.hpp/g' boost/numeric/ublas/storage.hpp

    ./bootstrap.sh --with-libraries=context,chrono,date_time,filesystem,program_options,regex,system,thread --prefix=$(pwd)/_build --libdir=$(pwd)/_build/lib
    options=(toolset=$TOOLSET variant=release link=static runtime-link=shared threading=multi --without-python address-model=64 cflags=-fno-omit-frame-pointer cxxflags=-fno-omit-frame-pointer cxxflags=-fPIC cxxflags=-std=c++17)
    ./b2 -j 4 ${options[@]} install
    cd _build
    # Packaging build files
    tar -czvf $PACKAGE_BOOST.tgz *
    MD5_BOOST=($(md5sum $PACKAGE_BOOST.tgz))
    echo $MD5_BOOST >$PACKAGE_BOOST.md5
    # Copy the package to destination
    cp $PACKAGE_BOOST.* $CACHE_DIRECTORY

    printf -- "Finished building %s .\n" "$PACKAGE_BOOST"
}

function buildCbpy() {
    source $PRESERVE_ENVARS
    NAME_CBPY=cbpy
    VERSION_CBPY=7.1.0
    BUILD_CBPY=cb11
    PACKAGE_CBPY=$NAME_CBPY-linux-s390x-$VERSION_CBPY-$BUILD_CBPY

    printf -- "Start building %s .\n" "$PACKAGE_CBPY"
    if [ -d  $SOURCE_ROOT/$NAME_CBPY ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    cd $SOURCE_ROOT
    wget https://repo.anaconda.com/miniconda/Miniconda3-py39_4.12.0-Linux-s390x.sh
    chmod a+x Miniconda3-py39_4.12.0-Linux-s390x.sh
    ./Miniconda3-py39_4.12.0-Linux-s390x.sh -b -p ./cbpy
    cd cbpy
    ./bin/pip3 install msgpack-python
    ./bin/pip3 install natsort
    ./bin/pip3 install pem
    ./bin/pip3 install pycryptodome
    ./bin/pip3 install python-snappy
    ./bin/pip3 install requests

    # Packaging build files
    tar -czvf $PACKAGE_CBPY.tgz bin lib share ssl
    MD5_CBPY=($(md5sum $PACKAGE_CBPY.tgz))
    echo $MD5_CBPY >$PACKAGE_CBPY.md5
    # Copy the package to destination
    cp $PACKAGE_CBPY.* $CACHE_DIRECTORY

    printf -- "Finished building %s .\n" "$PACKAGE_CBPY"
}

function buildCurl() {
    source $PRESERVE_ENVARS
    NAME_CURL=curl
    VERSION_CURL=7.78.0
    BUILD_CURL=7
    PACKAGE_CURL=$NAME_CURL-linux-s390x-$VERSION_CURL-$BUILD_CURL

    printf -- "Start building %s .\n" "$PACKAGE_CURL"
    if [ -d  $SOURCE_ROOT/$NAME_CURL ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi


    cd $SOURCE_ROOT
    sudo ldconfig /usr/local/lib64 /usr/local/lib
    git clone https://github.com/curl/curl.git
    cd curl
    git checkout curl-7_78_0
    cmake -G "Unix Makefiles" .
    autoreconf -fi
    ./configure --prefix=$(pwd)/_build --libdir=$(pwd)/_build/lib --without-ssl
    make -j$(nproc)
    make install
    hash -r
    cd _build
    cat <<EOF >CMakeLists.txt
FILE (COPY bin lib DESTINATION "\${CMAKE_INSTALL_PREFIX}")
SET_PROPERTY (GLOBAL APPEND PROPERTY CBDEPS_PREFIX_PATH "\${CMAKE_CURRENT_SOURCE_DIR}")
EOF
    echo "$VERSION_CURL-7" >VERSION.txt
    # Packaging build files
    tar -czvf $PACKAGE_CURL.tgz *
    MD5_CURL=($(md5sum $PACKAGE_CURL.tgz))
    echo $MD5_CURL >$PACKAGE_CURL.md5
    # Copy the package to destination
    cp $PACKAGE_CURL.* $CACHE_DIRECTORY

    printf -- "Finished building %s .\n" "$PACKAGE_CURL"
}

function buildDconvertion() {
    source $PRESERVE_ENVARS
    NAME_DCONVERTION=double-conversion
    VERSION_DCONVERTION=3.0.0
    BUILD_DCONVERTION=cb4
    PACKAGE_DCONVERTION=$NAME_DCONVERTION-$DISTRO-s390x-$VERSION_DCONVERTION-$BUILD_DCONVERTION

    printf -- "Start building %s .\n" "$PACKAGE_DCONVERTION"
    if [ -d  $SOURCE_ROOT/$NAME_DCONVERTION ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    cd $SOURCE_ROOT
    git clone https://github.com/google/double-conversion.git
    cd double-conversion
    git checkout v3.0.0
    cmake -D BUILD_SHARED_LIBS=OFF -D BUILD_TESTING=OFF -D CMAKE_INSTALL_PREFIX=$(pwd)/_build -D CMAKE_INSTALL_LIBDIR=lib .
    make -j$(nproc)
    make install
    cmake -E remove_directory $(pwd)/_build/lib/cmake
    cd _build
    # Packaging build files
    tar -czvf $PACKAGE_DCONVERTION.tgz *
    MD5_DCONVERTION=($(md5sum $PACKAGE_DCONVERTION.tgz))
    echo $MD5_DCONVERTION >$PACKAGE_DCONVERTION.md5
    # Copy the package to destination
    cp $PACKAGE_DCONVERTION.* $CACHE_DIRECTORY

    printf -- "Finished building %s .\n" "$PACKAGE_DCONVERTION"
}

function buildErlang() {
    source $PRESERVE_ENVARS
    NAME_ERLANG=erlang
    VERSION_ERLANG=neo
    BUILD_ERLANG=7
    PACKAGE_ERLANG=$NAME_ERLANG-linux-s390x-$VERSION_ERLANG-$BUILD_ERLANG

    printf -- "Start building %s .\n" "$PACKAGE_ERLANG"
    if [ -d  $SOURCE_ROOT/$NAME_ERLANG ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi


    cd $SOURCE_ROOT
    git clone https://github.com/couchbasedeps/erlang.git
    cd erlang && git checkout couchbase-neo-8
    ./configure --prefix=$(pwd)/_build --libdir=$(pwd)/_build/lib --enable-smp-support --disable-hipe --disable-fp-exceptions --without-javac --enable-m64-build CFLAGS="-fno-strict-aliasing -O3 -ggdb3"
    make -j$(nproc)
    make install
    hash -r
    cd _build
    echo 'neo-7' >VERSION.txt
    cat <<EOF >CMakeLists.txt
FILE (COPY bin lib DESTINATION "\${CMAKE_INSTALL_PREFIX}")
EXECUTE_PROCESS (
    COMMAND "\${CMAKE_INSTALL_PREFIX}/lib/erlang/Install"
        -minimal "\${CMAKE_INSTALL_PREFIX}/lib/erlang"
)
EOF
    # Packaging build files
    tar -czvf $PACKAGE_ERLANG.tgz *
    MD5_ERLANG=($(md5sum $PACKAGE_ERLANG.tgz))
    echo $MD5_ERLANG >$PACKAGE_ERLANG.md5
    # Copy the package to destination
    cp $PACKAGE_ERLANG.* $CACHE_DIRECTORY

    printf -- "Finished building %s .\n" "$PACKAGE_ERLANG"
}

function buildFbuf() {
    source $PRESERVE_ENVARS
    NAME_FBUF=flatbuffers
    VERSION_FBUF=1.10.0
    BUILD_FBUF=cb5
    PACKAGE_FBUF=$NAME_FBUF-$DISTRO-s390x-$VERSION_FBUF-$BUILD_FBUF

    printf -- "Start building %s .\n" "$PACKAGE_FBUF"
    if [ -d  $SOURCE_ROOT/$NAME_FBUF ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi


    cd $SOURCE_ROOT
    git clone https://github.com/google/flatbuffers
    cd flatbuffers && git checkout v1.10.0
    wget $PATCH_URL/flatbuffers.diff -P $SOURCE_ROOT/patch
    git apply $SOURCE_ROOT/patch/flatbuffers.diff
    curl https://github.com/google/flatbuffers/commit/2e865f4d4e67a9b628c137aab7da8140dd9339a4.patch | git apply -
    cmake -G "Unix Makefiles" -D CMAKE_INSTALL_PREFIX=$(pwd)/_build -D CMAKE_BUILD_TYPE=Release -D FLATBUFFERS_BUILD_TESTS=OFF -D CMAKE_INSTALL_LIBDIR=lib
    make -j $(nproc)
    make install
    hash -r
    cd _build
    touch CMakeLists.txt
    # Packaging build files
    tar -czvf $PACKAGE_FBUF.tgz *
    MD5_FBUF=($(md5sum $PACKAGE_FBUF.tgz))
    echo $MD5_FBUF >$PACKAGE_FBUF.md5
    # Copy the package to destination
    cp $PACKAGE_FBUF.* $CACHE_DIRECTORY

    printf -- "Finished building %s .\n" "$PACKAGE_FBUF"
}

function buildFmt() {
    source $PRESERVE_ENVARS
    NAME_FMT=fmt
    VERSION_FMT=7.1.3
    BUILD_FMT=cb2
    PACKAGE_FMT=$NAME_FMT-$DISTRO-s390x-$VERSION_FMT-$BUILD_FMT

    printf -- "Start building %s .\n" "$PACKAGE_FMT"
    if [ -d  $SOURCE_ROOT/$NAME_FMT ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    cd $SOURCE_ROOT
    git clone https://github.com/fmtlib/fmt.git
    cd fmt
    git checkout $VERSION_FMT
    cmake -D CMAKE_INSTALL_PREFIX=$(pwd)/_build -D CMAKE_BUILD_TYPE=RelWithDebInfo -D CMAKE_CXX_VISIBILITY_PRESET=hidden -D CMAKE_POSITION_INDEPENDENT_CODE=ON -D CMAKE_INSTALL_LIBDIR=lib .
    make -j$(nproc)
    make install
    cd _build
    # Packaging build files
    tar -czvf $PACKAGE_FMT.tgz *
    MD5_FMT=($(md5sum $PACKAGE_FMT.tgz))
    echo $MD5_FMT >$PACKAGE_FMT.md5
    # Copy the package to destination
    cp $PACKAGE_FMT.* $CACHE_DIRECTORY

    printf -- "Finished building %s .\n" "$PACKAGE_FMT"
}

function buildSnappy() {
    source $PRESERVE_ENVARS
    NAME_SNAPPY=snappy
    VERSION_SNAPPY=1.1.8
    BUILD_SNAPPY=cb4
    PACKAGE_SNAPPY=$NAME_SNAPPY-linux-s390x-$VERSION_SNAPPY-$BUILD_SNAPPY

    printf -- "Start building %s .\n" "$PACKAGE_SNAPPY"
    if [ -d  $SOURCE_ROOT/snappy-$VERSION_SNAPPY ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    cd $SOURCE_ROOT
    wget https://github.com/google/snappy/archive/refs/tags/$VERSION_SNAPPY.tar.gz
    tar -xzf $VERSION_SNAPPY.tar.gz
    cd snappy-$VERSION_SNAPPY
    cmake -D CMAKE_INSTALL_PREFIX=$(pwd)/_build -D SNAPPY_BUILD_TESTS=OFF -D BUILD_SHARED_LIBS=ON -D CMAKE_INSTALL_LIBDIR=lib .
    make -j$(nproc)
    make install
    hash -r
    cd _build
    cat <<EOF >CMakeLists.txt
file(GLOB snappy_libs lib/*snappy*)
file(COPY \${snappy_libs} DESTINATION "\${CMAKE_INSTALL_PREFIX}/lib")
EOF
    # Packaging build files
    tar -czvf $PACKAGE_SNAPPY.tgz *
    MD5_SNAPPY=($(md5sum $PACKAGE_SNAPPY.tgz))
    echo $MD5_SNAPPY >$PACKAGE_SNAPPY.md5
    # Copy the package to destination
    cp $PACKAGE_SNAPPY.* $CACHE_DIRECTORY

    printf -- "Finished building %s .\n" "$PACKAGE_SNAPPY"
}

function buildOssl() {
    source $PRESERVE_ENVARS
    NAME_OSSL=openssl
    VERSION_OSSL=1.1.1o
    BUILD_OSSL=1
    PACKAGE_OSSL=$NAME_OSSL-linux-s390x-$VERSION_OSSL-$BUILD_OSSL

    printf -- "Start building %s .\n" "$PACKAGE_OSSL"
    if [ -d  $SOURCE_ROOT/$NAME_OSSL-$VERSION_OSSL ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi


    cd $SOURCE_ROOT
    wget https://www.openssl.org/source/openssl-$VERSION_OSSL.tar.gz
    tar -xzf openssl-$VERSION_OSSL.tar.gz
    cd openssl-$VERSION_OSSL
    ./config --prefix=$(pwd)/_build --openssldir=$(pwd)/_build
    make -j$(nproc)
    make install
    hash -r
    cd _build
    echo '1.1.1o-1' >VERSION.txt
    cat <<EOF >CMakeLists.txt
FILE (COPY bin DESTINATION "\${CMAKE_INSTALL_PREFIX}")
FILE (COPY lib DESTINATION "\${CMAKE_INSTALL_PREFIX}")
SET_PROPERTY (GLOBAL APPEND PROPERTY CBDEPS_PREFIX_PATH "\${CMAKE_CURRENT_SOURCE_DIR}")
EOF
    # Packaging build files
    tar -czvf $PACKAGE_OSSL.tgz *
    MD5_OSSL=($(md5sum $PACKAGE_OSSL.tgz))
    echo $MD5_OSSL >$PACKAGE_OSSL.md5
    # Copy the package to destination
    cp $PACKAGE_OSSL.* $CACHE_DIRECTORY

    printf -- "Finished building %s .\n" "$PACKAGE_OSSL"
}

function buildLibevent() {
    source $PRESERVE_ENVARS
    NAME_LIBEVENT=libevent
    VERSION_LIBEVENT=2.1.11
    BUILD_LIBEVENT=cb7
    PACKAGE_LIBEVENT=$NAME_LIBEVENT-$DISTRO-s390x-$VERSION_LIBEVENT-$BUILD_LIBEVENT

    printf -- "Start building %s .\n" "$PACKAGE_LIBEVENT"
    if [ -d  $SOURCE_ROOT/$NAME_LIBEVENT ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    OPENSSL_BUILD=$SOURCE_ROOT/openssl-1.1.1o/_build

    cd $SOURCE_ROOT
    git clone https://github.com/libevent/libevent.git
    cd libevent
    git checkout release-2.1.11-stable

    cmake -D CMAKE_INSTALL_PREFIX=`pwd`/_build \
        -D CMAKE_INSTALL_LIBDIR=lib \
        -D CMAKE_BUILD_TYPE=RelWithDebInfo \
        -D EVENT__DISABLE_BENCHMARK=ON \
        -D EVENT__DISABLE_REGRESS=ON \
        -D EVENT__DISABLE_SAMPLES=ON \
        -D OPENSSL_ROOT_DIR=$OPENSSL_BUILD .

    make -j$(nproc)
    make install
    cd _build
    cat <<EOF >CMakeLists.txt
FILE (COPY lib DESTINATION \${CMAKE_INSTALL_PREFIX})
EOF
    # Packaging build files
    tar -czvf $PACKAGE_LIBEVENT.tgz *
    MD5_LIBEVENT=($(md5sum $PACKAGE_LIBEVENT.tgz))
    echo $MD5_LIBEVENT >$PACKAGE_LIBEVENT.md5
    # Copy the package to destination
    cp $PACKAGE_LIBEVENT.* $CACHE_DIRECTORY

    printf -- "Finished building %s .\n" "$PACKAGE_LIBEVENT"
}

function buildGlog() {
    source $PRESERVE_ENVARS
    NAME_GLOG=glog
    VERSION_GLOG=v0.4.0
    BUILD_GLOG=cb1
    PACKAGE_GLOG=$NAME_GLOG-$DISTRO-s390x-$VERSION_GLOG-$BUILD_GLOG

    printf -- "Start building %s .\n" "$PACKAGE_GLOG"
    if [ -d  $SOURCE_ROOT/$NAME_GLOG ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi


    cd $SOURCE_ROOT
    git clone https://github.com/google/glog.git
    cd glog
    git checkout $VERSION_GLOG
    cmake -S . -B build -G "Unix Makefiles" -D BUILD_SHARED_LIBS=OFF -D CMAKE_INSTALL_PREFIX=$(pwd)/_build -D CMAKE_BUILD_TYPE=RelWithDebInfo -D CMAKE_INSTALL_LIBDIR=lib
    cmake --build build --target install
    cd _build
    # Packaging build files
    tar -czvf $PACKAGE_GLOG.tgz *
    MD5_GLOG=($(md5sum $PACKAGE_GLOG.tgz))
    echo $MD5_GLOG >$PACKAGE_GLOG.md5
    # Copy the package to destination
    cp $PACKAGE_GLOG.* $CACHE_DIRECTORY

    printf -- "Finished building %s .\n" "$PACKAGE_GLOG"
}

function buildZstd() {
    source $PRESERVE_ENVARS
    NAME_ZSTD=zstd-cpp
    VERSION_ZSTD=1.5.0
    BUILD_ZSTD=2
    PACKAGE_ZSTD=$NAME_ZSTD-linux-s390x-$VERSION_ZSTD-$BUILD_ZSTD

    printf -- "Start building %s .\n" "$PACKAGE_ZSTD"
    if [ -d  $SOURCE_ROOT/zstd-1.5.0 ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi


    cd $SOURCE_ROOT
    wget https://github.com/facebook/zstd/archive/refs/tags/v1.5.0.tar.gz
    tar -xzvf v1.5.0.tar.gz
    cd zstd-1.5.0
    make DESTDIR=$(pwd)/_build install
    cd _build
    cp -r ./usr/local/* . && rm -drf usr bin share
    echo '1.5.0-2' >VERSION.txt
    cat <<EOF >CMakeLists.txt
FILE (COPY lib DESTINATION "\${CMAKE_INSTALL_PREFIX}")
EOF
    # Packaging build files
    tar -czvf $PACKAGE_ZSTD.tgz *
    MD5_ZSTD=($(md5sum $PACKAGE_ZSTD.tgz))
    echo $MD5_ZSTD >$PACKAGE_ZSTD.md5
    # Copy the package to destination
    cp $PACKAGE_ZSTD.* $CACHE_DIRECTORY

    printf -- "Finished building %s .\n" "$PACKAGE_ZSTD"
}

function buildJemalloc-5.3.0() {
    source $PRESERVE_ENVARS

    printf -- "Start building jemalloc-5.3.0 .\n"
    if [ -d  $SOURCE_ROOT/jemalloc-5.3.0 ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    mkdir $SOURCE_ROOT/jemalloc-5.3.0 && cd $SOURCE_ROOT/jemalloc-5.3.0
    git clone https://github.com/couchbasedeps/jemalloc.git .
    git checkout 5.3.0
    configure_args="--prefix=$(pwd)/_build \
   --with-jemalloc-prefix=je_ \
   --disable-cache-oblivious \
   --disable-zone-allocator \
   --disable-initial-exec-tls \
   --disable-cxx \
   --enable-prof \
   --libdir=$(pwd)/_build/lib"

    ./autogen.sh ${configure_args}
    make -j$(nproc)
    make install
}

function buildFolly() {
    buildJemalloc-5.3.0

    source $PRESERVE_ENVARS
    NAME_FOLLY=folly
    VERSION_FOLLY=v2020.09.07.00
    BUILD_FOLLY=couchbase-cb1
    PACKAGE_FOLLY=$NAME_FOLLY-$DISTRO-s390x-$VERSION_FOLLY-$BUILD_FOLLY

    printf -- "Start building %s .\n" "$PACKAGE_FOLLY"
    if [ -d  $SOURCE_ROOT/$NAME_FOLLY ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    JEMALLOC_BUILD=$SOURCE_ROOT/jemalloc-5.3.0/_build
    FMT_BUILD=$SOURCE_ROOT/fmt/_build
    GLOG_BUILD=$SOURCE_ROOT/glog/_build
    BOOST_BUILD=$SOURCE_ROOT/boost_1_74_0/_build
    DOUBLE_CONVERSION_BUILD=$SOURCE_ROOT/double-conversion/_build
    LIBEVENT_BUILD=$SOURCE_ROOT/libevent/_build
    OPENSSL_BUILD=$SOURCE_ROOT/openssl-1.1.1o/_build
    SNAPPY_BUILD=$SOURCE_ROOT/snappy-1.1.8/_build
    ZSTD_BUILD=$SOURCE_ROOT/zstd-1.5.0/_build

    LIBRARIES="$JEMALLOC_BUILD/lib;$FMT_BUILD/lib;$GLOG_BUILD/lib;$BOOST_BUILD/lib;$DOUBLE_CONVERSION_BUILD/lib;$LIBEVENT_BUILD/lib;$OPENSSL_BUILD/lib;$SNAPPY_BUILD/lib;$ZSTD_BUILD/lib;"
    INCLUDES="$JEMALLOC_BUILD/include;$FMT_BUILD/include;$GLOG_BUILD/include;$BOOST_BUILD/include;$DOUBLE_CONVERSION_BUILD/include;$LIBEVENT_BUILD/include;$OPENSSL_BUILD/include;$SNAPPY_BUILD/include;$ZSTD_BUILD/include"

    cd $SOURCE_ROOT
    git clone https://github.com/facebook/folly
    cd folly
    git checkout $VERSION_FOLLY
    wget $PATCH_URL/folly.diff -P $SOURCE_ROOT/patch
    git apply $SOURCE_ROOT/patch/folly.diff
    sudo ldconfig /usr/local/lib64 /usr/local/lib

    cmake \
        -D CMAKE_INCLUDE_PATH=$INCLUDES \
        -D CMAKE_LIBRARY_PATH=$LIBRARIES \
        -D CMAKE_CXX_FLAGS="-fPIC -fvisibility=hidden" \
        -D CMAKE_BUILD_TYPE=RelWithDebInfo \
        -D CMAKE_INSTALL_PREFIX=$(pwd)/_build \
        -D BUILD_SHARED_LIBS:STRING=OFF \
        -D Boost_INCLUDE_DIR=$BOOST_BUILD/include \
        -D Boost_ADDITIONAL_VERSIONS=1.74 \
        -D Boost_USE_STATIC_LIBS=ON \
        -D Boost_NO_SYSTEM_PATHS=ON \
        -D Boost_NO_BOOST_CMAKE=ON \
        -D BOOST_ROOT=$BOOST_BUILD \
        -D CMAKE_PREFIX_PATH=$FMT_BUILD \
        -D CMAKE_DISABLE_FIND_PACKAGE_ZLIB=TRUE .

    make -j$(nproc)
    make install
    cd _build
    # Packaging build files
    tar -czvf $PACKAGE_FOLLY.tgz *
    MD5_FOLLY=($(md5sum $PACKAGE_FOLLY.tgz))
    echo $MD5_FOLLY >$PACKAGE_FOLLY.md5
    # Copy the package to destination
    cp $PACKAGE_FOLLY.* $CACHE_DIRECTORY

    printf -- "Finished building %s .\n" "$PACKAGE_FOLLY"
}

function buildGtest() {
    source $PRESERVE_ENVARS
    NAME_GTEST=googletest
    VERSION_GTEST=1.11.0
    BUILD_GTEST=cb4
    PACKAGE_GTEST=$NAME_GTEST-linux-s390x-$VERSION_GTEST-$BUILD_GTEST

    printf -- "Start building %s .\n" "$PACKAGE_GTEST"
    if [ -d  $SOURCE_ROOT/$NAME_GTEST ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi


    cd $SOURCE_ROOT
    git clone https://github.com/google/googletest.git
    cd googletest
    git checkout release-$VERSION_GTEST
    cmake -D CMAKE_INSTALL_PREFIX=$(pwd)/_build \
        -D CMAKE_BUILD_TYPE=RelWithDebInfo \
        -D CMAKE_INSTALL_LIBDIR=lib \
        -D CMAKE_CXX_STANDARD=17 \
        -D CMAKE_CXX_STANDARD_REQUIRED=ON \
        -D BUILD_SHARED_LIBS=OFF \
        -D gtest_force_shared_crt=ON .

    make -j$(nproc)
    make install
    cd _build
    rm -drf ./lib/pkgconfig
    # Packaging build files
    tar -czvf $PACKAGE_GTEST.tgz *
    MD5_GTEST=($(md5sum $PACKAGE_GTEST.tgz))
    echo $MD5_GTEST >$PACKAGE_GTEST.md5
    # Copy the package to destination
    cp $PACKAGE_GTEST.* $CACHE_DIRECTORY

    printf -- "Finished building %s .\n" "$PACKAGE_GTEST"
}

function buildZlib() {
    source $PRESERVE_ENVARS
    NAME_ZLIB=zlib
    VERSION_ZLIB=1.2.12
    BUILD_ZLIB=1
    PACKAGE_ZLIB=$NAME_ZLIB-linux-s390x-$VERSION_ZLIB-$BUILD_ZLIB

    printf -- "Start building %s .\n" "$PACKAGE_ZLIB"
    if [ -d  $SOURCE_ROOT/$NAME_ZLIB ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi


    cd $SOURCE_ROOT
    git clone https://github.com/madler/zlib.git
    cd zlib
    git checkout v1.2.11 # v1.2.12 doesn't work on some distros (ub18 and rhel8)

    ./configure --prefix=$(pwd)/_build --64
    make -j$(nproc)
    make install
    cd _build
    echo '1.2.12-1' >VERSION.txt
    cat <<EOF >CMakeLists.txt
FILE (COPY lib DESTINATION "\${CMAKE_INSTALL_PREFIX}")
SET_PROPERTY (GLOBAL APPEND PROPERTY CBDEPS_PREFIX_PATH "\${CMAKE_CURRENT_SOURCE_DIR}")
EOF
    # Packaging build files
    tar -czvf $PACKAGE_ZLIB.tgz *
    MD5_ZLIB=($(md5sum $PACKAGE_ZLIB.tgz))
    echo $MD5_ZLIB >$PACKAGE_ZLIB.md5
    # Copy the package to destination
    cp $PACKAGE_ZLIB.* $CACHE_DIRECTORY

    printf -- "Finished building %s .\n" "$PACKAGE_ZLIB"
}

function buildGrpc() {
    source $PRESERVE_ENVARS
    NAME_GRPC=grpc
    VERSION_GRPC=1.28.1
    BUILD_GRPC=cb2
    PACKAGE_GRPC=$NAME_GRPC-$DISTRO-s390x-$VERSION_GRPC-$BUILD_GRPC

    printf -- "Start building %s .\n" "$PACKAGE_GRPC"
    if [ -d  $SOURCE_ROOT/$NAME_GRPC ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi


    cd $SOURCE_ROOT
    git clone -b v1.28.1 https://github.com/grpc/grpc
    cd grpc/
    git submodule update --init
    BUILD_DIR=$(pwd)/_build
    # Point to zlib build file.
    ZLIB_BUILD_DIR=$SOURCE_ROOT/zlib/_build
    # Point to OpenSSL build file.
    OPENSSL_BUILD_DIR=$SOURCE_ROOT/openssl-1.1.1o/_build
    (
        cd third_party/protobuf/cmake
        cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo \
            -DCMAKE_INSTALL_PREFIX="$BUILD_DIR" \
            -Dprotobuf_BUILD_TESTS=OFF \
            -D CMAKE_PREFIX_PATH="$ZLIB_BUILD_DIR" .
        make -j$(nproc) install
    )
    (
        cd third_party/cares/cares
        cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo \
            -DCMAKE_INSTALL_PREFIX="$BUILD_DIR" \
            -DCARES_STATIC=ON -DCARES_STATIC_PIC=ON -DCARES_SHARED=OFF .
        make -j$(nproc) install
    )
    cmake -D CMAKE_BUILD_TYPE=RelWithDebInfo \
        -D CMAKE_INSTALL_PREFIX=$BUILD_DIR \
        -D CMAKE_PREFIX_PATH="$ZLIB_BUILD_DIR;$OPENSSL_BUILD_DIR;$BUILD_DIR" \
        -DgRPC_INSTALL=ON \
        -DgRPC_BUILD_TESTS=OFF \
        -DgRPC_PROTOBUF_PROVIDER=package \
        -DgRPC_ZLIB_PROVIDER=package \
        -DgRPC_CARES_PROVIDER=package \
        -DgRPC_SSL_PROVIDER=package \
        -D CMAKE_INSTALL_LIBDIR=lib .
    make -j$(nproc) install
    cd _build
    # Packaging build files
    tar -czvf $PACKAGE_GRPC.tgz *
    MD5_GRPC=($(md5sum $PACKAGE_GRPC.tgz))
    echo $MD5_GRPC >$PACKAGE_GRPC.md5
    # Copy the package to destination
    cp $PACKAGE_GRPC.* $CACHE_DIRECTORY

    printf -- "Finished building %s .\n" "$PACKAGE_GRPC"
}

function buildJemalloc() {
    source $PRESERVE_ENVARS
    NAME_JEMALLOC=jemalloc
    VERSION_JEMALLOC=5.2.1
    BUILD_JEMALLOC=cb6
    PACKAGE_JEMALLOC=$NAME_JEMALLOC-$DISTRO-s390x-$VERSION_JEMALLOC-$BUILD_JEMALLOC

    printf -- "Start building %s .\n" "$PACKAGE_JEMALLOC"
    if [ -d  $SOURCE_ROOT/$NAME_JEMALLOC ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi


    cd $SOURCE_ROOT
    git clone https://github.com/couchbasedeps/jemalloc.git
    cd jemalloc && git checkout $VERSION_JEMALLOC
    configure_args="--prefix=$(pwd)/_build \
   --with-jemalloc-prefix=je_ \
   --disable-cache-oblivious \
   --disable-zone-allocator \
   --disable-initial-exec-tls \
   --disable-cxx \
   --enable-prof \
   --libdir=$(pwd)/_build/lib"

    ./autogen.sh ${configure_args}
    make -j8 build_lib_shared
    make -j8 check
    make install_lib_shared install_include install_bin

    cd _build
    cat <<EOF >CMakeLists.txt
FILE (COPY bin/jeprof DESTINATION "\${CMAKE_INSTALL_PREFIX}/bin")
FILE (COPY lib DESTINATION "\${CMAKE_INSTALL_PREFIX}")
SET_PROPERTY (GLOBAL APPEND PROPERTY CBDEPS_PREFIX_PATH "\${CMAKE_CURRENT_SOURCE_DIR}")
EOF
    # Packaging build files
    tar -czvf $PACKAGE_JEMALLOC.tgz *
    MD5_JEMALLOC=($(md5sum $PACKAGE_JEMALLOC.tgz))
    echo $MD5_JEMALLOC >$PACKAGE_JEMALLOC.md5
    # Copy the package to destination
    cp $PACKAGE_JEMALLOC.* $CACHE_DIRECTORY

    printf -- "Finished building %s .\n" "$PACKAGE_JEMALLOC"
}

function buildJson() {
    source $PRESERVE_ENVARS
    NAME_JSON=json
    VERSION_JSON=3.9.0
    BUILD_JSON=cb1
    PACKAGE_JSON=$NAME_JSON-$DISTRO-s390x-$VERSION_JSON-$BUILD_JSON

    printf -- "Start building %s .\n" "$PACKAGE_JSON"
    if [ -d  $SOURCE_ROOT/$NAME_JSON ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi


    cd $SOURCE_ROOT
    git clone https://github.com/nlohmann/json
    cd $SOURCE_ROOT/json
    git checkout v3.9.0
    cmake -D CMAKE_INSTALL_PREFIX=$(pwd)/_build -D CMAKE_BUILD_TYPE=RelWithDebInfo -D JSON_BuildTests=OFF -D JSON_Install=ON -D JSON_MultipleHeaders=ON -D JSON_SystemInclude=ON -D CMAKE_INSTALL_LIBDIR=lib
    cmake --build . --target install
    cd _build
    # Packaging build files
    tar -czvf $PACKAGE_JSON.tgz *
    MD5_JSON=($(md5sum $PACKAGE_JSON.tgz))
    echo $MD5_JSON >$PACKAGE_JSON.md5
    # Copy the package to destination
    cp $PACKAGE_JSON.* $CACHE_DIRECTORY

    printf -- "Finished building %s .\n" "$PACKAGE_JSON"
}

function buildLiburing() {
    source $PRESERVE_ENVARS
    NAME_LIBURING=liburing
    VERSION_LIBURING=0.6
    BUILD_LIBURING=2
    PACKAGE_LIBURING=$NAME_LIBURING-$DISTRO-s390x-$VERSION_LIBURING-$BUILD_LIBURING

    printf -- "Start building %s .\n" "$PACKAGE_LIBURING"
    if [ -d  $SOURCE_ROOT/$NAME_LIBURING ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi


    cd $SOURCE_ROOT
    git clone https://github.com/axboe/liburing.git
    cd liburing
    git checkout liburing-$VERSION_LIBURING

    #'MAP_HUGE_2MB' causes issues on rhel7 and sles12
    sed -i 's/|\sMAP_HUGE_2MB\s//g' ./test/io_uring_register.c

    ./configure --prefix=$(pwd)/_build --libdir=$(pwd)/_build/lib
    make -j$(nproc)
    make install
    cd _build
    cat <<EOF >CMakeLists.txt
FILE (COPY lib DESTINATION "\${CMAKE_INSTALL_PREFIX}")
EOF
    # Packaging build files
    tar -czvf $PACKAGE_LIBURING.tgz *
    MD5_LIBURING=($(md5sum $PACKAGE_LIBURING.tgz))
    echo $MD5_LIBURING >$PACKAGE_LIBURING.md5
    # Copy the package to destination
    cp $PACKAGE_LIBURING.* $CACHE_DIRECTORY

    printf -- "Finished building %s .\n" "$PACKAGE_LIBURING"
}

function buildLibuv() {
    source $PRESERVE_ENVARS
    NAME_LIBUV=libuv
    VERSION_LIBUV=1.20.3
    BUILD_LIBUV=22
    PACKAGE_LIBUV=$NAME_LIBUV-$DISTRO-s390x-$VERSION_LIBUV-$BUILD_LIBUV

    printf -- "Start building %s .\n" "$PACKAGE_LIBUV"
    if [ -d  $SOURCE_ROOT/$NAME_LIBUV ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi


    cd $SOURCE_ROOT
    git clone https://github.com/couchbasedeps/libuv
    cd libuv
    git checkout v1.20.3
    ./autogen.sh
    ./configure --disable-silent-rules --prefix=$(pwd)/_build --libdir=$(pwd)/_build/lib
    make -j$(nproc)
    make install
    cd _build
    cat <<EOF >CMakeLists.txt
FILE (COPY lib DESTINATION "\${CMAKE_INSTALL_PREFIX}")
EOF
    # Packaging build files
    tar -czvf $PACKAGE_LIBUV.tgz *
    MD5_LIBUV=($(md5sum $PACKAGE_LIBUV.tgz))
    echo $MD5_LIBUV >$PACKAGE_LIBUV.md5
    # Copy the package to destination
    cp $PACKAGE_LIBUV.* $CACHE_DIRECTORY

    printf -- "Finished building %s .\n" "$PACKAGE_LIBUV"
}

function buildLz4() {
    source $PRESERVE_ENVARS
    NAME_LZ4=lz4
    VERSION_LZ4=1.9.2
    BUILD_LZ4=cb2
    PACKAGE_LZ4=$NAME_LZ4-linux-s390x-$VERSION_LZ4-$BUILD_LZ4

    printf -- "Start building %s .\n" "$PACKAGE_LZ4"
    if [ -d  $SOURCE_ROOT/$NAME_LZ4-$VERSION_LZ4 ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    cd $SOURCE_ROOT
    wget https://github.com/lz4/lz4/archive/refs/tags/v1.9.2.tar.gz
    tar -xzf v1.9.2.tar.gz
    cd lz4-1.9.2
    make -j$(nproc)
    make DESTDIR=$(pwd)/_build install
    hash -r
    cd _build
    cp -r ./usr/local/* . && rm -drf usr
    cat <<EOF >CMakeLists.txt
FILE (COPY lib DESTINATION "\${CMAKE_INSTALL_PREFIX}")
EOF
    # Packaging build files
    tar -czvf $PACKAGE_LZ4.tgz *
    MD5_LZ4=($(md5sum $PACKAGE_LZ4.tgz))
    echo $MD5_LZ4 >$PACKAGE_LZ4.md5
    # Copy the package to destination
    cp $PACKAGE_LZ4.* $CACHE_DIRECTORY

    printf -- "Finished building %s .\n" "$PACKAGE_LZ4"
}

function buildNumctl() {
    source $PRESERVE_ENVARS
    NAME_NUMCTL=numactl
    VERSION_NUMCTL=2.0.11
    BUILD_NUMCTL=cb3
    PACKAGE_NUMCTL=$NAME_NUMCTL-$DISTRO-s390x-$VERSION_NUMCTL-$BUILD_NUMCTL

    printf -- "Start building %s .\n" "$PACKAGE_NUMCTL"
    if [ -d  $SOURCE_ROOT/$NAME_NUMCTL ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    cd $SOURCE_ROOT
    git clone https://github.com/numactl/numactl.git
    cd numactl

    # v2.0.11 doesn't work on some distroes
    git checkout v2.0.14
    ./autogen.sh
    ./configure --prefix=$(pwd)/_build --libdir=$(pwd)/_build/lib
    make -j$(nproc)
    make install
    cd _build
    cat <<EOF >CMakeLists.txt
FILE (COPY lib DESTINATION "\${CMAKE_INSTALL_PREFIX}")
SET_PROPERTY (GLOBAL APPEND PROPERTY CBDEPS_PREFIX_PATH "\${CMAKE_CURRENT_SOURCE_DIR}")
EOF
    rm -dfr share bin
    # Packaging build files
    tar -czvf $PACKAGE_NUMCTL.tgz *
    MD5_NUMCTL=($(md5sum $PACKAGE_NUMCTL.tgz))
    echo $MD5_NUMCTL >$PACKAGE_NUMCTL.md5
    # Copy the package to destination
    cp $PACKAGE_NUMCTL.* $CACHE_DIRECTORY

    printf -- "Finished building %s .\n" "$PACKAGE_NUMCTL"
}

function buildPcre() {
    source $PRESERVE_ENVARS
    NAME_PCRE=pcre
    VERSION_PCRE=8.44
    BUILD_PCRE=cb1
    PACKAGE_PCRE=$NAME_PCRE-linux-s390x-$VERSION_PCRE-$BUILD_PCRE

    printf -- "Start building %s .\n" "$PACKAGE_PCRE"
    if [ -d  $SOURCE_ROOT/$NAME_PCRE-$VERSION_PCRE ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi


    cd $SOURCE_ROOT
    wget https://sourceforge.net/projects/pcre/files/pcre/$VERSION_PCRE/pcre-$VERSION_PCRE.tar.gz
    tar -xzf pcre-$VERSION_PCRE.tar.gz
    cd pcre-$VERSION_PCRE
    ./configure --prefix=$(pwd)/_build --libdir=$(pwd)/_build/lib
    make -j$(nproc)
    make install
    cd _build
    cat <<EOF >CMakeLists.txt
FILE (COPY bin lib DESTINATION "\${CMAKE_INSTALL_PREFIX}")
SET_PROPERTY (GLOBAL APPEND PROPERTY CBDEPS_PREFIX_PATH "\${CMAKE_CURRENT_SOURCE_DIR}")
EOF
    # Packaging build files
    tar -czvf $PACKAGE_PCRE.tgz *
    MD5_PCRE=($(md5sum $PACKAGE_PCRE.tgz))
    echo $MD5_PCRE >$PACKAGE_PCRE.md5
    # Copy the package to destination
    cp $PACKAGE_PCRE.* $CACHE_DIRECTORY

    printf -- "Finished building %s .\n" "$PACKAGE_PCRE"
}

function buildPrometheus() {
    source $PRESERVE_ENVARS
    cd $SOURCE_ROOT
    NAME_PROM=prometheus
    VERSION_PROM=2.23
    BUILD_PROM=3
    PACKAGE_PROM=$NAME_PROM-linux-s390x-$VERSION_PROM-$BUILD_PROM

    printf -- "Start building %s .\n" "$PACKAGE_PROM"
    if [ -d  $GOPATH/src/github.com/$NAME_PROM ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    cd $SOURCE_ROOT
    wget https://nodejs.org/dist/v16.14.2/node-v16.14.2-linux-s390x.tar.xz
    tar xf node-v16.14.2-linux-s390x.tar.xz
    export PATH=$SOURCE_ROOT/node-v16.14.2-linux-s390x/bin:$PATH
    echo "export PATH=$SOURCE_ROOT/node-v16.14.2-linux-s390x/bin:$PATH" >> $PRESERVE_ENVARS
    npm install -g yarn
    mkdir -p $GOPATH/src/github.com
    cd $GOPATH/src/github.com
    git clone https://github.com/couchbasedeps/prometheus.git
    cd prometheus
    git checkout couchbase-v2.23
    make build
    mkdir -p _build/bin && cp prometheus _build/bin && cd _build
    echo '2.23-3' >VERSION.txt
    cat <<EOF >CMakeLists.txt
FILE (COPY bin DESTINATION "\${CMAKE_INSTALL_PREFIX}")
EOF
    # Packaging build files
    tar -czvf $PACKAGE_PROM.tgz *
    MD5_PROM=($(md5sum $PACKAGE_PROM.tgz))
    echo $MD5_PROM >$PACKAGE_PROM.md5
    # Copy the package to destination
    cp $PACKAGE_PROM.* $CACHE_DIRECTORY

    printf -- "Finished building %s .\n" "$PACKAGE_PROM"
}

function buildPromcpp() {
    source $PRESERVE_ENVARS
    NAME_PROMCPP=prometheus-cpp
    VERSION_PROMCPP=v0.10.0
    BUILD_PROMCPP=couchbase-cb2
    PACKAGE_PROMCPP=$NAME_PROMCPP-$DISTRO-s390x-$VERSION_PROMCPP-$BUILD_PROMCPP

    printf -- "Start building %s .\n" "$PACKAGE_PROMCPP"
    if [ -d  $SOURCE_ROOT/$NAME_PROMCPP ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    # Point to zlib build file.
    ZLIB_BUILD_DIR=$SOURCE_ROOT/zlib/_build

    cd $SOURCE_ROOT
    git clone https://github.com/jupp0r/prometheus-cpp.git
    cd prometheus-cpp
    git checkout $VERSION_PROMCPP
    git submodule init
    git submodule update
    mkdir _build
    cd _build

    cmake -DBUILD_SHARED_LIBS=OFF \
        -D ENABLE_PUSH=OFF \
        -D CMAKE_POSITION_INDEPENDENT_CODE=ON \
        -D CMAKE_INSTALL_PREFIX=$(pwd)/_build \
        -D CMAKE_BUILD_TYPE=RelWithDebInfo \
        -D ZLIB_ROOT=$ZLIB_BUILD_DIR \
        -D CMAKE_INSTALL_LIBDIR=lib ..

    make -j$(nproc)
    make install
    cd _build
    # Packaging build files
    tar -czvf $PACKAGE_PROMCPP.tgz *
    MD5_PROMCPP=($(md5sum $PACKAGE_PROMCPP.tgz))
    echo $MD5_PROMCPP >$PACKAGE_PROMCPP.md5
    # Copy the package to destination
    cp $PACKAGE_PROMCPP.* $CACHE_DIRECTORY

    printf -- "Finished building %s .\n" "$PACKAGE_PROMCPP"
}

function buildProtoc() {
    source $PRESERVE_ENVARS
    NAME_PROTOC=protoc-gen-go
    VERSION_PROTOC=1.2.5
    BUILD_PROTOC=4
    PACKAGE_PROTOC=$NAME_PROTOC-$DISTRO-s390x-$VERSION_PROTOC-$BUILD_PROTOC

    printf -- "Start building %s .\n" "$PACKAGE_PROTOC"
    if [ -d  $SOURCE_ROOT/$NAME_PROTOC ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    mkdir -p $SOURCE_ROOT/protoc-gen-go/bin && cd $SOURCE_ROOT/protoc-gen-go
    go install github.com/golang/protobuf/protoc-gen-go@v1.2.0
    cp $GOPATH/bin/protoc-gen-go ./bin
    # Packaging build files
    tar -czvf $PACKAGE_PROTOC.tgz *
    MD5_PROTOC=($(md5sum $PACKAGE_PROTOC.tgz))
    echo $MD5_PROTOC >$PACKAGE_PROTOC.md5
    # Copy the package to destination
    cp $PACKAGE_PROTOC.* $CACHE_DIRECTORY

    printf -- "Finished building %s .\n" "$PACKAGE_PROTOC"
}

function buildRock() {
    source $PRESERVE_ENVARS
    NAME_ROCK=rocksdb
    VERSION_ROCK=5.18.3
    BUILD_ROCK=cb6
    PACKAGE_ROCK=$NAME_ROCK-$DISTRO-s390x-$VERSION_ROCK-$BUILD_ROCK

    printf -- "Start building %s .\n" "$PACKAGE_ROCK"
    if [ -d  $SOURCE_ROOT/$NAME_ROCK ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    cd $SOURCE_ROOT
    git clone https://github.com/facebook/rocksdb.git
    cd rocksdb/
    git checkout v5.18.3
    CXXFLAGS='-Wno-error=deprecated-copy -Wno-error=pessimizing-move -Wno-error=redundant-move' make -j$(nproc) shared_lib
    make install-shared INSTALL_PATH=$(pwd)/_build
    cd _build
    cat <<EOF >CMakeLists.txt
FILE (COPY lib DESTINATION "\${CMAKE_INSTALL_PREFIX}")
EOF
    # Packaging build files
    tar -czvf $PACKAGE_ROCK.tgz *
    MD5_ROCK=($(md5sum $PACKAGE_ROCK.tgz))
    echo $MD5_ROCK >$PACKAGE_ROCK.md5
    # Copy the package to destination
    cp $PACKAGE_ROCK.* $CACHE_DIRECTORY

    printf -- "Finished building %s .\n" "$PACKAGE_ROCK"
}

function buildSpdlog() {
    source $PRESERVE_ENVARS
    NAME_SPDLOG=spdlog
    VERSION_SPDLOG=v1.8.5
    BUILD_SPDLOG=cb3
    PACKAGE_SPDLOG=$NAME_SPDLOG-$DISTRO-s390x-$VERSION_SPDLOG-$BUILD_SPDLOG

    printf -- "Start building %s .\n" "$PACKAGE_SPDLOG"
    if [ -d  $SOURCE_ROOT/$NAME_SPDLOG ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    cd $SOURCE_ROOT
    # Point to fmt build file.
    FMT_BUILD_DIR=$SOURCE_ROOT/fmt/_build
    git clone https://github.com/gabime/spdlog.git
    cd spdlog
    git checkout $VERSION_SPDLOG
    wget https://raw.githubusercontent.com/couchbase/tlm/v7.1.1/deps/packages/spdlog/custom_level_names.patch
    git apply custom_level_names.patch
    wget https://raw.githubusercontent.com/couchbase/tlm/v7.1.1/deps/packages/spdlog/relocatable_export_package.patch
    git apply relocatable_export_package.patch
    mkdir build && cd build
    cmake \
        -D CMAKE_CXX_VISIBILITY_PRESET=hidden \
        -D CMAKE_POSITION_INDEPENDENT_CODE=ON \
        -D SPDLOG_BUILD_EXAMPLE=OFF \
        -D SPDLOG_FMT_EXTERNAL=ON \
        -D CMAKE_PREFIX_PATH=$FMT_BUILD_DIR \
        -D CMAKE_BUILD_TYPE=RelWithDebInfo \
        -D CMAKE_INSTALL_PREFIX=$(pwd)/_build \
        -D CMAKE_INSTALL_LIBDIR=lib ..

    make -j$(nproc)
    make install
    cd _build
    # Packaging build files
    tar -czvf $PACKAGE_SPDLOG.tgz *
    MD5_SPDLOG=($(md5sum $PACKAGE_SPDLOG.tgz))
    echo $MD5_SPDLOG >$PACKAGE_SPDLOG.md5
    # Copy the package to destination
    cp $PACKAGE_SPDLOG.* $CACHE_DIRECTORY

    printf -- "Finished building %s .\n" "$PACKAGE_SPDLOG"
}

#V8 needs this tool
function buildDepotTools() {
    source $PRESERVE_ENVARS

    printf -- "Start building depot tools .\n"
    if [ -d  $SOURCE_ROOT/depot_tools ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    cd $SOURCE_ROOT
    git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
    cd $SOURCE_ROOT/depot_tools
    git checkout a0382d39be0d7bf0f0766633185f20dcdd32a459
    echo "export PATH=$PATH:$SOURCE_ROOT/depot_tools/" >> $PRESERVE_ENVARS
    echo 'export VPYTHON_BYPASS="manually managed python not supported by chrome operations"' >> $PRESERVE_ENVARS
    echo "export DEPOT_TOOLS_UPDATE=0" >> $PRESERVE_ENVARS
}

#V8 needs this tool
function buildGn() {
    source $PRESERVE_ENVARS

    printf -- "Start building gn .\n"
    if [ -d  $SOURCE_ROOT/gn ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    cd $SOURCE_ROOT
    git clone https://gn.googlesource.com/gn
    cd gn
    git checkout 8948350

    if [ $DISTRO != suse12 ]; then
        sed -i -e 's/-Wl,--icf=all//g' ./build/gen.py
        sed -i -e 's/-lpthread/-pthread/g' ./build/gen.py
    fi

    python build/gen.py
    ninja -C out
    echo "export PATH=$SOURCE_ROOT/gn/out:$PATH" >> $PRESERVE_ENVARS
}

function buildV8() {
    buildDepotTools
    buildGn

    source $PRESERVE_ENVARS
    NAME_V8=v8
    VERSION_V8=8.3
    BUILD_V8=cb4
    PACKAGE_V8=$NAME_V8-$DISTRO-s390x-$VERSION_V8-$BUILD_V8

    printf -- "Start building %s .\n" "$PACKAGE_V8"
    if [ -d  $SOURCE_ROOT/$NAME_V8 ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    cd $SOURCE_ROOT
    sudo ldconfig /usr/local/lib64 /usr/local/lib

    cat >.gclient <<EOF
solutions = [
  {
    "url": "https://chromium.googlesource.com/v8/v8.git@8.3.110.9",
    "managed": False,
    "name": "v8",
    "deps_file": "DEPS",
  },
];
EOF
    gclient sync

    cd v8
    wget $PATCH_URL/v8.diff -P $SOURCE_ROOT/patch
    git apply $SOURCE_ROOT/patch/v8.diff

    V8_ARGS='is_component_build=true target_cpu="s390x" v8_target_cpu="s390x" use_goma=false goma_dir="None" v8_enable_backtrace=true treat_warnings_as_errors=false is_clang=false use_custom_libcxx_for_host=false use_custom_libcxx=false v8_use_external_startup_data=false  use_sysroot=false use_gold=false linux_use_bundled_binutils=false    v8_enable_pointer_compression=false'
    # build release
    gn gen out/s390x.release --args="$V8_ARGS is_debug=false"
    if [ $DISTRO == rhel7 ]; then
        sed -i '/libs =/s/$/ -lstdc++/'  out/s390x.release/obj/v8_hello_world.ninja
    fi
    LD_LIBRARY_PATH=$SOURCE_ROOT/v8/out/s390x.release ninja -C $SOURCE_ROOT/v8/out/s390x.release -j$(nproc)

    INSTALL_DIR=$(pwd)/_build
    mkdir -p \
        $INSTALL_DIR/lib/Release \
        $INSTALL_DIR/lib/Debug \
        $INSTALL_DIR/include/libplatform \
        $INSTALL_DIR/include/cppgc \
        $INSTALL_DIR/include/unicode
    (
        cd out/s390x.release
        cp -avi libv8*.* $INSTALL_DIR/lib/Release
        cp -avi libchrome*.* $INSTALL_DIR/lib/Release
        cp -avi libcppgc*.* $INSTALL_DIR/lib/Release
        cp -avi libicu*.* $INSTALL_DIR/lib/Release
        cp -avi icu*.* $INSTALL_DIR/lib/Release
        rm -f $INSTALL_DIR/lib/Release/*.TOC
        rm -f $INSTALL_DIR/lib/Release/*for_testing*
        rm -f $INSTALL_DIR/lib/Release/*debug_helper*
    )
    (
        cd include
        cp -avi v8*.h $INSTALL_DIR/include
        cp -avi libplatform/[a-z]*.h $INSTALL_DIR/include/libplatform
        cp -avi cppgc/* $INSTALL_DIR/include/cppgc
    )
    (
        cd third_party/icu/source/common/unicode
        cp -avi *.h $INSTALL_DIR/include/unicode
    )
    (
        cd third_party/icu/source/io/unicode
        cp -avi *.h $INSTALL_DIR/include/unicode
    )
    (
        cd third_party/icu/source/i18n/unicode
        cp -avi *.h $INSTALL_DIR/include/unicode
    )
    (
        cd third_party/icu/source/extra/uconv/unicode
        cp -avi *.h $INSTALL_DIR/include/unicode
    )

    cd _build
    cat <<EOF >CMakeLists.txt
FILE(MAKE_DIRECTORY \${CMAKE_INSTALL_PREFIX}/bin)

# Determine which directory to copy libs from
IF (CMAKE_BUILD_TYPE STREQUAL "Debug" AND
    IS_DIRECTORY "\${CMAKE_CURRENT_SOURCE_DIR}/lib/Debug")
    SET (LIB_DIR Debug)
ELSE()
    SET (LIB_DIR Release)
ENDIF ()

FILE (COPY lib/\${LIB_DIR}/
      DESTINATION "\${CMAKE_INSTALL_PREFIX}/lib"
      PATTERN .dat EXCLUDE)
FILE (COPY lib/\${LIB_DIR}/icudtb.dat DESTINATION "\${CMAKE_INSTALL_PREFIX}/bin")
FILE (COPY lib/\${LIB_DIR}/icudtl_extra.dat DESTINATION "\${CMAKE_INSTALL_PREFIX}/bin")
EOF
    # Packaging build files
    tar -czvf $PACKAGE_V8.tgz *
    MD5_V8=($(md5sum $PACKAGE_V8.tgz))
    echo $MD5_V8 >$PACKAGE_V8.md5
    # Copy the package to destination
    cp $PACKAGE_V8.* $CACHE_DIRECTORY

    printf -- "Finished building %s .\n" "$PACKAGE_V8"
}

function buildCouchbase() {
    source $PRESERVE_ENVARS
    set +e
    user_name=$(git config user.name)
    user_email=$(git config user.email)
    set -e
    if [ -z ${user_name} ] || [ -z ${user_email} ]; then
        printf -- 'Set up git user\n'
        git config --global user.email "tester@email"
        git config --global user.name "tester"
    fi

    mkdir -p $SOURCE_ROOT/couchbase
    cd $SOURCE_ROOT/couchbase
    repo init -u https://github.com/couchbase/manifest -m released/couchbase-server/7.1.1.xml
    repo sync

    sudo git config --system --add safe.directory '*'

    cd $SOURCE_ROOT/couchbase/tlm
    wget "${PATCH_URL}"/tlm.diff
    git apply tlm.diff
    git apply $SOURCE_ROOT/patch/tlm.diff

    cd $SOURCE_ROOT/couchbase/couchstore
    wget "${PATCH_URL}"/couchstore.diff
    git apply couchstore.diff
    git apply $SOURCE_ROOT/patch/couchstore.diff

    cd $SOURCE_ROOT/couchbase/kv_engine
    wget "${PATCH_URL}"/kv_engine.diff
    git apply kv_engine.diff
    git apply $SOURCE_ROOT/patch/kv_engine.diff

    cd $SOURCE_ROOT/couchbase/platform
    wget "${PATCH_URL}"/platform.diff
    git apply platform.diff
    git apply $SOURCE_ROOT/patch/platform.diff

    # replace icudtl with icudtb in couchdb with this command
    sed -i 's/icudtl/icudtb/g' $SOURCE_ROOT/couchbase/couchdb/src/mapreduce/CMakeLists.txt

    # add s390x to supported arches by replacing aarch64
    sed -i '272s/aarch64/s390x/g' $SOURCE_ROOT/couchbase/forestdb/src/arch.h

    if [[ $DISTRO == rhel* ]]; then
        sed -i "s/centos7/$DISTRO/g" $SOURCE_ROOT/couchbase/tlm/deps/manifest.cmake
    fi

    OPTIONS=""
    if [[ "$HAS_PREFIX" == "true" ]]; then
        OPTIONS+=" -DCMAKE_INSTALL_PREFIX=$CB_PREFIX"
    fi

    cd $SOURCE_ROOT/couchbase/
    sudo ldconfig /usr/local/lib64 /usr/local/lib
    make -j$(nproc) EXTRA_CMAKE_OPTIONS="$OPTIONS" build/Makefile
    sudo LD_LIBRARY_PATH=$CB_PREFIX/lib:$LD_LIBRARY_PATH CC=$CC CXX=$CXX make -j$(nproc) EXTRA_CMAKE_OPTIONS="$OPTIONS" everything
}

function runTest() {
  set +e
  cd $SOURCE_ROOT/couchbase/build
  if [[ "$TESTS" == "true" ]]; then
    printf -- '\nRunning Couchbase tests...\n'
    sudo ctest --timeout 1000
  fi
  set -e
}

# Print the usage message
function printHelp() {
  echo
  echo "Usage: "
  echo "bash build_couchdb.sh [-t install-with-tests] [-p <install_prefix>]"
  echo
}

function main() {
    printf -- "Start Distro specific preperation for %s\n" "$ID$VERSION_ID"
    case $ID$VERSION_ID in

    ubuntu20.04)
        prepareUB20
        ;;

    ubuntu18.04)
        prepareUB18
        ;;

    rhel8.4 | rhel8.6 | rhel8.7)
        prepareRHEL8
        ;;

    rhel7.8 | rhel7.9)
        prepareRHEL7
        installGCC
        installGit
        installNinja
        ;;

    sles12.5)
        prepareSUSE12
        ;;

    sles15.4)
        prepareSUSE15
        ;;

    *)
        printf -- "%s is not supported \n" "$ID$VERSION_ID"
        exit 1
        ;;
    esac

    printf -- "Building dependencies from source.\n"
    installGo
    installCmake
    installRepoTool
    installGflags
    buildBenchmark
    buildBoost
    buildCbpy
    buildCurl
    buildDconvertion
    buildErlang
    buildFbuf
    buildFmt
    buildSnappy
    buildOssl
    buildLibevent
    buildGlog
    buildZstd
    buildFolly
    buildGtest
    buildZlib
    buildGrpc
    buildJemalloc
    buildJson
    buildLiburing
    buildLibuv
    buildLz4
    buildNumctl
    buildPcre
    buildPrometheus
    buildPromcpp
    buildProtoc
    buildRock
    buildSpdlog
    buildV8
    printf -- "Finished Building dependencies from source.\n"

    printf -- "Building couchbase.\n"
    buildCouchbase

    runTest

    printf -- '\nRun following command to run couchbase server.\n'
    printf -- "\n    sudo $CB_PREFIX/bin/couchbase-server --start\n"
    printf -- '\nThe Couchbase UI can be viewed at http://hostname:8091\n'
    printf -- '\nFor more help visit https://docs.couchbase.com/home/server.html \n'
}

function printSystemDetails() {
  printf -- 'SYSTEM DETAILS\n'
  cat "/etc/os-release"
  cat /proc/version
  printf -- "\nDetected %s \n"  "$PRETTY_NAME"
  printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION"
}

while getopts "h?dytp:" opt; do
  case "$opt" in
    h | \?)
    printHelp
    exit 0
    ;;
    t)
    TESTS="true"
    ;;
    p)
    HAS_PREFIX="true"
    CB_PREFIX=${OPTARG}
    ;;
  esac
done

printSystemDetails  |&  tee -a "$LOG_FILE"
# main workflow process
main  |&  tee -a "$LOG_FILE"
