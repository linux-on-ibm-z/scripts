#!/bin/bash
# © Copyright IBM Corporation 2025, 2026
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Envoy/1.36.3/build_envoy.sh
# Execute build script: bash build_envoy.sh    (provide -h for help)
#==============================================================================
set -e -o pipefail

PACKAGE_NAME="Envoy"
PACKAGE_VERSION="v1.36.3"
SOURCE_ROOT="$(pwd)"
PATCH_VERSION="${PACKAGE_VERSION#v}"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Envoy/${PATCH_VERSION}/patch"

FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
ENV_VARS=$SOURCE_ROOT/setenv.sh

CLANG_VERSION="18.1.8"
BAZEL_VERSION="7.7.1"
GO_VERSION="1.24.6"
RULES_RUST_VERSION="0.56.0"
LLVM_HOME_DIR="${SOURCE_ROOT}/LLVM-${CLANG_VERSION}-Linux"

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
# Set the Distro ID
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
  sudo rm -rf "$SOURCE_ROOT/go"${GO_VERSION}".linux-s390x.tar.gz"
  echo "Cleaned up the artifacts."
}

#==============================================================================
# Build and install pkgs common to all distros.
#
configureAndInstall() {
  msg "Configuration and Installation started"

  buildAndInstallClang
  buildAndInstallBazel
  installGo
  installRust
  buildAndInstallRulesRustCargoBazel

  saveEnvVars

  #----------------------------------------------------------
  msg "Cloning Envoy $PACKAGE_VERSION"

  cd "$SOURCE_ROOT"/
  rm -rf envoy
  retry git clone --depth 1 -b ${PACKAGE_VERSION} https://github.com/envoyproxy/envoy.git
  cd envoy
  ./bazel/setup_clang.sh "$LLVM_HOME_DIR"
  setupBazelEnvironment

  # Apply patches to allow envoy to build
  curl -sSL $PATCH_URL/envoy-build.patch | git apply -
  curl -sSL $PATCH_URL/envoy-gurl-backport.patch | git apply -
  
  # Apply patches for failing tests
  curl -sSL $PATCH_URL/envoy-test.patch | git apply -

  # Move patch files to envoy/bazel which will be applied to external packages while building envoy
  curl -sSL $PATCH_URL/boringssl-s390x.patch > $SOURCE_ROOT/envoy/bazel/boringssl-s390x.patch
  curl -sSL $PATCH_URL/quiche-s390x.patch > $SOURCE_ROOT/envoy/bazel/external/quiche-s390x.patch
  curl -sSL $PATCH_URL/proxy_wasm_cpp_host-s390x.patch > $SOURCE_ROOT/envoy/bazel/proxy_wasm_cpp_host-s390x.patch
  curl -sSL $PATCH_URL/rules_foreign_cc-s390x.patch > $SOURCE_ROOT/envoy/bazel/rules_foreign_cc-s390x.patch
  curl -sSL https://github.com/iii-i/moonjit/commit/dee73f516f0da49e930dcfa1dd61720dcb69b7dd.patch > $SOURCE_ROOT/envoy/bazel/foreign_cc/luajit-s390x.patch
  curl -sSL https://github.com/iii-i/moonjit/commit/035f133798adb856391928600f7cb6b4f81578ab.patch >> $SOURCE_ROOT/envoy/bazel/foreign_cc/luajit-s390x.patch
  curl -sSL https://github.com/openresty/luajit2/commit/e598aeb7426dbc069f90ba70db9bce43cd573b0e.patch >> $SOURCE_ROOT/envoy/bazel/foreign_cc/luajit-s390x.patch
  curl -sSL $PATCH_URL/highway-s390x.patch > $SOURCE_ROOT/envoy/bazel/highway-s390x.patch
  curl -sSL $PATCH_URL/luajit-as.patch > $SOURCE_ROOT/envoy/bazel/foreign_cc/luajit-as.patch
  curl -sSL $PATCH_URL/grpc-s390x.patch > $SOURCE_ROOT/envoy/bazel/grpc-s390x.patch

  msg "Building Envoy"

  bazel build envoy -c opt --config=clang
  runTest
}

#==============================================================================
runTest() {
  set +e
  if [[ "$TESTS" == "true" ]]; then
    msg "TEST Flag is set, continue with running test "
    cd "$SOURCE_ROOT/envoy"
    bazel test //test/... -c opt --config=clang --keep_going
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
  bash build_envoy.sh [-y] [-t]
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

buildAndInstallClang() {
  msg "Building Clang $CLANG_VERSION"
  cd "$SOURCE_ROOT"
  local z_default_arch="z13"
  local os_version_major=${VERSION_ID%%.*}
  local gpp_pkg="g++"
  local gcc_version=""
  case "$DISTRO" in
  rhel*)
      sudo dnf install -y "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${os_version_major}.noarch.rpm"
      sudo yum install -y --allowerasing gcc-c++ curl git cmake ninja-build chrpath elfutils-libelf-devel libffi-devel patchutils xz xz-libs python3 \
        libedit-devel ncurses-devel binutils-devel libxml2-devel jsoncpp-devel pkg-config procps zlib-devel libzstd-devel libpfm-devel
      if [[ $os_version_major == "8" ]]; then
        z_default_arch="z13"
      else
        z_default_arch="z14"
      fi
      ;;
  sles*)
      gpp_pkg="gcc-c++"
      if [[ $os_version_major == "16" ]]; then
        # gcc 15 is the default on SLES 16 but it can't build clang 18 stage 2
        gcc_version="13"
        gpp_pkg="gcc${gcc_version}-c++"
      fi
      sudo zypper install -y ${gpp_pkg} curl git cmake ninja chrpath libelf-devel libffi-devel patchutils xz xz-devel python3 \
        libedit-devel ncurses-devel binutils-devel libxml2-devel jsoncpp-devel pkg-config procps zlib-devel libzstd-devel libpfm-devel
      if [[ $os_version_major == "16" ]]; then
        z_default_arch="z14"
        # Make sure clang stage 2 uses the correct gcc runtime
        sudo ln -s "/usr/include/c++/${gcc_version}" "/usr/include/c++/99"
        sudo ln -s "/usr/lib64/gcc/s390x-suse-linux/${gcc_version}" "/usr/lib64/gcc/s390x-suse-linux/99"
      else
        z_default_arch="zEC12"
      fi
      ;;
  ubuntu*)
      if [[ $DISTRO == "ubuntu-25.10" ]]; then
        # gcc 15 is the default on 25.10 but it can't build clang 18 stage 2
        gcc_version="13"
        gpp_pkg="g++-${gcc_version}"
      fi
      sudo apt-get update
      sudo apt-get install -y ${gpp_pkg} curl git cmake ninja-build chrpath libelf-dev libffi-dev patchutils xz-utils python3 \
        libedit-dev libncurses-dev binutils-dev libxml2-dev libjsoncpp-dev pkg-config procps zlib1g-dev libzstd-dev libpfm4-dev
      if [[ $DISTRO == "ubuntu-25.10" ]]; then
        # Make sure clang stage 2 uses the correct gcc runtime
        sudo ln -s "/usr/include/s390x-linux-gnu/c++/${gcc_version}" "/usr/include/s390x-linux-gnu/c++/99"
        sudo ln -s "/usr/include/c++/${gcc_version}" "/usr/include/c++/99"
        sudo ln -s "/usr/lib/gcc/s390x-linux-gnu/${gcc_version}" "/usr/lib/gcc/s390x-linux-gnu/99"
      fi
      ;;
  *)
      echo "Error: Unrecognized distro id: ${DISTRO}. Exiting..."
      exit 1
      ;;
  esac

  mkdir -p "$SOURCE_ROOT/clang-build"
  cd "$SOURCE_ROOT/clang-build"
  cat << 'EOF' > Release-s390x.cmake
set_instrument_and_final_stage_var(LLVM_TARGETS_TO_BUILD "Native" STRING)

set(COMPILER_RT_USE_BUILTINS_LIBRARY OFF CACHE BOOL "")
set_instrument_and_final_stage_var(COMPILER_RT_USE_BUILTINS_LIBRARY "OFF" BOOL)
set(COMPILER_RT_BUILD_BUILTINS OFF CACHE BOOL "")
set_instrument_and_final_stage_var(COMPILER_RT_BUILD_BUILTINS "OFF" BOOL)
set(LIBCXX_USE_COMPILER_RT OFF CACHE BOOL "")
set_instrument_and_final_stage_var(LIBCXX_USE_COMPILER_RT "OFF" BOOL)
set(LIBCXXABI_USE_COMPILER_RT OFF CACHE BOOL "")
set_instrument_and_final_stage_var(LIBCXXABI_USE_COMPILER_RT "OFF" BOOL)
set(LIBCXXABI_USE_LLVM_UNWINDER OFF CACHE BOOL "")
set_instrument_and_final_stage_var(LIBCXXABI_USE_LLVM_UNWINDER "OFF" BOOL)
set(LLVM_BUILD_DOCS OFF CACHE BOOL "")
set_instrument_and_final_stage_var(LLVM_BUILD_DOCS "OFF" BOOL)
set(LLVM_TEMPORARILY_ALLOW_OLD_TOOLCHAIN ON CACHE BOOL "")
set_instrument_and_final_stage_var(LLVM_TEMPORARILY_ALLOW_OLD_TOOLCHAIN "ON" BOOL)
set(LLVM_ENABLE_CURL OFF CACHE BOOL "")
set_instrument_and_final_stage_var(LLVM_ENABLE_CURL "OFF" BOOL)

set_instrument_and_final_stage_var(PACKAGE_VENDOR "LoZ Open Source Ecosystem (https://www.ibm.com/community/z/usergroups/opensource)" STRING)

if(LLVM_RELEASE_CLANG_SYSTEMZ_DEFAULT_ARCH)
  set(CLANG_SYSTEMZ_DEFAULT_ARCH "${LLVM_RELEASE_CLANG_SYSTEMZ_DEFAULT_ARCH}" CACHE STRING "")
  set_instrument_and_final_stage_var(CLANG_SYSTEMZ_DEFAULT_ARCH "${LLVM_RELEASE_CLANG_SYSTEMZ_DEFAULT_ARCH}" STRING)
endif()
EOF

  git clone -b "llvmorg-$CLANG_VERSION" --depth=1 https://github.com/llvm/llvm-project.git  || { echo "Could not clone the llvm repo. Exiting..."; exit 1; }
  cd llvm-project
  curl -sSL https://github.com/llvm/llvm-project/commit/a356e6ccada87d6bfc4513fba4b1a682305e094a.patch | git apply -
  curl -sSL https://github.com/llvm/llvm-project/commit/ddaa5b3bfb2980f79c6f277608ad33a6efe8d554.patch | git apply -
  if [[ $DISTRO == "ubuntu-25.10" ]]; then
    # Fixes compile with newer glibc
    curl -sSL $PATCH_URL/clang-ubuntu-2510.patch | git apply -
  fi

  cd ../
  mkdir build

  env CC="gcc" CXX="g++" \
    cmake -G "Ninja" -B build -S llvm-project/llvm \
        -DLLVM_RELEASE_ENABLE_LTO="OFF" \
        -DLLVM_PARALLEL_LINK_JOBS=4 \
        -DBOOTSTRAP_LLVM_PARALLEL_LINK_JOBS=4 \
        -DLLVM_RELEASE_ENABLE_RUNTIMES="compiler-rt;libcxx;libcxxabi" \
        -DLLVM_RELEASE_ENABLE_PROJECTS="clang;lld;clang-tools-extra" \
        -DLLVM_RELEASE_CLANG_SYSTEMZ_DEFAULT_ARCH="$z_default_arch" \
        -C llvm-project/clang/cmake/caches/Release.cmake \
        -C Release-s390x.cmake

  ninja -C build stage2-package

  cd "$SOURCE_ROOT"
  tar xf "${SOURCE_ROOT}/clang-build/build/tools/clang/stage2-bins/LLVM-${CLANG_VERSION}-Linux.tar.gz"
  rm -rf "${SOURCE_ROOT}/clang-build"
}

buildAndInstallBazel() {
  msg "Building Bazel $BAZEL_VERSION"
  cd "$SOURCE_ROOT"
  mkdir -p bazel
  cd bazel/
  wget -q https://github.com/bazelbuild/bazel/releases/download/${BAZEL_VERSION}/bazel-${BAZEL_VERSION}-dist.zip
  unzip -q bazel-${BAZEL_VERSION}-dist.zip
  chmod -R +w .
  env EXTRA_BAZEL_ARGS="--tool_java_runtime_version=local_jdk" BAZEL_DEV_VERSION_OVERRIDE="$BAZEL_VERSION" bash ./compile.sh
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

buildAndInstallRulesRustCargoBazel() {
  msg "Installing cargo-bazel from rules_rust"
  cd "$SOURCE_ROOT"
  git clone -b "$RULES_RUST_VERSION" --depth 1 https://github.com/bazelbuild/rules_rust.git
  cd rules_rust/crate_universe/
  cargo build --release --locked --bin cargo-bazel
  cp target/release/cargo-bazel "$SOURCE_ROOT"/
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

setupBazelEnvironment() {
  # Set the location of the s390x cargo-bazel binary required by rules_rust
  echo "build --repo_env=CARGO_BAZEL_GENERATOR_URL=file:${SOURCE_ROOT}/cargo-bazel" >> "${SOURCE_ROOT}/envoy/user.bazelrc"
  # Disable heap checking because it slows down the tests and causes timeouts
  echo "build --test_env=HEAPCHECK=" >> "${SOURCE_ROOT}/envoy/user.bazelrc"
  echo "test --test_env=HEAPCHECK=" >> "${SOURCE_ROOT}/envoy/user.bazelrc"
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

"rhel-8.10" | "rhel-9.4" | "rhel-9.6" | "rhel-9.7")
  printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
  ALLOWERASING=""
  if [[ "$DISTRO" == rhel-9* ]]; then
    ALLOWERASING="--allowerasing"
  fi
  sudo yum install -y ${ALLOWERASING} wget curl zip unzip patch gcc-toolset-12-gcc gcc-toolset-12-gcc-c++ gcc-toolset-12-libstdc++-devel gcc-toolset-12-binutils-devel gcc-toolset-12-annobin-plugin-gcc gcc-toolset-12-libatomic-devel pkgconf-pkg-config openssl-devel java-21-openjdk-devel python3.11 file |& tee -a "${LOG_FILE}"

  #set gcc 12 as default
  source /opt/rh/gcc-toolset-12/enable

  # set JAVA_HOME location
  export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
  export PATH=$JAVA_HOME/bin:$PATH

  configureAndInstall |& tee -a "$LOG_FILE"
  ;;
#----------------------------------------------------------

"rhel-10.0" | "rhel-10.1")
  printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
  sudo yum install -y --allowerasing wget curl zip unzip patch gcc gcc-c++ libatomic libstdc++-devel pkgconf-pkg-config openssl-devel java-21-openjdk-devel python3 file diffutils |& tee -a "${LOG_FILE}"

  # set JAVA_HOME location
  export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
  export PATH=$JAVA_HOME/bin:$PATH

  configureAndInstall |& tee -a "$LOG_FILE"
  ;;
#----------------------------------------------------------

"sles-15.7" | "sles-16.0")
  printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
  PYTHON_PKG="python311"
  GPP_PKG="gcc-c++"
  if [[ $DISTRO =~ sles-16.* ]]; then
    PYTHON_PKG="python3"
    GPP_PKG="gcc13-c++"
  fi
  sudo zypper install -y awk autoconf curl libtool patch pkg-config wget git $GPP_PKG gzip make cmake $PYTHON_PKG java-21-openjdk-devel unzip zip tar xz libopenssl-devel zlib-devel which |& tee -a "${LOG_FILE}"

  if [[ $DISTRO =~ sles-16.* ]]; then
    sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-13 12
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-13 12
    sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-13 12
    sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-13 12
  fi

  export JAVA_HOME=/usr/lib64/jvm/java-21-openjdk
  export PATH=$JAVA_HOME/bin:$PATH

  configureAndInstall |& tee -a "$LOG_FILE"
  ;;
#----------------------------------------------------------

"ubuntu-22.04")
  printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
  sudo apt-get update
  sudo apt-get install -y autoconf curl wget git libtool patch python3-pip unzip virtualenv pkg-config locales libssl-dev build-essential openjdk-21-jdk-headless python2 python2-dev python3 python3-dev zip | tee -a "${LOG_FILE}"
  
  sudo apt-get install -y gcc-12 g++-12
  sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-12 12
  sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 12
  sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-12 12
  sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-12 12
  
  export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-s390x
  export PATH=$JAVA_HOME/bin:$PATH

  configureAndInstall |& tee -a "$LOG_FILE"
  ;;
#----------------------------------------------------------

"ubuntu-24.04")
  printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
  sudo apt-get update
  sudo apt-get install -y autoconf curl wget git libtool patch python3-pip virtualenv pkg-config locales gcc g++ openssl libssl-dev build-essential openjdk-21-jdk-headless python3 zip unzip | tee -a "${LOG_FILE}"

  export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-s390x
  export PATH=$JAVA_HOME/bin:$PATH

  configureAndInstall |& tee -a "$LOG_FILE"
  ;;
#----------------------------------------------------------

"ubuntu-25.10")
  printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
  sudo apt-get update
  sudo apt-get install -y autoconf curl wget git libtool patch python3-pip virtualenv pkg-config locales openssl libssl-dev build-essential openjdk-21-jdk-headless python3 zip unzip | tee -a "${LOG_FILE}"

  sudo apt-get install -y gcc-13 g++-13
  sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-13 12
  sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-13 12
  sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-13 12
  sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-13 12
  
  export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-s390x
  export PATH=$JAVA_HOME/bin:$PATH

  configureAndInstall |& tee -a "$LOG_FILE"
  ;;
#----------------------------------------------------------
esac

gettingStarted |& tee -a "$LOG_FILE"
