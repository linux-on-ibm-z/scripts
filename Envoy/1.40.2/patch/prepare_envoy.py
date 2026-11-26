#!/usr/bin/env python3
# Wire envoy v1.40.2 (bzlmod) for s390x. Idempotent: run on a clean checkout (git checkout . first).
import re, sys, os
R=os.environ.get("SOURCE_ROOT"); E=R+"/envoy"
LLVM=R+"/LLVM-22.1.8-Linux"
m=open(E+"/MODULE.bazel").read()
def sub(pat,rep,s,flags=re.S):
    n,c=re.subn(pat,rep,s,flags=flags)
    assert c==1,(pat,c)
    return n
# (b) cmake/ninja: use the source-built 4.0.7 / 1.13.2 from PATH
m=sub(r'foreign_cc_tools\.cmake\(\s*mode = "binary",\s*version = "4\.0\.7",\s*\)','foreign_cc_tools.cmake(\n    mode = "system",\n)',m)
m=sub(r'foreign_cc_tools\.ninja\(\s*mode = "binary",\s*version = "1\.13\.2",\s*\)','foreign_cc_tools.ninja(\n    mode = "system",\n)',m)
# (a) host LLVM, same pattern as bazel/tests/codeql/MODULE.bazel
start=m.index('llvm.cxx_cross_lib(\n    name = "llvm_toolchain",\n    label = "@libcxx_libs_aarch64"')
end=m.index('use_repo(llvm, "llvm_toolchain")')
m=m[:start]+'''llvm.toolchain(
    name = "llvm_toolchain",
    cxx_standard = {"": "c++20"},
    llvm_version = "22.1.8",
    stdlib = {"": "libc++"},
)
llvm.toolchain_root(
    name = "llvm_toolchain",
    path = "%s",
)
'''%LLVM+m[end:]
m=sub(r'(envoy_llvm_ext = use_extension\("//bazel:extensions\.bzl", "envoy_llvm_extension"\)\n)',r'\1envoy_llvm_ext.host(llvm_version = "22.1.8", path = "%s")\n'%LLVM,m)
# (d) go_sdk: add linux_s390x (checksum from go.dev/dl)
m=sub(r'(sdks = \{\n)',r'\1        "linux_s390x": ("go1.27.3.linux-s390x.tar.gz", "62e109a6280a073c9025e1b51ea298ec1d3575d3ce62238721311f5ff2c854e6"),\n',m)
# (e) per-module patches
m=m.replace('''single_version_override(
    module_name = "boringssl",
    version = "0.20260929.0",
)''','''single_version_override(
    module_name = "boringssl",
    version = "0.20260929.0",
    patch_strip = 1,
    patches = ["//bazel/s390x-patches:boringssl-s390x.patch"],
)

single_version_override(
    module_name = "highway",
    version = "1.2.0",
    patch_strip = 1,
    patches = ["//bazel/s390x-patches:highway-s390x.patch"],
)

single_version_override(
    module_name = "v8",
    version = "14.6.202.10.envoy",
    patch_strip = 1,
    patches = ["//bazel/s390x-patches:v8-s390x.patch"],
)

single_version_override(
    module_name = "toolchains_llvm",
    version = "1.9.1.envoy",
    patch_strip = 1,
    patches = ["//bazel/s390x-patches:toolchains_llvm-s390x.patch"],
)

single_version_override(
    module_name = "proxy-wasm-cpp-host",
    version = "0.0.0-260704-f2db56a.envoy",
    patch_strip = 1,
    patches = ["//bazel/s390x-patches:proxy_wasm_cpp_host-s390x.patch"],
)

single_version_override(
    module_name = "grpc",
    version = "1.83.0.envoy",
    patch_strip = 1,
    patches = ["//bazel/s390x-patches:grpc-s390x.patch"],
)

single_version_override(
    module_name = "quiche",
    version = "0.0.0-261006-9e60ac2.envoy",
    patch_strip = 1,
    patches = ["//bazel/s390x-patches:quiche-s390x.patch"],
)

single_version_override(
    module_name = "luajit",
    version = "0.0.0-260126-871db2c.envoy",
    patch_strip = 1,
    patches = ["//bazel/s390x-patches:luajit-s390x.patch"],
)''')
open(E+"/MODULE.bazel","w").write(m)
# (f) rust: upstream repository_set has no target_triple -> rules_rust gets "" as a triple. Set it to the exec triple.
#     rc-3: also register wasm32 target triples on the s390x exec repository_set so the wasm/wasi
#     transitions in bazel/wasm/wasm.bzl find a rust toolchain. rules_rust only accepts target_triple /
#     target_compatible_with / opt_level / strip_level on follow-up repository_set calls with the same name.
m=open(E+"/MODULE.bazel").read()
m=sub(r'(rust\.repository_set\(\n    name = "rust_linux_s390x",\n    edition = "2018",\n    exec_triple = "s390x-unknown-linux-gnu",\n    versions = \["1\.97\.1"\],\n)\)\n',r'''\1    target_compatible_with = ["@platforms//os:linux", "@platforms//cpu:s390x"],
    target_triple = "s390x-unknown-linux-gnu",
)
rust.repository_set(
    name = "rust_linux_s390x",
    target_compatible_with = ["@platforms//cpu:wasm32", "@platforms//os:none"],
    target_triple = "wasm32-unknown-unknown",
)
rust.repository_set(
    name = "rust_linux_s390x",
    target_compatible_with = [
        "@platforms//cpu:wasm32",
        "@platforms//os:wasi",
        "@rules_rust//rust/platform:wasi_preview_1",
    ],
    target_triple = "wasm32-wasip1",
)
''',m)
open(E+"/MODULE.bazel","w").write(m)
# (g) pip: rules_python default platforms lack linux_s390x -> v8_python_deps//jinja2 has no BUILD file
m=open(E+"/MODULE.bazel").read()
m=sub(r'(pip = use_extension\("@rules_python//python/extensions:pip.bzl", "pip"\)\n)',r'''\1pip.default(
    arch_name = "s390x",
    config_settings = [
        "@platforms//cpu:s390x",
        "@platforms//os:linux",
        "@rules_python//python/config_settings:_is_py_freethreaded_no",
    ],
    env = {"platform_version": "0"},
    os_name = "linux",
    platform = "linux_s390x",
    whl_abi_tags = ["abi3", "cp{major}{minor}"],
    whl_platform_tags = ["linux_s390x", "manylinux_*_s390x"],
)
''',m)
open(E+"/MODULE.bazel","w").write(m)
# (h) crate_universe: s390x is not in the default supported_platform_triples -> every crate is @platforms//:incompatible
m=open(E+"/MODULE.bazel").read()
m=sub(r'(crate\.from_cargo\(\n    name = "envoy_rust_crate_index",\n    cargo_lockfile = "//:Cargo.lock",\n    lockfile = "//:Cargo.Bazel.envoy.lock",\n    manifests = \["//:Cargo.toml"\],\n)',r'''\1    supported_platform_triples = [
        "aarch64-apple-darwin",
        "aarch64-unknown-linux-gnu",
        "s390x-unknown-linux-gnu",
        "wasm32-unknown-unknown",
        "wasm32-wasip1",
        "x86_64-pc-windows-msvc",
        "x86_64-unknown-linux-gnu",
        "x86_64-unknown-nixos-gnu",
    ],
''',m)
open(E+"/MODULE.bazel","w").write(m)
# (c) force wee8 source build on s390x (no s390x prebuilt)
b=open(E+"/bazel/BUILD").read()
b=sub(r'(        "//conditions:default": "@envoy_toolshed//v8:wee8",)',r'        ":linux_s390x": "@proxy-wasm-cpp-host//bazel:wee8_no_pointer_compression",\n\1',b)
open(E+"/bazel/BUILD","w").write(b)
# Lua/LuaJIT is enabled on s390x: luajit-s390x.patch adds the s390x port (interpreter) to the luajit
# bzlmod module, and source/exe/BUILD keeps the upstream default (NO_HTTP3_SKIP_TARGETS), which does
# not skip the lua extensions.
os.makedirs(E+"/bazel/s390x-patches",exist_ok=True)
open(E+"/bazel/s390x-patches/BUILD","w").write('exports_files(glob(["*.patch"]))\n')
open(E+"/user.bazelrc","w").write(f'''startup --host_jvm_args=-XX:TieredStopAtLevel=1
build --repo_env=CARGO_BAZEL_GENERATOR_URL=file:{R}/cargo-bazel
build --test_env=HEAPCHECK=
test --test_env=HEAPCHECK=
build --jobs=10
''')
print("prepared")
