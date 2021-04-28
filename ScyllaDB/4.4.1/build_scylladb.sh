#!/bin/bash
# © Copyright IBM Corporation 2021.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Usage:
# bash build_scylladb.sh -h
#==============================================================================
set -e -o pipefail

PACKAGE_NAME="ScyllaDB"
PACKAGE_VERSION="4.4.1"
SOURCE_ROOT="$(pwd)"

FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/${PACKAGE_NAME}/${PACKAGE_VERSION}/patch"

NINJA_VERSION=1.10.1

PREFIX=/usr/local
declare -a CENV

TARGET=native
TOOLSET=gcc
CMAKE=/usr/local/bin/cmake

#==============================================================================
mkdir -p "$SOURCE_ROOT/logs"

error() { echo "Error: ${*}"; exit 1; }
errlog() { echo "Error: ${*}" |& tee -a "$LOG_FILE"; exit 1; }

msg() { echo "${*}"; }
log() { echo "${*}" >> "$LOG_FILE"; }
msglog() { echo "${*}" |& tee -a "$LOG_FILE"; }


trap cleanup 0 1 2 ERR

#==============================================================================
#Set the Distro ID
if [ -f "/etc/os-release" ]; then
  source "/etc/os-release"
else
  error "Unknown distribution"
fi
DISTRO="$ID-$VERSION_ID"

#==============================================================================
checkPrequisites()
{
  if [ -z "$TARGET" ]; then
    error "No target architecture specified with -z"
  else
    log "Building ScyllaDB on target $TARGET"
  fi

  if command -v "sudo" >/dev/null; then
    msglog "Sudo : Yes"
  else
    msglog "Sudo : No "
    error "sudo is required. Install using apt, yum or zypper based on your distro."
  fi

  if [[ "$FORCE" == "true" ]]; then
    msglog "Force - install without confirmation message"
  else
    # Ask user for prerequisite installation
    msg "As part of the installation , dependencies would be installed/upgraded."
    while true; do
      read -r -p "Do you want to continue (y/n) ? : " yn
      case $yn in
      [Yy]*)
        log "User responded with Yes."
        break
        ;;
      [Nn]*) exit ;;
      *) msg "Please provide confirmation to proceed." ;;
      esac
    done
  fi
}


#==============================================================================
cleanup()
{
  rm -f $SOURCE_ROOT/cryptopp/CRYPTOPP_8_2_0.zip
  rm -f $SOURCE_ROOT/v${NINJA_VERSION}.zip
  echo "Cleaned up the artifacts."
}


#==============================================================================
# Build and install pkgs common to all distros.
#
configureAndInstall()
{
  local ver=1
  declare -a options
  msg "Configuration and Installation started"

#----------------------------------------------------------
buildHwloc

#----------------------------------------------------------
  ver=3.5.2
  msg "Installing antlr $ver"
  cd "$SOURCE_ROOT"

  URL=https://github.com/antlr/antlr3/archive/${ver}.tar.gz
  curl -sSL $URL | tar xzf - || error "antlr $ver"
  cd antlr3-${ver}
  curl -sSL ${PATCH_URL}/antlr3.diff | patch -p1 || error "antlr3.diff"

  sudo cp runtime/Cpp/include/antlr3* ${PREFIX}/include/

  cd antlr-complete
  MAVEN_OPTS="-Xmx4G" mvn
  echo 'java -cp '"$(pwd)"'/target/antlr-complete-3.5.2.jar org.antlr.Tool $@' | sudo tee ${PREFIX}/bin/antlr3
  sudo chmod +x ${PREFIX}/bin/antlr3

#----------------------------------------------------------
  ver=1.74.0
  local uver=${ver//\./_}
  msg "Building Boost $ver"

  cd "$SOURCE_ROOT"
  URL=https://boostorg.jfrog.io/artifactory/main/release/${ver}/source/boost_${uver}.tar.gz
  curl -sSL $URL | tar xzf - || error "Boost $ver"
  cd boost_${uver}

  sed -i 's/array\.hpp/array_wrapper.hpp/g' boost/numeric/ublas/matrix.hpp
  sed -i 's/array\.hpp/array_wrapper.hpp/g' boost/numeric/ublas/storage.hpp

  ./bootstrap.sh

  options=( toolset=$TOOLSET variant=release link=shared
            runtime-link=shared threading=multi --without-python
          )

  ./b2 ${options[@]} stage
  sudo ${CENV[@]} ./b2 ${options[@]} install

#----------------------------------------------------------
  ver=0.13.0
  msg "Building Thrift $ver"

  cd "$SOURCE_ROOT"
  URL=http://archive.apache.org/dist/thrift/${ver}/thrift-${ver}.tar.gz
  curl -sSL $URL | tar xzf - || error "Thrift $ver"
  cd thrift-${ver}
  ./configure --without-java --without-lua --without-go --disable-tests --disable-tutorial
  make -j 8
  sudo make install

#----------------------------------------------------------
# https://fmt.dev/latest/usage.html#building-the-library
# version 6.2.1
  msg "Building fmt"

  cd "$SOURCE_ROOT"
  git clone https://github.com/fmtlib/fmt.git
  cd fmt
  git checkout 6.2.1
  mkdir build
  cd build
  $CMAKE -DFMT_TEST=OFF -DCMAKE_CXX_STANDARD=17 ..
  make
  sudo make install

#----------------------------------------------------------
  ver=0.6.3
  msg "Building yaml-cpp $ver"

  cd "$SOURCE_ROOT"
  URL=https://github.com/jbeder/yaml-cpp/archive/yaml-cpp-${ver}.tar.gz
  curl -sSL $URL | tar xzf - || error "yaml-cpp $ver"
  cd yaml-cpp-yaml-cpp-${ver}
  mkdir build
  cd build
  $CMAKE ..
  make
  sudo make install


#----------------------------------------------------------
  ver=${PACKAGE_VERSION}
  msg "Cloning scylla $ver"

  cd "$SOURCE_ROOT"/
  git clone https://github.com/scylladb/scylla.git
  cd scylla
  git checkout scylla-${ver}
  git submodule update --init --force --recursive

  curl -sSL ${PATCH_URL}/seastar.diff | patch -d seastar -p1 || error "seastar.diff"
  curl -sSL ${PATCH_URL}/scylla.diff | patch -p1 || error "scylla.diff"

  msg "Building scylla"

  export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}
  msg "PKG_CONFIG_PATH=$PKG_CONFIG_PATH"

  local cflags="-I${PREFIX}/include -I${PREFIX}/include/boost"
  cflags+=" -L${PREFIX}/lib -L${PREFIX}/lib64 "
  cflags+=" -fcoroutines "

  #Fix warning about deprecated boost/function_output_iterator.hpp
  sudo sed -i 's/boost\/function_output_iterator\.hpp/boost\/iterator\/function_output_iterator\.hpp/g' \
    $PREFIX/include/boost/signals2/detail/null_output_iterator.hpp

  ./configure.py --mode="release" --target="${TARGET}" --debuginfo=1 \
    --static-thrift --cflags="${cflags}" --ldflags="-Wl,--build-id=sha1" \
    --compiler="${CXX}" --c-compiler="${CC}"

  ninja build -j 8

  if [ "$?" -ne "0" ]; then
    error "Build  for ScyllaDB failed. Please check the error logs."
  else
    msg "Build  for ScyllaDB completed successfully. "
  fi

  if  [[  "$DISTRO"  =~  "ubuntu-20"  ]]; then 
    #increase the request capacity in /proc/sys/fs/aio-max-nr for setting up Async I/O
    echo "fs.aio-max-nr = 1048576" |& sudo tee /etc/sysctl.conf
    sudo sysctl -p
  fi

  runTest
}


#==============================================================================
runTest()
{
  set +e
  if [[ "$TESTS" == "true" ]]; then
    log "TEST Flag is set, continue with running test "
    cd "$SOURCE_ROOT/scylla"
    ./test.py --mode release
    msg "Test execution completed. "
  fi
  set -e
}


#==============================================================================
logDetails()
{
  log "**************************** SYSTEM DETAILS ***************************"
  cat "/etc/os-release" >>"$LOG_FILE"
  cat /proc/version >>"$LOG_FILE"
  log "***********************************************************************"

  msg "Detected $PRETTY_NAME"
  msglog "Request details: PACKAGE NAME=$PACKAGE_NAME, VERSION=$PACKAGE_VERSION"
}


#==============================================================================
printHelp()
{
  cat <<eof
  Usage:
  bash build_scylladb.sh [-z (z13|z14|native)] [-y] [-d] [-t]
  where:
   -z select target architecture - default: native
   -y install-without-confirmation
   -d debug
   -t test
eof
}

###############################################################################
while getopts "h?dyt?z:" opt
do
  case "$opt" in
    h | \?) printHelp; exit 0; ;;
    d) set -x; ;;
    y) FORCE="true"; ;;
    z) TARGET=$OPTARG; ;;
    t) TESTS="true"; ;;
  esac
done


#==============================================================================
gettingStarted()
{
  cat <<-eof
        ***********************************************************************
        Usage:
        ***********************************************************************
          ScyllaDB installed successfully.
          Set the environment variables:
          export PATH=${PREFIX}/bin\${PATH:+:\${PATH}}
          LD_LIBRARY_PATH=${PREFIX}/lib64\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}
          LD_LIBRARY_PATH+=:${PREFIX}/lib
          LD_LIBRARY_PATH+=:/usr/lib64
          export LD_LIBRARY_PATH
          Run the following commands to use ScyllaDB:
          $SOURCE_ROOT/scylla/build/release/scylla --help
          More information can be found here:
          https://github.com/scylladb/scylla/blob/master/HACKING.md
eof
}

#==============================================================================
buildBinutils()
{
  local ver=2.36

  msg "Building binutils $ver"
  cd "$SOURCE_ROOT"

  URL=http://ftpmirror.gnu.org/binutils/binutils-${ver}.tar.gz
  curl -sSL $URL | tar xzf - || error "binutils $ver"
  cd binutils-${ver}
  mkdir objdir
  cd objdir

  CC=/usr/bin/gcc ../configure --prefix=${PREFIX} --build=s390x-linux-gnu
  make -j 8
  sudo make install
}

#==============================================================================
buildGcc()
{
  local ver=10.2.0
  msg "Building GCC $ver"
  cd "$SOURCE_ROOT"

  URL=https://ftp.gnu.org/gnu/gcc/gcc-${ver}/gcc-${ver}.tar.gz
  curl -sSL $URL | tar xzf - || error "GCC $ver"

  cd gcc-${ver}
  ./contrib/download_prerequisites
  mkdir objdir
  cd objdir

  ../configure --enable-languages=c,c++ --prefix=${PREFIX} \
    --enable-shared --enable-threads=posix \
    --disable-multilib --disable-libmpx \
    --with-system-zlib --with-long-double-128 --with-arch=zEC12 \
    --disable-libphobos --disable-werror \
    --build=s390x-linux-gnu --host=s390x-linux-gnu --target=s390x-linux-gnu

  make -j 8 bootstrap
  sudo make install
}

#==============================================================================
# requires libffi-dev
buildPython()
{
  local ver=3.8.6
  msg "Building Python $ver"

  cd "$SOURCE_ROOT"
  URL="https://www.python.org/ftp/python/${ver}/Python-${ver}.tgz"
  curl -sSL $URL | tar xzf - || error "Python $ver"
  cd Python-${ver}
  ./configure
  make
  sudo make install
  pip3 install --user --upgrade pip
  pip3 install --user pyparsing colorama pyyaml cassandra-driver boto3 requests pytest
}

#==============================================================================
buildCmake()
{
  local ver=3.17.4
  msg "Building cmake $ver"

  cd "$SOURCE_ROOT"
  URL=https://github.com/Kitware/CMake/releases/download/v${ver}/cmake-${ver}.tar.gz
  curl -sSL $URL | tar xzf - || error "cmake $ver"
  cd cmake-${ver}
  ./bootstrap
  make
  sudo make install
}

#==============================================================================
buildAnt()
{
  local ver=1.10.9
  msglog "Installing ant $ver"

  cd "$SOURCE_ROOT"
  URL=https://downloads.apache.org/ant/binaries/apache-ant-${ver}-bin.tar.gz
  curl -sSL $URL | tar xzf - || error "ant $ver"
  export ANT_HOME="$SOURCE_ROOT/apache-ant-${ver}"
  export PATH=$PATH:"$ANT_HOME/bin"
  ant -version |& tee -a "$LOG_FILE"
}

#==============================================================================
# https://github.com/c-ares/c-ares/blob/cares-1_14_0/INSTALL.md
buildCares()
{
  local ver=1.15.0
  msg "Building c-ares $ver"

  cd ${SOURCE_ROOT}
  URL=https://c-ares.haxx.se/download/c-ares-${ver}.tar.gz
  curl -sSL $URL | tar xzf - || error "c-ares $ver"
  cd c-ares-${ver}
  ./configure
  make
  sudo make install
}

#==============================================================================
buildRagel() {
  local ver=6.10
  msg "Building ragel $ver"

  cd "$SOURCE_ROOT"
  URL=http://www.colm.net/files/ragel/ragel-${ver}.tar.gz
  curl -sSL $URL | tar xzf - || error "ragel $ver"
  cd ragel-${ver}
  ./configure
  make -j 8
  sudo make install
}

#==============================================================================
buildCryptopp() {
  msg "Building cryptopp820"

  cd "$SOURCE_ROOT"
  mkdir cryptopp
  cd cryptopp
  curl -ksSLO https://github.com/weidai11/cryptopp/archive/refs/tags/CRYPTOPP_8_2_0.zip
  unzip CRYPTOPP_8_2_0.zip
  cd cryptopp-CRYPTOPP_8_2_0
  CXXFLAGS="-std=c++11 -g -O2" make
  sudo make install
}

#==============================================================================
buildJsonCpp() {
  local ver=1.7.7
  msg "Building jsoncpp $ver"

  cd "$SOURCE_ROOT"
  URL=https://github.com/open-source-parsers/jsoncpp/archive/${ver}.tar.gz
  curl -sSL $URL | tar xzf - || error "jsoncpp $ver"
  cd jsoncpp-${ver}
  mkdir -p build/release
  cd build/release
  $CMAKE ../..
  make -j 8
  sudo make install
}

#==============================================================================
buildRJson()
{
  local ver=v1.1.0
  msg "Building RapidJson $ver"

  cd "$SOURCE_ROOT"
  git clone https://github.com/Tencent/rapidjson.git
  cd rapidjson
  git checkout ${ver}
  sudo cp -r ./include/rapidjson ${PREFIX}/include
}

buildProtobuf() {
  local ver=v3.11.2
  msg "Building Protobuf $ver"

  cd "$SOURCE_ROOT"
  git clone https://github.com/protocolbuffers/protobuf.git
  cd protobuf
  git checkout ${ver}
  ./autogen.sh
  ./configure
  make
  sudo make install
}

#==============================================================================
buildLz4()
{
  ver=1.9.3
  msg "Building lz4 $ver"

  cd "$SOURCE_ROOT"
  URL=https://github.com/lz4/lz4/archive/v${ver}.tar.gz
  curl -sSL $URL | tar xzf - || error "lz4 $ver"
  cd lz4-${ver}
  sudo make install
}

#==============================================================================
buildXxHash()
{
  ver=0.8.0
  msg "Building xxHash $ver"

  cd "$SOURCE_ROOT"
  URL=https://github.com/Cyan4973/xxHash/archive/v${ver}.tar.gz
  curl -sSL $URL | tar xzf - || error "xxHash $ver"
  cd xxHash-${ver}
  sudo make install
}

#==============================================================================
buildZstd()
{
  ver=1.4.5
  msg "Building zstd $ver"

  cd "$SOURCE_ROOT"
  URL=https://github.com/facebook/zstd/releases/download/v${ver}/zstd-${ver}.tar.gz
  curl -sSL $URL | tar xzf - || error "zstd $ver"
  cd zstd-${ver}
  curl -sSL ${PATCH_URL}/zstd.diff | patch -p1 || error "zstd.diff"
  cd lib
  make
  sudo make install
}

#==============================================================================
buildStow() {
  local ver=2.3.1
  msg "Building Stow $ver"

  cd "$SOURCE_ROOT"
  URL=http://ftpmirror.gnu.org/gnu/stow/stow-${ver}.tar.gz
  curl -sSL $URL | tar xzf - || error "Stow $ver"
  cd stow-${ver}
  ./configure
  sudo make install
}

#==============================================================================
buildHwloc() {
  local ver=2.4.1
  msg "Building hwloc $ver"

  cd "$SOURCE_ROOT"
  URL=https://download.open-mpi.org/release/hwloc/v2.4/hwloc-${ver}.tar.gz
  curl -sSL $URL | tar xzf - || error "hwloc $ver"
  cd hwloc-${ver}
  ./configure
  sudo make install
}

#==============================================================================
# Build pkgs required only on RHEL7.
buildRHEL7()
{
  local ver=1

#----------------------------------------------------------
  buildPython
  python3 --version

#----------------------------------------------------------
  msg "Building ninja-${NINJA_VERSION}"

  cd "$SOURCE_ROOT"
  curl -sSLO https://github.com/ninja-build/ninja/archive/v${NINJA_VERSION}.zip
  unzip v${NINJA_VERSION}.zip
  cd ninja-${NINJA_VERSION}
  ./configure.py --bootstrap
  sudo cp ninja ${PREFIX}/bin

#----------------------------------------------------------
  buildCmake

#----------------------------------------------------------
  ver=2.3.0
  msg "Building libidn2 $ver"

  cd ${SOURCE_ROOT}
  URL=https://ftp.gnu.org/gnu/libidn/libidn2-${ver}.tar.gz
  curl -sSL $URL | tar xzf - || error "libidn2 $ver"
  cd libidn2-${ver}
  ./configure --disable-doc --disable-gtk-doc
  make
  sudo make install

#----------------------------------------------------------
  ver=2.0.14
  msg "Building numactl $ver"

  cd ${SOURCE_ROOT}
  git clone https://github.com/numactl/numactl.git
  cd numactl
  git checkout v${ver}
  ./autogen.sh
  ./configure
  make
  sudo make install

#----------------------------------------------------------
  buildCares

#----------------------------------------------------------
  buildRagel

#----------------------------------------------------------
  buildCryptopp

#----------------------------------------------------------
  buildJsonCpp

#----------------------------------------------------------
  ver=5.3.5
  msg "Building LUA $ver"

  cd "$SOURCE_ROOT"
  URL=http://www.lua.org/ftp/lua-${ver}.tar.gz
  curl -sSL $URL | tar xzf - || error "LUA $ver"
  cd lua-${ver}
  make linux
  sudo make install

#----------------------------------------------------------
  buildRJson

#----------------------------------------------------------
  buildProtobuf

#----------------------------------------------------------
  buildStow

#----------------------------------------------------------
  buildXxHash

#----------------------------------------------------------
  buildZstd

#----------------------------------------------------------
  ver=0.23.21
  msg "Building p11-kit $ver"

  cd "$SOURCE_ROOT"
  URL=https://github.com/p11-glue/p11-kit/releases/download/${ver}/p11-kit-${ver}.tar.xz
  curl -sSL $URL | tar xJf - || error "p11-kit $ver"
  cd p11-kit-${ver}
  ./configure --prefix=${PREFIX}
  make
  sudo make install

#----------------------------------------------------------
  ver=6.2.1
  msg "Building gmplib $ver"

  cd "$SOURCE_ROOT"
  URL=https://gmplib.org/download/gmp/gmp-${ver}.tar.xz
  curl -sSL $URL | tar xJf - || error "gmplib $ver"
  cd gmp-${ver}
  ./configure --prefix=${PREFIX}
  make
  make check
  sudo make install

#----------------------------------------------------------
  ver=3.6
  msg "Building nettle $ver"

  cd "$SOURCE_ROOT"
  URL=https://ftp.gnu.org/gnu/nettle/nettle-${ver}.tar.gz
  curl -sSL $URL | tar xzf - || error "nettle $ver"
  cd nettle-${ver}
  ./configure --prefix=${PREFIX}
  make
  make check
  sudo make install

#----------------------------------------------------------
  ver=3.6.15
  msg "Building gnutls $ver"

  cd "$SOURCE_ROOT"
  URL=https://www.gnupg.org/ftp/gcrypt/gnutls/v3.6/gnutls-${ver}.tar.xz
  curl -sSL $URL | tar xJf - || error "gnutls $ver"
  cd gnutls-${ver}
  PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}} ./configure --prefix=${PREFIX}
  make
  make check
  sudo make install

}


#==============================================================================
logDetails
checkPrequisites

msglog "Installing $PACKAGE_NAME $PACKAGE_VERSION for $DISTRO"
msglog "Installing the dependencies for ScyllaDB from repository"

case "$DISTRO" in
#----------------------------------------------------------
"ubuntu-18.04" | "ubuntu-20.04")
  sudo apt-get update >/dev/null
  sudo apt-get install -y software-properties-common
  sudo add-apt-repository -y ppa:ubuntu-toolchain-r/test
  sudo apt-get update >/dev/null
  sudo apt-get install -y --no-install-recommends gcc g++  | tee -a "${LOG_FILE}"
  sudo apt-get install -y openjdk-8-jdk libaio-dev \
    systemtap-sdt-dev lksctp-tools xfsprogs \
    libyaml-dev openssl libevent-dev \
    libmpfr-dev libmpcdec-dev \
    libssl-dev libsystemd-dev \
    libsctp-dev libsnappy-dev libpciaccess-dev libxml2-dev xfslibs-dev \
    libgnutls28-dev libiconv-hook-dev liblzma-dev libbz2-dev \
    libxslt-dev libjsoncpp-dev libc-ares-dev \
    libprotobuf-dev protobuf-compiler libcrypto++-dev \
    libtool perl ant libffi-dev \
    automake make git maven ninja-build \
    unzip bzip2 wget curl xz-utils texinfo \
    diffutils liblua5.3-dev libnuma-dev libunistring-dev \
    pigz ragel rapidjson-dev stow patch locales valgrind libudev-dev |& tee -a "$LOG_FILE"

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# C/C++ environment settings
  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  
  buildBinutils |& tee -a "$LOG_FILE"
  buildGcc |& tee -a "$LOG_FILE"

# C/C++ environment settings
  sudo locale-gen en_US.UTF-8
  export LC_ALL=C
  unset LANGUAGE

  export PATH=${PREFIX}/bin${PATH:+:${PATH}}
  export PATH=$PATH:~/.local/bin/
  LD_LIBRARY_PATH=${PREFIX}/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
  LD_LIBRARY_PATH+=:${PREFIX}/lib
  LD_LIBRARY_PATH+=:/usr/lib64
  export LD_LIBRARY_PATH

  LD_RUN_PATH=${PREFIX}/lib64${LD_RUN_PATH:+:${LD_RUN_PATH}}
  LD_RUN_PATH+=:${PREFIX}/lib
  LD_RUN_PATH+=:/usr/lib64
  export LD_RUN_PATH

  export CC=${PREFIX}/bin/gcc
  export CXX=${PREFIX}/bin/g++

  CENV=(PATH=$PATH LD_LIBRARY_PATH=$LD_LIBRARY_PATH
        LD_RUN_PATH=$LD_RUN_PATH
        CC=$CC CXX=$CXX
        )
  msglog "${CENV[@]}"

  gcc -v |& tee -a "$LOG_FILE"
  TOOLSET=gcc

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  buildPython |& tee -a "$LOG_FILE"
  python3 --version |& tee -a "$LOG_FILE"
  buildCmake |& tee -a "$LOG_FILE"
  buildLz4 |& tee -a "$LOG_FILE"
  buildXxHash |& tee -a "$LOG_FILE"
  buildZstd |& tee -a "$LOG_FILE"
  buildCryptopp |& tee -a "$LOG_FILE"
  configureAndInstall |& tee -a "$LOG_FILE"
;;

#----------------------------------------------------------
"rhel-7.8" |"rhel-7.9")

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  set +e
  sudo yum list installed glibc-2.17-307.el7.1.s390 |& tee -a "$LOG_FILE"
  if [[ $? ]]; then
    sudo yum downgrade -y glibc glibc-common |& tee -a "$LOG_FILE"
    sudo yum downgrade -y krb5-libs |& tee -a "$LOG_FILE"
    sudo yum downgrade -y libss e2fsprogs-libs e2fsprogs libcom_err |& tee -a "$LOG_FILE"
    sudo yum downgrade -y libselinux-utils libselinux-python libselinux |& tee -a "$LOG_FILE"
    fi
  set -e

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  sudo yum install -y java-1.8.0-openjdk-devel libaio-devel \
  systemtap-sdt-devel lksctp-tools-devel xfsprogs-devel snappy-devel \
  libyaml-devel openssl-devel libevent-devel \
  libtasn1-devel libmpcdec lz4-devel \
  libatomic libatomic_ops-devel perl-devel \
  automake make git gcc gcc-c++ maven \
  unzip bzip2 wget curl xz-devel texinfo \
  libffi-devel libpciaccess-devel libxml2-devel \
  libtool diffutils libtool-ltdl-devel trousers-devel \
  libunistring-devel libicu-devel readline-devel \
  lua-devel patch systemd-devel valgrind-devel |& tee -a "$LOG_FILE"
 
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  buildBinutils |& tee -a "$LOG_FILE"
  buildGcc |& tee -a "$LOG_FILE"

# C/C++ environment settings
  
  export PATH=${PREFIX}/bin${PATH:+:${PATH}}
  export PATH=$PATH:~/.local/bin/
  LD_LIBRARY_PATH=${PREFIX}/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
  LD_LIBRARY_PATH+=:${PREFIX}/lib
  LD_LIBRARY_PATH+=:/usr/lib64
  export LD_LIBRARY_PATH

  LD_RUN_PATH=${PREFIX}/lib64${LD_RUN_PATH:+:${LD_RUN_PATH}}
  LD_RUN_PATH+=:${PREFIX}/lib
  LD_RUN_PATH+=:/usr/lib64
  export LD_RUN_PATH

  export CC=${PREFIX}/bin/gcc
  export CXX=${PREFIX}/bin/g++

  CENV=(PATH=$PATH LD_LIBRARY_PATH=$LD_LIBRARY_PATH
        LD_RUN_PATH=$LD_RUN_PATH
        CC=$CC CXX=$CXX
        )
  msglog "${CENV[@]}"

  gcc -v |& tee -a "$LOG_FILE"
  TOOLSET=gcc

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  buildRHEL7 |& tee -a "$LOG_FILE"
  buildAnt |& tee -a "$LOG_FILE"
  configureAndInstall |& tee -a "$LOG_FILE"
;;

#----------------------------------------------------------
"rhel-8.1" | "rhel-8.2" | "rhel-8.3")

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  sudo yum install -y gcc gcc-c++ libatomic libatomic_ops-devel \
  java-1.8.0-openjdk-devel \
  lksctp-tools-devel xfsprogs-devel snappy-devel \
  libyaml-devel openssl-devel libevent-devel \
  libtasn1-devel libmpcdec \
  libidn2-devel numactl-devel c-ares-devel \
  gnutls-devel gnutls-c++ gnutls-dane \
  perl-devel \
  python38 python38-devel python38-pip python38-PyYAML \
  python38-setuptools python38-requests \
  make automake git maven ant ninja-build \
  unzip bzip2 wget curl xz-devel texinfo \
  libffi-devel libpciaccess-devel libxml2-devel \
  libtool diffutils libtool-ltdl-devel trousers-devel p11-kit-devel \
  libunistring-devel libicu-devel readline-devel \
  lua-devel patch systemd-devel valgrind-devel |& tee -a "$LOG_FILE"

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  buildBinutils |& tee -a "$LOG_FILE"
  buildGcc |& tee -a "$LOG_FILE"

# C/C++ environment settings
  
  export PATH=${PREFIX}/bin${PATH:+:${PATH}}
  export PATH=$PATH:~/.local/bin/
  LD_LIBRARY_PATH=${PREFIX}/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
  LD_LIBRARY_PATH+=:${PREFIX}/lib
  LD_LIBRARY_PATH+=:/usr/lib64
  export LD_LIBRARY_PATH

  LD_RUN_PATH=${PREFIX}/lib64${LD_RUN_PATH:+:${LD_RUN_PATH}}
  LD_RUN_PATH+=:${PREFIX}/lib
  LD_RUN_PATH+=:/usr/lib64
  export LD_RUN_PATH

  export CC=${PREFIX}/bin/gcc
  export CXX=${PREFIX}/bin/g++

  CENV=(PATH=$PATH LD_LIBRARY_PATH=$LD_LIBRARY_PATH
        LD_RUN_PATH=$LD_RUN_PATH
        CC=$CC CXX=$CXX
        )
  msglog "${CENV[@]}"

  gcc -v |& tee -a "$LOG_FILE"
  TOOLSET=gcc

  if [ "$DISTRO"x = "rhel-8.3"x ]
  then
    #make /usr/bin/python3 link to python3.8
    sudo update-alternatives --set python3 "/usr/bin/python3.8"
  fi

  pip3 install --user --upgrade pip
  pip3 install --user pyparsing colorama pyyaml cassandra-driver boto3 requests pytest

  buildCmake |& tee -a "$LOG_FILE"
  buildLz4 |& tee -a "$LOG_FILE"
  buildZstd |& tee -a "$LOG_FILE"
  buildXxHash |& tee -a "$LOG_FILE"
  buildRJson |& tee -a "$LOG_FILE"
  buildProtobuf |& tee -a "$LOG_FILE"
  buildCryptopp |& tee -a "$LOG_FILE"
  buildJsonCpp |& tee -a "$LOG_FILE"
  buildRagel |& tee -a "$LOG_FILE"
  buildStow |& tee -a "$LOG_FILE"
  configureAndInstall |& tee -a "$LOG_FILE"
;;

#----------------------------------------------------------
*)
  errlog "$DISTRO not supported"
;;

esac

gettingStarted |& tee -a "$LOG_FILE"
