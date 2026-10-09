#!/bin/bash
# © Copyright IBM Corporation 2026
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
# Builds Envoy (main branch) on s390x.
#
# To run on a local VM:
#   env LOZ_ENVOY_CI_LOCAL_TEST="true" bash build_envoy.sh

set -ex

# To run this script on a local vm:
#   env LOZ_ENVOY_CI_LOCAL_TEST="true" bash <path to script dir>/build_envoy.sh
: ${LOZ_ENVOY_CI_LOCAL_TEST:="false"}

cat /etc/os-release
gcc -v
ls

export SOURCE_ROOT=$(pwd)
sudo rm -rf "$SOURCE_ROOT/build_bazel.sh"* "$SOURCE_ROOT/logs"
sudo rm -rf .cache "$SOURCE_ROOT/.cache" /root/.cache
sudo rm -rf "$SOURCE_ROOT/gcc_build" "$SOURCE_ROOT/gcc-11.4.0"
sudo rm -rf "$SOURCE_ROOT/rules_foreign_cc"
sudo rm -rf "$SOURCE_ROOT/rules_rust"
sudo rm -rf "$SOURCE_ROOT/envoy-main"*
sudo rm -rf "$SOURCE_ROOT/llvm.sh"*
# Wipe any leftover Rust/Cargo state from a previous CI run.
# On CI, HOME is set to the workspace so .rustup/.cargo accumulate there.
# A partial or version-mismatched toolchain causes "missing manifest" errors.
sudo rm -rf "$SOURCE_ROOT/.rustup" "$SOURCE_ROOT/.cargo"
sudo rm -rf /root/.rustup /root/.cargo

#sudo rm -rf "$SOURCE_ROOT/clang"
sudo rm -rf "$SOURCE_ROOT/bazel"

ls

SOURCE_ROOT="$(pwd)"
CLANG_VERSION="22.1.8"
BAZEL_VERSION="8.8.0"
GO_VERSION="1.25.0"
LLVM_HOME_DIR="${SOURCE_ROOT}/clang/LLVM-${CLANG_VERSION}-Linux"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/CI/Envoy/patch"

# Pinned bazel-registry commit that matches the dependency versions used below.
# Do not update this commit independently of the dep versions — they must stay in sync.
ENVOY_REGISTRY="https://raw.githubusercontent.com/envoyproxy/bazel-registry/b565623d89166dd153aee61ba421ec1638bf7a3e"

export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-s390x
export PATH=$JAVA_HOME/bin:$PATH

if [[ $LOZ_ENVOY_CI_LOCAL_TEST != "true" ]]; then
  export HOME=/home/alfred/jenkins/workspace/Envoy_IBMZ_CI_test
  export XDG_CACHE_HOME=/home/alfred/jenkins/workspace/Envoy_IBMZ_CI_test
fi

msg()    { echo "${*}"; }
msglog() { echo "${*}"; }

# ===========================================================================
# configureAndInstall — top-level orchestrator
# ===========================================================================
configureAndInstall() {

  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y autoconf curl wget git libtool patch python3-pip \
    unzip zip pkg-config locales libssl-dev build-essential openjdk-21-jdk-headless \
    python3 python3-dev libtinfo5

  buildAndInstallClang
  buildAndInstallBazel
  installGo
  installRust

  cd "$SOURCE_ROOT"
  if [[ $LOZ_ENVOY_CI_LOCAL_TEST == "true" && ! -d envoy ]]; then
    echo "Local test: cloning the envoy repo"
    retry git clone --depth 1 -b main https://github.com/envoyproxy/envoy.git
  fi

  cd "$SOURCE_ROOT/envoy"
  setupBazelEnvironment

  installEnvoyBuildPatch

  export CARGO_HOME="${HOME}/.cargo"
  cd "$SOURCE_ROOT/envoy"
  rm -f .cargo/config.toml
  rmdir .cargo 2>/dev/null || true

  # cargo-bazel (using crates-index 3.7.0) looks for crate registry index config.json
  # at multiple paths depending on HashKind (Stable vs Legacy) and URL.
  # Empirically (confirmed via strace) the failing path is always
  #   ${CARGO_HOME}/registry/index/index.crates.io-7f555b6b8ccf4919/config.json
  # We pre-create all known variant hash directories with config.json.
  _crates_io_cfg() {
    local d="${CARGO_HOME}/registry/index/${1}"
    if [[ ! -f "${d}/config.json" ]]; then
      mkdir -p "${d}"
      cat > "${d}/config.json" << 'SPCFG_EOF'
{
  "dl": "https://static.crates.io/crates",
  "api": "https://crates.io"
}
SPCFG_EOF
      msg "crate index dir pre-created: ${d}"
    fi
  }
  # 1949cf8c6b5b557f — legacy SipHash of sparse+https://index.crates.io/ (cargo-created)
  # 6f17d22bba15001f — legacy SipHash of https://index.crates.io/
  # 9a317a96d82ef565 — sha256[0:8]-LE of sparse+https://index.crates.io/
  # 7f555b6b8ccf4919 — stable SipHash used by crates-index 3.7.0 for TreeResolver workspace
  _crates_io_cfg "index.crates.io-1949cf8c6b5b557f"
  _crates_io_cfg "index.crates.io-6f17d22bba15001f"
  _crates_io_cfg "index.crates.io-9a317a96d82ef565"
  _crates_io_cfg "index.crates.io-7f555b6b8ccf4919"

  # Common bazel flags
  _BAZEL_FLAGS=(
    -c opt --config=libc++
    --lockfile_mode=off
    --cxxopt=-std=c++20 --host_cxxopt=-std=c++20
    --repo_env=CARGO_HOME="${CARGO_HOME}"
    --repo_env=CARGO_BAZEL_ISOLATED=false
    --repo_env=CARGO_BAZEL_REPIN=1
  )

  cd "$SOURCE_ROOT/envoy" || { echo "ERROR: envoy dir missing for bazel build"; exit 1; }

  # jinja2 must be installed into the hermetic Python 3.12 that Bazel extracts
  # under the output base. The genrule replaces PATH with that Python, so system
  # site-packages is unreachable regardless of PYTHONPATH.
  # Pre-install if already on disk (warm cache). On cold cache, pass 1 extracts
  # the hermetic Python, we install into it, pass 2 succeeds via action cache.
  _jinja2_install() {
    local _py
    _py="$(bazel info output_base 2>/dev/null)/external/rules_python++python+python_3_12_s390x-unknown-linux-gnu/bin/python3"
    [[ -x "$_py" ]] || return 0
    "$_py" -m pip install --quiet jinja2==3.0.3 markupsafe==2.1.5
    msg "jinja2: installed into hermetic Python3.12"
  }

  _jinja2_install

  set +e
  bazel build //source/exe:envoy-static "${_BAZEL_FLAGS[@]}"
  _rc=$?
  set -e

  if [[ $_rc -ne 0 ]]; then
    _jinja2_install
    msg "jinja2 installed — retrying build"
    bazel build //source/exe:envoy-static "${_BAZEL_FLAGS[@]}"
  fi

  msglog "Build complete."
  msglog "Binary: ${SOURCE_ROOT}/envoy/bazel-bin/source/exe/envoy-static"
}

# ===========================================================================
# buildAndInstallClang
# Builds clang/LLVM 22.1.8 from source if not already present.
# ===========================================================================
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
  curl -sSL "${PATCH_URL}/Release-s390x.cmake" -o Release-s390x.cmake
  git clone -b "llvmorg-$CLANG_VERSION" --depth=1 https://github.com/llvm/llvm-project.git  || { echo "Could not clone the llvm repo. Exiting..."; exit 1; }
  cd llvm-project
  sed -i 's/set_final_stage_var(CLANG_BOLT "INSTRUMENT" STRING)/set_final_stage_var(CLANG_BOLT "OFF" STRING)/' clang/cmake/caches/Release.cmake

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
  tar xf "${SOURCE_ROOT}/clang-build/build/tools/clang/stage2-instrumented-bins/tools/clang/stage2-bins/LLVM-${CLANG_VERSION}-Linux.tar.xz"
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

# ===========================================================================
# installGo
# ===========================================================================
installGo() {
  cd "$SOURCE_ROOT"
  wget -q "https://golang.org/dl/go${GO_VERSION}.linux-s390x.tar.gz"
  chmod ugo+r "go${GO_VERSION}.linux-s390x.tar.gz"
  sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf "go${GO_VERSION}.linux-s390x.tar.gz"
  rm -f "go${GO_VERSION}.linux-s390x.tar.gz"
  export PATH=/usr/local/go/bin:$PATH
  go version
  cd "$SOURCE_ROOT"
}

# ===========================================================================
# installRust
# ===========================================================================
installRust() {
  cd "$SOURCE_ROOT"
  # Remove any existing rustup/cargo to avoid "missing manifest" errors
  # from a partial or stale toolchain left by a previous run.
  rm -rf "$HOME/.rustup" "$HOME/.cargo"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh /dev/stdin -y
  export PATH=$HOME/.cargo/bin:$PATH
  rustc --version
  cargo --version
  cd "$SOURCE_ROOT"
}

# ===========================================================================
# setupBazelEnvironment
# Appends s390x-specific knobs to user.bazelrc.  Called before
# installEnvoyBuildPatch so that the file exists when patches are applied.
# user.bazelrc is git-ignored and therefore survives git clean.
# ===========================================================================
setupBazelEnvironment() {
  # Disable heap checking — gperftools has no s390x support and causes timeouts
  echo "build --test_env=HEAPCHECK=" >> "${SOURCE_ROOT}/envoy/user.bazelrc"
  echo "test  --test_env=HEAPCHECK=" >> "${SOURCE_ROOT}/envoy/user.bazelrc"
  # cargo-bazel must not run in isolated mode on s390x (no pre-built binary)
  echo "build --repo_env=CARGO_BAZEL_ISOLATED=false" >> "${SOURCE_ROOT}/envoy/user.bazelrc"
}

# ===========================================================================
# Inline patch writers (re-written after every git clean)
# ===========================================================================

installBoringsslPatch() {
  mkdir -p "$SOURCE_ROOT/envoy/bazel"
  rm -f "$SOURCE_ROOT/envoy/bazel/boringssl-s390x.patch"
  curl -sSL "${PATCH_URL}/boringssl-s390x.patch" -o $SOURCE_ROOT/envoy/bazel/boringssl-s390x.patch
  msg "boringssl-s390x.patch: written"
}

installRulesRustPatch() {
  mkdir -p "$SOURCE_ROOT/envoy/bazel"
  # Two-file patch:
  #  1. generate_utils.bzl: add CARGO_HOME to CRATES_REPOSITORY_ENVIRON so
  #     --repo_env=CARGO_HOME is visible inside the module extension context.
  #  2. common_utils.bzl: when isolated=False, explicitly return CARGO_HOME
  #     in the env dict passed to repository_ctx.execute() (which replaces
  #     the subprocess env entirely — cargo-bazel would otherwise have no HOME).
  rm -f "$SOURCE_ROOT/envoy/bazel/rules_rust-s390x.patch"
  curl -sSL "${PATCH_URL}/rules_rust-s390x.patch" -o $SOURCE_ROOT/envoy/bazel/rules_rust-s390x.patch
  msg "rules_rust-s390x.patch: written (generate_utils.bzl + common_utils.bzl)"
}

installLuajitAsPatch() {
  mkdir -p "$SOURCE_ROOT/envoy/bazel"
  rm -f "$SOURCE_ROOT/envoy/bazel/luajit-as.patch"
  curl -sSL "${PATCH_URL}/luajit-as.patch" -o $SOURCE_ROOT/envoy/bazel/luajit-as.patch
  msg "luajit-as.patch: written"
}

installToolchainsLlvmPatch() {
  mkdir -p "$SOURCE_ROOT/envoy/bazel"
  rm -f "$SOURCE_ROOT/envoy/bazel/toolchains_llvm-s390x.patch"
  curl -sSL "${PATCH_URL}/toolchains_llvm-s390x.patch" -o $SOURCE_ROOT/envoy/bazel/toolchains_llvm-s390x.patch
  msg "toolchains_llvm-s390x.patch: written"
}

installGrpcS390xPatch() {
  mkdir -p "$SOURCE_ROOT/envoy/bazel"
  rm -f "$SOURCE_ROOT/envoy/bazel/grpc-s390x.patch"
  curl -sSL "${PATCH_URL}/grpc-s390x.patch" -o $SOURCE_ROOT/envoy/bazel/grpc-s390x.patch
  msg "grpc-s390x.patch: written"
}

installProtobufS390xPatch() {
  # protobuf 35.1 no longer uses the protoc alias block that needed s390x patching
  msg "protobuf-s390x.patch: not needed for 35.1"
}

installQuicheS390xPatch() {
  mkdir -p "$SOURCE_ROOT/envoy/bazel/external"
  rm -f "$SOURCE_ROOT/envoy/bazel/external/quiche-s390x.patch"
  curl -sSL "${PATCH_URL}/quiche-s390x.patch" -o $SOURCE_ROOT/envoy/bazel/external/quiche-s390x.patch
  msg "quiche-s390x.patch: written"
}

installV8S390xPatch() {
  mkdir -p "$SOURCE_ROOT/envoy/bazel"
  curl -fsSL \
    "https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Envoy/1.39.0/patch/v8-s390x.patch" \
    -o "$SOURCE_ROOT/envoy/bazel/v8-s390x.patch"
  msg "v8-s390x.patch: fetched"
}

installV8BzlmodPatch() {
  mkdir -p "$SOURCE_ROOT/envoy/bazel"
  rm -f "$SOURCE_ROOT/envoy/bazel/v8-bzlmod.patch"
  curl -sSL "${PATCH_URL}/v8-bzlmod.patch" -o $SOURCE_ROOT/envoy/bazel/v8-bzlmod.patch
  msg "v8-bzlmod.patch: written"
}

installHighwayS390xPatch() {
  mkdir -p "$SOURCE_ROOT/envoy/bazel"
  curl -fsSL \
    "https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Envoy/1.39.0/patch/highway-s390x.patch" \
    -o "$SOURCE_ROOT/envoy/bazel/highway-s390x.patch"
  msg "highway-s390x.patch: fetched"
}

installProxyWasmCppHostS390xPatch() {
  mkdir -p "$SOURCE_ROOT/envoy/bazel"
  curl -fsSL \
    "https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Envoy/1.39.0/patch/proxy_wasm_cpp_host-s390x.patch" \
    -o "$SOURCE_ROOT/envoy/bazel/proxy-wasm-cpp-host-s390x.patch"
  msg "proxy-wasm-cpp-host-s390x.patch: fetched"
}

installV8NoPipPatch() {
  # v8-nopip.patch is generated by runModulePatch (write_v8_nopip_patch function).
  # No manual patch content here — the file is created in the runModulePatch step.
  msg "v8-nopip.patch: will be written by runModulePatch"
}

# ===========================================================================
# installEnvoyBuildPatch
# Orchestrates all patch writes then applies Cargo.Bazel.lock and MODULE.bazel
# transformations.
# ===========================================================================
installEnvoyBuildPatch() {
  cd "$SOURCE_ROOT/envoy"

  # Allow git to operate even if the repo owner differs from the running user
  # (common in Docker containers where files are owned by a different uid).
  git config --global --add safe.directory "$SOURCE_ROOT/envoy" 2>/dev/null || true

  # Hard-reset any state left by a previous failed run
  git reset --hard HEAD 2>/dev/null || true
  git clean -fd bazel/ 2>/dev/null || true

  # Re-write patch files (git clean removes untracked files)
  installBoringsslPatch
  installRulesRustPatch
  installLuajitAsPatch
  installToolchainsLlvmPatch
  installGrpcS390xPatch
  installProtobufS390xPatch
  installQuicheS390xPatch
  installHighwayS390xPatch
  installProxyWasmCppHostS390xPatch
  installV8S390xPatch
  installV8BzlmodPatch
  installV8NoPipPatch

  # ---- 1. Cargo.Bazel.lock: mirror aarch64 entries as s390x ----
  runCargoBazelLockPatch

  # ---- 2a. bazel/envoy_binary.bzl: add -latomic after -pthread ----
  if ! grep -q '"-latomic"' bazel/envoy_binary.bzl; then
    sed -i 's/            "-pthread",/            "-pthread",\n            "-latomic",/' \
      bazel/envoy_binary.bzl
    msg "bazel/envoy_binary.bzl: patched (-latomic)"
  else
    msg "bazel/envoy_binary.bzl: already patched"
  fi

  # ---- 2b. bazel/platforms/BUILD: add linux_s390x platform ----
  if ! grep -q 'linux_s390x' bazel/platforms/BUILD; then
    cat >> bazel/platforms/BUILD << 'PLATFORMS_EOF'

platform(
    name = "linux_s390x",
    constraint_values = [
        "@platforms//os:linux",
        "@platforms//cpu:s390x",
    ],
)
PLATFORMS_EOF
    msg "bazel/platforms/BUILD: patched (linux_s390x)"
  else
    msg "bazel/platforms/BUILD: already patched"
  fi

  # ---- 2c. bazel/extensions.bzl: add s390x to arch_alias dict ----
  if ! grep -q '"s390x"' bazel/extensions.bzl; then
    sed -i 's|"aarch64": str(Label("//bazel/platforms/rbe:linux_arm64")),|"aarch64": str(Label("//bazel/platforms/rbe:linux_arm64")),\n            "s390x": str(Label("//bazel/platforms:linux_s390x")),|' \
      bazel/extensions.bzl
    msg "bazel/extensions.bzl: patched (s390x arch_alias)"
  else
    msg "bazel/extensions.bzl: already patched"
  fi

  # ---- 3. MODULE.bazel: archive_overrides + llvm_s390x toolchain ----
  runModulePatch

  cd "$SOURCE_ROOT"
}

# ===========================================================================
# runCargoBazelLockPatch
# Mirrors every aarch64-unknown-linux-gnu entry in Cargo.Bazel.lock as
# s390x-unknown-linux-gnu, injects s390x into the conditions map, and clears
# the checksum so Bazel accepts the modified file.
# ===========================================================================
runCargoBazelLockPatch() {
  ENVOY_DIR="$SOURCE_ROOT/envoy" python3 - << 'CARGO_LOCK_PY_EOF'
import json, copy, sys, os

os.chdir(os.environ.get("ENVOY_DIR", "."))
lock_path = "Cargo.Bazel.lock"
with open(lock_path) as fh:
    data = json.load(fh)

T_S390  = "s390x-unknown-linux-gnu"
T_ARM64 = "aarch64-unknown-linux-gnu"
modified = False

def mirror(v):
    changed = False
    if isinstance(v, dict):
        if T_ARM64 in v and T_S390 not in v:
            v[T_S390] = copy.deepcopy(v[T_ARM64])
            changed = True
        for child in v.values():
            changed |= mirror(child)
    elif isinstance(v, list):
        for item in v:
            changed |= mirror(item)
    return changed

modified |= mirror(data.get("crates", {}))

conds = data.get("conditions", {})
if T_S390 not in conds:
    conds[T_S390] = [T_S390]
    modified = True
for val in conds.values():
    if isinstance(val, list) and T_ARM64 in val and T_S390 not in val:
        val.insert(val.index(T_ARM64) + 1, T_S390)
        modified = True

if data.get("checksum"):
    data["checksum"] = ""
    modified = True

if modified:
    with open(lock_path, "w") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
    print("Cargo.Bazel.lock: injected s390x entries")
else:
    print("Cargo.Bazel.lock: s390x already present")
CARGO_LOCK_PY_EOF
}

# ===========================================================================
# runModulePatch
# Fetches upstream patches and overlay files, generates all archive_override
# stanzas in MODULE.bazel, injects the llvm_toolchain_s390x extension, patches
# luajit BUILD.bazel for s390x, and generates v8-nopip.patch.
# Requires: ENVOY_DIR, LLVM_HOME_DIR, ENVOY_REGISTRY in the environment.
# ===========================================================================
runModulePatch() {
  ENVOY_DIR="$SOURCE_ROOT/envoy" \
  LLVM_HOME_DIR="$LLVM_HOME_DIR" \
  ENVOY_REGISTRY="$ENVOY_REGISTRY" \
    python3 - << 'MODULE_PY_EOF'
import os, sys, re, subprocess

llvm_path = os.environ["LLVM_HOME_DIR"]
envoy_reg = os.environ["ENVOY_REGISTRY"]
bcr       = "https://bcr.bazel.build"
bdir      = "bazel"
os.chdir(os.environ.get("ENVOY_DIR", "."))

def fetch(url, dest):
    os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
    r = subprocess.run(["curl", "-sSfL", "-o", dest, url],
                       capture_output=True, text=True)
    if r.returncode != 0:
        print("ERROR fetching " + url + ": " + r.stderr, file=sys.stderr)
        sys.exit(1)
    print("  fetched " + dest)

def fetch_text(url):
    r = subprocess.run(["curl", "-sSfL", url],
                       capture_output=True, text=True)
    if r.returncode != 0:
        print("ERROR fetching " + url, file=sys.stderr)
        sys.exit(1)
    return r.stdout

def fetch_patch(url, dest):
    raw = fetch_text(url)
    idx = raw.find("\ndiff --git ")
    if idx == -1:
        idx = raw.find("diff --git ")
        if idx == -1:
            print("ERROR: no diff --git in " + url, file=sys.stderr)
            sys.exit(1)
    else:
        idx += 1
    os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
    with open(dest, "w") as f:
        f.write(raw[idx:])
    print("  wrote patch: " + dest)

def add_file_patch(dest, content, name):
    lines = [l + "\n" for l in content.splitlines()]
    body  = "".join("+" + l for l in lines)
    patch = ("diff --git a/" + name + " b/" + name + "\n"
             "new file mode 100644\n"
             "--- /dev/null\n"
             "+++ b/" + name + "\n"
             "@@ -0,0 +1," + str(len(lines)) + " @@\n"
             + body)
    os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
    with open(dest, "w") as f:
        f.write(patch)
    print("  wrote add-file patch: " + dest)

def replace_file_patch(dest, old, new, name):
    old_lines = [l + "\n" for l in old.splitlines()]
    new_lines = [l + "\n" for l in new.splitlines()]
    patch = ("diff --git a/" + name + " b/" + name + "\n"
             "--- a/" + name + "\n"
             "+++ b/" + name + "\n"
             "@@ -1," + str(len(old_lines)) + " +1," + str(len(new_lines)) + " @@\n"
             + "".join("-" + l for l in old_lines)
             + "".join("+" + l for l in new_lines))
    os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
    with open(dest, "w") as f:
        f.write(patch)
    print("  wrote replace-file patch: " + dest)

def blabel(p):
    p = p.replace("\\", "/")
    if p.startswith("bazel/external/"):
        return "//bazel/external:" + os.path.basename(p)
    return "//bazel:" + os.path.basename(p)

ER = envoy_reg

deps = [
    {
        "name": "boringssl",
        "url": "https://github.com/google/boringssl/releases/download/0.20260813.0/boringssl-0.20260813.0.tar.gz",
        "integrity": "sha256-N+I8uaX6VPAbB8rdZTzrwdGyNZRUOabDNP6ljqR7Wwo=",
        "strip": "boringssl-0.20260813.0/",
        "pstrip": 1,
        "patches": [],
        "overlays": [],
        "s390x": bdir + "/boringssl-s390x.patch",
    },
    {
        "name": "boringssl-source",
        "url": "https://github.com/google/boringssl/releases/download/0.20260813.0/boringssl-0.20260813.0.tar.gz",
        "integrity": "sha256-N+I8uaX6VPAbB8rdZTzrwdGyNZRUOabDNP6ljqR7Wwo=",
        "strip": "boringssl-0.20260813.0/",
        "pstrip": 1,
        "patches": [],
        "overlays": [
            (ER + "/modules/boringssl-source/0.20260813.0.envoy/overlay/BUILD.bazel",
             bdir + "/boringssl-source-overlay-BUILD.patch", "BUILD.bazel", None),
            (ER + "/modules/boringssl-source/0.20260813.0.envoy/MODULE.bazel",
             bdir + "/boringssl-source-overlay-MODULE.patch", "MODULE.bazel",
             "https://raw.githubusercontent.com/google/boringssl/refs/tags/0.20260813.0/MODULE.bazel"),
        ],
        "s390x": None,
    },
    {
        "name": "quiche",
        "url": "https://github.com/google/quiche/archive/7f07dc4d14c5702607a0dee9c7e4ab07f63f9883.tar.gz",
        "integrity": "sha256-YI8/Lnv4lmm/77LsbsV/BfSFy/TpGI7Z5gDeAGYqo8Q=",
        "strip": "quiche-7f07dc4d14c5702607a0dee9c7e4ab07f63f9883",
        "pstrip": 1,
        "patches": [
            (ER, "modules/quiche/0.0.0-260922-7f07dc4.envoy/patches/delete-bazel-files.patch",
             bdir + "/external/delete-bazel-files.patch"),
            (ER, "modules/quiche/0.0.0-260922-7f07dc4.envoy/patches/balsa_frame_unused_variable.patch",
             bdir + "/external/balsa_frame_unused_variable.patch"),
        ],
        "overlays": [
            (ER + "/modules/quiche/0.0.0-260922-7f07dc4.envoy/overlay/BUILD.bazel",
             bdir + "/external/quiche-overlay-BUILD.patch", "BUILD.bazel", None),
            (ER + "/modules/quiche/0.0.0-260922-7f07dc4.envoy/overlay/quiche_overlay.bzl",
             bdir + "/external/quiche-overlay-quiche_overlay_bzl.patch", "quiche_overlay.bzl", None),
            (ER + "/modules/quiche/0.0.0-260922-7f07dc4.envoy/overlay/extensions.bzl",
             bdir + "/external/quiche-overlay-extensions_bzl.patch", "extensions.bzl", None),
            (ER + "/modules/quiche/0.0.0-260922-7f07dc4.envoy/overlay/envoy_deps.bzl",
             bdir + "/external/quiche-overlay-envoy_deps_bzl.patch", "envoy_deps.bzl", None),
            # Replace upstream MODULE.bazel (missing @platforms dep and
            # extensions.bzl use_extension) with the registry overlay.
            (ER + "/modules/quiche/0.0.0-260922-7f07dc4.envoy/MODULE.bazel",
             bdir + "/external/quiche-overlay-MODULE.patch", "MODULE.bazel",
             "https://raw.githubusercontent.com/google/quiche/7f07dc4d14c5702607a0dee9c7e4ab07f63f9883/MODULE.bazel"),
        ],
        "s390x": bdir + "/external/quiche-s390x.patch",
    },
    {
        "name": "proxy-wasm-cpp-host",
        "url": "https://github.com/proxy-wasm/proxy-wasm-cpp-host/archive/f2db56af443571e92a31c0b877106d9ea96e19ef.tar.gz",
        "integrity": "sha256-NNrFvOvwsVbkNb+N2b2sW+YLlflnxCDGgFeNc68oxgQ=",
        "strip": "proxy-wasm-cpp-host-f2db56af443571e92a31c0b877106d9ea96e19ef",
        "pstrip": 1,
        "patches": [
            (ER, "modules/proxy-wasm-cpp-host/0.0.0-260704-f2db56a.envoy/patches/proxy-wasm-cpp-host.patch",
             bdir + "/proxy-wasm-cpp-host.patch"),
        ],
        "overlays": [
            (ER + "/modules/proxy-wasm-cpp-host/0.0.0-260704-f2db56a.envoy/MODULE.bazel",
             bdir + "/proxy-wasm-cpp-host-overlay-MODULE.patch", "MODULE.bazel", None),
        ],
        "s390x": bdir + "/proxy-wasm-cpp-host-s390x.patch",
    },
    {
        "name": "rules_foreign_cc",
        "url": "https://github.com/bazel-contrib/rules_foreign_cc/releases/download/0.16.0/rules_foreign_cc-0.16.0.tar.gz",
        "integrity": "sha256-Mns/ys3pe5ZlQk2ytsN+b42lnsx4PcW4aDxpOW+CChI=",
        "strip": "rules_foreign_cc-0.16.0",
        "pstrip": 1,
        "patches": [
            (bcr, "modules/rules_foreign_cc/0.16.0/patches/module_dot_bazel_version.patch",
             bdir + "/module_dot_bazel_version.patch"),
        ],
        "overlays": [],
        "s390x": None,
    },
    {
        "name": "rules_rust",
        "url": "https://github.com/bazelbuild/rules_rust/releases/download/0.74.0/rules_rust-0.74.0.tar.gz",
        "integrity": "sha256-2LzB4RHpgnDcAxcuIu96+cL5TzJpgBYYorg9IIkPjfU=",
        "strip": "",
        "pstrip": 1,
        "patches": [
            (ER, "modules/rules_rust/0.74.0.envoy/patches/rules_rust.patch",
             bdir + "/rules_rust-envoy.patch"),
        ],
        "overlays": [],
        "s390x": bdir + "/rules_rust-s390x.patch",
    },
    {
        "name": "grpc",
        "url": "https://github.com/grpc/grpc/archive/v1.83.0.tar.gz",
        "integrity": "sha256-kNRTOTqdQSFd9UYQOxCzO5Vm33nN9vSdxn9sTQRNCQ0=",
        "strip": "grpc-1.83.0",
        "pstrip": 1,
        "patches": [
            (ER, "modules/grpc/1.83.0.envoy/patches/grpc.patch",
             bdir + "/grpc-envoy.patch"),
        ],
        "overlays": [],
        "s390x": bdir + "/grpc-s390x.patch",
    },
    {
        "name": "protobuf",
        "url": "https://github.com/protocolbuffers/protobuf/releases/download/v35.1/protobuf-35.1.tar.gz",
        "integrity": "sha256-8LaDjnUiqNqWEm1IcGjJWbxiSSY2jzAkrI/QOr0KGsQ=",
        "strip": "protobuf-35.1",
        "pstrip": 1,
        "patches": [
            (ER, "modules/protobuf/35.1.bcr.envoy/patches/envoy.patch",
             bdir + "/protobuf-envoy.patch"),
        ],
        "overlays": [],
        "s390x": None,  # protobuf 35.1 does not need s390x patch
    },
    {
        "name": "v8",
        "url": "https://github.com/v8/v8/archive/refs/tags/14.6.202.10.tar.gz",
        "integrity": "sha256-CcPZ95amcfuWMMcZADLwAXHOme/9fIDHquuhSKe8vBs=",
        "strip": "v8-14.6.202.10",
        "pstrip": 1,
        "patches": [
            (ER, "modules/v8/14.6.202.10.envoy/patches/v8.patch",
             bdir + "/v8-envoy.patch"),
            (ER, "modules/v8/14.6.202.10.envoy/patches/requirements.patch",
             bdir + "/v8-requirements.patch"),
        ],
        "overlays": [
            (ER + "/modules/v8/14.6.202.10.envoy/MODULE.bazel",
             bdir + "/v8-overlay-MODULE.patch", "MODULE.bazel",
             "https://raw.githubusercontent.com/v8/v8/refs/tags/14.6.202.10/MODULE.bazel"),
        ],
        "s390x": bdir + "/v8-s390x.patch",
        "extra_patches": [bdir + "/v8-bzlmod.patch", bdir + "/v8-nopip.patch"],
    },
    {
        "name": "toolchains_llvm",
        "url": "https://github.com/bazel-contrib/toolchains_llvm/releases/download/v1.9.1/toolchains_llvm-v1.9.1.tar.gz",
        "integrity": "sha256-QJmeWn22JiaEVxR56Nr7nAre+g775m2yKxN4cheM1HM=",
        "strip": "toolchains_llvm-v1.9.1",
        "pstrip": 1,
        "patches": [
            (ER, "modules/toolchains_llvm/1.9.1.envoy/patches/allow_nonroot.patch",
             bdir + "/allow_nonroot.patch"),
            (ER, "modules/toolchains_llvm/1.9.1.envoy/patches/x_compile.patch",
             bdir + "/x_compile.patch"),
        ],
        "overlays": [],
        "s390x": bdir + "/toolchains_llvm-s390x.patch",
    },
]

os.makedirs(bdir, exist_ok=True)
os.makedirs(bdir + "/external", exist_ok=True)

for dep in deps:
    for (rb, rp, ld) in dep["patches"]:
        fetch(rb + "/" + rp, ld)

def strip_pip_parse(content):
    import re as _re
    content = _re.sub(r'\npip = use_extension\([^\n]*\)\n', '\n', content)
    content = _re.sub(r'\npip\.parse\(.*?\)\n', '\n', content, flags=_re.DOTALL)
    content = _re.sub(r'\nuse_repo\(pip[^)]*\)\n', '\n', content)
    return content

for dep in deps:
    for (url, dest, fname, old_url) in dep["overlays"]:
        new_c = fetch_text(url)
        if dep["name"] == "v8" and fname == "MODULE.bazel":
            new_c = strip_pip_parse(new_c)
        if old_url:
            replace_file_patch(dest, fetch_text(old_url), new_c, fname)
        else:
            add_file_patch(dest, new_c, fname)

def write_v8_nopip_patch(dest):
    import difflib as _dl
    raw = fetch_text("https://raw.githubusercontent.com/v8/v8/refs/tags/14.6.202.10/BUILD.bazel")
    lines = raw.splitlines(keepends=True)
    new_lines = []
    i = 0
    while i < len(lines):
        if lines[i].strip() == 'load("@v8_python_deps//:requirements.bzl", "requirement")':
            i += 1
            continue
        if (lines[i].strip() == 'deps = [' and
                i + 1 < len(lines) and 'requirement("jinja2")' in lines[i+1] and
                i + 2 < len(lines) and lines[i+2].strip() == '],'):
            i += 3
            continue
        new_lines.append(lines[i])
        i += 1
    diff = list(_dl.unified_diff(lines, new_lines,
                                 fromfile="a/BUILD.bazel",
                                 tofile="b/BUILD.bazel"))
    os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
    with open(dest, "w") as f:
        f.writelines(diff)
    print("  wrote v8-nopip patch: " + dest)

write_v8_nopip_patch(bdir + "/v8-nopip.patch")

for dep in deps:
    labels = []
    for (_, dest, _, _) in dep["overlays"]:
        labels.append(blabel(dest))
    for (_, _, ld) in dep["patches"]:
        labels.append(blabel(ld))
    if dep["s390x"]:
        if os.path.exists(dep["s390x"]):
            labels.append(blabel(dep["s390x"]))
        else:
            print("WARNING: missing s390x patch: " + dep["s390x"], file=sys.stderr)
    for ep in dep.get("extra_patches", []):
        if os.path.exists(ep):
            labels.append(blabel(ep))
        else:
            print("WARNING: missing extra patch: " + ep, file=sys.stderr)
    dep["labels"] = labels

def make_override(dep):
    name   = dep["name"]
    labels = dep["labels"]
    out = ("\narchive_override(\n"
           "    module_name = \"" + name + "\",\n"
           "    urls = [\"" + dep["url"] + "\"],\n"
           "    integrity = \"" + dep["integrity"] + "\",\n"
           "    strip_prefix = \"" + dep["strip"] + "\",\n")
    if labels:
        out += "    patches = [\n"
        for lb in labels:
            out += "        \"" + lb + "\",\n"
        out += "    ],\n"
        out += "    patch_strip = " + str(dep["pstrip"]) + ",\n"
    out += ")\n"
    return out

with open("MODULE.bazel") as f:
    mod = f.read()

anchor = "####################################################################################\n# deps: Overrides"
if anchor not in mod:
    for cand in ["single_version_override(", "archive_override("]:
        if cand in mod:
            anchor = cand
            break
    else:
        print("ERROR: anchor not found in MODULE.bazel", file=sys.stderr)
        sys.exit(1)

for dep in deps:
    nm = dep["name"]
    for ot in ["single_version_override", "archive_override"]:
        mod = re.sub(
            r"\n" + ot + r"\(\s*\n\s*module_name\s*=\s*\"" + re.escape(nm) + r"\".*?\n\)\n",
            "", mod, flags=re.DOTALL)
    mod = mod.replace(anchor, make_override(dep) + anchor, 1)
    print("MODULE.bazel: archive_override for " + nm)

_S390X_PLATFORM_TRIPLES = (
    "    supported_platform_triples = [\n"
    "        \"aarch64-apple-darwin\",\n"
    "        \"aarch64-unknown-linux-gnu\",\n"
    "        \"s390x-unknown-linux-gnu\",\n"
    "        \"wasm32-unknown-unknown\",\n"
    "        \"wasm32-wasip1\",\n"
    "        \"x86_64-pc-windows-msvc\",\n"
    "        \"x86_64-unknown-linux-gnu\",\n"
    "        \"x86_64-unknown-nixos-gnu\",\n"
    "    ],\n"
)

def inject_isolated(text):
    result = []
    pos = 0
    marker = "crate.from_cargo("
    while True:
        idx = text.find(marker, pos)
        if idx == -1:
            result.append(text[pos:])
            break
        result.append(text[pos:idx + len(marker)])
        depth = 1
        i = idx + len(marker)
        while i < len(text) and depth > 0:
            if text[i] == "(":   depth += 1
            elif text[i] == ")": depth -= 1
            i += 1
        inner = text[idx + len(marker):i - 1]
        extra = ""
        if "isolated" not in inner:
            extra += "    isolated = False,\n"
        if "supported_platform_triples" not in inner:
            extra += _S390X_PLATFORM_TRIPLES
        result.append(inner + extra)
        result.append(")")
        pos = i
    return "".join(result)

if "isolated = False" not in mod and "crate.from_cargo(" in mod:
    mod = inject_isolated(mod)
    print("MODULE.bazel: injected isolated=False + s390x supported_platform_triples into crate.from_cargo() calls")

def fix_rust_repository_set_target_triple(text):
    import re as _re
    def _add_target_triple(m):
        inner = m.group(1)
        if "target_triple" not in inner:
            exec_m = _re.search(r'exec_triple\s*=\s*"([^"]+)"', inner)
            if exec_m:
                triple_val = exec_m.group(1)
                inner = inner.rstrip() + '\n    target_triple = "' + triple_val + '",\n'
        return "rust.repository_set(" + inner + ")"
    return _re.sub(r"rust\.repository_set\(([^)]+)\)", _add_target_triple, text, flags=_re.DOTALL)

if "rust.repository_set(" in mod:
    mod = fix_rust_repository_set_target_triple(mod)
    print("MODULE.bazel: fixed rust.repository_set() target_triple")

# ---- luajit archive_override ----
for ot in ["single_version_override", "archive_override"]:
    mod = re.sub(
        r"\n" + ot + r"\(\s*\n\s*module_name\s*=\s*\"luajit\".*?\n\)\n",
        "", mod, flags=re.DOTALL)

luajit_stanza = (
    "\narchive_override(\n"
    "    module_name = \"luajit\",\n"
    "    urls = [\"https://github.com/LuaJIT/LuaJIT/archive/871db2c.tar.gz\"],\n"
    "    integrity = \"sha256-qz8W2C32lGVDVlz7DSgQ04fXmjpD4EMWlbA0ZhiOJoA=\",\n"
    "    strip_prefix = \"LuaJIT-871db2c84ecefd70a850e03a6c340214a81739f0\",\n"
    "    patches = [\n"
    "        \"//bazel:luajit-overlay-BUILD.patch\",\n"
    "        \"//bazel:luajit-overlay-MODULE.patch\",\n"
    "        \"//bazel:luajit-s390x-dynasm.patch\",\n"
    "        \"//bazel:luajit-s390x-vm.patch\",\n"
    "        \"//bazel:luajit-s390x-fix.patch\",\n"
    "        \"//bazel:luajit-as.patch\",\n"
    "    ],\n"
    "    patch_strip = 1,\n"
    ")\n"
)
mod = mod.replace(anchor, luajit_stanza + anchor, 1)
print("MODULE.bazel: archive_override for luajit")

# ---- highway single_version_override with s390x patch ----
highway_s390x_patch = bdir + "/highway-s390x.patch"
if os.path.exists(highway_s390x_patch):
    for ot in ["single_version_override", "archive_override"]:
        mod = re.sub(
            r"\n" + ot + r"\(\s*\n\s*module_name\s*=\s*\"highway\".*?\n\)\n",
            "", mod, flags=re.DOTALL)
    highway_stanza = (
        "\nsingle_version_override(\n"
        "    module_name = \"highway\",\n"
        "    version = \"1.2.0\",\n"
        "    patches = [\"//bazel:highway-s390x.patch\"],\n"
        "    patch_strip = 1,\n"
        ")\n"
    )
    mod = mod.replace(anchor, highway_stanza + anchor, 1)
    print("MODULE.bazel: single_version_override for highway (s390x patch)")

def inject_luajit_s390x(content):
    setting_s390x = """
config_setting(
    name = "linux_s390x",
    constraint_values = [
        "@platforms//cpu:s390x",
        "@platforms//os:linux",
    ],
)
"""
    insert_before1 = "\n##############################################################################\n# Stage 1"
    if insert_before1 in content and "linux_s390x" not in content:
        content = content.replace(insert_before1, setting_s390x + insert_before1, 1)

    arch_h_s390x = """
genrule(
    name = "buildvm_arch_h_s390x",
    srcs = ["src/vm_s390x.dasc"] + _DYNASM_SRCS,
    outs = ["_s390x/buildvm_arch.h"],
    cmd = "$(location :minilua) $(location dynasm/dynasm.lua) -D S390X -D ENDIAN_BE -D P64 -D FFI -D DUALNUM -D FPU -D HFABI -D VER=0 -o $@ $(location src/vm_s390x.dasc)",
    tools = [":minilua"],
)
"""
    insert_before3 = "\n##############################################################################\n# Stage 3"
    if insert_before3 in content and "buildvm_arch_h_s390x" not in content:
        content = content.replace(insert_before3, arch_h_s390x + insert_before3, 1)

    buildvm_s390x_rule = """
cc_binary(
    name = "buildvm_s390x",
    srcs = _BUILDVM_SRCS + [":buildvm_arch_h_s390x"],
    copts = _BUILDVM_COPTS,
    includes = _BUILDVM_INCLUDES + ["_s390x"],
    local_defines = _BUILDVM_DEFINES + ["LUAJIT_TARGET=LUAJIT_ARCH_S390X"],
)
"""
    insert_before4 = "\n##############################################################################\n# Stage 4"
    if insert_before4 in content and "buildvm_s390x" not in content:
        content = content.replace(insert_before4, buildvm_s390x_rule + insert_before4, 1)

    import re as _re
    _sed = "sed " + chr(39) + "s/.hword/.2byte/g" + chr(39)
    _s390x_elfasm = (
        "        " + chr(34) + ":linux_s390x" + chr(34) + ": "
        + chr(34) + "$(location :buildvm_s390x) -m elfasm -o $@.tmp && " + _sed + " $@.tmp > $@" + chr(34) + ",\n"
    )
    content = _re.sub(
        r'(":linux_arm64": "\$\(location :buildvm_arm64\) -m elfasm -o \$@",\n)',
        r'\1' + _s390x_elfasm,
        content)
    content = _re.sub(
        r'(":linux_arm64": \[":buildvm_arm64"\],)',
        r'\1\n        ":linux_s390x": [":buildvm_s390x"],',
        content)
    for mode in ["bcdef", "ffdef", "libdef", "recdef", "folddef"]:
        content = _re.sub(
            r'(":linux_arm64": "\$\(location :buildvm_arm64\) -m ' + mode + r' -o \$@ \$\(SRCS\)",)',
            r'\1\n        ":linux_s390x": "$(location :buildvm_s390x) -m ' + mode + r' -o $@ $(SRCS)",',
            content)
    return content

reg_base = envoy_reg + "/modules/luajit/0.0.0-260126-871db2c.envoy/overlay"
for (fname, dest) in [("BUILD.bazel",  bdir + "/luajit-overlay-BUILD.patch"),
                       ("MODULE.bazel", bdir + "/luajit-overlay-MODULE.patch")]:
    raw = fetch_text(reg_base + "/" + fname)
    if fname == "BUILD.bazel":
        raw = inject_luajit_s390x(raw)
    add_file_patch(dest, raw, fname)

fetch_patch("https://github.com/iii-i/moonjit/commit/dee73f516f0da49e930dcfa1dd61720dcb69b7dd.patch",
            bdir + "/luajit-s390x-dynasm.patch")
fetch_patch("https://github.com/iii-i/moonjit/commit/035f133798adb856391928600f7cb6b4f81578ab.patch",
            bdir + "/luajit-s390x-vm.patch")
fetch_patch("https://github.com/openresty/luajit2/commit/e598aeb7426dbc069f90ba70db9bce43cd573b0e.patch",
            bdir + "/luajit-s390x-fix.patch")

# ---- llvm_s390x toolchain extension ----
for pat in [
    r"\nllvm_s390x\s*=\s*use_extension\([^\n]*\)\n"
    r"llvm_s390x\.toolchain\([^)]*\)\n"
    r"llvm_s390x\.toolchain_root\([^)]*\)\n"
    r"use_repo\(llvm_s390x[^)]*\)\n",
    r'register_toolchains\("@llvm_toolchain_s390x//:all"\)\n',
]:
    mod = re.sub(pat, "", mod, flags=re.DOTALL)

s390x_ext = (
    "\nllvm_s390x = use_extension("
    "\"@toolchains_llvm//toolchain/extensions:llvm.bzl\", \"llvm\")\n"
    "llvm_s390x.toolchain(\n"
    "    name = \"llvm_toolchain_s390x\",\n"
    "    llvm_version = \"22.1.8\",\n"
    ")\n"
    "llvm_s390x.toolchain_root(\n"
    "    name = \"llvm_toolchain_s390x\",\n"
    "    path = \"" + llvm_path + "\",\n"
    "    targets = [\"linux-s390x\"],\n"
    ")\n"
    "use_repo(llvm_s390x, \"llvm_toolchain_s390x\")\n"
)

marker = "use_repo(llvm, \"llvm_toolchain\")"
if marker in mod:
    mod = mod.replace(marker, s390x_ext + marker, 1)
    print("MODULE.bazel: inserted llvm_toolchain_s390x")
else:
    print("WARNING: llvm marker not found, appending s390x ext")
    mod += s390x_ext

reg_tc = "register_toolchains(\"@llvm_toolchain//:all\")"
if reg_tc in mod and "register_toolchains(\"@llvm_toolchain_s390x//:all\")" not in mod:
    mod = mod.replace(reg_tc,
                      reg_tc + "\nregister_toolchains(\"@llvm_toolchain_s390x//:all\")", 1)
    print("MODULE.bazel: registered llvm_toolchain_s390x")

# ---- envoy_llvm_extension: inject host() tag so s390x bypasses the
#      _llvm_alias_repo platform check (only supports x86/arm/mac).
#      Without this, the build fails with "Unsupported host platform for
#      llvm_toolchain_llvm: linux s390x" on any s390x host. ----
_ENVOY_LLVM_EXT_MARKER = 'envoy_llvm_ext = use_extension("//bazel:extensions.bzl", "envoy_llvm_extension")'
_ENVOY_LLVM_HOST_TAG = (
    'envoy_llvm_ext = use_extension("//bazel:extensions.bzl", "envoy_llvm_extension")\n'
    'envoy_llvm_ext.host(\n'
    '    llvm_version = "22.1.8",\n'
    '    path = "' + llvm_path + '",\n'
    ')\n'
)
if _ENVOY_LLVM_EXT_MARKER in mod:
    if 'envoy_llvm_ext.host(' not in mod:
        mod = mod.replace(_ENVOY_LLVM_EXT_MARKER, _ENVOY_LLVM_HOST_TAG, 1)
        print("MODULE.bazel: injected envoy_llvm_ext.host() for s390x")
    else:
        print("MODULE.bazel: envoy_llvm_ext.host() already present")
else:
    print("WARNING: envoy_llvm_ext marker not found — skipping host() injection")

# ---- go_sdk.download(): add linux_s390x entry ----
# The go_sdk.download() block in MODULE.bazel only lists amd64/arm64/darwin
# platforms.  On s390x rules_go fails with "unsupported platform linux_s390x"
# during the gazelle extension load.  We inject the s390x SDK entry so
# rules_go can resolve the toolchain without trying to download anything
# (the system Go in /usr/local/go is used at build time via GOPATH, but
# rules_go still needs to parse the sdks dict during analysis).
# Inject linux_s390x into go_sdk.download() sdks dict.
# The upstream block only lists amd64/arm64/darwin — rules_go fails with
# "unsupported platform linux_s390x" during analysis without this entry.
_GO_S390X_LINE = (
    '        "linux_s390x": ("go1.27.1.linux-s390x.tar.gz",'
    ' "c9e1ad7bddea40e2eb10b4d3267ae06d462667839bf0ba94c2e2d160b06f9b9e"),\n'
)
_GO_ANCHOR = '        "darwin_amd64":'
# Check specifically inside the go_sdk.download() block, not the whole file
# (linux_s390x already appears in rust.repository_set stanzas above).
_go_sdk_idx = mod.find('go_sdk.download(')
_go_sdk_end = mod.find(')', _go_sdk_idx) if _go_sdk_idx != -1 else -1
_go_sdk_block = mod[_go_sdk_idx:_go_sdk_end] if _go_sdk_idx != -1 else ''
if 'go_sdk.download(' in mod and 'linux_s390x' not in _go_sdk_block:
    # Find the darwin_amd64 line (always last in the upstream sdks dict)
    # and insert s390x right after it.
    idx = mod.find(_GO_ANCHOR)
    if idx != -1:
        eol = mod.index("\n", idx)
        mod = mod[:eol+1] + _GO_S390X_LINE + mod[eol+1:]
        print("MODULE.bazel: injected linux_s390x into go_sdk.download()")
    else:
        print("WARNING: go_sdk.download darwin_amd64 anchor not found")

with open("MODULE.bazel", "w") as f:
    f.write(mod)
print("MODULE.bazel: done")
MODULE_PY_EOF
}

# ===========================================================================
# retry — retry a command up to 5 times with a 3-second back-off
# ===========================================================================
retry() {
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
