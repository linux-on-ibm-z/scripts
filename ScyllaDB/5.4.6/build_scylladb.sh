#!/bin/bash
# © Copyright IBM Corporation 2019, 2025
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget -q https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ScyllaDB/5.4.6/build_scylladb.sh
# Execute build script: bash build_scylladb.sh    (provide -h for help)
#==============================================================================
set -e -o pipefail

PACKAGE_NAME="ScyllaDB"
PACKAGE_VERSION="5.4.6"
SOURCE_ROOT="$(pwd)"

FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
ENV_VARS=$SOURCE_ROOT/setenv.sh

PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ScyllaDB/5.4.6/patch"

PREFIX=/usr/local
declare -a CENV

TARGET=native
TOOLSET=gcc
CMAKE=cmake

GCC_VERSION=12.1.0
CLANG_VERSION=17.0.6

#==============================================================================
mkdir -p "$SOURCE_ROOT/logs"

error() {
  echo "Error: ${*}"
  exit 1
}
errlog() {
  echo "Error: ${*}" |& tee -a "$LOG_FILE"
  exit 1
}

msg() { echo "${*}"; }
log() { echo "${*}" >>"$LOG_FILE"; }
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
checkPrequisites() {
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
cleanup() {
  rm -f $SOURCE_ROOT/cryptopp/CRYPTOPP_8_2_0.zip
  rm -f $SOURCE_ROOT/v${NINJA_VERSION}.zip
  echo "Cleaned up the artifacts."
}

#==============================================================================
# Build and install pkgs common to all distros.
#
configureAndInstall() {
  local ver=1
  declare -a options
  msg "Configuration and Installation started"


  #----------------------------------------------------------
  # https://fmt.dev/latest/usage.html#building-the-library
  # version 9.1.0
  msg "Building fmt"
  cd "$SOURCE_ROOT"
  git clone https://github.com/fmtlib/fmt.git
  cd fmt
  git checkout 9.1.0
  $CMAKE -DFMT_TEST=OFF \
    -DCMAKE_CXX_STANDARD=17 \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_CXX_VISIBILITY_PRESET=hidden \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON .
  make
  sudo make install

  buildZstd |& tee -a "$LOG_FILE"

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
 if ! [[ $DISTRO =~ "rhel-9" ]]; then
   ver=1.74.0
   local uver=${ver//\./_}
   msg "Building Boost $ver"

   cd "$SOURCE_ROOT"
   URL=https://sourceforge.net/projects/boost/files/boost/${ver}/boost_${uver}.tar.gz
   curl -sSL $URL | tar xzf - || error "Boost $ver"
   cd boost_${uver}

   sed -i 's/array\.hpp/array_wrapper.hpp/g' boost/numeric/ublas/matrix.hpp
   sed -i 's/array\.hpp/array_wrapper.hpp/g' boost/numeric/ublas/storage.hpp

   ./bootstrap.sh

   options=(toolset=$TOOLSET variant=release link=shared
   runtime-link=shared threading=multi --without-python
   )

   ./b2 ${options[@]} stage
   sudo ${CENV[@]} ./b2 ${options[@]} install


   #Fix for errors "libboost_program_options.so.1.74.0: cannot open shared object file: No such file or directory" on RHEL 8.x
   if [[ $DISTRO =~ "rhel-8" ]]; then
      sudo ln -s ${SOURCE_ROOT}/boost_1_74_0/stage/lib/libboost_program_options.so.1.74.0 /usr/lib64/libboost_program_options.so.1.74.0
      sudo ln -s ${SOURCE_ROOT}/boost_1_74_0/stage/lib/libboost_thread.so.1.74.0 /usr/lib64/libboost_thread.so.1.74.0
      sudo ln -s ${SOURCE_ROOT}/boost_1_74_0/stage/lib/libboost_date_time.so.1.74.0 /usr/lib64/libboost_date_time.so.1.74.0
      sudo ln -s ${SOURCE_ROOT}/boost_1_74_0/stage/lib/libboost_regex.so.1.74.0 /usr/lib64/libboost_regex.so.1.74.0
      sudo ln -s ${SOURCE_ROOT}/boost_1_74_0/stage/lib/libboost_system.so.1.74.0 /usr/lib64/libboost_system.so.1.74.0
      sudo ln -s ${SOURCE_ROOT}/boost_1_74_0/stage/lib/libboost_unit_test_framework.so.1.74.0 /usr/lib64/libboost_unit_test_framework.so.1.74.0
   fi


   #----------------------------------------------------------
   ver=0.13.0
   msg "Building Thrift $ver"

   cd "$SOURCE_ROOT"
   URL=http://archive.apache.org/dist/thrift/${ver}/thrift-${ver}.tar.gz
   curl -sSL $URL | tar xzf - || error "Thrift $ver"
   cd thrift-${ver}
   curl -sSL ${PATCH_URL}/thrift.diff | patch -p1 || error "thrift.diff"
   ./configure --without-java --without-lua --without-go --disable-tests --disable-tutorial
   make -j 8
   sudo make install

   #Fix for "libthrift-0.13.0.so: cannot open shared object file: No such file or directory" on RHEL 8.x
   if [[ $DISTRO =~ "rhel-8" ]]; then
      sudo ln -s ${SOURCE_ROOT}/thrift-0.13.0/lib/cpp/.libs/libthrift-0.13.0.so /usr/lib64/libthrift-0.13.0.so
   fi
 fi

 if [[ $DISTRO =~ "rhel-9" ]]; then
   buildGmp
 fi

  #----------------------------------------------------------
 if  [[ $DISTRO =~ "ubuntu-2" ]]; then
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
  git clone -b scylla-${ver} https://github.com/scylladb/scylla.git --depth 1
  cd scylla
  git submodule update --init --force --recursive
  curl -sSL ${PATCH_URL}/seastar.diff | patch -d seastar -p1 || error "seastar.diff"

  if [[ $DISTRO =~ "rhel-9" ]]; then
    curl -sSL ${PATCH_URL}/scylla_rh9.diff | patch -p1 || error "scylla_rh9.diff"
  elif [[ $DISTRO =~ "rhel-8" ]]; then
    curl -sSL ${PATCH_URL}/scylla_rh8.diff | patch -p1 || error "scylla_rh8.diff"
  elif [[ $DISTRO =~ "ubuntu-2" ]]; then
    curl -sSL ${PATCH_URL}/scylla_ub.diff | patch -p1 || error "scylla_ub.diff"
  fi
  find . -type f -exec sed -i 's,wasm32-wasi,wasm32-wasip1,g' {} +
  msg "Building scylla"

  export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig:$PREFIX/lib64/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}
  echo "export PKG_CONFIG_PATH=$PKG_CONFIG_PATH" >>$ENV_VARS

  msg "PKG_CONFIG_PATH=$PKG_CONFIG_PATH"

  export cflags="-I${PREFIX}/include -I${PREFIX}/include/boost"

  ./configure.py --mode="release" --target="${TARGET}" --debuginfo=1 --cflags="${cflags}" \
    --compiler="${CXX}" --c-compiler="${CC}"

  ninja build -j 8

  if [ "$?" -ne "0" ]; then
    error "Build  for ScyllaDB failed. Please check the error logs."
  else
    msg "Build  for ScyllaDB completed successfully. "
  fi

  if [[ "$DISTRO" =~ "ubuntu-2" ]]; then
    #increase the request capacity in /proc/sys/fs/aio-max-nr for setting up Async I/O
    echo "fs.aio-max-nr = 1048576" |& sudo tee -a /etc/sysctl.conf
    sudo sysctl -p
  fi

  runTest
}

#==============================================================================
runTest() {
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
logDetails() {
  log "**************************** SYSTEM DETAILS ***************************"
  cat "/etc/os-release" >>"$LOG_FILE"
  cat /proc/version >>"$LOG_FILE"
  log "***********************************************************************"

  msg "Detected $PRETTY_NAME"
  msglog "Request details: PACKAGE NAME=$PACKAGE_NAME, VERSION=$PACKAGE_VERSION"
}

#==============================================================================
printHelp() {
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
while getopts "h?dyt?z:" opt; do
  case "$opt" in
  h | \?)
    printHelp
    exit 0
    ;;
  d) set -x ;;
  y) FORCE="true" ;;
  z) TARGET=$OPTARG ;;
  t) TESTS="true" ;;
  esac
done

#==============================================================================
gettingStarted() {
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

buildWabt() {
  cd "$SOURCE_ROOT"
  git clone --recursive https://github.com/WebAssembly/wabt
  cd wabt
  git submodule update --init
  mkdir build
  cd build
  cmake ..
  cmake --build .
}

buildGmp() {
  cd "$SOURCE_ROOT"
  sudo yum install -y xz
  URL=https://gmplib.org/download/gmp/gmp-6.2.1.tar.xz
  curl -sSL $URL | tar xJf - || error "gmplib 6.2.1"
  cd gmp-6.2.1
  ./configure --prefix=${PREFIX} --with-pic
  make
  sudo make install

  sudo mkdir -p /builddir/build/BUILD/gnutls-3.8.3/bundled_gmp/.libs/
  sudo cp ${SOURCE_ROOT}/gmp-6.2.1/.libs/libgmp.a /builddir/build/BUILD/gnutls-3.8.3/bundled_gmp/.libs/
}
#==============================================================================
buildBinutils() {
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
buildGcc() {
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
buildPython() {
  local ver=3.11.8
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
buildCmake() {
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
buildLz4() {
  ver=1.9.3
  msg "Building lz4 $ver"

  cd "$SOURCE_ROOT"
  URL=https://github.com/lz4/lz4/archive/v${ver}.tar.gz
  curl -sSL $URL | tar xzf - || error "lz4 $ver"
  cd lz4-${ver}
  sudo make install
}

#==============================================================================
buildXxHash() {
  ver=0.8.0
  msg "Building xxHash $ver"

  cd "$SOURCE_ROOT"
  URL=https://github.com/Cyan4973/xxHash/archive/v${ver}.tar.gz
  curl -sSL $URL | tar xzf - || error "xxHash $ver"
  cd xxHash-${ver}
  sudo make install

  #Fix for "libxxhash.so.0: cannot open shared object file: No such file or directory" on RHEL 8.x
  if [[ $DISTRO =~ "rhel-8" ]]; then
     sudo ln -s ${SOURCE_ROOT}/xxHash-0.8.0/libxxhash.so.0 /usr/lib64/libxxhash.so.0
  fi

}

#==============================================================================
buildZstd() {
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
  cmake -DLLVM_ENABLE_PROJECTS=clang -DCMAKE_BUILD_TYPE="Release" -G "Unix Makefiles" \
  -DGCC_INSTALL_PREFIX="/opt/rh/gcc-toolset-12/root/" -DCMAKE_C_COMPILER=/bin/gcc \
  -DCMAKE_CXX_COMPILER=/bin/g++  ../llvm
  make clang -j8
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
  sudo -E env "PATH=$PATH" cmake --build build --target install
}

function installRust() {
  cd "$SOURCE_ROOT"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh /dev/stdin -y
  export PATH="$HOME/.cargo/bin:$PATH"
  cargo install cxxbridge-cmd --root $SOURCE_ROOT/cxxbridge
  sudo cp -r $SOURCE_ROOT/cxxbridge/. /usr/local
  cargo install wasm-opt |& tee -a "$LOG_FILE"
  rustup target add wasm32-wasip1 |& tee -a "$LOG_FILE"
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
  sudo apt-get install -y --no-install-recommends gcc g++ | tee -a "${LOG_FILE}"
  sudo apt-get install -y openjdk-8-jdk libaio-dev systemtap-sdt-dev lksctp-tools xfsprogs \
    libyaml-dev openssl libevent-dev libmpfr-dev libmpcdec-dev libssl-dev libsystemd-dev \
    libsctp-dev libsnappy-dev libpciaccess-dev libxml2-dev xfslibs-dev libgnutls28-dev \
    libiconv-hook-dev liblzma-dev libbz2-dev libxslt-dev libc-ares-dev libprotobuf-dev \
    protobuf-compiler libcrypto++-dev libtool perl ant libffi-dev rapidjson-dev automake \
    make git maven ninja-build unzip bzip2 wget curl xz-utils texinfo diffutils liblua5.3-dev \
    libnuma-dev libunistring-dev python3 python3-pip pigz ragel stow patch locales valgrind \
    libudev-dev libdeflate-dev zlib1g-dev doxygen librapidxml-dev |& tee -a "$LOG_FILE"

  if [ $DISTRO = "ubuntu-22.04" ]; then
    sudo apt-get install -y libabsl-dev |& tee -a "$LOG_FILE"
    # Install GCC 12 from repo
    sudo apt-get install -y gcc-12 g++-12
    sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-12 12
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 12
    sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-12 12
    sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-12 12
  fi

  installRust

  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # C/C++ environment settings
  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  buildBinutils |& tee -a "$LOG_FILE"

  # Clang needs latest linker from bin utils, removing old linker version
  sudo rm /usr/bin/s390x-linux-gnu-ld /usr/bin/s390x-linux-gnu-ld.bfd
  sudo ln -s /usr/bin/ld /usr/bin/s390x-linux-gnu-ld
  sudo ln -s /usr/bin/ld.bfd /usr/bin/s390x-linux-gnu-ld.bfd

  if [ $DISTRO = "ubuntu-20.04" ]; then
    buildGcc |& tee -a "$LOG_FILE"
    #For clang to find this gcc version
    sudo ln -s ${PREFIX}/lib/gcc/s390x-linux-gnu/${GCC_VERSION} /usr/lib/gcc/s390x-linux-gnu/${GCC_VERSION}
    #Build python 3.11
    buildPython |& tee -a "$LOG_FILE"
  fi

  #Install Clang 17
  wget https://apt.llvm.org/llvm.sh
  sed -i 's,add-apt-repository "${REPO_NAME}",add-apt-repository "${REPO_NAME}" -y,g' llvm.sh
  chmod +x llvm.sh
  sudo ./llvm.sh 17
  rm ./llvm.sh
  sudo ln -s /usr/bin/clang-17 /usr/bin/clang
  sudo ln -s /usr/bin/clang++-17 /usr/bin/clang++
  export PATH=${SOURCE_ROOT}/llvm-project-llvmorg-17.0.6/llvm/utils/lit/tests/Inputs/lld-features:$PATH

  # C/C++ environment settings
  sudo locale-gen en_US.UTF-8
  export LC_ALL=C
  unset LANGUAGE

  export PATH=${PREFIX}/bin${PATH:+:${PATH}}
  export PATH=$PATH:~/.local/bin/
  export PATH="$HOME/.cargo/bin:$PATH"
  LD_LIBRARY_PATH=${PREFIX}/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
  LD_LIBRARY_PATH+=:${PREFIX}/lib
  LD_LIBRARY_PATH+=:/usr/lib64
  export LD_LIBRARY_PATH
  export PATH=$PATH:$HOME/.rustup/toolchains/stable-s390x-unknown-linux-gnu/lib/rustlib/s390x-unknown-linux-gnu/bin/gcc-ld
  LD_RUN_PATH=${PREFIX}/lib64${LD_RUN_PATH:+:${LD_RUN_PATH}}
  LD_RUN_PATH+=:${PREFIX}/lib
  LD_RUN_PATH+=:/usr/lib64
  export LD_RUN_PATH
  export RUSTPATH=~/.cargo/bin
  export PATH=$RUSTPATH:$PATH
  export CC=clang-17
  export CXX=clang++

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
  #buildZstd |& tee -a "$LOG_FILE"
  buildCryptopp |& tee -a "$LOG_FILE"
  buildHwloc |& tee -a "$LOG_FILE"
  buildJsonCpp |& tee -a "$LOG_FILE"
  buildAbseil |& tee -a "$LOG_FILE"
  
  if [ $DISTRO = "ubuntu-20.04" ]; then
    buildValgrind |& tee -a "$LOG_FILE"
  fi
  buildWabt |& tee -a "LOG_FILE"
  export PATH=$PATH:${SOURCE_ROOT}/wabt/build
  echo "export PATH=$PATH" >>$ENV_VARS
  echo "export LD_LIBRARY_PATH=$LD_LIBRARY_PATH" >>$ENV_VARS
  echo "export CC=$CC" >>$ENV_VARS
  echo "export CXX=$CXX" >>$ENV_VARS
  echo "export LD_RUN_PATH=$LD_RUN_PATH" >>$ENV_VARS
  source $ENV_VARS
  configureAndInstall |& tee -a "$LOG_FILE"
  ;;

#----------------------------------------------------------
"rhel-8.8" | "rhel-8.9" | "rhel-8.10")

  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  sudo dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm

  gcc_toolset="gcc-toolset-12 gcc-toolset-12-libatomic-devel"

  sudo yum install -y --allowerasing gcc gcc-c++ \
  libatomic libatomic_ops-devel java-1.8.0-openjdk-devel \
   lksctp-tools-devel xfsprogs-devel snappy-devel libyaml-devel \
  openssl-devel libevent-devel libtasn1-devel libmpcdec libidn2-devel numactl-devel \
  c-ares-devel gnutls-devel gnutls-c++ gnutls-dane perl-devel \
  python38 python38-devel python38-pip python38-PyYAML python38-setuptools python38-requests \
  make automake git maven ant ninja-build unzip bzip2 wget curl xz-devel texinfo libffi-devel \
  libpciaccess-devel libxml2-devel libtool diffutils libtool-ltdl-devel trousers-devel \
  p11-kit-devel libunistring-devel libicu-devel readline-devel lua-devel patch systemd-devel \
  valgrind-devel cmake hwloc hwloc-devel cryptopp cryptopp-devel lz4 lz4-devel jsoncpp \
  jsoncpp-devel protobuf rapidjson-devel stow yaml-cpp yaml-cpp-devel ragel langpacks-en \
  glibc-all-langpacks libdeflate libdeflate-devel file abseil-cpp-devel rapidxml-devel doxygen |& tee -a "$LOG_FILE"

  sudo yum install -y $gcc_toolset |& tee -a "$LOG_FILE"

  installRust |& tee -a "$LOG_FILE"
  export PATH="$HOME/.cargo/bin:$PATH"
  export PATH=$PATH:$HOME/.rustup/toolchains/stable-s390x-unknown-linux-gnu/lib/rustlib/s390x-unknown-linux-gnu/bin/gcc-ld
  buildBinutils |& tee -a "$LOG_FILE"

  #Build Python 3.11.8
  buildPython |& tee -a "$LOG_FILE"
  python3 -V |& tee -a "$LOG_FILE"
  python3 -m pip -V |& tee -a "$LOG_FILE"

  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  # Build clang 17
  buildClang |& tee -a "$LOG_FILE"
  clangbuild=${SOURCE_ROOT}/llvm-project-llvmorg-${CLANG_VERSION}/build
  ln -s clang++ ${SOURCE_ROOT}/llvm-project-llvmorg-${CLANG_VERSION}/build/bin/clang++-17
  export PATH=$clangbuild/bin:${SOURCE_ROOT}/llvm-project-llvmorg-17.0.6/llvm/utils/lit/tests/Inputs/lld-features:$PATH
  export LD_LIBRARY_PATH=$clangbuild/lib:$LD_LIBRARY_PATH
  export CC=clang-17
  export CXX=clang++
  # C/C++ environment settings
  export PATH=$PATH:~/.local/bin/:~/.cargo/bin
  export PATH=${PREFIX}/bin${PATH:+:${PATH}}
  LD_LIBRARY_PATH=${PREFIX}/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
  LD_LIBRARY_PATH+=:${PREFIX}/lib
  LD_LIBRARY_PATH+=:/usr/lib64
  export LD_LIBRARY_PATH

  CENV=(PATH=$PATH LD_LIBRARY_PATH=$LD_LIBRARY_PATH
    LD_RUN_PATH=$LD_RUN_PATH
    CC=$CC CXX=$CXX
  )
  msglog "${CENV[@]}"

  gcc -v |& tee -a "$LOG_FILE"
  TOOLSET=gcc
  buildXxHash |& tee -a "$LOG_FILE"
  buildAbseil |& tee -a "$LOG_FILE"
  buildWabt |& tee -a "LOG_FILE"
  export PATH=$PATH:${SOURCE_ROOT}/wabt/build
 
  echo "export PATH=$PATH" >>$ENV_VARS
  echo "export LD_LIBRARY_PATH=$LD_LIBRARY_PATH" >>$ENV_VARS
  echo "export CC=$CC" >>$ENV_VARS
  echo "export CXX=$CXX" >>$ENV_VARS
  echo "export LD_RUN_PATH=$LD_RUN_PATH" >>$ENV_VARS

  source $ENV_VARS
  configureAndInstall |& tee -a "$LOG_FILE"
  ;;

#----------------------------------------------------------
"rhel-9.2" | "rhel-9.3" | "rhel-9.4")

  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  sudo dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm

  gcc_toolset="gcc-toolset-12 gcc-toolset-12-libatomic-devel"

  sudo yum install -y --allowerasing gcc gcc-c++ \
  libatomic libatomic_ops-devel java-1.8.0-openjdk-devel lksctp-tools-devel xfsprogs-devel \
  snappy-devel libyaml-devel openssl-devel libevent-devel libtasn1-devel libmpcdec \
  libidn2-devel numactl-devel c-ares-devel gnutls-devel gnutls-c++ gnutls-dane perl-devel \
  python3.11 python3.11-devel python3.11-pip python3.11-pyyaml python3.11-setuptools python3.11-requests \
  make automake git maven ant ninja-build unzip bzip2 wget curl xz-devel texinfo libffi-devel \
  libpciaccess-devel libxml2-devel libtool diffutils libtool-ltdl-devel trousers-devel \
  p11-kit-devel libunistring-devel libicu-devel readline-devel lua-devel patch systemd-devel \
  valgrind-devel cmake hwloc hwloc-devel cryptopp cryptopp-devel lz4 lz4-devel jsoncpp \
  jsoncpp-devel protobuf rapidjson-devel stow yaml-cpp yaml-cpp-devel ragel langpacks-en \
  glibc-all-langpacks libdeflate libdeflate-devel abseil-cpp-devel doxygen thrift thrift-devel boost boost-devel \
  xxhash xxhash-devel rapidxml-devel |& tee -a "$LOG_FILE"

  sudo yum install -y $gcc_toolset |& tee -a "$LOG_FILE"

  #Install Wasm and wasm32-wasi
  installRust  |& tee -a "$LOG_FILE"
  export PATH="$HOME/.cargo/bin:$PATH"
  export PATH=$PATH:$HOME/.rustup/toolchains/stable-s390x-unknown-linux-gnu/lib/rustlib/s390x-unknown-linux-gnu/bin/gcc-ld
  buildBinutils |& tee -a "$LOG_FILE"

  #Build Python 3.11.8
  buildPython |& tee -a "$LOG_FILE"
  python3 -V |& tee -a "$LOG_FILE"
  python3 -m pip -V |& tee -a "$LOG_FILE"

  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  # Build clang 17
  buildClang |& tee -a "$LOG_FILE"
  clangbuild=${SOURCE_ROOT}/llvm-project-llvmorg-${CLANG_VERSION}/build
  ln -s clang++ ${SOURCE_ROOT}/llvm-project-llvmorg-${CLANG_VERSION}/build/bin/clang++-17
  export PATH=$clangbuild/bin:${SOURCE_ROOT}/llvm-project-llvmorg-17.0.6/llvm/utils/lit/tests/Inputs/lld-features:$PATH
  export LD_LIBRARY_PATH=$clangbuild/lib:$LD_LIBRARY_PATH
  export CC=clang-17
  export CXX=clang++

  buildWabt |& tee -a "LOG_FILE"
  export PATH=$PATH:${SOURCE_ROOT}/wabt/build

  echo "export PATH=$PATH" >>$ENV_VARS
  echo "export LD_LIBRARY_PATH=$LD_LIBRARY_PATH" >>$ENV_VARS
  echo "export CC=$CC" >>$ENV_VARS
  echo "export CXX=$CXX" >>$ENV_VARS
  #sudo ln -sf /usr/bin/python3.11 /usr/bin/python3
  source $ENV_VARS
  configureAndInstall |& tee -a "$LOG_FILE"
  ;;

#----------------------------------------------------------
*)
  errlog "$DISTRO not supported"
  ;;

esac

gettingStarted |& tee -a "$LOG_FILE"
