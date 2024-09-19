#!/bin/bash
# © Copyright IBM Corporation 2024.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Couchbase/7.6.2/build_couchbase.sh
# Execute build script: bash build_couchbase.sh  (provide -h for help)
#

set -e -o pipefail

PACKAGE_NAME="couchbase"
PACKAGE_VERSION="7.6.2"
DATE_AND_TIME="$(date +"%F-%T")"
SOURCE_ROOT=$(pwd)
LOG_FILE="$SOURCE_ROOT/${PACKAGE_NAME}-${PACKAGE_VERSION}-${DATE_AND_TIME}.log"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Couchbase/7.6.2/patch"

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

function prepareRHEL8() {
    source $PRESERVE_ENVARS
    printf -- "Installing dependencies from repository.\n"
    sudo subscription-manager repos --enable codeready-builder-for-rhel-8-s390x-rpms
    sudo subscription-manager repos --enable rhel-8-for-s390x-appstream-rpms
    sudo dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
    sudo yum install -y gcc-toolset-11 gcc-toolset-11-gcc gcc-toolset-11-gcc-c++ gcc-toolset-11-libatomic-devel gcc-toolset-11-libstdc++-devel
    sudo ln -sf /opt/rh/gcc-toolset-11/root/usr/bin/gcc /usr/local/bin/gcc
    sudo ln -sf /opt/rh/gcc-toolset-11/root/usr/bin/g++ /usr/local/bin/g++
    sudo yum install -y atk-devel autoconf automake binutils-devel bison bzip2 ccache \
        cmake cups-devel flex git gnome-keyring libcurl-devel langpacks-en glibc-all-langpacks \
        libev-devel libtool make ncurses-devel ninja-build openssl-devel perl openssl-perl libpsl-devel\
        python2 python38 python38-devel python38-pip python3-httplib2 tar texinfo unzip wget which xz xz-devel \
        glib2-devel clang diffutils procps asciidoctor

    sudo ln -sf /usr/bin/python3 /usr/bin/python
    sudo ln -sf /opt/rh/gcc-toolset-11/root/usr/bin/as /usr/bin/as
    pip3 install httplib2 --user
    echo 'export CC=/opt/rh/gcc-toolset-11/root/usr/bin/gcc' >> $PRESERVE_ENVARS
    echo 'export CXX=/opt/rh/gcc-toolset-11/root/usr/bin/g++' >> $PRESERVE_ENVARS
    echo "export PATH=/opt/rh/gcc-toolset-11/root/usr/bin:$PATH" >> $PRESERVE_ENVARS
    echo "export LANG=en_US.UTF-8" >> $PRESERVE_ENVARS
}

function prepareRHEL9() {
    printf -- "Installing dependencies from repository.\n"
    sudo subscription-manager repos --enable codeready-builder-for-rhel-9-s390x-rpms
    sudo subscription-manager repos --enable rhel-9-for-s390x-appstream-rpms
    sudo dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
    sudo yum install -y gcc gcc-c++ atk-devel autoconf automake binutils-devel bison bzip2 perl \
        cmake cups-devel flex git gnome-keyring libcurl-devel langpacks-en glibc-all-langpacks ccache \
        libtool make ncurses-devel ninja-build openssl-devel openssl-perl perl-core libpsl-devel \
        python3 python3-devel tar texinfo unzip wget which xz xz-devel glib2-devel clang compat-openssl11 python3-httplib2 asciidoctor

    sudo ln -sf /usr/bin/python3 /usr/bin/python
    sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
    sudo ldconfig
}

function prepareSUSE15() {
    sudo zypper install -y asciidoc autoconf automake cmake curl flex \
        gcc gcc-c++ gcc10-c++ gcc10 git-core glib2 glib2-devel \
        libopenssl-devel libncurses6 xz glibc-locale bzip2 ccache\
        libtirpc-devel libtool libxml2-tools libxslt-tools binutils-devel\
        make makedepend ncurses-devel ninja patch pkg-config libpsl-devel\
        python311 python-xml python3-httplib2 re2c ruby sqlite3 tar \
        unixODBC wget which xinetd xmlto python311-pip python311-devel

    sudo ln -sf /usr/bin/python3.11 /usr/bin/python3
    sudo ln -sf /usr/bin/python3 /usr/bin/python
    pip3 install pyparsing
    pip3 install httplib2 --user

    sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-10 10
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-10 10
    sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-10 10
    sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-10 10
    sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc

    echo 'export CC=/usr/bin/gcc' >> $PRESERVE_ENVARS
    echo 'export CXX=/usr/bin/g++' >> $PRESERVE_ENVARS
    echo "export LANG=en_US.UTF-8" >> $PRESERVE_ENVARS
}

function prepareUB20() {
    printf -- "Installing dependencies from repository.\n"
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive TZ=America/Toronto apt-get install -y \
        autoconf automake autotools-dev binutils-dev bison ccache cmake curl flex \
        git libssl-dev ncurses-dev ninja-build python3 locales locales-all libpsl-dev \
        python3-httplib2 python3-six pkg-config re2c texinfo tzdata unzip wget \
        g++-10 gcc-10 gcc-10-multilib g++-10-multilib libglib2.0-dev libtool

    sudo ln -sf /usr/bin/python3 /usr/bin/python
    echo "export LANG=en_US.UTF-8" >> $PRESERVE_ENVARS
    echo "export CC=gcc" >> $PRESERVE_ENVARS
    echo "export CXX=g++" >> $PRESERVE_ENVARS

    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-10 10
    sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-10 10
}

function prepareUB22() {
    printf -- "Installing dependencies from repository.\n"
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive TZ=America/Toronto apt-get install -y \
        autoconf automake autotools-dev binutils-dev bison ccache cmake curl flex \
        git libssl-dev ncurses-dev ninja-build python3 locales locales-all libpsl-dev \
        python3-httplib2 python3-six pkg-config re2c texinfo tzdata unzip wget \
        g++-11 gcc-11 gcc-11-multilib g++-11-multilib libglib2.0-dev libtool

    sudo ln -sf /usr/bin/python3 /usr/bin/python
    echo "export LANG=en_US.UTF-8" >> $PRESERVE_ENVARS
    echo "export CC=gcc" >> $PRESERVE_ENVARS
    echo "export CXX=g++" >> $PRESERVE_ENVARS

    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-11 11
    sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-11 11
}

function installGo() {
    source $PRESERVE_ENVARS
    printf -- "Start building golang.\n"
    if command -v "go" >/dev/null; then
        printf -- "Golang already exists.\n"
        return 0
    fi

    cd $SOURCE_ROOT
    wget https://go.dev/dl/go1.22.2.linux-s390x.tar.gz
    chmod ugo+r go1.22.2.linux-s390x.tar.gz
    sudo tar -C /usr/local -xzf go1.22.2.linux-s390x.tar.gz
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
        if [ ${CMAKE_VERSION[2]} == 3.27.4 ]; then
            printf -- "Cmake already exists.\n"
            return 0
        fi
    fi

    cd $SOURCE_ROOT
    rm -rdf cmake-3.27.4
    wget --no-check-certificate https://cmake.org/files/v3.27/cmake-3.27.4.tar.gz
    tar -xzf cmake-3.27.4.tar.gz
    cd cmake-3.27.4
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
    wget --no-check-certificate https://github.com/gflags/gflags/archive/refs/tags/v$version.tar.gz
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
    VERSION_BENCHMARK=v1.6.2
    BUILD_BENCHMARK=cb2
    PACKAGE_BENCHMARK=$NAME_BENCHMARK-linux-s390x-$VERSION_BENCHMARK-$BUILD_BENCHMARK

    printf -- "Start building %s .\n" "$PACKAGE_BENCHMARK"
    if [ -d  $SOURCE_ROOT/$NAME_BENCHMARK ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    cd $SOURCE_ROOT
    git clone -b $VERSION_BENCHMARK --depth 1 https://github.com/couchbasedeps/benchmark.git
    cd benchmark
    cmake -D CMAKE_INSTALL_PREFIX=$(pwd)/_build -D CMAKE_BUILD_TYPE=RelWithDebInfo -D CMAKE_INSTALL_LIBDIR=lib -D CMAKE_CXX_STANDARD=17 -D CMAKE_CXX_STANDARD_REQUIRED=ON -D BUILD_SHARED_LIBS=OFF -D BENCHMARK_ENABLE_TESTING=OFF -D BENCHMARK_ENABLE_GTEST_TESTS=OFF -D BENCHMARK_ENABLE_INSTALL=ON -D BENCHMARK_DOWNLOAD_DEPENDENCIES=OFF
    cmake --build . --target install
    cmake -E remove_directory ./_build/lib/pkgconfig
    cd _build
    # Packaging build files
    tar -czvf $PACKAGE_BENCHMARK.tgz *
    MD5_BENCHMARK=($(md5sum $PACKAGE_BENCHMARK.tgz))
    echo $MD5_BENCHMARK > $PACKAGE_BENCHMARK.md5
    # Copy the package to destination
    cp $PACKAGE_BENCHMARK.* $CACHE_DIRECTORY

    printf -- "Finished building %s .\n" "$PACKAGE_BENCHMARK"
}

function buildBoost() {
    source $PRESERVE_ENVARS
    NAME_BOOST=boost
    VERSION_BOOST=1.82.0
    BUILD_BOOST=cb1
    PACKAGE_BOOST=$NAME_BOOST-linux-s390x-$VERSION_BOOST-$BUILD_BOOST

    printf -- "Start building %s .\n" "$PACKAGE_BOOST"
    if [ -d  $SOURCE_ROOT/boost_1_82_0 ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    sudo ldconfig /usr/local/lib64 /usr/local/lib
    cd $SOURCE_ROOT
    TOOLSET=gcc
    URL=https://boostorg.jfrog.io/artifactory/main/release/$VERSION_BOOST/source/boost_1_82_0.tar.gz
    curl -sSL $URL | tar xzf -
    cd boost_1_82_0
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
    VERSION_CBPY=3.11.8
    BUILD_CBPY=2
    PACKAGE_CBPY=$NAME_CBPY-linux-s390x-$VERSION_CBPY-$BUILD_CBPY

    printf -- "Start building %s .\n" "$PACKAGE_CBPY"
    if [ -d  $SOURCE_ROOT/$NAME_CBPY ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    cd $SOURCE_ROOT
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source $HOME/.cargo/env

    cd $SOURCE_ROOT
    wget --no-check-certificate https://repo.anaconda.com/miniconda/Miniconda3-py311_23.5.0-3-Linux-s390x.sh
    chmod a+x Miniconda3-py311_23.5.0-3-Linux-s390x.sh
    ./Miniconda3-py311_23.5.0-3-Linux-s390x.sh -b -p ./cbpy
    cd cbpy
    ./bin/pip3 install msgpack-python
    ./bin/pip3 install natsort
    ./bin/pip3 install pem
    ./bin/pip3 install pycryptodome
    ./bin/pip3 install python-snappy
    ./bin/pip3 install requests
    ./bin/pip3 install cryptography==38.0.4
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
    VERSION_CURL=8.6.0
    BUILD_CURL=1
    PACKAGE_CURL=$NAME_CURL-linux-s390x-$VERSION_CURL-$BUILD_CURL

    printf -- "Start building %s .\n" "$PACKAGE_CURL"
    if [ -d  $SOURCE_ROOT/$NAME_CURL ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi


    cd $SOURCE_ROOT
    sudo ldconfig /usr/local/lib64 /usr/local/lib
    git clone -b curl-8_6_0 --depth 1 https://github.com/curl/curl.git
    cd curl
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
    echo "$VERSION_CURL-$BUILD_CURL" >VERSION.txt
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
    BUILD_DCONVERTION=cb6
    PACKAGE_DCONVERTION=$NAME_DCONVERTION-linux-s390x-$VERSION_DCONVERTION-$BUILD_DCONVERTION

    printf -- "Start building %s .\n" "$PACKAGE_DCONVERTION"
    if [ -d  $SOURCE_ROOT/$NAME_DCONVERTION ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    cd $SOURCE_ROOT
    git clone -b v$VERSION_DCONVERTION --depth 1 https://github.com/google/double-conversion.git
    cd double-conversion
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
    VERSION_ERLANG=25.3
    BUILD_ERLANG=11
    PACKAGE_ERLANG=$NAME_ERLANG-linux-s390x-$VERSION_ERLANG-$BUILD_ERLANG

    printf -- "Start building %s .\n" "$PACKAGE_ERLANG"
    if [ -d  $SOURCE_ROOT/$NAME_ERLANG ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi


    cd $SOURCE_ROOT
    git clone -b couchbase-$VERSION_ERLANG --depth 1 https://github.com/couchbasedeps/erlang.git
    cd erlang
    ./configure --prefix=$(pwd)/_build \
            --libdir=$(pwd)/_build/lib \
            --enable-smp-support \
            --disable-hipe \
            --disable-fp-exceptions \
            --without-javac \
            --enable-m64-build \
            CFLAGS="-fno-strict-aliasing -O3 -ggdb3"
    make -j$(nproc)
    make install
    hash -r
    cd _build
    echo $VERSION_ERLANG >VERSION.txt
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
    VERSION_FBUF=v1.10.0
    BUILD_FBUF=cb7
    PACKAGE_FBUF=$NAME_FBUF-linux-s390x-$VERSION_FBUF-$BUILD_FBUF

    printf -- "Start building %s .\n" "$PACKAGE_FBUF"
    if [ -d  $SOURCE_ROOT/$NAME_FBUF ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi


    cd $SOURCE_ROOT
    git clone -b $VERSION_FBUF --depth 1 https://github.com/google/flatbuffers
    cd flatbuffers
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
    VERSION_FMT=8.1.1
    BUILD_FMT=cb4
    PACKAGE_FMT=$NAME_FMT-linux-s390x-$VERSION_FMT-$BUILD_FMT

    printf -- "Start building %s .\n" "$PACKAGE_FMT"
    if [ -d  $SOURCE_ROOT/$NAME_FMT ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    cd $SOURCE_ROOT
    git clone -b $VERSION_FMT --depth 1 https://github.com/fmtlib/fmt.git
    cd fmt
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
    VERSION_SNAPPY=1.1.10
    BUILD_SNAPPY=cb2
    PACKAGE_SNAPPY=$NAME_SNAPPY-linux-s390x-$VERSION_SNAPPY-$BUILD_SNAPPY

    printf -- "Start building %s .\n" "$PACKAGE_SNAPPY"
    if [ -d  $SOURCE_ROOT/snappy ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    cd $SOURCE_ROOT
    git clone -b $VERSION_SNAPPY --depth 1 https://github.com/google/snappy.git
    cd snappy
    wget --no-check-certificate https://raw.githubusercontent.com/couchbase/tlm/7.6.2/deps/packages/snappy/snappy.patch
    git apply snappy.patch
    cmake -D CMAKE_INSTALL_PREFIX=$(pwd)/_build \
        -D SNAPPY_BUILD_TESTS=OFF \
        -D BUILD_SHARED_LIBS=ON \
        -D CMAKE_INSTALL_LIBDIR=lib \
        -D SNAPPY_BUILD_BENCHMARKS=OFF .
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
    VERSION_OSSL=3.1.4
    BUILD_OSSL=1
    PACKAGE_OSSL=$NAME_OSSL-linux-s390x-$VERSION_OSSL-$BUILD_OSSL

    printf -- "Start building %s .\n" "$PACKAGE_OSSL"
    if [ -d  $SOURCE_ROOT/$NAME_OSSL-$VERSION_OSSL ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi


    cd $SOURCE_ROOT
    wget --no-check-certificate https://github.com/openssl/openssl/releases/download/openssl-$VERSION_OSSL/openssl-$VERSION_OSSL.tar.gz
    tar -xzf openssl-$VERSION_OSSL.tar.gz
    cd openssl-$VERSION_OSSL
    ./config --prefix=$(pwd)/_build --openssldir=$(pwd)/_build/etc/openssl --libdir=$(pwd)/_build/lib
    make -j$(nproc)
    make install
    hash -r
    cd _build
    echo "$VERSION_OSSL-$BUILD_OSSL" >VERSION.txt
    cat <<EOF >CMakeLists.txt
FILE (COPY bin DESTINATION "\${CMAKE_INSTALL_PREFIX}")
FILE (COPY lib DESTINATION "\${CMAKE_INSTALL_PREFIX}")
FILE (COPY etc DESTINATION "\${CMAKE_INSTALL_PREFIX}")
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
    BUILD_LIBEVENT=cb12
    PACKAGE_LIBEVENT=$NAME_LIBEVENT-linux-s390x-$VERSION_LIBEVENT-$BUILD_LIBEVENT

    printf -- "Start building %s .\n" "$PACKAGE_LIBEVENT"
    if [ -d  $SOURCE_ROOT/$NAME_LIBEVENT ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    OPENSSL_BUILD=$SOURCE_ROOT/openssl-3.1.4/_build

    cd $SOURCE_ROOT
    git clone -b release-$VERSION_LIBEVENT-stable --depth 1 https://github.com/libevent/libevent.git
    cd libevent

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
    BUILD_GLOG=cb3
    PACKAGE_GLOG=$NAME_GLOG-linux-s390x-$VERSION_GLOG-$BUILD_GLOG

    printf -- "Start building %s .\n" "$PACKAGE_GLOG"
    if [ -d  $SOURCE_ROOT/$NAME_GLOG ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi


    cd $SOURCE_ROOT
    git clone -b $VERSION_GLOG --depth 1 https://github.com/google/glog.git
    cd glog
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
    BUILD_ZSTD=4
    PACKAGE_ZSTD=$NAME_ZSTD-linux-s390x-$VERSION_ZSTD-$BUILD_ZSTD

    printf -- "Start building %s .\n" "$PACKAGE_ZSTD"
    if [ -d  $SOURCE_ROOT/zstd-$VERSION_ZSTD ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi


    cd $SOURCE_ROOT
    wget --no-check-certificate https://github.com/facebook/zstd/archive/refs/tags/v$VERSION_ZSTD.tar.gz
    tar -xzvf v$VERSION_ZSTD.tar.gz
    cd zstd-$VERSION_ZSTD
    make DESTDIR=$(pwd)/_build install
    cd _build
    cp -r ./usr/local/* . && rm -drf usr bin share
    echo "${VERSION_ZSTD}-4" >VERSION.txt
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

function setGitGlobalConfig() {
    user_name=$(git config user.name)
    user_email=$(git config user.email)
    set -e
    if [ -z ${user_name} ] || [ -z ${user_email} ]; then
        printf -- 'Set up git user\n'
        git config --global user.email "tester@email"
        git config --global user.name "tester"
    fi
}

function buildFolly() {
    buildJemalloc
    source $PRESERVE_ENVARS
    NAME_FOLLY=folly
    VERSION_FOLLY=v2022.05.23.00-couchbase
    BUILD_FOLLY=cb15
    PACKAGE_FOLLY=$NAME_FOLLY-linux-s390x-$VERSION_FOLLY-$BUILD_FOLLY

    printf -- "Start building %s .\n" "$PACKAGE_FOLLY"
    if [ -d  $SOURCE_ROOT/$NAME_FOLLY ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    JEMALLOC_BUILD=$SOURCE_ROOT/jemalloc/_build
    FMT_BUILD=$SOURCE_ROOT/fmt/_build
    GLOG_BUILD=$SOURCE_ROOT/glog/_build
    BOOST_BUILD=$SOURCE_ROOT/boost_1_82_0/_build
    DOUBLE_CONVERSION_BUILD=$SOURCE_ROOT/double-conversion/_build
    LIBEVENT_BUILD=$SOURCE_ROOT/libevent/_build
    OPENSSL_BUILD=$SOURCE_ROOT/openssl-3.1.4/_build
    SNAPPY_BUILD=$SOURCE_ROOT/snappy/_build
    ZSTD_BUILD=$SOURCE_ROOT/zstd-1.5.0/_build

    LIBRARIES="$JEMALLOC_BUILD/lib;$FMT_BUILD/lib;$GLOG_BUILD/lib;$BOOST_BUILD/lib;$DOUBLE_CONVERSION_BUILD/lib;$LIBEVENT_BUILD/lib;$OPENSSL_BUILD/lib;$SNAPPY_BUILD/lib;$ZSTD_BUILD/lib;"
    INCLUDES="$JEMALLOC_BUILD/include;$FMT_BUILD/include;$GLOG_BUILD/include;$BOOST_BUILD/include;$DOUBLE_CONVERSION_BUILD/include;$LIBEVENT_BUILD/include;$OPENSSL_BUILD/include;$SNAPPY_BUILD/include;$ZSTD_BUILD/include"

    cd $SOURCE_ROOT
    git clone -b $VERSION_FOLLY --depth 1 https://github.com/couchbasedeps/folly.git
    cd folly
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
        -D Boost_ADDITIONAL_VERSIONS=1.82 \
        -D Boost_USE_STATIC_LIBS=ON \
        -D Boost_NO_SYSTEM_PATHS=ON \
        -D Boost_NO_BOOST_CMAKE=ON \
        -D BOOST_ROOT=$BOOST_BUILD \
        -D CMAKE_PREFIX_PATH=$FMT_BUILD \
        -D CMAKE_DISABLE_FIND_PACKAGE_ZLIB=TRUE .

    make -j$(nproc)
    make install
    cd _build
    echo "${VERSION_FOLLY}-${BUILD_FOLLY}" >VERSION.txt
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
    VERSION_GTEST=1.14.0
    BUILD_GTEST=cb1
    PACKAGE_GTEST=$NAME_GTEST-linux-s390x-$VERSION_GTEST-$BUILD_GTEST

    printf -- "Start building %s .\n" "$PACKAGE_GTEST"
    if [ -d  $SOURCE_ROOT/$NAME_GTEST ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi


    cd $SOURCE_ROOT
    git clone -b v$VERSION_GTEST --depth 1 https://github.com/google/googletest.git
    cd googletest
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
    VERSION_ZLIB=1.2.13
    BUILD_ZLIB=2
    PACKAGE_ZLIB=$NAME_ZLIB-linux-s390x-$VERSION_ZLIB-$BUILD_ZLIB

    printf -- "Start building %s .\n" "$PACKAGE_ZLIB"
    if [ -d  $SOURCE_ROOT/$NAME_ZLIB ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi


    cd $SOURCE_ROOT
    git clone -b v$VERSION_ZLIB --depth 1 https://github.com/madler/zlib.git
    cd zlib

    ./configure --prefix=$(pwd)/_build --64
    make -j$(nproc)
    make install
    cd _build
    echo "${VERSION_ZLIB}-2" >VERSION.txt
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
    VERSION_GRPC=1.59.3
    BUILD_GRPC=cb1
    PACKAGE_GRPC=$NAME_GRPC-linux-s390x-$VERSION_GRPC-$BUILD_GRPC

    printf -- "Start building %s .\n" "$PACKAGE_GRPC"
    if [ -d  $SOURCE_ROOT/$NAME_GRPC ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi


    cd $SOURCE_ROOT
    git clone -b v$VERSION_GRPC https://github.com/grpc/grpc
    cd grpc/
    git submodule update --init --recursive

    if [ $ID$VERSION_ID == "ubuntu22.04" ] || [ $ID$VERSION_ID == "rhel9.2" ] || [ $ID$VERSION_ID == "rhel9.4" ]; then
        sed -i '59i #undef SIGSTKSZ' third_party/abseil-cpp/absl/debugging/failure_signal_handler.cc
        sed -i '60i #define SIGSTKSZ 16384' third_party/abseil-cpp/absl/debugging/failure_signal_handler.cc
    fi
    if [ $ID$VERSION_ID == "rhel9.2" ] || [ $ID$VERSION_ID == "rhel9.4" ]; then
        sed -i '20i #include <limits>' third_party/abseil-cpp/absl/flags/usage_config.cc
    fi
    BUILD_DIR=$(pwd)/_build
    # Point to zlib build file.
    ZLIB_BUILD_DIR=$SOURCE_ROOT/zlib/_build
    # Point to OpenSSL build file.
    OPENSSL_BUILD_DIR=$SOURCE_ROOT/openssl-3.1.4/_build
    (
        cd third_party/abseil-cpp
        cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo \
            -DCMAKE_INSTALL_PREFIX="$BUILD_DIR" .
         make -j$(nproc) install
    )
    (
        cd third_party/protobuf
        CXXFLAGS="-fcommon" cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo \
            -DCMAKE_INSTALL_PREFIX="$BUILD_DIR" \
            -Dprotobuf_BUILD_TESTS=OFF \
            -Dprotobuf_ABSL_PROVIDER=package \
            -DCMAKE_PREFIX_PATH="$BUILD_DIR" \
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
    (
        cd third_party/re2
        cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo \
            -DCMAKE_INSTALL_PREFIX="$BUILD_DIR" .
        make -j$(nproc) install
    )
    cmake -D CMAKE_BUILD_TYPE=RelWithDebInfo \
        -D CMAKE_INSTALL_PREFIX=$BUILD_DIR \
        -D CMAKE_PREFIX_PATH="$ZLIB_BUILD_DIR;$OPENSSL_BUILD_DIR;$BUILD_DIR" \
        -DgRPC_INSTALL=ON \
        -DgRPC_BUILD_TESTS=OFF \
        -DgRPC_ABSL_PROVIDER=package     \
        -DgRPC_PROTOBUF_PROVIDER=package \
        -DgRPC_ZLIB_PROVIDER=package \
        -DgRPC_CARES_PROVIDER=package \
        -DgRPC_RE2_PROVIDER=package  \
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
    VERSION_JEMALLOC=5.3.0
    BUILD_JEMALLOC=13
    PACKAGE_JEMALLOC=$NAME_JEMALLOC-linux-s390x-$VERSION_JEMALLOC-$BUILD_JEMALLOC

    printf -- "Start building %s .\n" "$PACKAGE_JEMALLOC"
    if [ -d  $SOURCE_ROOT/$NAME_JEMALLOC ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi


    cd $SOURCE_ROOT
    git clone -b $VERSION_JEMALLOC --depth 1 https://github.com/couchbasedeps/jemalloc.git
    cd jemalloc
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

    configure_args="--prefix=$(pwd)/_build \
   --with-jemalloc-prefix=je_ \
   --enable-debug \
   --disable-cache-oblivious \
   --disable-zone-allocator \
   --disable-initial-exec-tls \
   --disable-cxx \
   --enable-prof \
   --with-install-suffix=d \
   --libdir=$(pwd)/_build/lib"

    CFLAGS=-Og ./autogen.sh ${configure_args}
    make -j8 build_lib_shared
    make -j8 check
    make install_lib_shared

    cd _build
    cat <<EOF >CMakeLists.txt
FILE (COPY bin/jeprof DESTINATION "\${CMAKE_INSTALL_PREFIX}/bin")
FILE (COPY lib DESTINATION "\${CMAKE_INSTALL_PREFIX}")
SET_PROPERTY (GLOBAL APPEND PROPERTY CBDEPS_PREFIX_PATH "\${CMAKE_CURRENT_SOURCE_DIR}")
EOF
    mkdir -p cmake && cd cmake
    wget https://raw.githubusercontent.com/couchbase/build-tools/master/cbdeps/jemalloc/package/cmake/JemallocConfig.cmake

    cd $SOURCE_ROOT/jemalloc/_build
    # Packaging build files
    tar -czvf $PACKAGE_JEMALLOC.tgz *
    MD5_JEMALLOC=($(md5sum $PACKAGE_JEMALLOC.tgz))
    echo $MD5_JEMALLOC >$PACKAGE_JEMALLOC.md5
    # Copy the package to destination
    cp $PACKAGE_JEMALLOC.* $CACHE_DIRECTORY

    printf -- "Finished building %s .\n" "$PACKAGE_JEMALLOC"
}

function buildJemalloc_noprefix() {
    source $PRESERVE_ENVARS
    NAME_JEMALLOC=jemalloc_noprefix
    VERSION_JEMALLOC=5.2.1
    BUILD_JEMALLOC=11
    PACKAGE_JEMALLOC=$NAME_JEMALLOC-linux-s390x-$VERSION_JEMALLOC-$BUILD_JEMALLOC

    printf -- "Start building %s .\n" "$PACKAGE_JEMALLOC"
    if [ -d  $SOURCE_ROOT/$NAME_JEMALLOC ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi


    cd $SOURCE_ROOT
    git clone -b $VERSION_JEMALLOC --depth 1 https://github.com/couchbasedeps/jemalloc.git jemalloc_noprefix
    cd jemalloc_noprefix
    configure_args="--prefix=$(pwd)/_build \
   --with-jemalloc-prefix= \
   --with-install-suffix=_noprefix \
   --enable-prof \
   --libdir=$(pwd)/_build/lib"

    ./autogen.sh ${configure_args}
    make -j8 build_lib_shared
    make -j8 check
    make install_lib_shared install_include install_bin

    configure_args="--prefix=$(pwd)/_build \
   --with-jemalloc-prefix= \
   --enable-debug \
   --with-install-suffix=_noprefix \
   --enable-prof \
   --with-install-suffix=_noprefixd \
   --libdir=$(pwd)/_build/lib"

    CFLAGS=-Og ./autogen.sh ${configure_args}
    make -j8 build_lib_shared
    make -j8 check
    make install_lib_shared

    cd _build
    cat <<EOF >CMakeLists.txt
FILE (COPY bin/jeprof DESTINATION "\${CMAKE_INSTALL_PREFIX}/bin")
FILE (COPY lib DESTINATION "\${CMAKE_INSTALL_PREFIX}")
SET_PROPERTY (GLOBAL APPEND PROPERTY CBDEPS_PREFIX_PATH "\${CMAKE_CURRENT_SOURCE_DIR}")
EOF

    mkdir -p cmake && cd cmake
    wget https://raw.githubusercontent.com/couchbase/build-tools/master/cbdeps/jemalloc_noprefix/package/cmake/Jemalloc_NoprefixConfig.cmake 

    cd $SOURCE_ROOT/jemalloc_noprefix/_build
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
    VERSION_JSON=3.11.2
    BUILD_JSON=cb1
    PACKAGE_JSON=$NAME_JSON-linux-s390x-$VERSION_JSON-$BUILD_JSON

    printf -- "Start building %s .\n" "$PACKAGE_JSON"
    if [ -d  $SOURCE_ROOT/$NAME_JSON ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi


    cd $SOURCE_ROOT
    git clone -b v$VERSION_JSON --depth 1 https://github.com/nlohmann/json
    cd $SOURCE_ROOT/json
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
    BUILD_LIBURING=3
    PACKAGE_LIBURING=$NAME_LIBURING-linux-s390x-$VERSION_LIBURING-$BUILD_LIBURING

    printf -- "Start building %s .\n" "$PACKAGE_LIBURING"
    if [ -d  $SOURCE_ROOT/$NAME_LIBURING ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi


    cd $SOURCE_ROOT
    git clone https://github.com/axboe/liburing.git
    cd liburing
    set +e
    git checkout liburing-$VERSION_LIBURING
    if [[ $DISTRO != rhel8* ]]; then
        setGitGlobalConfig
        git cherry-pick 8aac320ae8445c5434ab3be1761414a5247e5d42
    fi
    set -e
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
    BUILD_LIBUV=23
    PACKAGE_LIBUV=$NAME_LIBUV-linux-s390x-$VERSION_LIBUV-$BUILD_LIBUV

    printf -- "Start building %s .\n" "$PACKAGE_LIBUV"
    if [ -d  $SOURCE_ROOT/$NAME_LIBUV ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi


    cd $SOURCE_ROOT
    git clone -b v$VERSION_LIBUV --depth 1 https://github.com/couchbasedeps/libuv
    cd libuv
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
    BUILD_LZ4=cb5
    PACKAGE_LZ4=$NAME_LZ4-linux-s390x-$VERSION_LZ4-$BUILD_LZ4

    printf -- "Start building %s .\n" "$PACKAGE_LZ4"
    if [ -d  $SOURCE_ROOT/$NAME_LZ4-$VERSION_LZ4 ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    cd $SOURCE_ROOT
    wget --no-check-certificate https://github.com/lz4/lz4/archive/refs/tags/v$VERSION_LZ4.tar.gz
    tar -xzf v$VERSION_LZ4.tar.gz
    cd lz4-$VERSION_LZ4
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
    BUILD_NUMCTL=cb4
    PACKAGE_NUMCTL=$NAME_NUMCTL-linux-s390x-$VERSION_NUMCTL-$BUILD_NUMCTL

    printf -- "Start building %s .\n" "$PACKAGE_NUMCTL"
    if [ -d  $SOURCE_ROOT/$NAME_NUMCTL ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    cd $SOURCE_ROOT
    # v2.0.11 doesn't work on some distros
    git clone -b v2.0.14 --depth 1 https://github.com/numactl/numactl.git
    cd numactl
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
    BUILD_PCRE=cb3
    PACKAGE_PCRE=$NAME_PCRE-linux-s390x-$VERSION_PCRE-$BUILD_PCRE

    printf -- "Start building %s .\n" "$PACKAGE_PCRE"
    if [ -d  $SOURCE_ROOT/$NAME_PCRE-$VERSION_PCRE ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi


    cd $SOURCE_ROOT
    wget --no-check-certificate https://sourceforge.net/projects/pcre/files/pcre/$VERSION_PCRE/pcre-$VERSION_PCRE.tar.gz
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
    VERSION_PROM=2.45.0
    BUILD_PROM=6
    PACKAGE_PROM=$NAME_PROM-linux-s390x-$VERSION_PROM-$BUILD_PROM

    printf -- "Start building %s .\n" "$PACKAGE_PROM"
    if [ -d  $GOPATH/src/github.com/$NAME_PROM ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    cd $SOURCE_ROOT
    wget --no-check-certificate https://nodejs.org/dist/v20.15.0/node-v20.15.0-linux-s390x.tar.xz
    tar xf node-v20.15.0-linux-s390x.tar.xz
    export PATH=$SOURCE_ROOT/node-v20.15.0-linux-s390x/bin:$PATH
    echo "export PATH=$SOURCE_ROOT/node-v20.15.0-linux-s390x/bin:$PATH" >> $PRESERVE_ENVARS
    npm install -g yarn
    mkdir -p $GOPATH/src/github.com
    cd $GOPATH/src/github.com
    git clone -b v$VERSION_PROM --depth 1 https://github.com/couchbasedeps/prometheus.git
    cd prometheus
    make build
    mkdir -p _build/bin && cp prometheus _build/bin && cd _build
    echo "${VERSION_PROM}-${BUILD_PROM}" >VERSION.txt
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
    VERSION_PROMCPP=v1.2.1-couchbase
    BUILD_PROMCPP=cb1
    PACKAGE_PROMCPP=$NAME_PROMCPP-linux-s390x-$VERSION_PROMCPP-$BUILD_PROMCPP

    printf -- "Start building %s .\n" "$PACKAGE_PROMCPP"
    if [ -d  $SOURCE_ROOT/$NAME_PROMCPP ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    # Point to zlib build file.
    ZLIB_BUILD_DIR=$SOURCE_ROOT/zlib/_build

    cd $SOURCE_ROOT
    git clone -b $VERSION_PROMCPP --depth 1 https://github.com/couchbasedeps/prometheus-cpp.git
    cd prometheus-cpp
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
    BUILD_PROTOC=7
    PACKAGE_PROTOC=$NAME_PROTOC-linux-s390x-$VERSION_PROTOC-$BUILD_PROTOC

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

function buildSpdlog() {
    source $PRESERVE_ENVARS
    NAME_SPDLOG=spdlog
    VERSION_SPDLOG=v1.10.0
    BUILD_SPDLOG=cb6
    PACKAGE_SPDLOG=$NAME_SPDLOG-linux-s390x-$VERSION_SPDLOG-$BUILD_SPDLOG

    printf -- "Start building %s .\n" "$PACKAGE_SPDLOG"
    if [ -d  $SOURCE_ROOT/$NAME_SPDLOG ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    cd $SOURCE_ROOT
    # Point to fmt build file.
    FMT_BUILD_DIR=$SOURCE_ROOT/fmt/_build
    git clone -b $VERSION_SPDLOG --depth 1 https://github.com/gabime/spdlog.git
    cd spdlog
    wget --no-check-certificate https://raw.githubusercontent.com/couchbase/tlm/7.6.2/deps/packages/spdlog/custom_level_names.patch
    git apply custom_level_names.patch
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

function buildLibsodium() {
    source $PRESERVE_ENVARS
    NAME_LIBSODIUM=libsodium
    VERSION_LIBSODIUM=1.0.18
    BUILD_LIBSODIUM=5
    PACKAGE_LIBSODIUM=$NAME_LIBSODIUM-linux-s390x-$VERSION_LIBSODIUM-$BUILD_LIBSODIUM

    printf -- "Start building %s .\n" "$PACKAGE_LIBSODIUM"
    if [ -d  $SOURCE_ROOT/$NAME_LIBSODIUM ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    cd $SOURCE_ROOT
    git clone -b $VERSION_LIBSODIUM --depth 1 https://github.com/jedisct1/libsodium.git
    cd libsodium
    ./autogen.sh
    ./configure --prefix=$(pwd)/_build --libdir=$(pwd)/_build/lib
    make -j$(nproc)
    make install
    cd _build
    cat <<EOF >CMakeLists.txt
FILE (COPY lib DESTINATION "\${CMAKE_INSTALL_PREFIX}")
EOF
    # Packaging build files
    tar -czvf $PACKAGE_LIBSODIUM.tgz *
    MD5_LIBSODIUM=($(md5sum $PACKAGE_LIBSODIUM.tgz))
    echo $MD5_LIBSODIUM >$PACKAGE_LIBSODIUM.md5
    # Copy the package to destination
    cp $PACKAGE_LIBSODIUM.* $CACHE_DIRECTORY

    printf -- "Finished building %s .\n" "$PACKAGE_LIBSODIUM"
}

#faiss requires this dependency
function buildOpenblas() {
    source $PRESERVE_ENVARS
    NAME_OPENBLAS=OpenBLAS
    VERSION_OPENBLAS=0.3.25
    BUILD_OPENBLAS=1
    PACKAGE_OPENBLAS=$NAME_OPENBLAS-linux-s390x-$VERSION_OPENBLAS-$BUILD_OPENBLAS

    printf -- "Start building %s .\n" "$PACKAGE_OPENBLAS"
    if [ -d  $SOURCE_ROOT/$NAME_OPENBLAS ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    cd $SOURCE_ROOT
    git clone -b v$VERSION_OPENBLAS --depth 1 https://github.com/xianyi/OpenBLAS.git
    cd OpenBLAS
    make -j$(nproc)
    make PREFIX=$(pwd)/_build install
    cd _build
    # Packaging build files
    tar -czvf $PACKAGE_OPENBLAS.tgz *
    MD5_OPENBLAS=($(md5sum $PACKAGE_OPENBLAS.tgz))
    echo $MD5_OPENBLAS >$PACKAGE_OPENBLAS.md5
    # Copy the package to destination
    cp $PACKAGE_OPENBLAS.* $CACHE_DIRECTORY

    printf -- "Finished building %s .\n" "$PACKAGE_OPENBLAS"
}

function buildFAISS(){
    buildOpenblas
    source $PRESERVE_ENVARS
    NAME_FAISS=faiss
    VERSION_FAISS=1.7.4
    BUILD_FAISS=17
    PACKAGE_FAISS=$NAME_FAISS-linux-s390x-$VERSION_FAISS-$BUILD_FAISS
    printf -- "Start building %s .\n" "$PACKAGE_FAISS"
    if [ -d  $SOURCE_ROOT/$NAME_FAISS ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi
    cd $SOURCE_ROOT
    git clone -b v$VERSION_FAISS --depth 1 https://github.com/facebookresearch/faiss.git
    cd faiss
    cmake \
        -DFAISS_ENABLE_GPU=OFF \
        -DMKL_LIBRARIES=$SOURCE_ROOT/OpenBLAS/_build/lib \
        -DFAISS_ENABLE_PYTHON=OFF \
        -DBUILD_TESTING=OFF\
        -DCMAKE_INSTALL_PREFIX=$(pwd)/_build \
        -DCMAKE_INSTALL_LIBDIR=$(pwd)/_build/lib
    make -j$(nproc) install
    cd _build
    cat <<EOF >CMakeLists.txt
FILE (COPY lib DESTINATION "\${CMAKE_INSTALL_PREFIX}")
SET_PROPERTY (GLOBAL APPEND PROPERTY CBDEPS_PREFIX_PATH "\${CMAKE_CURRENT_SOURCE_DIR}")
EOF
    # Packaging build files
    tar -czvf $PACKAGE_FAISS.tgz *
    MD5_FAISS=($(md5sum $PACKAGE_FAISS.tgz))
    echo $MD5_FAISS >$PACKAGE_FAISS.md5
    # Copy the package to destination
    cp $PACKAGE_FAISS.* $CACHE_DIRECTORY
}

function buildSimdutf() {
    source $PRESERVE_ENVARS
    NAME_SIMDUTF=simdutf
    VERSION_SIMDUTF=3.2.14
    BUILD_SIMDUTF=cb1
    PACKAGE_SIMDUTF=$NAME_SIMDUTF-linux-s390x-$VERSION_SIMDUTF-$BUILD_SIMDUTF

    printf -- "Start building %s .\n" "$PACKAGE_SIMDUTF"
    if [ -d  $SOURCE_ROOT/$NAME_SIMDUTF ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    cd $SOURCE_ROOT
    git clone -b v$VERSION_SIMDUTF --depth 1 https://github.com/simdutf/simdutf.git
    cd simdutf
    cmake\
        -D CMAKE_BUILD_TYPE=RelWithDebInfo \
        -D CMAKE_CXX_STANDARD=17 \
        -D CMAKE_CXX_STANDARD_REQUIRED=ON \
        -D BUILD_SHARED_LIBS=OFF \
        -D CMAKE_INSTALL_PREFIX=$(pwd)/_build \
        -D CMAKE_INSTALL_LIBDIR=lib
    make -j$(nproc)
    make PREFIX=$(pwd)/_build install
    cd _build
    # Packaging build files
    tar -czvf $PACKAGE_SIMDUTF.tgz *
    MD5_SIMDUTF=($(md5sum $PACKAGE_SIMDUTF.tgz))
    echo $MD5_SIMDUTF >$PACKAGE_SIMDUTF.md5
    # Copy the package to destination
    cp $PACKAGE_SIMDUTF.* $CACHE_DIRECTORY

    printf -- "Finished building %s .\n" "$PACKAGE_SIMDUTF"
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
    git checkout 081bca8cb31b7e96e663806b2493bce10dbb42f0
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
    git checkout 415b3b1
    sed -i -e 's/-Wl,--icf=all//g' ./build/gen.py
    python3 build/gen.py
    ninja -C out
    echo "export PATH=$SOURCE_ROOT/gn/out:$PATH" >> $PRESERVE_ENVARS
}

function buildV8() {
    buildDepotTools
    buildGn

    source $PRESERVE_ENVARS
    NAME_V8=v8
    VERSION_V8=12.1.285.26
    BUILD_V8=1
    PACKAGE_V8=$NAME_V8-linux-s390x-$VERSION_V8-$BUILD_V8

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
    "url": "https://chromium.googlesource.com/v8/v8.git@$VERSION_V8",
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
    sed -i 's/-Wl,-z,relro/-Wl,-z,relro,-lstdc++/' ./build/config/compiler/BUILD.gn
    V8_ARGS='is_component_build=true target_cpu="s390x" v8_target_cpu="s390x" use_goma=false goma_dir="None" v8_enable_backtrace=true treat_warnings_as_errors=false is_clang=false use_custom_libcxx_for_host=false use_custom_libcxx=false v8_use_external_startup_data=false  use_sysroot=false use_gold=false linux_use_bundled_binutils=false    v8_enable_pointer_compression=false'
    # build release
    gn gen out/s390x.release --args="$V8_ARGS is_debug=false"
    LD_LIBRARY_PATH=$SOURCE_ROOT/v8/out/s390x.release ninja -C $SOURCE_ROOT/v8/out/s390x.release -j$(nproc)
    gn gen out/s390x.debug --args="$V8_ARGS is_debug=true"
    LD_LIBRARY_PATH=$SOURCE_ROOT/v8/out/s390x.debug ninja -C $SOURCE_ROOT/v8/out/s390x.debug -j$(nproc)

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
        cp -avi libthird_party*.* $INSTALL_DIR/lib/Release
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
    (
        cd out/s390x.debug
        cp -avi libv8*.* $INSTALL_DIR/lib/Debug
        cp -avi libchrome*.* $INSTALL_DIR/lib/Debug
        cp -avi libcppgc*.* $INSTALL_DIR/lib/Debug
        cp -avi libicu*.* $INSTALL_DIR/lib/Debug
        cp -avi icu*.* $INSTALL_DIR/lib/Debug
        cp -avi libthird_party*.* $INSTALL_DIR/lib/Debug
        rm -f $INSTALL_DIR/lib/Debug/*.TOC
        rm -f $INSTALL_DIR/lib/Debug/*for_testing*
        rm -f $INSTALL_DIR/lib/Debug/*debug_helper*
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
EOF
    # Packaging build files
    tar -czvf $PACKAGE_V8.tgz *
    MD5_V8=($(md5sum $PACKAGE_V8.tgz))
    echo $MD5_V8 >$PACKAGE_V8.md5
    # Copy the package to destination
    cp $PACKAGE_V8.* $CACHE_DIRECTORY

    printf -- "Finished building %s .\n" "$PACKAGE_V8"
}

function buildSSH() {
    source $PRESERVE_ENVARS
    printf -- "Start building %s .\n" "openssh-9.4p1"
    if [ -d  $SOURCE_ROOT/openssh-9.4p1 ]; then
        printf -- "The file already exists. Nothing to do. \n"
        return 0
    fi

    cd $SOURCE_ROOT
    wget --no-check-certificate https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-9.4p1.tar.gz
    tar -xzf openssh-9.4p1.tar.gz
    cd openssh-9.4p1
    ./configure --prefix=/usr/local --with-ssl-dir=$OPENSSL_ROOT_DIR
    make -j$(nproc)
    set +e
    sudo useradd -r -d /var/empty -s /sbin/nologin sshd
    set -e
    sudo make install
    ssh -V
}

function buildCouchbase() {
    echo "export PATH=$SOURCE_ROOT/openssl-3.1.4/_build/bin:$PATH" >> $PRESERVE_ENVARS
    echo "export LD_LIBRARY_PATH=$SOURCE_ROOT/openssl-3.1.4/_build/lib:$LD_LIBRARY_PATH" >> $PRESERVE_ENVARS
    echo "export OPENSSL_ROOT_DIR=$SOURCE_ROOT/openssl-3.1.4/_build" >> $PRESERVE_ENVARS
    echo "export OPENSSL_CONF=$SOURCE_ROOT/openssl-3.1.4/_build/etc/openssl" >> $PRESERVE_ENVARS
    source $PRESERVE_ENVARS
    if [[ $DISTRO == ubuntu* ]]; then
        export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
    elif [[ $DISTRO == rhel* ]]; then
        export SSL_CERT_FILE=/etc/pki/tls/certs/ca-bundle.crt
    else
        export SSL_CERT_FILE=/etc/ssl/ca-bundle.pem
    fi
    sudo ldconfig
    #To avoid openssl mismatch error
    if [ $ID$VERSION_ID == ubuntu22.04 ] || [ $ID$VERSION_ID == rhel9.2 ] || [ $ID$VERSION_ID == sles15.6 ]; then
        buildSSH
    fi
    set +e
    setGitGlobalConfig
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
    repo init -u https://github.com/couchbase/manifest -m released/couchbase-server/$PACKAGE_VERSION.xml
    repo sync

    sudo git config --system --add safe.directory '*'

    cd $SOURCE_ROOT/couchbase/tlm
    wget "${PATCH_URL}"/tlm.diff
    git apply tlm.diff

    cd $SOURCE_ROOT/couchbase/kv_engine
    wget "${PATCH_URL}"/kv_engine.diff
    git apply kv_engine.diff

    cd $SOURCE_ROOT/couchbase/platform
    wget "${PATCH_URL}"/platform.diff
    git apply platform.diff

    # add s390x to supported arches by replacing aarch64
    sed -i '272s/aarch64/s390x/g' $SOURCE_ROOT/couchbase/forestdb/src/arch.h

    OPTIONS=""
    if [[ "$HAS_PREFIX" == "true" ]]; then
        OPTIONS+=" -DCMAKE_INSTALL_PREFIX=$CB_PREFIX"
    fi


    cd $SOURCE_ROOT/couchbase/
    sudo ldconfig /usr/local/lib64 /usr/local/lib
    sudo cp tlm/CMakeLists.txt CMakeLists.txt 
    LD_LIBRARY_PATH=$CB_PREFIX/lib:$LD_LIBRARY_PATH CC=$CC CXX=$CXX EXTRA_CMAKE_OPTIONS="$OPTIONS" ./Build.sh everything
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
  echo "bash build_couchbase.sh [-y install-without-confirmation] [-t install-with-tests] [-p <install_prefix>]"
  echo
}

function main() {
    printf -- "Start Distro specific preperation for %s\n" "$ID$VERSION_ID"
    case $ID$VERSION_ID in

    rhel8.8 | rhel8.10)
        prepareRHEL8
        ;;

    rhel9.2 | rhel9.4)
        prepareRHEL9
        ;; 

    sles15.5 | sles15.6)
        prepareSUSE15
        ;;
    
    ubuntu20.04)
        prepareUB20
        ;;

    ubuntu22.04)
        prepareUB22
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
    buildJemalloc_noprefix
    buildJson
    buildLiburing
    buildLibuv
    buildLz4
    buildNumctl
    buildPcre
    buildPrometheus
    buildPromcpp
    buildProtoc
    buildSpdlog
    buildLibsodium
    buildFAISS
    buildSimdutf
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
