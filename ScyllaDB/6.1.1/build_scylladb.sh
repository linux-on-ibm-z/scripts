#!/bin/bash
# © Copyright IBM Corporation 2025
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget -q https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ScyllaDB/6.1.1/build_scylladb.sh
# Execute build script: bash build_scylladb.sh    (provide -h for help)
#==============================================================================
set -e -o pipefail

PACKAGE_NAME="ScyllaDB"
PACKAGE_VERSION="6.1.1"
SOURCE_ROOT="$(pwd)"

FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
ENV_VARS=$SOURCE_ROOT/setenv.sh

PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ScyllaDB/6.1.1/patch"

PREFIX=/usr/local
TARGET=native
GCC_VERSION=12.3.0

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
  sudo rm -rf $SOURCE_ROOT/fmt $SOURCE_ROOT/boost_1_* $SOURCE_ROOT/Python-3.12.4 $SOURCE_ROOT/cmake-* $SOURCE_ROOT/gcc-* $SOURCE_ROOT/cryptopp $SOURCE_ROOT/jsoncpp-* $SOURCE_ROOT/valgrind-* $SOURCE_ROOT/wabt $SOURCE_ROOT/ragel-* $SOURCE_ROOT/xxHash-* $SOURCE_ROOT/zstd-*
  echo "Cleaned up the artifacts."
}

#==============================================================================
# Build and install pkgs common to all distros.
#
configureAndInstall() {
  msg "Configuration and Installation started"

  #----------------------------------------------------------
  msg "Building fmt 10.2.1"
  cd "$SOURCE_ROOT"
  git clone https://github.com/fmtlib/fmt.git
  cd fmt
  git checkout 10.2.1
  cmake -DFMT_TEST=OFF \
         -DCMAKE_CXX_STANDARD=20 \
         -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
	 -DFMT_DOC=OFF \
	 -DCMAKE_VISIBILITY_INLINES_HIDDEN=ON \
	 -DFMT_PEDANTIC=ON \
	 -DFMT_WERROR=ON \
	 -DBUILD_SHARED_LIBS=ON .
  make
  sudo make install

  #----------------------------------------------------------

  if [[ $DISTRO == ubuntu* ]]; then
    msg "Installing antlr headers"

    git clone --depth 1 https://github.com/antlr/antlr3.git
    cd antlr3
    curl -sSL ${PATCH_URL}/antlr3.diff | patch -p1 || error "antlr3.diff"
    sudo cp -r runtime/Cpp/include/* ${PREFIX}/include/
  fi

  #----------------------------------------------------------

  if [[ $DISTRO == ubuntu* ]]; then
    msg "Installing Clang 17"
    cd "$SOURCE_ROOT"
    wget https://apt.llvm.org/llvm.sh
    chmod +x llvm.sh
    sudo ./llvm.sh 17
    rm ./llvm.sh
    sudo ln -sf /usr/bin/clang-17 /usr/bin/clang
    sudo ln -sf /usr/bin/clang++-17 /usr/bin/clang++
  fi
  
  #----------------------------------------------------------
  if [[ $DISTRO != "ubuntu-24.04" ]]; then
   msg "Building Boost 1.83.0"

   cd "$SOURCE_ROOT"
   URL=https://archives.boost.io/release/1.83.0/source/boost_1_83_0.tar.gz
   curl -sSL $URL | tar xzf -
   cd boost_1_83_0
   ./bootstrap.sh
   sudo ./b2 variant=release link=shared runtime-link=shared threading=multi install
   if [[ $DISTRO =~ "rhel" ]]; then
     sudo bash -c "echo -e ''"$PREFIX"'/lib\n'"$PREFIX"'/lib64' > /etc/ld.so.conf.d/scylla.conf"
   fi
   sudo ldconfig
  fi

  #----------------------------------------------------------

  sudo wget https://dl.minio.io/server/minio/release/linux-s390x/minio -P ${PREFIX}/bin
  sudo wget https://dl.min.io/client/mc/release/linux-s390x/mc -P ${PREFIX}/bin
  sudo chmod +x ${PREFIX}/bin/mc ${PREFIX}/bin/minio

  ver=${PACKAGE_VERSION}
  msg "Cloning Scylla $ver"

  cd "$SOURCE_ROOT"/
  git clone -b scylla-${ver} https://github.com/scylladb/scylla.git --depth 1
  cd scylla
  git submodule update --init --force --recursive
  
  curl -sSL ${PATCH_URL}/scylladb.diff | patch -p1 || error "scylladb.diff"

  msg "Building scylla"

  ./configure.py --mode="release" --target=${TARGET} \
--cflags="${EXTRA_CFLAGS}-I${PREFIX}/include" --ldflags="${EXTRA_LDFLAGS}-L${PREFIX}/lib"

  ninja build -j$(nproc)

  if [ "$?" -ne "0" ]; then
    error "Build  for ScyllaDB failed. Please check the error logs."
  else
    msg "Build  for ScyllaDB completed successfully. "
  fi

  if [[ "$DISTRO" =~ "ubuntu" ]]; then
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
  bash build_scylladb.sh [-z (z13|z14|z15|z16)] [-y] [-d] [-t]
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
          Run the following commands to use ScyllaDB:
          $SOURCE_ROOT/scylla/build/release/scylla --help
          More information can be found here:
          https://github.com/scylladb/scylla/blob/master/HACKING.md
eof
}

#==============================================================================
buildRagel() {
  cd "$SOURCE_ROOT"
  URL=http://www.colm.net/files/ragel/ragel-6.10.tar.gz
  curl -sSL $URL | tar xzf -
  cd ragel-6.10
  ./configure
  make -j$(nproc)
  sudo make install
}

#==============================================================================
buildAntlr3() {
  local ver=3.5.2

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
}

#==============================================================================
buildWabt() {
  cd "$SOURCE_ROOT"
  git clone -b 1.0.27 --recursive https://github.com/WebAssembly/wabt
  cd wabt
  git submodule update --init
  mkdir build
  cd build
  CC=gcc CXX=g++ cmake ..
  cmake --build .
  sudo make install
}

#==============================================================================
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
buildGcc() {
  msg "Building GCC $GCC_VERSION"
  cd "$SOURCE_ROOT"

  sudo apt install -y gcc g++

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

  make -j$(nproc) bootstrap
  sudo make install

  sudo update-alternatives --install /usr/bin/cc cc ${PREFIX}/bin/gcc 40
  sudo sed -i "1s,^,${PREFIX}/lib64\n," /etc/ld.so.conf.d/s390x-linux-gnu.conf
  sudo ldconfig
}

#==============================================================================
buildPython() {
  local ver=3.12.4
  msg "Building Python $ver"

  cd "$SOURCE_ROOT"
  URL="https://www.python.org/ftp/python/${ver}/Python-${ver}.tgz"
  curl -sSL $URL | tar xzf - || error "Python $ver"
  cd Python-${ver}
  ./configure --enable-optimizations
  make
  sudo make install
  pip3 install --user --upgrade pip
  pip3 install --user pyparsing colorama pyyaml boto3 requests pytest traceback-with-variables \
  scylla-driver scylla-api-client aiohttp==3.9.5 tabulate boto3 pytest-asyncio \
  geomet treelib allure-pytest unidiff humanfriendly redis

  export PATH="$HOME/.local/bin:$PATH"
}

#==============================================================================
buildGdb() {
  msg "Building GDB 15.2"
  cd "$SOURCE_ROOT"
  wget "http://ftp.gnu.org/gnu/gdb/gdb-15.2.tar.gz"
  tar -xzf gdb-15.2.tar.gz
  cd gdb-15.2
  ./configure --with-python
  make -j$(nproc)
  sudo make install
}

#==============================================================================
buildCmake() {
  local ver=3.27.9
  msg "Building cmake $ver"

  cd "$SOURCE_ROOT"
  URL=https://github.com/Kitware/CMake/releases/download/v${ver}/cmake-${ver}.tar.gz
  curl -sSL $URL | tar xzf - || error "cmake $ver"
  cd cmake-${ver}
  CC=/usr/bin/gcc CXX=/usr/bin/g++ ./bootstrap --parallel=$(nproc)
  make -j$(nproc)
  sudo make install
  cmake --version
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
  cmake ../..
  make -j$(nproc)
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
}

#==============================================================================
buildZstd() {
  ver=1.5.6
  msg "Building zstd $ver"

  cd "$SOURCE_ROOT"
  URL=https://github.com/facebook/zstd/releases/download/v${ver}/zstd-${ver}.tar.gz
  curl -sSL $URL | tar xzf - || error "zstd $ver"
  cd zstd-${ver}
  cd lib
  make -j$(nproc)
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
  ./configure
  make -j$(nproc)
  sudo make install
}

#==============================================================================
function installRust() {
  local ver=1.0.188
  cd "$SOURCE_ROOT"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh /dev/stdin -y
  export PATH="$HOME/.cargo/bin:$PATH"
  cargo install cxxbridge-cmd --version $ver  
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
"ubuntu-20.04")
  sudo apt-get update >/dev/null
  sudo apt-get install -y software-properties-common
  sudo add-apt-repository -y ppa:ubuntu-toolchain-r/test
  sudo apt-get update >/dev/null
  sudo apt-get install -y openjdk-8-jdk libaio-dev systemtap-sdt-dev lksctp-tools xfsprogs \
  libyaml-dev openssl libevent-dev libmpfr-dev libmpcdec-dev libssl-dev libsystemd-dev \
  libsctp-dev libsnappy-dev libpciaccess-dev libxml2-dev xfslibs-dev libgnutls28-dev \
  libiconv-hook-dev liblzma-dev libbz2-dev libxslt-dev libc-ares-dev libprotobuf-dev \
  protobuf-compiler libtool perl ant libffi-dev rapidjson-dev automake \
  make git maven ninja-build unzip bzip2 wget curl xz-utils texinfo diffutils liblua5.3-dev \
  libnuma-dev libunistring-dev pigz ragel stow patch locales \
  libudev-dev libdeflate-dev zlib1g-dev doxygen librapidxml-dev \
  libzstd-dev libxxhash-dev \
  liblz4-dev libhwloc-dev libyaml-cpp-dev antlr3 net-tools |& tee -a "$LOG_FILE"

  buildGcc |& tee -a "$LOG_FILE"
  #For clang to find this gcc version
  sudo ln -s ${PREFIX}/lib/gcc/s390x-linux-gnu/${GCC_VERSION} /usr/lib/gcc/s390x-linux-gnu/${GCC_VERSION}
  #Build python 3.12
  buildPython
  buildCmake |& tee -a "$LOG_FILE"
  buildWabt |& tee -a "LOG_FILE"
  buildValgrind |& tee -a "$LOG_FILE"
  buildCryptopp |& tee -a "$LOG_FILE"
  buildJsonCpp |& tee -a "$LOG_FILE"
  buildGdb |& tee -a "$LOG_FILE"

  installRust
  # C/C++ environment settings
  sudo locale-gen en_US.UTF-8
  export LC_ALL=C
  unset LANGUAGE
  python3 --version |& tee -a "$LOG_FILE"
  configureAndInstall |& tee -a "$LOG_FILE"

  ;;

"ubuntu-22.04" | "ubuntu-24.04")
  sudo apt-get update >/dev/null
  sudo apt-get install -y software-properties-common
  sudo add-apt-repository -y ppa:ubuntu-toolchain-r/test
  sudo apt-get update >/dev/null
  sudo apt-get install -y openjdk-8-jdk libaio-dev systemtap-sdt-dev lksctp-tools xfsprogs \
  libyaml-dev openssl libevent-dev libmpfr-dev libmpcdec-dev libssl-dev libsystemd-dev \
  libsctp-dev libsnappy-dev libpciaccess-dev libxml2-dev xfslibs-dev libgnutls28-dev \
  libiconv-hook-dev liblzma-dev libbz2-dev libxslt-dev libc-ares-dev libprotobuf-dev \
  protobuf-compiler libcrypto++-dev libtool perl ant libffi-dev rapidjson-dev automake \
  make git maven ninja-build unzip bzip2 wget curl xz-utils texinfo diffutils liblua5.3-dev \
  libnuma-dev libunistring-dev pigz ragel stow patch locales valgrind \
  libudev-dev libdeflate-dev zlib1g-dev doxygen librapidxml-dev \
  libjsoncpp-dev libzstd-dev libxxhash-dev \
  liblz4-dev cmake libhwloc-dev libyaml-cpp-dev wabt antlr3 net-tools |& tee -a "$LOG_FILE"

  if [ $DISTRO = "ubuntu-22.04" ]; then
    # Install GCC 12 from repo
    sudo apt-get install -y gcc-12 g++-12
    sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-12 12
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 12
    sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-12 12
    sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-12 12
    buildPython
    buildGdb |& tee -a "$LOG_FILE"
  fi

  if [ $DISTRO = "ubuntu-24.04" ]; then
    sudo apt install -y gcc-12 g++-12 libboost-all-dev python3 python3-pip python3-aiohttp python3-magic \
      python3-colorama python3-tabulate python3-boto3 python3-pytest python3-pytest-asyncio \
      python3-redis python3-unidiff python3-humanfriendly python3-jinja2 python3-geomet python3-treelib gdb
    pip3 install --user --break-system-packages scylla-driver traceback-with-variables scylla-api-client allure-pytest
    export PATH="$HOME/.local/bin:$PATH"
    sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-12 12
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 12
    sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-12 12
    sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-12 12
    export EXTRA_CFLAGS="--gcc-install-dir=/usr/bin/../lib/gcc/s390x-linux-gnu/12 "
  fi

  installRust

  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # C/C++ environment settings
  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  # C/C++ environment settings
  sudo locale-gen en_US.UTF-8
  export LC_ALL=C
  unset LANGUAGE

  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  python3 --version |& tee -a "$LOG_FILE"
  configureAndInstall |& tee -a "$LOG_FILE"
  ;;

#----------------------------------------------------------
"rhel-8.8" | "rhel-8.10" | "rhel-9.2" | "rhel-9.4" | "rhel-9.5")

  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  if [[ $DISTRO =~ "rhel-8" ]]; then
    sudo dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
  else
    sudo dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
   fi

  sudo yum install -y --allowerasing libatomic libatomic_ops-devel \
   java-1.8.0-openjdk-devel mpfr-devel llvm-toolset-17.0.6 \
   lksctp-tools-devel xfsprogs-devel snappy-devel libyaml-devel \
  openssl-devel libevent-devel libtasn1-devel libmpcdec libidn2-devel numactl-devel \
  c-ares-devel gnutls-devel gnutls-c++ gnutls-dane perl-devel \
  make automake git maven ant ninja-build unzip bzip2 wget curl xz-devel texinfo libffi-devel \
  libpciaccess-devel libxml2-devel libtool diffutils libtool-ltdl-devel trousers-devel \
  p11-kit-devel libunistring-devel libicu-devel readline-devel lua-devel patch systemd-devel \
  valgrind-devel cmake hwloc hwloc-devel cryptopp cryptopp-devel lz4 lz4-devel jsoncpp \
  jsoncpp-devel protobuf protobuf-devel rapidjson-devel stow yaml-cpp yaml-cpp-devel langpacks-en \
  glibc-all-langpacks libdeflate libdeflate-devel file abseil-cpp-devel rapidxml-devel doxygen net-tools python3.12 python3.12-devel python3.12-pip gcc-toolset-12 gcc-toolset-12-libatomic-devel iproute |& tee -a "$LOG_FILE"

  sudo alternatives --install /usr/bin/ld ld /opt/rh/gcc-toolset-12/root/usr/bin/ld.bfd 100
  sudo ln -s /opt/rh/gcc-toolset-12/root/usr/bin/ld.bfd ${PREFIX}/bin
  sudo ln -s /opt/rh/gcc-toolset-12/root/usr/lib/gcc/s390x-redhat-linux/12/libatomic.so ${PREFIX}/lib/libatomic.so
  sudo ln -s /opt/rh/gcc-toolset-12/root/usr/lib/gcc/s390x-redhat-linux/12/libatomic.a ${PREFIX}/lib/libatomic.a
  export EXTRA_CFLAGS="--gcc-install-dir=/opt/rh/gcc-toolset-12/root/usr/lib/gcc/s390x-redhat-linux/12 "
  sudo alternatives --install ${PREFIX}/bin/cc cc /opt/rh/gcc-toolset-12/root/usr/bin/gcc 30
  sudo alternatives --install ${PREFIX}/bin/gcc gcc /opt/rh/gcc-toolset-12/root/usr/bin/gcc 30
  sudo alternatives --install ${PREFIX}/bin/g++ g++ /opt/rh/gcc-toolset-12/root/usr/bin/g++ 30
  if [[ $DISTRO =~ "rhel-9" ]]; then
    sudo ln -s /usr/bin/python3.12 /usr/local/bin/python3
    sudo ln -s /usr/bin/pip3.12 /usr/local/bin/pip3
  fi

  installRust
  export PATH=$PATH:$HOME/.rustup/toolchains/stable-s390x-unknown-linux-gnu/lib/rustlib/s390x-unknown-linux-gnu/bin/gcc-ld

  #Install Python packages
  pip3 install --user --upgrade pip
  pip3 install --user pyparsing colorama pyyaml boto3 requests pytest traceback-with-variables \
  scylla-driver scylla-api-client aiohttp==3.9.5 tabulate boto3 pytest-asyncio \
  geomet treelib allure-pytest unidiff humanfriendly redis

  export PATH="$HOME/.local/bin:$PATH"

  buildAntlr3 |& tee -a "$LOG_FILE"
  buildRagel |& tee -a "$LOG_FILE"
  buildWabt |& tee -a "LOG_FILE"
  buildZstd |& tee -a "$LOG_FILE"
  buildGdb |& tee -a "$LOG_FILE"

  if [[ $DISTRO =~ "rhel-8" ]]; then
    buildXxHash |& tee -a "$LOG_FILE"
  else
    sudo yum install -y xxhash-devel
    buildGmp |& tee -a "$LOG_FILE"
  fi

  export EXTRA_LDFLAGS="-B${PREFIX}/bin "

  configureAndInstall |& tee -a "$LOG_FILE"
  ;;

#----------------------------------------------------------
*)
  errlog "$DISTRO not supported"
  ;;

esac

gettingStarted |& tee -a "$LOG_FILE"
