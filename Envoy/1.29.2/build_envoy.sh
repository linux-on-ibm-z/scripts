#!/bin/bash
# Â© Copyright IBM Corporation 2024
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Envoy/1.29.2/build_envoy.sh
# Execute build script: bash build_envoy.sh    (provide -h for help)
#==============================================================================
set -e -o pipefail

PACKAGE_NAME="Envoy"
PACKAGE_VERSION="v1.29.2"
SOURCE_ROOT="$(pwd)"

PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Envoy/1.29.2/patch"

FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
ENV_VARS=$SOURCE_ROOT/setenv.sh

PREFIX=/usr/local
declare -a CENV

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
  sudo rm -rf "$SOURCE_ROOT/https://golang.org/dl/go"${GO_VERSION}".linux-s390x.tar.gz"
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
  #Install Go
  msg "Installing Go 1.21.5"
  export GOPATH=$SOURCE_ROOT
  GO_VERSION=1.21.5

  cd $GOPATH
  wget -q https://golang.org/dl/go"${GO_VERSION}".linux-s390x.tar.gz |& tee -a  "$LOG_FILE"
  chmod ugo+r go"${GO_VERSION}".linux-s390x.tar.gz
  sudo rm -rf /usr/local/go /usr/bin/go
  sudo tar -C /usr/local -xzf go"${GO_VERSION}".linux-s390x.tar.gz
  sudo ln -sf /usr/local/go/bin/go /usr/bin/
  sudo ln -sf /usr/local/go/bin/gofmt /usr/bin/
  go version |& tee -a  "$LOG_FILE"
  export PATH=$PATH:$GOPATH/bin

  #----------------------------------------------------------
  #Building Buildozer and Buildifier
  msg "Cloning bazel/buildtools"
  cd "$SOURCE_ROOT"/
  git clone -b v6.3.2 https://github.com/bazelbuild/buildtools.git

  #Build buildifer
  msg "Building buildifer"
  cd "$SOURCE_ROOT"/buildtools/buildifier
  bazel build //buildifier
  export BUILDIFIER_BIN=$GOPATH/bin/buildifier

  #Build buildozer
  msg "Building buildozer"
  cd "$SOURCE_ROOT"/buildtools/buildozer
  bazel build //buildozer
  export BUILDOZER_BIN=$GOPATH/bin/buildozer

  #----------------------------------------------------------
  #Cloning rules_foreign_cc
  msg "Cloning rules_foreign_cc"
  cd "$SOURCE_ROOT"/
  #remove existing repo if any
  rm -rf rules_foreign_cc
  git clone -b 0.10.1 https://github.com/bazelbuild/rules_foreign_cc.git
  cd rules_foreign_cc/
  curl -sSL $PATCH_URL/rules_foreign_cc.patch | git apply -
  wget -O $SOURCE_ROOT/rules_foreign_cc/toolchains/pkgconfig-valgrind.patch $PATCH_URL/pkgconfig-valgrind.patch
  
  #----------------------------------------------------------
  msg "Cloning Envoy $PACKAGE_VERSION"

  cd "$SOURCE_ROOT"/
  #remove existing repo if any
  rm -rf envoy
  git clone --depth 1 -b ${PACKAGE_VERSION} https://github.com/envoyproxy/envoy.git
  cd envoy

  # Apply patch-
  curl -sSL $PATCH_URL/envoy_patch.diff | git apply -
  
  #Apply patch to update certificates-
  curl -sSL https://github.com/phlax/envoy/commit/c84d38dbc13982c899b9bedc290525938c92fd16.patch | git apply -

  #Apply patch for failing tests-
  curl -sSL $PATCH_URL/envoy-test.patch | git apply -

  #Move patch files to envoy/bazel which will be applied to external packages while building envoy
  wget -O $SOURCE_ROOT/envoy/bazel/boringssl-s390x.patch $PATCH_URL/boringssl-s390x.patch
  wget -O $SOURCE_ROOT/envoy/bazel/cel-cpp-memory.patch $PATCH_URL/cel-cpp-memory.patch
  wget -O $SOURCE_ROOT/envoy/bazel/grpc-s390x.patch $PATCH_URL/grpc-s390x.patch
  wget -O $SOURCE_ROOT/envoy/bazel/foreign_cc/luajit-s390x.patch $PATCH_URL/luajit-s390x.patch
  wget -O $SOURCE_ROOT/envoy/bazel/quiche-s390x.patch $PATCH_URL/quiche-s390x.patch
  
  if [[ "$DISTRO" == "sles-12.5" ]]; then
    #Apply distro specific patch
    curl -sSL $PATCH_URL/envoy-sl12.patch | git apply -
    wget -O $SOURCE_ROOT/envoy/bazel/io_uring.patch $PATCH_URL/io_uring.patch
  fi
  
  msg "Building Envoy"
  
  bazel build envoy -c opt --override_repository=rules_foreign_cc=${SOURCE_ROOT}/rules_foreign_cc --config=clang 2>&1 | tee -a "${LOG_FILE}"

  if [ "$?" -ne "0" ]; then
    error "Build  for Envoy failed. Please check the error logs."
  else
    msg "Build  for Envoy completed successfully. "
  fi

  runTest
}

#==============================================================================
runTest() {
  set +e
  if [[ "$TESTS" == "true" ]]; then
    log "TEST Flag is set, continue with running test "
    cd "$SOURCE_ROOT/envoy"
    bazel test //test/... -c opt --override_repository=rules_foreign_cc=${SOURCE_ROOT}/rules_foreign_cc --config=clang --keep_going --test_env=HEAPCHECK= 2>&1 | tee -a "${LOG_FILE}"
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
  bash build.sh [-y] [-t]
  where:
   -y install-without-confirmation
   -t test
eof
}

###############################################################################
while getopts "h?yt" opt; do
  case "$opt" in
  h | \?)
    printHelp
    exit 0
    ;;
  y) FORCE="true" ;;
  t) TESTS="true" ;;
  esac
done

#==============================================================================
gettingStarted() {
        printf -- '\n*********************************************************************************************\n'
        printf -- "Getting Started:\n\n"
        printf -- "Envoy Build Successful \n"
        printf -- "Envoy binary can be found here : $SOURCE_ROOT/envoy/bazel-bin/source/exe/envoy-static \n"
        printf -- '*********************************************************************************************\n'
        printf -- '\n'

}

buildBazel() {
  msg "Building Bazel 6.3.2"

  cd "$SOURCE_ROOT"
  mkdir bazel && cd bazel
  wget https://github.com/bazelbuild/bazel/releases/download/6.3.2/bazel-6.3.2-dist.zip
  unzip -q bazel-6.3.2-dist.zip
  chmod -R +w .
  curl -sSL https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Bazel/6.3.2/patch/bazel.patch | patch -p1
  bash ./compile.sh
}

installRust() {
  cd "$SOURCE_ROOT"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh /dev/stdin -y
}

#==============================================================================
logDetails
checkPrequisites

msglog "Installing $PACKAGE_NAME $PACKAGE_VERSION for $DISTRO"
msglog "Installing the dependencies for Envoy from repository"

case "$DISTRO" in
#----------------------------------------------------------

"rhel-8.8" | "rhel-8.9")
  printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
  sudo yum install -y autoconf curl libtool patch python3-pip pkg-config vim wget curl file git gzip make python2 python3 java-11-openjdk-devel unzip zip tar openssl-devel xz expat-devel glib2-devel gcc gcc-c++ | tee -a "${LOG_FILE}"
  
  export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
  export PATH=$JAVA_HOME/bin:$PATH
  
  #Build and Install Bazel 6.3.2
  buildBazel |& tee -a "$LOG_FILE"
  export PATH=$PATH:${SOURCE_ROOT}/bazel/output/
  
  sudo yum install -y  gcc-toolset-12-gcc-c++ gcc-toolset-12-libstdc++-devel gcc-toolset-12-binutils-devel gcc-toolset-12-binutils-gold gcc-toolset-12-libatomic-devel rust-toolset pkgconf-pkg-config openssl-devel python3.11 unzip | tee -a "${LOG_FILE}"

  #set gcc 12 as default 
  source /opt/rh/gcc-toolset-12/enable
  
  sudo yum install -y clang-14.0.6
  export CC=clang
  export CXX=clang++
  clang --version

  installRust |& tee -a "$LOG_FILE"
  export PATH=$HOME/.cargo/bin:$PATH
  
  echo "export PATH=$PATH" >>$ENV_VARS
  echo "export CC=$CC" >>$ENV_VARS
  echo "export CXX=$CXX" >>$ENV_VARS
  
  configureAndInstall |& tee -a "$LOG_FILE"
  ;;
#----------------------------------------------------------

"rhel-9.2" | "rhel-9.3")
  printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
  sudo yum install -y wget curl bison ncurses ncurses-devel pkgconfig net-tools gcc-toolset-12-gcc gcc-toolset-12-gcc-c++ gcc-toolset-12-binutils-devel gcc-toolset-12-annobin-plugin-gcc gcc-toolset-12-libstdc++-devel gcc-toolset-12-binutils-gold gcc-toolset-12-libatomic-devel patch unzip openssl-devel java-11-openjdk-devel python3 zlib-devel diffutils libtool libatomic libarchive zip file |& tee -a "${LOG_FILE}"
  
  #set gcc 12 as default
  source /opt/rh/gcc-toolset-12/enable

  #Build and Install Bazel 6.3.2
  buildBazel |& tee -a "$LOG_FILE"
  export PATH=$PATH:$SOURCE_ROOT/bazel/output/

  sudo yum install -y clang-14.0.6
  export CC=clang
  export CXX=clang++

  installRust |& tee -a "$LOG_FILE"
  export PATH=$HOME/.cargo/bin:$PATH
  
  echo "export PATH=$PATH" >>$ENV_VARS
  echo "export CC=$CC" >>$ENV_VARS
  echo "export CXX=$CXX" >>$ENV_VARS
  
  configureAndInstall |& tee -a "$LOG_FILE"
  ;;
#----------------------------------------------------------

"sles-12.5")
  printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
  sudo zypper install -y autoconf curl libtool patch python3-pip pkg-config vim wget git gzip make cmake python python3 python36 java-11-openjdk-devel unzip zip tar xz which gawk glib2-devel libexpat-devel bind-chrootenv coreutils ed expect file iproute2 iputils less libopenssl-devel python2 python3 python3-devel python3-pip python3-requests python3-setuptools python3-six python3-wheel unzip zlib-devel python3-PyYAML | tee -a "${LOG_FILE}"
  sudo zypper install -y gcc gcc-c++ gcc12-c++ git-core automake libelf-devel glibc-devel-static kmod binutils-gold | tee -a "${LOG_FILE}"
  
  sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-12 12
  sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 12
  sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-12 12
  sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-12 12

  export JAVA_HOME=/usr/lib64/jvm/java-11-openjdk
  export PATH=$JAVA_HOME/bin:$PATH
  
  #Install Openssl
  cd $SOURCE_ROOT
  wget https://www.openssl.org/source/openssl-1.1.1w.tar.gz --no-check-certificate
  tar -xzf openssl-1.1.1w.tar.gz
  cd openssl-1.1.1w
  ./config --prefix=/usr/local --openssldir=/usr/local
  make && sudo make install
  sudo mkdir -p /usr/local/etc/openssl
  sudo wget https://curl.se/ca/cacert.pem --no-check-certificate -P /usr/local/etc/openssl
  export LDFLAGS="-L/usr/local/lib/ -L/usr/local/lib64/"
  export LD_LIBRARY_PATH=/usr/local/lib/:/usr/local/lib64/${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
  export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}
  export LD_RUN_PATH=/usr/local/lib:/usr/local/lib64${LD_RUN_PATH:+:${LD_RUN_PATH}}
  export CPPFLAGS="-I/usr/local/include/ -I/usr/local/include/openssl"
  export SSL_CERT_FILE=/usr/local/etc/openssl/cacert.pem
  sudo ldconfig /usr/local/lib64

  #Install Cmake
  cd $SOURCE_ROOT
  wget https://github.com/Kitware/CMake/releases/download/v3.22.5/cmake-3.22.5.tar.gz
  tar -xf cmake-3.22.5.tar.gz
  cd cmake-3.22.5
  ./bootstrap -- -DCMAKE_BUILD_TYPE:STRING=Release
  make && sudo make install
  sudo ln -sf /usr/local/bin/cmake /usr/bin/cmake
  
  #Build and Install Bazel 6.3.2
  buildBazel |& tee -a "$LOG_FILE"
  export PATH=$PATH:${SOURCE_ROOT}/bazel/output/
  
  #Install clang 14
  cd $SOURCE_ROOT
  URL=https://github.com/llvm/llvm-project/archive/refs/tags/llvmorg-14.0.6.tar.gz
  curl -sSL $URL | tar xzf - || error "Clang 14.0.6"
  cd llvm-project-llvmorg-14.0.6
  mkdir build && cd build
  cmake -DLLVM_ENABLE_PROJECTS=clang -DCMAKE_C_COMPILER="/usr/bin/gcc" -DCMAKE_CXX_COMPILER="/usr/bin/g++"  -DCMAKE_BUILD_TYPE="Release" -G "Unix Makefiles" ../llvm
  make clang -j8
  clangbuild=${SOURCE_ROOT}/llvm-project-llvmorg-14.0.6/build
  export PATH=$clangbuild/bin:$PATH
  export LD_LIBRARY_PATH=$clangbuild/lib:$LD_LIBRARY_PATH
  cd $clangbuild/bin
  sudo ln -sf clang++ clang++-14
  export CC=${SOURCE_ROOT}/llvm-project-llvmorg-14.0.6/build/bin/clang
  export CXX=${SOURCE_ROOT}/llvm-project-llvmorg-14.0.6/build/bin/clang++-14
  cd $SOURCE_ROOT
  clang --version
  
  installRust |& tee -a "$LOG_FILE"
  export PATH=$HOME/.cargo/bin:$PATH
  
  echo "export PATH=$PATH" >>$ENV_VARS
  echo "export CC=$CC" >>$ENV_VARS
  echo "export CXX=$CXX" >>$ENV_VARS
  
  configureAndInstall |& tee -a "$LOG_FILE"
  ;;
#----------------------------------------------------------

"sles-15.5")
  printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
  sudo zypper install -y autoconf curl libtool patch python3-pip pkg-config vim wget git gcc12-c++ gzip make cmake python python3 java-11-openjdk-devel unzip zip tar xz which gawk glib2-devel libexpat-devel meson ninja gobject-introspection-devel python3-bind bind-chrootenv coreutils ed expect file iproute2 iputils lcov less libopenssl-devel netcat python2 python2-devel python3 python3-devel python3-pip python3-requests python3-setuptools python3-six python3-wheel unzip zlib-devel python3-python-gnupg python3-PyYAML | tee -a "${LOG_FILE}"

  sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-12 12
  sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 12
  sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-12 12
  sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-12 12

  export JAVA_HOME=/usr/lib64/jvm/java-11-openjdk
  export PATH=$JAVA_HOME/bin:$PATH
  
  #Build and Install Bazel 6.3.2
  buildBazel |& tee -a "$LOG_FILE"
  export PATH=$PATH:${SOURCE_ROOT}/bazel/output/
  
  #Install clang 14
  sudo zypper install -y clang14 llvm14 bpftool libclang-cpp14 libunwind llvm14-gold libLLVM14 binutils-gold
  export CC=clang
  export CXX=clang++
  clang --version
  
  installRust |& tee -a "$LOG_FILE"
  export PATH=$HOME/.cargo/bin:$PATH
  
  echo "export PATH=$PATH" >>$ENV_VARS
  echo "export CC=$CC" >>$ENV_VARS
  echo "export CXX=$CXX" >>$ENV_VARS
  
  configureAndInstall |& tee -a "$LOG_FILE"
  ;;
#----------------------------------------------------------

"ubuntu-20.04")
  printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
  sudo apt-get update
  sudo apt-get install -y autoconf curl git libtool patch python3-pip virtualenv pkg-config gcc g++ locales build-essential openjdk-11-jdk python2 python2-dev python-is-python3 python3 python3-dev zip unzip libssl-dev | tee -a "${LOG_FILE}"

  export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x
  export PATH=$JAVA_HOME/bin:$PATH

  buildBazel |& tee -a "$LOG_FILE"
  export PATH=$PATH:${SOURCE_ROOT}/bazel/output/
  
  # Build GCC 12 from source
  cd "$SOURCE_ROOT"
  URL=https://ftp.gnu.org/gnu/gcc/gcc-12.3.0/gcc-12.3.0.tar.gz
  curl -sSL $URL | tar xzf - || error "GCC 12.3.0"

  cd gcc-12.3.0
  ./contrib/download_prerequisites
  mkdir objdir && cd objdir

  ../configure --enable-languages=c,c++ --prefix=${PREFIX} \
    --enable-shared --enable-threads=posix \
    --disable-multilib --disable-libmpx \
    --with-system-zlib --with-long-double-128 --with-arch=zEC12 \
    --disable-libphobos --disable-werror \
    --build=s390x-linux-gnu --host=s390x-linux-gnu --target=s390x-linux-gnu

  make -j 8 bootstrap
  sudo make install

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
   
  # C/C++ environment settings
  sudo locale-gen en_US.UTF-8
  export LC_ALL=C
  unset LANGUAGE

  sudo apt-get install -y clang-12
  export CC=clang-12
  export CXX=clang++-12

  sudo ln -sf /usr/bin/clang-12 /usr/bin/clang
  sudo ln -sf /usr/bin/clang++-12 /usr/bin/clang++
  
  installRust |& tee -a "$LOG_FILE"
  export PATH=$HOME/.cargo/bin:$PATH

  echo "export PATH=$PATH" >>$ENV_VARS
  echo "export LD_LIBRARY_PATH=$LD_LIBRARY_PATH" >>$ENV_VARS
  echo "export CC=$CC" >>$ENV_VARS
  echo "export CXX=$CXX" >>$ENV_VARS
  echo "export LD_RUN_PATH=$LD_RUN_PATH" >>$ENV_VARS

  CENV=(PATH=$PATH LD_LIBRARY_PATH=$LD_LIBRARY_PATH
    LD_RUN_PATH=$LD_RUN_PATH
    CC=$CC CXX=$CXX
  )
  msglog "${CENV[@]}"

  configureAndInstall |& tee -a "$LOG_FILE"
  ;;
#----------------------------------------------------------

"ubuntu-22.04")
  printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
  sudo apt-get update
  sudo apt-get install -y autoconf curl git libtool patch python3-pip unzip virtualenv pkg-config locales libssl-dev build-essential openjdk-11-jdk python2 python2-dev python3 python3-dev zip | tee -a "${LOG_FILE}"
  
  # Install GCC 12 from repo
  sudo apt-get install -y gcc-12 g++-12

  sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-12 12
  sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 12
  sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-12 12
  sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-12 12
  
  export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x
  export PATH=$JAVA_HOME/bin:$PATH

  buildBazel |& tee -a "$LOG_FILE"
  export PATH=$PATH:${SOURCE_ROOT}/bazel/output/

  #Install Clang 14
  sudo apt-get update
  sudo apt-get install -y lsb-release wget software-properties-common gnupg | tee -a "${LOG_FILE}"
  wget https://apt.llvm.org/llvm.sh
  sed -i 's,add-apt-repository "${REPO_NAME}",add-apt-repository "${REPO_NAME}" -y,g' llvm.sh
  chmod +x llvm.sh
  sudo ./llvm.sh 14
  rm ./llvm.sh
  
  export CC=clang-14
  export CXX=clang++-14

  sudo ln -sf /usr/bin/clang-14 /usr/bin/clang
  sudo ln -sf /usr/bin/clang++-14 /usr/bin/clang++
  
  installRust |& tee -a "$LOG_FILE"
  export PATH=$HOME/.cargo/bin:$PATH

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

  LD_RUN_PATH=${PREFIX}/lib64${LD_RUN_PATH:+:${LD_RUN_PATH}}
  LD_RUN_PATH+=:${PREFIX}/lib
  LD_RUN_PATH+=:/usr/lib64
  export LD_RUN_PATH

  echo "export PATH=$PATH" >>$ENV_VARS
  echo "export LD_LIBRARY_PATH=$LD_LIBRARY_PATH" >>$ENV_VARS
  echo "export CC=$CC" >>$ENV_VARS
  echo "export CXX=$CXX" >>$ENV_VARS
  echo "export LD_RUN_PATH=$LD_RUN_PATH" >>$ENV_VARS

  CENV=(PATH=$PATH LD_LIBRARY_PATH=$LD_LIBRARY_PATH
    LD_RUN_PATH=$LD_RUN_PATH
    CC=$CC CXX=$CXX
  )
  msglog "${CENV[@]}"

  configureAndInstall |& tee -a "$LOG_FILE"
  ;;
#----------------------------------------------------------

"ubuntu-24.04")
  printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
  sudo apt-get update
  sudo apt-get install -y autoconf curl git libtool patch python3-pip unzip virtualenv pkg-config locales gcc g++ openssl libssl-dev build-essential openjdk-11-jdk python3 gcc-12 g++-12 zip unzip | tee -a "${LOG_FILE}"

  export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x
  export PATH=$JAVA_HOME/bin:$PATH
  
  # use gcc-12 to build bazel due to error compiling with gcc-13:  https://github.com/bazelbuild/bazel/issues/18642
  sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 20
  sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-12 20
  sudo update-alternatives --install /usr/bin/gcov gcov /usr/bin/gcov-12 20
  sudo update-alternatives --install /usr/bin/gcov-tool gcov-tool /usr/bin/gcov-tool-12 20
  sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-13 13
  sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-13 13
  sudo update-alternatives --install /usr/bin/gcov gcov /usr/bin/gcov-13 13
  sudo update-alternatives --install /usr/bin/gcov-tool gcov-tool /usr/bin/gcov-tool-13 13

  buildBazel |& tee -a "$LOG_FILE"
  export PATH=$PATH:${SOURCE_ROOT}/bazel/output/

  sudo update-alternatives --remove-all gcc
  sudo update-alternatives --remove-all g++
  sudo update-alternatives --remove-all gcov
  sudo update-alternatives --remove-all gcov-tool
  sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-13 12
  sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-13 12
  sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-13 12
  sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-13 12

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

  LD_RUN_PATH=${PREFIX}/lib64${LD_RUN_PATH:+:${LD_RUN_PATH}}
  LD_RUN_PATH+=:${PREFIX}/lib
  LD_RUN_PATH+=:/usr/lib64
  export LD_RUN_PATH

  sudo apt-get install -y clang-14
  export CC=clang-14
  export CXX=clang++-14

  sudo ln -sf /usr/bin/clang-14 /usr/bin/clang
  sudo ln -sf /usr/bin/clang++-14 /usr/bin/clang++
  
  installRust |& tee -a "$LOG_FILE"
  export PATH=$HOME/.cargo/bin:$PATH
  
  echo "export PATH=$PATH" >>$ENV_VARS
  echo "export LD_LIBRARY_PATH=$LD_LIBRARY_PATH" >>$ENV_VARS
  echo "export CC=$CC" >>$ENV_VARS
  echo "export CXX=$CXX" >>$ENV_VARS
  echo "export LD_RUN_PATH=$LD_RUN_PATH" >>$ENV_VARS

  CENV=(PATH=$PATH LD_LIBRARY_PATH=$LD_LIBRARY_PATH
    LD_RUN_PATH=$LD_RUN_PATH
    CC=$CC CXX=$CXX
  )
  msglog "${CENV[@]}"

  configureAndInstall |& tee -a "$LOG_FILE"
  ;;
#----------------------------------------------------------

esac

gettingStarted |& tee -a "$LOG_FILE"
