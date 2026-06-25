#!/bin/bash
# © Copyright IBM Corporation 2026
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)

set -x

# To run a this script on a local vm:
#   env LOZ_ENVOY_CI_LOCAL_TEST="true" bash <path to script dir>/build_envoy.sh
: ${LOZ_ENVOY_CI_LOCAL_TEST:="false"}

cat /etc/os-release
gcc -v
ls
export SOURCE_ROOT=$(pwd)
sudo rm -rf $SOURCE_ROOT/build_bazel.sh* $SOURCE_ROOT/logs $SOURCE_ROOT/bazel/ $SOURCE_ROOT/netty-tcnative $SOURCE_ROOT/netty
sudo rm -rf .cache $SOURCE_ROOT/.cache /root/.cache
sudo rm -rf  $SOURCE_ROOT/gcc_build $SOURCE_ROOT/gcc-11.4.0
sudo rm -rf  $SOURCE_ROOT/bazel/bazel/rules_java
sudo rm -rf $SOURCE_ROOT/rules_foreign_cc
sudo rm -rf $SOURCE_ROOT/rules_rust
sudo rm -rf $SOURCE_ROOT/llvm.sh*
ls

SOURCE_ROOT="$(pwd)"
CLANG_VERSION="18.1.8"
BAZEL_VERSION="8.7.0"
GO_VERSION="1.24.6"
LLVM_HOME_DIR="${SOURCE_ROOT}/clang/LLVM-${CLANG_VERSION}-Linux"

export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-s390x
export PATH=$JAVA_HOME/bin:$PATH

if [[ $LOZ_ENVOY_CI_LOCAL_TEST != "true" ]]; then
  export HOME=/home/alfred/jenkins/workspace/Envoy_IBMZ_CI_test
  export XDG_CACHE_HOME=/home/alfred/jenkins/workspace/Envoy_IBMZ_CI_test
fi

configureAndInstall() {

  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y autoconf curl wget git libtool patch python3-pip \
    unzip virtualenv pkg-config locales libssl-dev build-essential openjdk-21-jdk-headless \
    python2 python2-dev python3 python3-dev zip libtinfo5

  buildAndInstallClang
  buildAndInstallBazel
  installGo
  installRust

  cd "$SOURCE_ROOT"
  if [[ $LOZ_ENVOY_CI_LOCAL_TEST == "true" && ! -d envoy ]]; then
    echo "Local test: cloning the envoy repo"
    retry git clone --depth 1 -b main https://github.com/envoyproxy/envoy.git
  fi

  cd "$SOURCE_ROOT"/envoy
  setupBazelEnvironment

  installEnvoyBuildPatch
  installBoringsslPatch
  installQuichePatch
  installWasmPatch
  installRulesForeignCcPatch
  curl -sSL https://github.com/iii-i/moonjit/commit/dee73f516f0da49e930dcfa1dd61720dcb69b7dd.patch > $SOURCE_ROOT/envoy/bazel/foreign_cc/luajit-s390x.patch
  curl -sSL https://github.com/iii-i/moonjit/commit/035f133798adb856391928600f7cb6b4f81578ab.patch >> $SOURCE_ROOT/envoy/bazel/foreign_cc/luajit-s390x.patch
  curl -sSL https://github.com/openresty/luajit2/commit/e598aeb7426dbc069f90ba70db9bce43cd573b0e.patch >> $SOURCE_ROOT/envoy/bazel/foreign_cc/luajit-s390x.patch
  installHighwayPatch
  installLuajitPatch
  installGrpcPatch
  installToolchainsLlvmPatch
  installProtobufPatch
  installV8Patch

  cd "$SOURCE_ROOT"/envoy
  bazel build envoy -c opt --config=clang --repo_env=BAZEL_LLVM_PATH="${LLVM_HOME_DIR}" --@envoy_repo//:use_local_llvm_flag=True
}

buildAndInstallClang() {
  cd "$SOURCE_ROOT"
  if [[ -d "clang/LLVM-${CLANG_VERSION}-Linux" ]]; then
    echo "Using existing ${SOURCE_ROOT}/clang/LLVM-${CLANG_VERSION}-Linux clang distribution"
    return 0
  fi

  rm -rf clang
  local z_default_arch="z13"
  sudo apt-get update
  sudo apt-get install -y g++ curl git cmake ninja-build chrpath libelf-dev libffi-dev patchutils xz-utils python3 \
    libedit-dev libncurses-dev binutils-dev libxml2-dev libjsoncpp-dev pkg-config procps zlib1g-dev libzstd-dev libpfm4-dev

  rm -rf "$SOURCE_ROOT/clang-build"
  mkdir -p "$SOURCE_ROOT/clang-build"
  cd "$SOURCE_ROOT/clang-build"
  cp $SOURCE_ROOT/patch/Release-s390x.cmake .
  git clone -b "llvmorg-$CLANG_VERSION" --depth=1 https://github.com/llvm/llvm-project.git  || { echo "Could not clone the llvm repo. Exiting..."; exit 1; }
  cd llvm-project
  curl -sSL https://github.com/llvm/llvm-project/commit/a356e6ccada87d6bfc4513fba4b1a682305e094a.patch | git apply -
  curl -sSL https://github.com/llvm/llvm-project/commit/ddaa5b3bfb2980f79c6f277608ad33a6efe8d554.patch | git apply -

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

  mkdir -p "$SOURCE_ROOT"/clang
  cd "$SOURCE_ROOT"/clang
  tar xf "${SOURCE_ROOT}/clang-build/build/tools/clang/stage2-bins/LLVM-${CLANG_VERSION}-Linux.tar.gz"
  cd "$SOURCE_ROOT"/
  rm -rf "${SOURCE_ROOT}/clang-build"
}

buildAndInstallBazel() {
  cd "$SOURCE_ROOT"
  local bazel_build_dir="bazel-build/${BAZEL_VERSION}/"
  if [[ -f "${bazel_build_dir}/output/bazel" ]]; then
    sudo cp ${bazel_build_dir}/output/bazel /usr/local/bin/
    echo "Using existing ${SOURCE_ROOT}/${BAZEL_VERSION}/bazel bazel distribution"
    return 0
  fi

  rm -rf "bazel-build"
  mkdir -p "${bazel_build_dir}/"
  cd "${bazel_build_dir}/"
  wget -q https://github.com/bazelbuild/bazel/releases/download/${BAZEL_VERSION}/bazel-${BAZEL_VERSION}-dist.zip
  unzip -q bazel-${BAZEL_VERSION}-dist.zip
  chmod -R +w .
  env EXTRA_BAZEL_ARGS="--tool_java_runtime_version=local_jdk" BAZEL_DEV_VERSION_OVERRIDE="$BAZEL_VERSION" bash ./compile.sh
  sudo cp output/bazel /usr/local/bin/
  cd "$SOURCE_ROOT"
}

installGo() {
  cd "$SOURCE_ROOT"
  wget -q https://golang.org/dl/go"${GO_VERSION}".linux-s390x.tar.gz
  chmod ugo+r go"${GO_VERSION}".linux-s390x.tar.gz
  sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf go"${GO_VERSION}".linux-s390x.tar.gz
  export PATH=/usr/local/go/bin:$PATH
  go version
  cd "$SOURCE_ROOT"
}

installRust() {
  cd "$SOURCE_ROOT"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh /dev/stdin -y
  export PATH=$HOME/.cargo/bin:$PATH
  rustc --version
  cargo --version
  cd "$SOURCE_ROOT"
}

setupBazelEnvironment() {
  # Disable heap checking because it slows down the tests and causes timeouts
  echo "build --test_env=HEAPCHECK=" >> "${SOURCE_ROOT}/envoy/user.bazelrc"
  echo "test --test_env=HEAPCHECK=" >> "${SOURCE_ROOT}/envoy/user.bazelrc"
}

installEnvoyBuildPatch() {
  cd "$SOURCE_ROOT/envoy"
  git apply $SOURCE_ROOT/patch/envoy.patch
  cd "$SOURCE_ROOT"
}

installBoringsslPatch() {
  cd "$SOURCE_ROOT"
  rm -f "$SOURCE_ROOT/envoy/bazel/boringssl-s390x.patch"
  cp $SOURCE_ROOT/patch/boringssl-s390x.patch $SOURCE_ROOT/envoy/bazel
  cd "$SOURCE_ROOT"
}

installQuichePatch() {
  cd "$SOURCE_ROOT"
  rm -f "$SOURCE_ROOT/envoy/bazel/external/quiche-s390x.patch"
  cp $SOURCE_ROOT/patch/quiche-s390x.patch $SOURCE_ROOT/envoy/bazel/external
  cd "$SOURCE_ROOT"
}

installWasmPatch() {
  cd "$SOURCE_ROOT"
  rm -f "$SOURCE_ROOT/envoy/bazel/proxy_wasm_cpp_host-s390x.patch"
  cp $SOURCE_ROOT/patch/proxy_wasm_cpp_host-s390x.patch $SOURCE_ROOT/envoy/bazel/
  cd "$SOURCE_ROOT"
}

installRulesForeignCcPatch() {
  cd "$SOURCE_ROOT"
  rm -f "$SOURCE_ROOT/envoy/bazel/rules_foreign_cc-s390x.patch"
  cp $SOURCE_ROOT/patch/rules_foreign_cc-s390x.patch $SOURCE_ROOT/envoy/bazel
  cd "$SOURCE_ROOT"
}

installHighwayPatch() {
  cd "$SOURCE_ROOT"
  rm -f "$SOURCE_ROOT/envoy/bazel/highway-s390x.patch"
  cp $SOURCE_ROOT/patch/highway-s390x.patch $SOURCE_ROOT/envoy/bazel
  cd "$SOURCE_ROOT"
}

installLuajitPatch() {
  cd "$SOURCE_ROOT"
  rm -f "$SOURCE_ROOT/envoy/bazel/foreign_cc/luajit-as.patch"
  cp $SOURCE_ROOT/patch/luajit-as.patch $SOURCE_ROOT/envoy/bazel/foreign_cc
  cd "$SOURCE_ROOT"
}

installGrpcPatch() {
  cd "$SOURCE_ROOT"
  rm -f "$SOURCE_ROOT/envoy/bazel/grpc-s390x.patch"
  cp $SOURCE_ROOT/patch/grpc-s390x.patch $SOURCE_ROOT/envoy/bazel
  cd "$SOURCE_ROOT"
}

installToolchainsLlvmPatch() {
  cd "$SOURCE_ROOT"
  rm -f "$SOURCE_ROOT/envoy/bazel/toolchains_llvm-s390x.patch"
  cp $SOURCE_ROOT/patch/toolchains_llvm-s390x.patch $SOURCE_ROOT/envoy/bazel
  cd "$SOURCE_ROOT"
}

installProtobufPatch() {
  cd "$SOURCE_ROOT"
  rm -f "$SOURCE_ROOT/envoy/bazel/protobuf-s390x.patch"
  cp $SOURCE_ROOT/patch/protobuf-s390x.patch $SOURCE_ROOT/envoy/bazel
  cd "$SOURCE_ROOT"
}

installV8Patch() {
  cd "$SOURCE_ROOT"
  rm -f "$SOURCE_ROOT/envoy/bazel/v8_s390x.patch"
  cp $SOURCE_ROOT/patch/v8_s390x.patch $SOURCE_ROOT/envoy/bazel
  cd "$SOURCE_ROOT"
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

# ======================================================
# Start of commands

configureAndInstall
