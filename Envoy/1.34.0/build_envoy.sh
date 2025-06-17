#!/bin/bash
# © Copyright IBM Corporation 2025
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Envoy/1.34.0/build_envoy.sh
# Execute build script: bash build_envoy.sh    (provide -h for help)
#==============================================================================
set -e -o pipefail

PACKAGE_NAME="Envoy"
PACKAGE_VERSION="v1.34.0"
SOURCE_ROOT="$(pwd)"

PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Envoy/1.34.0/patch"

FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
ENV_VARS=$SOURCE_ROOT/setenv.sh

BAZEL_VERSION="7.6.0"
GO_VERSION="1.24.2"
RULES_RUST_VERSION="0.56.0"
BUF_VERSION="1.50.0"
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

  buildAndInstallBazel
  installGo
  installRust
  buildAndInstallRulesRustCargoBazel
  buildAndInstallRulesBufBinaries

  saveEnvVars

  #----------------------------------------------------------
  msg "Cloning Envoy $PACKAGE_VERSION"

  cd "$SOURCE_ROOT"/
  rm -rf envoy
  retry git clone --depth 1 -b ${PACKAGE_VERSION} https://github.com/envoyproxy/envoy.git
  cd envoy
  ./bazel/setup_clang.sh "$LLVM_HOME_DIR"
  setupBazelEnvironment
  if [[ ${GCC_TOOLCHAIN_SOURCE} != "" && ${GCC_TOOLCHAIN_VERSION_OVERRIDE} != "" ]]; then
    setupGccToolchain "$GCC_TOOLCHAIN_SOURCE" "$GCC_TOOLCHAIN_VERSION_OVERRIDE"
  fi

  # Apply patches to allow envoy to build
  curl -sSL $PATCH_URL/envoy-build.patch | git apply -
  
  # Apply patches for failing tests
  curl -sSL $PATCH_URL/envoy-test.patch | git apply -

  # Move patch files to envoy/bazel which will be applied to external packages while building envoy
  curl -sSL $PATCH_URL/boringssl-s390x.patch > $SOURCE_ROOT/envoy/bazel/boringssl-s390x.patch
  curl -sSL $PATCH_URL/quiche-s390x.patch > $SOURCE_ROOT/envoy/bazel/external/quiche-s390x.patch
  curl -sSL $PATCH_URL/proxy_wasm_cpp_host-s390x.patch > $SOURCE_ROOT/envoy/bazel/proxy_wasm_cpp_host-s390x.patch
  curl -sSL $PATCH_URL/rules_foreign_cc-s390x.patch > $SOURCE_ROOT/envoy/bazel/rules_foreign_cc-s390x.patch
  curl -sSL https://github.com/iii-i/moonjit/commit/dee73f516f0da49e930dcfa1dd61720dcb69b7dd.patch > $SOURCE_ROOT/envoy/bazel/foreign_cc/luajit-s390x.patch
  curl -sSL https://github.com/iii-i/moonjit/commit/035f133798adb856391928600f7cb6b4f81578ab.patch >> $SOURCE_ROOT/envoy/bazel/foreign_cc/luajit-s390x.patch
  curl -sSL $PATCH_URL/luajit-as.patch > $SOURCE_ROOT/envoy/bazel/foreign_cc/luajit-as.patch
  curl -sSL $PATCH_URL/rules_buf-s390x.patch > $SOURCE_ROOT/envoy/api/bazel/rules_buf-s390x.patch
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

buildAndInstallBazel() {
  msg "Building Bazel $BAZEL_VERSION"
  cd "$SOURCE_ROOT"
  mkdir -p bazel
  cd bazel/
  wget -q https://github.com/bazelbuild/bazel/releases/download/${BAZEL_VERSION}/bazel-${BAZEL_VERSION}-dist.zip
  unzip -q bazel-${BAZEL_VERSION}-dist.zip
  chmod -R +w .
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

buildAndInstallRulesRustCargoBazel() {
  msg "Installing cargo-bazel from rules_rust"
  cd "$SOURCE_ROOT"
  git clone -b "$RULES_RUST_VERSION" --depth 1 https://github.com/bazelbuild/rules_rust.git
  cd rules_rust/crate_universe/
  cargo build --release --locked --bin cargo-bazel
  cp target/release/cargo-bazel "$SOURCE_ROOT"/
}

buildAndInstallRulesBufBinaries() {
  msg "Installing buf binaries for rules_buf"
  cd "$SOURCE_ROOT"
  local buf_dir="${SOURCE_ROOT}/rules_buf/local"
  mkdir -p "$buf_dir"
  git clone -b "v$BUF_VERSION" --depth 1 https://github.com/bufbuild/buf.git
  cd buf
  GOBIN="$buf_dir" go install "github.com/bufbuild/buf/cmd/buf@v${BUF_VERSION}"
  mv "$buf_dir/buf" "$buf_dir/buf-Linux-s390x"
  GOBIN="$buf_dir" go install "github.com/bufbuild/buf/cmd/protoc-gen-buf-breaking@v${BUF_VERSION}"
  mv "$buf_dir/protoc-gen-buf-breaking" "$buf_dir/protoc-gen-buf-breaking-Linux-s390x"
  GOBIN="$buf_dir" go install "github.com/bufbuild/buf/cmd/protoc-gen-buf-lint@v${BUF_VERSION}"
  mv "$buf_dir/protoc-gen-buf-lint" "$buf_dir/protoc-gen-buf-lint-Linux-s390x"
  cd "$buf_dir"
  sha256sum buf-Linux-s390x protoc-gen-buf-breaking-Linux-s390x protoc-gen-buf-lint-Linux-s390x > sha256.txt
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

# Set a specific version of gcc's libstdc++ to be used by clang
setupGccToolchain() {
  local source=$1
  local gcc_version=$2
  if [[ $source == "distro" ]]; then
    setupDistroGccToolchainDir "$gcc_version" "include/s390x-linux-gnu/c++"
    setupDistroGccToolchainDir "$gcc_version" "include/c++"
    setupDistroGccToolchainDir "$gcc_version" "lib/gcc/s390x-linux-gnu"
  else
    error "Unknown gcc toolchain source: $source"
  fi
}

setupBazelEnvironment() {
  # Set the location of the s390x cargo-bazel binary required by rules_rust
  echo "build --repo_env=CARGO_BAZEL_GENERATOR_URL=file:${SOURCE_ROOT}/cargo-bazel" >> "${SOURCE_ROOT}/envoy/user.bazelrc"
  # Set the location of the s390x buf binaries required by rules_buf
  echo "build --repo_env=BUFBUILD_BUF_TOOLCHAIN_URL=file:${SOURCE_ROOT}/rules_buf" >> "${SOURCE_ROOT}/envoy/user.bazelrc"
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

"rhel-8.10" | "rhel-9.4" | "rhel-9.5" | "rhel-9.6")
  printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
  ALLOWERASING=""
  if [[ "$DISTRO" == rhel-9* ]]; then
    ALLOWERASING="--allowerasing"
  fi
  sudo yum install -y ${ALLOWERASING} wget curl zip unzip patch clang-14.0.6 llvm-devel-14.0.6 gcc-toolset-12-gcc gcc-toolset-12-gcc-c++ gcc-toolset-12-libstdc++-devel gcc-toolset-12-binutils-devel gcc-toolset-12-binutils-gold gcc-toolset-12-annobin-plugin-gcc gcc-toolset-12-libatomic-devel pkgconf-pkg-config openssl-devel java-21-openjdk-devel python3.11 |& tee -a "${LOG_FILE}"
  LLVM_HOME_DIR="/usr"

  #set gcc 12 as default
  source /opt/rh/gcc-toolset-12/enable

  # set JAVA_HOME location
  export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
  export PATH=$JAVA_HOME/bin:$PATH

  configureAndInstall |& tee -a "$LOG_FILE"
  ;;
#----------------------------------------------------------

"sles-15.6")
  printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
  if [[ $DISTRO == "sles-15.6" ]]; then
    sudo zypper addrepo --priority 199 http://download.opensuse.org/distribution/leap/15.6/repo/oss/ oss
    sudo zypper --gpg-auto-import-keys refresh -r oss
  fi
  sudo zypper install -y awk autoconf curl libtool patch pkg-config wget git gcc12-c++ gcc-c++ clang14 llvm14-devel binutils-gold gzip make cmake python311 java-21-openjdk-devel unzip zip tar xz libopenssl-devel |& tee -a "${LOG_FILE}"
  LLVM_HOME_DIR="/usr"

  export JAVA_HOME=/usr/lib64/jvm/java-21-openjdk
  export PATH=$JAVA_HOME/bin:$PATH

  configureAndInstall |& tee -a "$LOG_FILE"
  ;;
#----------------------------------------------------------

"ubuntu-22.04")
  printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
  sudo apt-get update
  sudo apt-get install -y autoconf curl git libtool patch python3-pip unzip virtualenv pkg-config locales libssl-dev build-essential openjdk-21-jdk-headless python2 python2-dev python3 python3-dev zip | tee -a "${LOG_FILE}"
  
  # Install GCC 12 from repo
  sudo apt-get install -y gcc-12 g++-12

  sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-12 12
  sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 12
  sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-12 12
  sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-12 12
  
  export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-s390x
  export PATH=$JAVA_HOME/bin:$PATH

  # Install Clang 14
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

"ubuntu-24.04" | "ubuntu-24.10" | "ubuntu-25.04")
  printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
  sudo apt-get update
  sudo apt-get install -y autoconf curl wget git libtool patch python3-pip virtualenv pkg-config locales clang-14 gcc g++ libstdc++-12-dev openssl libssl-dev build-essential openjdk-21-jdk-headless python3 zip unzip binutils-gold | tee -a "${LOG_FILE}"
  LLVM_HOME_DIR="/usr/lib/llvm-14"
  GCC_TOOLCHAIN_VERSION_OVERRIDE="12"
  GCC_TOOLCHAIN_SOURCE="distro"

  export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-s390x
  export PATH=$JAVA_HOME/bin:$PATH

  configureAndInstall |& tee -a "$LOG_FILE"
  ;;
#----------------------------------------------------------
esac

gettingStarted |& tee -a "$LOG_FILE"
