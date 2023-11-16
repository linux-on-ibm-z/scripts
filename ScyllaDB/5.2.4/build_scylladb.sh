#!/bin/bash
# © Copyright IBM Corporation 2023
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget -q https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ScyllaDB/5.2.4/build_scylladb.sh
# Execute build script: bash build_scylladb.sh    (provide -h for help)
#==============================================================================
set -e -o pipefail

PACKAGE_NAME="ScyllaDB"
PACKAGE_VERSION="5.2.4"
SOURCE_ROOT="$(pwd)"

FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
ENV_VARS=$SOURCE_ROOT/setenv.sh

PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ScyllaDB/5.2.4/patch"

NINJA_VERSION=1.11.1

PREFIX=/usr/local
declare -a CENV

TARGET=native
TOOLSET=gcc
CMAKE=cmake

GCC_VERSION=12.1.0
CLANG_VERSION=14.0.6

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
  
  #Fix warning about deprecated boost/function_output_iterator.hpp
  sudo sed -i 's/boost\/function_output_iterator\.hpp/boost\/iterator\/function_output_iterator\.hpp/g' \
    $PREFIX/include/boost/signals2/detail/null_output_iterator.hpp

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
# version 7.1.3

  msg "Building fmt"

  cd "$SOURCE_ROOT"
  git clone https://github.com/fmtlib/fmt.git
  cd fmt
  git checkout 7.1.3
  $CMAKE -DFMT_TEST=OFF \
         -DCMAKE_CXX_STANDARD=17 \
         -DCMAKE_BUILD_TYPE=RelWithDebInfo \
         -DCMAKE_CXX_VISIBILITY_PRESET=hidden \
         -DCMAKE_POSITION_INDEPENDENT_CODE=ON .
  make
  sudo make install

#----------------------------------------------------------
if ! [[ $DISTRO =~ "rhel-8" ]]
  then
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
fi
#----------------------------------------------------------
  ver=${PACKAGE_VERSION}
  msg "Cloning Scylla $ver"

  cd "$SOURCE_ROOT"/
  git clone https://github.com/scylladb/scylla.git
  cd scylla
  git checkout scylla-${ver}
  git submodule update --init --force --recursive

  curl -sSL ${PATCH_URL}/seastar.diff | patch -d seastar -p1 || error "seastar.diff"
  curl -sSL ${PATCH_URL}/scylla.diff | patch -p1 || error "scylla.diff"

  if [[ $DISTRO =~ "rhel-7" ]]
  then
        # Add patch for rhel 7
        curl -sSL ${PATCH_URL}/rhel7.diff | patch -d seastar -p1 || error "rhel7.diff"
  fi

  msg "Building scylla"

  export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig:$PREFIX/lib64/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}
  echo "export PKG_CONFIG_PATH=$PKG_CONFIG_PATH" >> $ENV_VARS

  msg "PKG_CONFIG_PATH=$PKG_CONFIG_PATH"

  local cflags="-I${PREFIX}/include -I${PREFIX}/include/boost -mzvector -g"

  ./configure.py --mode="release" --target="${TARGET}" --debuginfo=1 --cflags="${cflags}" \
    --compiler="${CXX}" --c-compiler="${CC}"

  # using optimize 0 only for one target.
  sed -i -E 's/(build \$builddir\/release\/service\/storage_proxy\.o.+)/\1\n   optimize = -O0/g' ./build.ninja
  # clang14 failed on Ubuntu22 and RHEL 8.6 for this file!
  sed -i -E 's/(build \$builddir\/release\/service\/raft\/group0_state_machine\.o.+)/\1\n   optimize = -O0/g' ./build.ninja
  sed -i -E 's/(build \$builddir\/release\/service\/raft\/raft_server_test\.o.+)/\1\n   optimize = -O0/g' ./build.ninja


  ninja build -j 8

  if [ "$?" -ne "0" ]; then
    error "Build  for ScyllaDB failed. Please check the error logs."
  else
    msg "Build  for ScyllaDB completed successfully. "
  fi

  if  [[  "$DISTRO"  =~  "ubuntu-2"  ]]; then 
    #increase the request capacity in /proc/sys/fs/aio-max-nr for setting up Async I/O
    echo "fs.aio-max-nr = 1048576" |& sudo tee -a /etc/sysctl.conf
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
  bash build_scylladb.sh [-z (z13|z14)] [-y] [-d] [-t]
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
  local ver=2.38

  msg "Building binutils $ver"
  cd "$SOURCE_ROOT"

  URL=https://ftp.gnu.org/gnu/binutils/binutils-${ver}.tar.gz 
  curl -sSL $URL | tar xzf - || error "binutils $ver"
  cd binutils-${ver}
  mkdir objdir
  cd objdir

  CC=/usr/bin/gcc ../configure --prefix=/usr --build=s390x-linux-gnu
  make -j 8
  sudo make install
}

#==============================================================================
buildGcc()
{
  msg "Building GCC $GCC_VERSION"
  cd "$SOURCE_ROOT"

  URL=https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.gz
  curl -sSL $URL | tar xzf - || error "GCC $GCC_VERSION"

  cd gcc-${GCC_VERSION}
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
  local ver=3.11.3
  msg "Building Python $ver"

  cd "$SOURCE_ROOT"
  URL="https://www.python.org/ftp/python/${ver}/Python-${ver}.tgz"
  curl -sSL $URL | tar xzf - || error "Python $ver"
  cd Python-${ver}
  ./configure
  make
  sudo make install
  pip3 install --user --upgrade pip
  pip3 install --user pyparsing colorama pyyaml boto3 requests pytest traceback-with-variables \
                      scylla-driver scylla-api-client aiohttp tabulate boto3 pytest-asyncio
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
  local ver=1.10.14
  msglog "Installing ant $ver"

  cd "$SOURCE_ROOT"
  URL=https://downloads.apache.org/ant/binaries/apache-ant-${ver}-bin.tar.gz
  curl -sSL $URL | tar xzf - || error "ant $ver"
  export ANT_HOME="$SOURCE_ROOT/apache-ant-${ver}"
  export PATH=$PATH:"$ANT_HOME/bin"
  echo "export PATH=$PATH" >> $ENV_VARS
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
  local ver=1.9.5
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
  msg "Building RapidJson $ver"

  cd "$SOURCE_ROOT"
  git clone https://github.com/Tencent/rapidjson.git
  cd rapidjson
  git checkout v1.1.0
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
  ./configure CC=gcc CXX=g++
  sudo make install
}

#==============================================================================
buildClang() {
  msg "Building clang-$CLANG_VERSION"

  cd "$SOURCE_ROOT"
  URL=https://github.com/llvm/llvm-project/archive/refs/tags/llvmorg-${CLANG_VERSION}.tar.gz
  curl -sSL $URL | tar xzf - || error "Clang $CLANG_VERSION"
  cd llvm-project-llvmorg-${CLANG_VERSION}
  mkdir build
  cd build

  if [[ $DISTRO = "rhel-8.6" || $DISTRO = "rhel-8.8" ]]; then
    cmake -DLLVM_ENABLE_PROJECTS=clang  -DCMAKE_BUILD_TYPE="Release" -G "Unix Makefiles" -DGCC_INSTALL_PREFIX="/opt/rh/gcc-toolset-11/root/" ../llvm
  else
    cmake -DLLVM_ENABLE_PROJECTS=clang -DCMAKE_C_COMPILER="${PREFIX}/bin/gcc" -DCMAKE_CXX_COMPILER="${PREFIX}/bin/g++" \
          -DCMAKE_BUILD_TYPE="Release" -G "Unix Makefiles" ../llvm
  fi

  make clang -j8
}

#==============================================================================
buildNumactl() {  
  local ver=2.0.14
  msg "Building numactl $ver"

  cd ${SOURCE_ROOT}
  git clone https://github.com/numactl/numactl.git
  cd numactl
  git checkout v${ver}
  ./autogen.sh
  ./configure
  make
  sudo make install
}

#==============================================================================
buildValgrind() {
   local ver=3.19.0
   msg "Building Valgrind $ver"

   cd "$SOURCE_ROOT"
   URL=https://sourceware.org/pub/valgrind/valgrind-${ver}.tar.bz2
   curl -sSL $URL | tar -xj || error "Valgrind $ver"
   cd valgrind-${ver}
   ./configure CC=gcc CXX=g++
   make
   sudo make install
}

#==============================================================================
buildAbseil() {
    # install abseil-cpp
    msg "Building abseil-cpp"
    cd "$SOURCE_ROOT"
    git clone https://github.com/abseil/abseil-cpp.git
    cd abseil-cpp
    git checkout 20230125.3
    cmake -Bbuild -H. -DCMAKE_INSTALL_PREFIX=/usr/local
    sudo cmake --build build --target install
}

#==============================================================================
# Build pkgs required only on RHEL7.
buildRHEL7()
{
  local ver=1

#----------------------------------------------------------
  msg "Building OpenSSL on RHEL 7.x"
  cd "$SOURCE_ROOT"
  wget https://www.openssl.org/source/openssl-1.1.1u.tar.gz --no-check-certificate
  tar -xzf openssl-1.1.1u.tar.gz
  cd openssl-1.1.1u
  ./config --prefix=/usr/local --openssldir=/usr/local
  make
  sudo make install
  sudo ldconfig /usr/local/lib64
  export LDFLAGS="-L/usr/local/lib/ -L/usr/local/lib64/"
  export CPPFLAGS="-I/usr/local/include/ -I/usr/local/include/openssl"

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
  buildNumactl

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

buildLibdeflate() {  
  msg "Building libdeflate"
  cd ${SOURCE_ROOT}
  git clone https://github.com/ebiggers/libdeflate.git
  cd libdeflate
  git checkout v1.18
  cmake -Bbuild -H. -DCMAKE_INSTALL_PREFIX=/usr/local
  cmake --build build --target install
}

function installRust()
{
  cd "$SOURCE_ROOT"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh /dev/stdin -y
  export PATH="$HOME/.cargo/bin:$PATH"
  echo "export PATH=$PATH" >> $ENV_VARS
  cargo install cxxbridge-cmd --root $SOURCE_ROOT/cxxbridge
  sudo cp -r $SOURCE_ROOT/cxxbridge/. /usr/local
}


#==============================================================================
logDetails
checkPrequisites

msglog "Installing $PACKAGE_NAME $PACKAGE_VERSION for $DISTRO"
msglog "Installing the dependencies for ScyllaDB from repository"

case "$DISTRO" in
#----------------------------------------------------------
"ubuntu-20.04" | "ubuntu-22.04")
  sudo apt-get update >/dev/null
  sudo apt-get install -y software-properties-common
  sudo add-apt-repository -y ppa:ubuntu-toolchain-r/test
  sudo apt-get update >/dev/null
  sudo apt-get install -y --no-install-recommends gcc g++  | tee -a "${LOG_FILE}"
  sudo apt-get install -y openjdk-8-jdk libaio-dev systemtap-sdt-dev lksctp-tools xfsprogs \
    libyaml-dev openssl libevent-dev libmpfr-dev libmpcdec-dev libssl-dev libsystemd-dev \
    libsctp-dev libsnappy-dev libpciaccess-dev libxml2-dev xfslibs-dev libgnutls28-dev \
    libiconv-hook-dev liblzma-dev libbz2-dev libxslt-dev libc-ares-dev libprotobuf-dev \
    protobuf-compiler libcrypto++-dev libtool perl ant libffi-dev rapidjson-dev automake \
    make git maven ninja-build unzip bzip2 wget curl xz-utils texinfo diffutils liblua5.3-dev \
    libnuma-dev libunistring-dev python3 python3-pip pigz ragel stow patch locales valgrind \
    libudev-dev libdeflate-dev zlib1g-dev |& tee -a "$LOG_FILE"
    
  if [ $DISTRO = "ubuntu-22.04" ]
  then
    sudo apt-get install -y libabsl-dev |& tee -a "$LOG_FILE"
  fi

  python3 -m pip install --user --upgrade pip
  python3 -m pip install --user pyparsing colorama pyyaml boto3 requests pytest scylla-driver \
          traceback-with-variables scylla-api-client aiohttp tabulate pytest-asyncio
  
  installRust

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# C/C++ environment settings
  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  
  buildBinutils |& tee -a "$LOG_FILE"
  
  # Clang needs latest linker from bin utils, removing old linker version
  sudo rm /usr/bin/s390x-linux-gnu-ld /usr/bin/s390x-linux-gnu-ld.bfd
  sudo ln -s /usr/bin/ld /usr/bin/s390x-linux-gnu-ld
  sudo ln -s /usr/bin/ld.bfd /usr/bin/s390x-linux-gnu-ld.bfd
  
  if [ $DISTRO = "ubuntu-20.04" ]
  then
    buildGcc |& tee -a "$LOG_FILE"
    #For clang to find this gcc version
    sudo ln -s ${PREFIX}/lib/gcc/s390x-linux-gnu/${GCC_VERSION} /usr/lib/gcc/s390x-linux-gnu/${GCC_VERSION}
    #Build python 3.11
    buildPython |& tee -a "$LOG_FILE"
  fi
  
  #Install Clang
  wget https://apt.llvm.org/llvm.sh
  sed -i 's,add-apt-repository "${REPO_NAME}",add-apt-repository "${REPO_NAME}" -y,g' llvm.sh
  chmod +x llvm.sh
  sudo ./llvm.sh 14
  rm ./llvm.sh

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


  export CC=clang-14
  export CXX=clang++-14

  echo "export PATH=$PATH" >> $ENV_VARS
  echo "export LD_LIBRARY_PATH=$LD_LIBRARY_PATH" >> $ENV_VARS
  echo "export CC=$CC" >> $ENV_VARS
  echo "export CXX=$CXX" >> $ENV_VARS
  echo "export LD_RUN_PATH=$LD_RUN_PATH" >> $ENV_VARS

  CENV=(PATH=$PATH LD_LIBRARY_PATH=$LD_LIBRARY_PATH
        LD_RUN_PATH=$LD_RUN_PATH
        CC=$CC CXX=$CXX
        )
  msglog "${CENV[@]}"

  gcc -v |& tee -a "$LOG_FILE"
  TOOLSET=gcc

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  python3 --version |& tee -a "$LOG_FILE"
  buildCmake |& tee -a "$LOG_FILE"
  buildLz4 |& tee -a "$LOG_FILE"
  buildXxHash |& tee -a "$LOG_FILE"
  buildZstd |& tee -a "$LOG_FILE"
  buildCryptopp |& tee -a "$LOG_FILE"
  buildHwloc |& tee -a "$LOG_FILE"
  buildJsonCpp |& tee -a "$LOG_FILE"
  buildAbseil |& tee -a "$LOG_FILE"
  
  if [ $DISTRO = "ubuntu-20.04" ]
  then
    buildValgrind |& tee -a "$LOG_FILE"
  fi
  
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
  sudo yum install -y java-1.8.0-openjdk-devel libaio-devel systemtap-sdt-devel lksctp-tools-devel \
    xfsprogs-devel snappy-devel libyaml-devel libevent-devel libtasn1-devel libmpcdec \
    lz4-devel libatomic libatomic_ops-devel perl-devel automake make git gcc gcc-c++ maven unzip \
    bzip2 wget curl xz-devel texinfo libffi-devel libpciaccess-devel libxml2-devel libtool diffutils \
    libtool-ltdl-devel trousers-devel libunistring-devel libicu-devel readline-devel lua-devel patch \
    systemd-devel valgrind-devel net-tools langpacks-en glibc-all-langpacks zlib-devel libdeflate libdeflate-devel |& tee -a "$LOG_FILE"
    # openssl-devel
  installRust
 
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

  echo "export PATH=$PATH" >> $ENV_VARS
  echo "export LD_LIBRARY_PATH=$LD_LIBRARY_PATH" >> $ENV_VARS
  echo "export CC=$CC" >> $ENV_VARS
  echo "export CXX=$CXX" >> $ENV_VARS
  echo "export LD_RUN_PATH=$LD_RUN_PATH" >> $ENV_VARS
  
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
  buildValgrind |& tee -a "$LOG_FILE"
  buildHwloc |& tee -a "$LOG_FILE"
  buildAbseil |& tee -a "$LOG_FILE"
    
  #Build Clang and its environment settings
  buildClang |& tee -a "$LOG_FILE"  
  clangbuild=${SOURCE_ROOT}/llvm-project-llvmorg-${CLANG_VERSION}/build
  export PATH=$clangbuild/bin:$PATH
  export LD_LIBRARY_PATH=$clangbuild/lib:$LD_LIBRARY_PATH
  export CC=clang
  export CXX=clang++

  echo "export PATH=$PATH" >> $ENV_VARS
  echo "export LD_LIBRARY_PATH=$LD_LIBRARY_PATH" >> $ENV_VARS
  echo "export CC=$CC" >> $ENV_VARS
  echo "export CXX=$CXX" >> $ENV_VARS

  sudo ln -s ${PREFIX}/lib/gcc/s390x-linux-gnu/${GCC_VERSION} /usr/lib/gcc/s390x-redhat-linux/${GCC_VERSION}
  sudo ln -s ${PREFIX}/include/c++/${GCC_VERSION}/s390x-linux-gnu /usr/include

  # Build libdeflate
  buildLibdeflate |& tee -a "$LOG_FILE"  
  libbuild=${SOURCE_ROOT}/libdeflate
  export PATH=$libbuild/build:$PATH
  export LD_LIBRARY_PATH=$libbuild/lib:$LD_LIBRARY_PATH
  
  configureAndInstall |& tee -a "$LOG_FILE"
;;

#----------------------------------------------------------
"rhel-8.6" | "rhel-8.8")

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  sudo dnf install -y  https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm

  gcc_toolset="gcc-toolset-11 gcc-toolset-11-libatomic-devel"
  
  sudo yum install -y --allowerasing gcc gcc-c++ $gcc_toolset \
    libatomic libatomic_ops-devel java-1.8.0-openjdk-devel lksctp-tools-devel xfsprogs-devel \
    snappy-devel libyaml-devel openssl-devel libevent-devel libtasn1-devel libmpcdec \
    libidn2-devel numactl-devel c-ares-devel gnutls-devel gnutls-c++ gnutls-dane perl-devel \
    python38 python38-devel python38-pip python38-PyYAML python38-setuptools python38-requests \
    make automake git maven ant ninja-build unzip bzip2 wget curl xz-devel texinfo libffi-devel \
    libpciaccess-devel libxml2-devel libtool diffutils libtool-ltdl-devel trousers-devel \
    p11-kit-devel libunistring-devel libicu-devel readline-devel lua-devel patch systemd-devel \
    valgrind-devel cmake hwloc hwloc-devel cryptopp cryptopp-devel lz4 lz4-devel jsoncpp \
    jsoncpp-devel protobuf rapidjson-devel stow yaml-cpp yaml-cpp-devel ragel langpacks-en \
    glibc-all-langpacks libdeflate libdeflate-devel abseil-cpp-devel |& tee -a "$LOG_FILE"

  buildXxHash |& tee -a "$LOG_FILE"
  installRust

  #Build Python 3.11.3
  buildPython |& tee -a "$LOG_FILE"
  python3 -V |& tee -a "$LOG_FILE"
  python3 -m pip -V |& tee -a "$LOG_FILE"

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  buildBinutils |& tee -a "$LOG_FILE"
  
  # Build clang 14
  buildClang |& tee -a "$LOG_FILE"
  clangbuild=${SOURCE_ROOT}/llvm-project-llvmorg-${CLANG_VERSION}/build
  ln -s clang++ ${SOURCE_ROOT}/llvm-project-llvmorg-${CLANG_VERSION}/build/bin/clang++-14
  export PATH=$clangbuild/bin:$PATH
  export LD_LIBRARY_PATH=$clangbuild/lib:$LD_LIBRARY_PATH


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

  export CC=clang-14
  export CXX=clang++-14

  echo "export PATH=$PATH" >> $ENV_VARS
  echo "export LD_LIBRARY_PATH=$LD_LIBRARY_PATH" >> $ENV_VARS
  echo "export CC=$CC" >> $ENV_VARS
  echo "export CXX=$CXX" >> $ENV_VARS
  echo "export LD_RUN_PATH=$LD_RUN_PATH" >> $ENV_VARS

  CENV=(PATH=$PATH LD_LIBRARY_PATH=$LD_LIBRARY_PATH
        LD_RUN_PATH=$LD_RUN_PATH
        CC=$CC CXX=$CXX
        )
  msglog "${CENV[@]}"

  gcc -v |& tee -a "$LOG_FILE"
  TOOLSET=gcc

  python3 -m pip install --user --upgrade pip
  python3 -m pip install --user pyparsing colorama pyyaml boto3 requests pytest scylla-driver \
          traceback-with-variables scylla-api-client aiohttp tabulate pytest-asyncio

  buildZstd |& tee -a "$LOG_FILE"
  buildAbseil |& tee -a "$LOG_FILE"
  
  configureAndInstall |& tee -a "$LOG_FILE"
;;

#----------------------------------------------------------
*)
  errlog "$DISTRO not supported"
;;

esac

gettingStarted |& tee -a "$LOG_FILE"
