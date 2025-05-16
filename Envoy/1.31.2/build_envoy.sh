#!/bin/bash
# © Copyright IBM Corporation 2024, 2025
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Envoy/1.31.2/build_envoy.sh
# Execute build script: bash build_envoy.sh    (provide -h for help)
#==============================================================================
set -e -o pipefail

PACKAGE_NAME="Envoy"
PACKAGE_VERSION="v1.31.2"
SOURCE_ROOT="$(pwd)"

PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Envoy/1.31.2/patch"

FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
ENV_VARS=$SOURCE_ROOT/setenv.sh

BAZEL_VERSION="6.5.0"
GO_VERSION="1.23.1"
LLVM_HOME_DIR=""
GCC_TOOLCHAIN_VERSION_OVERRIDE=""

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
  msg "Configuration and Installation started"

  buildAndInstallBazel
  installGo
  installRust

  EXTRA_BAZEL_ARGS_ENVOY=()
  if [[ ${GCC_TOOLCHAIN_SOURCE} == "local" ]]; then
    buildAndInstallGcc
    buildAndInstallBinutils
    EXTRA_BAZEL_ARGS_ENVOY=("--action_env=LD_LIBRARY_PATH=/usr/local/lib64" "--host_action_env=LD_LIBRARY_PATH=/usr/local/lib64")
  fi

  saveEnvVars

  #----------------------------------------------------------
  msg "Cloning Envoy $PACKAGE_VERSION"

  cd "$SOURCE_ROOT"/
  rm -rf envoy
  retry git clone --depth 1 -b ${PACKAGE_VERSION} https://github.com/envoyproxy/envoy.git
  cd envoy
  ./bazel/setup_clang.sh "$LLVM_HOME_DIR"
  if [[ ${GCC_TOOLCHAIN_SOURCE} != "" && ${GCC_TOOLCHAIN_VERSION_OVERRIDE} != "" ]]; then
    setupGccToolchain "$GCC_TOOLCHAIN_SOURCE" "$GCC_TOOLCHAIN_VERSION_OVERRIDE"
  fi

  # Apply patches to allow envoy to build
  curl -sSL https://github.com/envoyproxy/envoy/commit/55b0fc45cfdc2c0df002690606853540cf794fab.patch | git apply -
  curl -sSL $PATCH_URL/envoy-build.patch | git apply -
  
  # Apply patches for failing tests
  curl -sSL $PATCH_URL/envoy-test.patch | git apply -
  curl -sSL https://github.com/envoyproxy/envoy/commit/f6a84d8c66c1346063c32d046b56e52b28b4da9a.patch | git apply -

  # Move patch files to envoy/bazel which will be applied to external packages while building envoy
  curl -sSL $PATCH_URL/boringssl-s390x.patch > $SOURCE_ROOT/envoy/bazel/boringssl-s390x.patch
  curl -sSL $PATCH_URL/cel-cpp-memory.patch > $SOURCE_ROOT/envoy/bazel/cel-cpp-memory.patch
  curl -sSL $PATCH_URL/cel-cpp-json.patch > $SOURCE_ROOT/envoy/bazel/cel-cpp-json.patch
  curl -sSL $PATCH_URL/grpc-s390x.patch > $SOURCE_ROOT/envoy/bazel/grpc-s390x.patch
  curl -sSL $PATCH_URL/rules_foreign_cc-s390x.patch > $SOURCE_ROOT/envoy/bazel/rules_foreign_cc-s390x.patch
  curl -sSL https://github.com/iii-i/moonjit/commit/db9c993d2ffcf09b3995b8949bb8f5026e610857.patch > $SOURCE_ROOT/envoy/bazel/foreign_cc/luajit-s390x.patch
  curl -sSL https://github.com/iii-i/moonjit/commit/e0728b5f0616088db6f7856b5eaba91625e23577.patch >> $SOURCE_ROOT/envoy/bazel/foreign_cc/luajit-s390x.patch
  curl -sSL $PATCH_URL/luajit-as.patch > $SOURCE_ROOT/envoy/bazel/foreign_cc/luajit-as.patch
  curl -sSL $PATCH_URL/quiche-s390x.patch > $SOURCE_ROOT/envoy/bazel/quiche-s390x.patch

  msg "Building Envoy"
  
  bazel build envoy -c opt --config=clang --test_env=HEAPCHECK= "${EXTRA_BAZEL_ARGS_ENVOY[@]}"

  runTest
}

#==============================================================================
runTest() {
  set +e
  if [[ "$TESTS" == "true" ]]; then
    msg "TEST Flag is set, continue with running test "
    cd "$SOURCE_ROOT/envoy"
    bazel test //test/... -c opt --config=clang --keep_going --test_env=HEAPCHECK= "${EXTRA_BAZEL_ARGS_ENVOY[@]}"
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

buildAndInstallBazel() {
  msg "Building Bazel $BAZEL_VERSION"
  cd "$SOURCE_ROOT"
  mkdir -p bazel
  cd bazel/
  wget -q https://github.com/bazelbuild/bazel/releases/download/${BAZEL_VERSION}/bazel-${BAZEL_VERSION}-dist.zip
  unzip -q bazel-${BAZEL_VERSION}-dist.zip
  chmod -R +w .
  curl -sSL $PATCH_URL/dist-md5.patch | patch -p1
  env EXTRA_BAZEL_ARGS="--tool_java_runtime_version=local_jdk" bash ./compile.sh
  sudo cp output/bazel /usr/local/bin/
}

installGo() {
  msg "Installing Go"
  cd "$SOURCE_ROOT"
  wget -q https://golang.org/dl/go"${GO_VERSION}".linux-s390x.tar.gz
  chmod ugo+r go"${GO_VERSION}".linux-s390x.tar.gz
  sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf go"${GO_VERSION}".linux-s390x.tar.gz
  export PATH=/usr/local/go/bin:$PATH
  go version
}

installRust() {
  msg "Installing Rust"
  cd "$SOURCE_ROOT"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh /dev/stdin -y
  export PATH=$HOME/.cargo/bin:$PATH
  rustc --version
  cargo --version
}

buildAndInstallGcc() {
  # Build GCC 12 from source
  GCC_INSTALL_DIR="/usr/local"
  GCC_BIN_SUFFIX="-12"
  cd "$SOURCE_ROOT"
  URL=https://ftp.gnu.org/gnu/gcc/gcc-12.3.0/gcc-12.3.0.tar.gz
  curl -sSL $URL | tar xzf - || error "GCC 12.3.0"

  cd gcc-12.3.0
  ./contrib/download_prerequisites
  mkdir objdir && cd objdir

  ../configure --enable-languages=c++ --prefix=${GCC_INSTALL_DIR} \
    --program-suffix=${GCC_BIN_SUFFIX} \
    --enable-shared --enable-threads=posix \
    --disable-multilib --disable-libmpx \
    --with-system-zlib --with-long-double-128 --with-arch=z13 \
    --disable-libphobos --disable-werror \
    --with-gcc-major-version-only \
    --build=s390x-linux-gnu --host=s390x-linux-gnu --target=s390x-linux-gnu

  make -j "$(nproc)" bootstrap
  sudo make install

  LD_LIBRARY_PATH=${GCC_INSTALL_DIR}/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
  export LD_LIBRARY_PATH

  LD_RUN_PATH=${GCC_INSTALL_DIR}/lib64${LD_RUN_PATH:+:${LD_RUN_PATH}}
  export LD_RUN_PATH

  # C/C++ environment settings
  sudo locale-gen en_US.UTF-8
  export LC_ALL=C
  unset LANGUAGE
}

buildAndInstallBinutils() {
  local ver=2.38

  msg "Building binutils $ver"
  cd "$SOURCE_ROOT"

  URL=https://ftp.gnu.org/gnu/binutils/binutils-${ver}.tar.gz
  curl -sSL $URL | tar xzf - || error "binutils $ver"
  cd binutils-${ver}
  mkdir objdir
  cd objdir

  CC=/usr/bin/gcc ../configure --prefix=/usr --build=s390x-linux-gnu --enable-gold --program-prefix="s390x-linux-gnu-"
  make -j "$(nproc)"
  sudo make install
}

saveEnvVar() {
  local name=$1
  local value=$2
  echo "export $name=$value" >>"$ENV_VARS"
  msg "$name=$value"
}

saveEnvVars() {
  msg "Environment:"
  saveEnvVar PATH "$PATH"
  saveEnvVar JAVA_HOME "$JAVA_HOME"
  [[ ${LD_LIBRARY_PATH:-unset} == "unset" ]] || saveEnvVar LD_LIBRARY_PATH "$LD_LIBRARY_PATH"
  [[ ${LD_RUN_PATH:-unset} == "unset" ]] || saveEnvVar LD_RUN_PATH "$LD_RUN_PATH"
  [[ ${LC_ALL:-unset} == "unset" ]] || saveEnvVar LC_ALL "$LC_ALL"
}

setupDistroGccToolchainDir() {
  local gcc_version=$1
  local subdir=$2
  # Override any installed gcc toolchain dir by setting a higher version
  sudo ln -s "/usr/${subdir}/${gcc_version}" "/usr/${subdir}/99"
}

setupLocalGccToolchainDir() {
  local src_subdir=$1
  local dst_subdir=$2
  # Override any installed gcc toolchain dir by setting a higher version
  sudo mkdir -p "/usr/${dst_subdir}/99/"
  sudo ln -s "/usr/local/${src_subdir}"/* "/usr/${dst_subdir}/99/"
}

# Set a specific version of gcc's libstdc++ to be used by clang
setupGccToolchain() {
  local source=$1
  local gcc_version=$2
  if [[ $source == "distro" ]]; then
    setupDistroGccToolchainDir "$gcc_version" "include/s390x-linux-gnu/c++"
    setupDistroGccToolchainDir "$gcc_version" "include/c++"
    setupDistroGccToolchainDir "$gcc_version" "lib/gcc/s390x-linux-gnu"
  elif [[ $source == "local" ]]; then
    setupLocalGccToolchainDir "include/c++/$gcc_version" "include/c++"
    setupLocalGccToolchainDir "lib/gcc/s390x-linux-gnu/$gcc_version" "lib/gcc/s390x-linux-gnu"
    setupLocalGccToolchainDir "lib64" "lib/gcc/s390x-linux-gnu"
  else
    error "Unknown gcc toolchain source: $source"
  fi
}

function retry() {
    local max_retries=5
    local retry=0

    until "$@"; do
        exit=$?
        wait=3
        retry=$((retry + 1))
        if [[ $retry -lt $max_retries ]]; then
            echo "Retry $retry/$max_retries exited $exit, retrying in $wait seconds..."
            sleep $wait
        else
            echo "Retry $retry/$max_retries exited $exit, no more retries left."
            return $exit
        fi
    done
    return 0
}

#==============================================================================
logDetails
checkPrequisites

msglog "Installing $PACKAGE_NAME $PACKAGE_VERSION for $DISTRO"
msglog "Installing the dependencies for Envoy from repository"

case "$DISTRO" in
#----------------------------------------------------------

"rhel-8.10" | "rhel-9.4")
  printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
  ALLOWERASING=""
  if [[ "$DISTRO" == rhel-9* ]]; then
    ALLOWERASING="--allowerasing"
  fi
  sudo yum install -y ${ALLOWERASING} wget curl zip unzip patch clang-14.0.6 llvm-devel-14.0.6 gcc-toolset-12-gcc gcc-toolset-12-gcc-c++ gcc-toolset-12-libstdc++-devel gcc-toolset-12-binutils-devel gcc-toolset-12-binutils-gold gcc-toolset-12-annobin-plugin-gcc gcc-toolset-12-libatomic-devel pkgconf-pkg-config openssl-devel java-11-openjdk-devel python3.11 |& tee -a "${LOG_FILE}"
  LLVM_HOME_DIR="/usr"

  #set gcc 12 as default
  source /opt/rh/gcc-toolset-12/enable

  configureAndInstall |& tee -a "$LOG_FILE"
  ;;
#----------------------------------------------------------

"sles-15.6")
  printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
  if [[ $DISTRO == "sles-15.6" ]]; then
    sudo zypper addrepo --priority 199 http://download.opensuse.org/distribution/leap/15.6/repo/oss/ oss
    sudo zypper --gpg-auto-import-keys refresh -r oss
  fi
  sudo zypper install -y awk autoconf curl libtool patch pkg-config wget git gcc12-c++ gcc-c++ clang14 llvm14-devel binutils-gold gzip make cmake python311 java-11-openjdk-devel unzip zip tar xz libopenssl-devel |& tee -a "${LOG_FILE}"
  LLVM_HOME_DIR="/usr"

  export JAVA_HOME=/usr/lib64/jvm/java-11-openjdk
  export PATH=$JAVA_HOME/bin:$PATH

  configureAndInstall |& tee -a "$LOG_FILE"
  ;;
#----------------------------------------------------------

"ubuntu-22.04")
  printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
  sudo apt-get update
  sudo apt-get install -y autoconf curl git libtool patch python3-pip unzip virtualenv pkg-config locales libssl-dev build-essential openjdk-11-jdk-headless python2 python2-dev python3 python3-dev zip | tee -a "${LOG_FILE}"
  
  # Install GCC 12 from repo
  sudo apt-get install -y gcc-12 g++-12

  sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-12 12
  sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 12
  sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-12 12
  sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-12 12
  
  export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x
  export PATH=$JAVA_HOME/bin:$PATH

  #Install Clang 14
  sudo apt-get update
  sudo apt-get install -y lsb-release wget software-properties-common gnupg | tee -a "${LOG_FILE}"
  wget https://apt.llvm.org/llvm.sh
  chmod +x llvm.sh
  sudo ./llvm.sh 14
  rm ./llvm.sh
  LLVM_HOME_DIR="/usr/lib/llvm-14"
  
  configureAndInstall |& tee -a "$LOG_FILE"
  ;;
#----------------------------------------------------------

"ubuntu-24.04" | "ubuntu-24.10")
  printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
  sudo apt-get update
  sudo apt-get install -y autoconf curl git libtool patch python3-pip unzip virtualenv pkg-config locales clang-14 gcc g++ libstdc++-12-dev openssl libssl-dev build-essential openjdk-11-jdk-headless python3 zip unzip | tee -a "${LOG_FILE}"
  LLVM_HOME_DIR="/usr/lib/llvm-14"
  GCC_TOOLCHAIN_VERSION_OVERRIDE="12"
  GCC_TOOLCHAIN_SOURCE="distro"

  export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x
  export PATH=$JAVA_HOME/bin:$PATH

  configureAndInstall |& tee -a "$LOG_FILE"
  ;;
#----------------------------------------------------------

esac

gettingStarted |& tee -a "$LOG_FILE"
