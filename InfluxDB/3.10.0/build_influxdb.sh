#!/usr/bin/env bash
# © Copyright IBM Corporation 2026.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/InfluxDB/3.10.0/build_influxdb.sh
# Execute build script: bash build_influxdb.sh    (provide -h for help)

set -e -o pipefail

SOURCE_ROOT="$(pwd)"
PACKAGE_NAME="InfluxDB"
PACKAGE_VERSION="3.10.0"
FORCE="false"
TEST="false"
OVERRIDE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/InfluxDB/${PACKAGE_VERSION}/patch"

#Check if directory exsists
if [ ! -d "$SOURCE_ROOT/logs" ]; then
        mkdir -p "$SOURCE_ROOT/logs"
fi

source "/etc/os-release"
trap cleanup 0 1 2 ERR

function cleanup() {
    printf -- '\nCleaned up the artifacts\n'
    sudo rm -rf "$SOURCE_ROOT/wasi-sdk"  "$SOURCE_ROOT/tombi"
}

function checkPrequisites() {
        printf -- "Checking Prequisites\n"

        if command -v "sudo" >/dev/null; then
                printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
        else
                printf -- 'Sudo : No \n' >>"$LOG_FILE"
                printf -- 'You can install sudo from repository using apt, yum or zypper based on your distro. \n'
                exit 1
        fi
        if [[ "$FORCE" == "true" ]]; then
                printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
        else
                # Ask user for prerequisite installation
                printf -- "\nAs part of the installation , dependencies would be installed/upgraded.\n"
                while true; do
                        read -r -p "Do you want to continue (y/n) ? :  " yn
                        case $yn in
                        [Yy]*)
                                printf -- 'User responded with Yes. \n' >>"$LOG_FILE"
                                break
                                ;;
                        [Nn]*) exit ;;
                        *) echo "Please provide confirmation to proceed." ;;
                        esac
                done
        fi
}

function installCMakeFromSource() {
    if [[ $(cmake --version | head -n 1 | awk '{print $3}') < "3.28.0" ]]; then
        sudo apt-get remove --purge -y cmake || true
        sudo yum remove -y cmake || true

        printf -- '\nInstalling CMake (3.28.3) from source...\n'
        cd $SOURCE_ROOT
        wget -q https://cmake.org/files/v3.28/cmake-3.28.3.tar.gz
        tar -xf cmake-3.28.3.tar.gz
        cd cmake-3.28.3
        ./bootstrap
        make -j"$(nproc)"
        sudo make install
        hash -r
        cmake --version
        rm $SOURCE_ROOT/cmake-3.28.3.tar.gz
        printf -- '\nCMake 3.28.3 installed successfully.\n'
    fi
}

function configureAndInstall() {
    printf -- 'Configuration and Installation started \n'

    # Install Rust
    printf -- 'Installing rust...\n'
    cd $SOURCE_ROOT
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source $HOME/.cargo/env
    cargo install cargo-nextest --locked

    # Setup arrow-rs
    cd $SOURCE_ROOT
    git clone -b 57.3.0 --depth 1 https://github.com/apache/arrow-rs.git
    cd arrow-rs
    curl -sSL ${PATCH_URL}/arrow.patch | git apply || error "arrow.patch"

    export IOX_QUERY_UDF_PYTHON_WASM="$SOURCE_ROOT/datafusion-udf-wasm/out/datafusion_udf_wasm_python.release.s390x-unknown-linux-gnu.elf"

    if [ ! -f "$IOX_QUERY_UDF_PYTHON_WASM" ]; then
        printf -- 'Building datafusion_udf_wasm_python.release.s390x-unknown-linux-gnu.elf...\n'

        # Build wasi-sdk (needed by datafusion_udf_wasm_python.wasm)
        cd $SOURCE_ROOT
        git clone --recursive -b wasi-sdk-24 --depth 1 https://github.com/webassembly/wasi-sdk
        cd wasi-sdk
        sed -i '22i #include <cstdint>' src/llvm-project/llvm/include/llvm/ADT/SmallVector.h

        #build toolchain
        cmake -G Ninja -B build/toolchain -S . \
            -DWASI_SDK_BUILD_TOOLCHAIN=ON \
            -DCMAKE_INSTALL_PREFIX=build/install
        cmake --build build/toolchain --target install
        cmake --build build/toolchain --target dist
        #build sysroot
        cmake -G Ninja -B build/sysroot -S . \
            -DCMAKE_INSTALL_PREFIX=build/install \
            -DCMAKE_TOOLCHAIN_FILE=build/install/share/cmake/wasi-sdk.cmake \
            -DCMAKE_C_COMPILER_WORKS=ON \
            -DCMAKE_CXX_COMPILER_WORKS=ON
        cmake --build build/sysroot --target install
        cmake --build build/sysroot --target dist
        mkdir dist-my-platform
        cp build/toolchain/dist/* build/sysroot/dist/* dist-my-platform
        ./ci/merge-artifacts.sh

        # Build datafusion_udf_wasm_python.wasm
        #pre-req
        cd $SOURCE_ROOT
        rustup target add wasm32-wasip2
        cargo install --locked cargo-deny
        cargo install --locked just
        curl -LsSf https://astral.sh/uv/0.9.30/install.sh | sh
        if [ -f "$HOME/.local/bin/env" ]; then
            source $HOME/.local/bin/env
        fi

        cd $SOURCE_ROOT
        git clone https://github.com/tombi-toml/tombi.git
        cd tombi
        cargo build --release
        uvx tombi --version

        cargo install --locked typos-cli
        cargo install --locked wasm-tools

        cd $SOURCE_ROOT
        git clone https://github.com/influxdata/datafusion-udf-wasm
        cd datafusion-udf-wasm
        git checkout -b for-influxdb 89ab4ae6312c3a44859ddd43d9df4d4300d3086a
        export WASI_SDK_LOCAL_TARBALL="$SOURCE_ROOT/wasi-sdk/build/sysroot/dist/wasi-sysroot-24.0.tar.gz"

        #build the wasm
        just guests::python::build-release

        # Compile Python guest to s390x ELF
        mkdir -p out
        cargo run --bin=compile --features="all-arch" --release -- \
        target/wasm32-wasip2/release/datafusion_udf_wasm_python.wasm \
        out/datafusion_udf_wasm_python.release.s390x-unknown-linux-gnu.elf \
        s390x-unknown-linux-gnu
    fi
    # Download and configure InfluxDB
    printf -- 'Downloading InfluxDB. Please wait.\n'
    cd $SOURCE_ROOT
    git clone --depth 1 -b v${PACKAGE_VERSION} https://github.com/influxdata/influxdb.git
    cd influxdb
    curl -sSL ${PATCH_URL}/influxdb.patch | git apply || error "influxdb.patch"
    sed -i "s|SOURCE_ROOT|$SOURCE_ROOT|g" Cargo.toml
    sed -i "s|SOURCE_ROOT|$SOURCE_ROOT|g" core/iox_query_udf/build.rs

    #Build InfluxDB
    printf -- 'Building InfluxDB \n'
    printf -- 'Build might take some time. Sit back and relax\n'
    cargo build --profile release
    sudo cp ./target/release/influxdb3 /usr/bin
    printf -- 'Successfully installed InfluxDB. \n'

    #Run Test
    runTests
}

function runTests() {
        set +e
        if [[ "$TESTS" == "true" ]]; then
                printf -- "TEST Flag is set, continue with running test \n"  >> "$LOG_FILE"

                cd ${SOURCE_ROOT}/influxdb
                cargo nextest run --workspace --nocapture --no-fail-fast
        fi
        set -e
}

function logDetails() {
        printf -- '**************************** SYSTEM DETAILS *************************************************************\n' >"$LOG_FILE"

        if [ -f "/etc/os-release" ]; then
                cat "/etc/os-release" >>"$LOG_FILE"
        fi

        cat /proc/version >>"$LOG_FILE"
        printf -- '*********************************************************************************************************\n' >>"$LOG_FILE"

        printf -- "Detected %s \n" "$PRETTY_NAME"
        printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" |& tee -a "$LOG_FILE"

}

# Print the usage message
function printHelp() {
        echo
        echo "Usage: "
        echo "  bash build_influxdb.sh [-y install-without-confirmation -t run-test-cases]"
        echo
}

while getopts "h?dyt" opt; do
        case "$opt" in
        h | \?)
                printHelp
                exit 0
                ;;
        d)
                set -x
                ;;
        y)
                FORCE="true"
                ;;
        t)
                TESTS="true"
                ;;

        esac
done

function gettingStarted() {
    printf -- '\n********************************************************************************************************\n'
    printf -- "\n* Getting Started * \n"
    printf -- "\nInfluxDB binary has been installed at /usr/bin/influxdb3\n"
    printf -- "\nMore information can be found here: https://docs.influxdata.com/influxdb3/core/get-started\n"
    printf -- '\n\n**********************************************************************************************************\n'
}

###############################################################################################################

logDetails
DISTRO="$ID-$VERSION_ID"
checkPrequisites #Check Prequisites

case "$DISTRO" in
"rhel-8.10")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
        sudo yum install -y clang git wget curl patch pkg-config python3.12 python3.12-devel python3.12-pip unzip cmake lld ninja-build |& tee -a "$LOG_FILE"
        sudo yum install -y gcc-toolset-11 gcc-toolset-11-gcc gcc-toolset-11-gcc-c++ gcc-toolset-11-libatomic-devel gcc-toolset-11-libstdc++-devel |& tee -a "$LOG_FILE"
        source /opt/rh/gcc-toolset-11/enable |& tee -a "$LOG_FILE"
        wget https://github.com/protocolbuffers/protobuf/releases/download/v32.0/protoc-32.0-linux-s390_64.zip
        sudo unzip -q protoc-32.0-linux-s390_64.zip -d /usr/local/
        export PROTOC=/usr/local/bin/protoc
        rm protoc-32.0-linux-s390_64.zip
        protoc --version | tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

"rhel-9.6" | "rhel-9.7" | "rhel-9.8" | "rhel-10.0" | "rhel-10.1" | "rhel-10.2")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
        sudo yum install -y clang git wget protobuf protobuf-devel curl patch pkg-config python3 python3-devel cmake diffutils lld ninja-build unzip |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

"sles-15.7" | "sles-16.0")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
        sudo zypper install -y git wget which protobuf-devel curl patch pkg-config clang gawk make gcc gcc-c++ cmake diffutils lld19 ninja unzip |& tee -a "$LOG_FILE"

        if [[ $DISTRO == "sles-16.0" ]]; then
            sudo zypper install -y python3 python3-devel python3-pip |& tee -a "$LOG_FILE"
        else
            sudo zypper install -y python311 python311-devel python311-pip libexpat1 |& tee -a "$LOG_FILE"
            sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 60 |& tee -a "$LOG_FILE"
            sudo zypper install -y gcc15 gcc15-c++ |& tee -a "$LOG_FILE"
            sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-15 60 |& tee -a "$LOG_FILE"
            sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-15 60 |& tee -a "$LOG_FILE"
            sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-15 60 |& tee -a "$LOG_FILE"
        fi
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

"ubuntu-22.04")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
        sudo apt-get update >/dev/null
        sudo apt-get install -y build-essential pkg-config libssl-dev curl git protobuf-compiler python3 python3-dev python3-pip python3-venv libprotobuf-dev ninja-build unzip |& tee -a "$LOG_FILE"

        sudo apt install -y lsb-release wget software-properties-common gnupg |& tee -a "$LOG_FILE"
        wget https://apt.llvm.org/llvm.sh |& tee -a "$LOG_FILE"
        chmod +x llvm.sh |& tee -a "$LOG_FILE"
        sudo ./llvm.sh 18 |& tee -a "$LOG_FILE"
        sudo apt install -y lld-18 |& tee -a "$LOG_FILE"
        sudo update-alternatives --install /usr/bin/clang clang /usr/bin/clang-18 100 \
            --slave /usr/bin/clang++ clang++ /usr/bin/clang++-18 |& tee -a "$LOG_FILE"
        sudo rm -f /usr/bin/lld |& tee -a "$LOG_FILE"
        sudo ln -sf /usr/bin/lld-18 /usr/bin/lld |& tee -a "$LOG_FILE"
        sudo ln -sf /usr/bin/ld.lld-18 /usr/bin/ld.lld |& tee -a "$LOG_FILE"
        installCMakeFromSource |& tee -a "$LOG_FILE"

        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

"ubuntu-24.04")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
        sudo apt-get update >/dev/null
        sudo apt-get install -y build-essential pkg-config libssl-dev clang curl git protobuf-compiler python3 python3-dev python3-pip python3-venv libprotobuf-dev cmake lld ninja-build unzip |& tee -a "$LOG_FILE"

        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

*)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
        exit 1
        ;;
esac

gettingStarted |& tee -a "$LOG_FILE"

