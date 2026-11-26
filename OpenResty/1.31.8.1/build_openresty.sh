#!/bin/bash
# © Copyright IBM Corporation 2026.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/OpenResty/1.31.8.1/build_openresty.sh
# Execute build script: bash build_openresty.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="openresty"
PACKAGE_VERSION="1.31.8.1"
SOURCE_ROOT="$(pwd)"
FORCE="false"
TESTS="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
JOBS=3
PCRE_VER=10.47
PCRE_PREFIX=/opt/pcre2
PCRE_LIB=$PCRE_PREFIX/lib
PCRE_INC=$PCRE_PREFIX/include
OPENSSL_VER=3.5.7
OPENSSL_PATCH_VER=3.5.5
OPENSSL_PREFIX=/opt/ssl3
OPENSSL_LIB=$OPENSSL_PREFIX/lib
OPENSSL_INC=$OPENSSL_PREFIX/include
OPENRESTY_PREFIX=/opt/openresty
trap cleanup EXIT

#Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
    mkdir -p "$SOURCE_ROOT/logs/"
fi

# Set the Distro ID
source "/etc/os-release"

function prepare() {
    if command -v "sudo" >/dev/null; then
        printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
    else
        printf -- 'Sudo : No \n' >>"$LOG_FILE"
        printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n'
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

function cleanup() {
    # Remove artifacts
    rm -f "$SOURCE_ROOT/openresty/download-cache/openssl-${OPENSSL_VER}.tar.gz"
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started\n"

    # Clone OpenResty repository
    cd "$SOURCE_ROOT"
    git clone -b "v${PACKAGE_VERSION}" https://github.com/openresty/openresty.git

    cd "$SOURCE_ROOT/openresty"
    mkdir -p download-cache

    # Install PCRE2 with JIT support
    wget -P download-cache \
        "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${PCRE_VER}/pcre2-${PCRE_VER}.tar.gz"

    tar -xzf "download-cache/pcre2-${PCRE_VER}.tar.gz"
    cd "pcre2-${PCRE_VER}"

    ./configure --prefix="$PCRE_PREFIX" \
        --enable-jit \
        --enable-utf \
        --enable-unicode-properties

    make -j"$JOBS"
    sudo env PATH="$PATH" make install

    # Download OpenResty source code
    cd "$SOURCE_ROOT/openresty"

    wget https://openresty.org/download/openresty-${PACKAGE_VERSION}.tar.gz
    tar -xvf "openresty-${PACKAGE_VERSION}.tar.gz"

    # Build OpenSSL
    cd "$SOURCE_ROOT/openresty"

    wget -P download-cache \
        "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VER}/openssl-${OPENSSL_VER}.tar.gz"

    tar -zxf "download-cache/openssl-${OPENSSL_VER}.tar.gz"

    cd "openssl-${OPENSSL_VER}"

    patch -p1 < "$SOURCE_ROOT/openresty/patches/openssl-${OPENSSL_PATCH_VER}-sess_set_get_cb_yield.patch"

    ./config no-threads shared enable-ssl3 enable-ssl3-method \
        -g --libdir=lib --prefix="$OPENSSL_PREFIX" -DPURIFY

    make -j"$JOBS"
    sudo env PATH="$PATH" make install_sw

    # Clone test-nginx
    cd "$SOURCE_ROOT/openresty"

    rm -rf test-nginx
    git clone --depth 1 https://github.com/openresty/test-nginx.git

    # Build and install OpenResty
    cd "$SOURCE_ROOT/openresty"

    util/mirror-tarballs

    cd "$SOURCE_ROOT/openresty/openresty-$(./util/ver)"

    if [[ "${ID}" == "sles" ]]; then
        export PATH="$PATH:/sbin"
    fi

    ./configure \
        --with-http_v3_module \
        --with-stream_realip_module \
        --with-http_realip_module \
        --prefix="$OPENRESTY_PREFIX" \
        --with-cc-opt="-I$PCRE_INC -I$OPENSSL_INC" \
        --with-ld-opt="-L$PCRE_LIB -L$OPENSSL_LIB -Wl,-rpath,$PCRE_LIB:$OPENSSL_LIB" \
        --with-pcre-jit \
        --with-http_ssl_module \
        --with-debug \
        "-j$JOBS"

    make -j"$JOBS"
    sudo make install

    # Set environment variables
    export PATH="$OPENRESTY_PREFIX/bin:$OPENRESTY_PREFIX/nginx/sbin:$PATH"

    # Verify installation
    nginx -V
    ldd "$(command -v nginx)" | grep -E 'luajit|ssl|pcre'

    # Run tests
    runTest

    printf -- "\n* OpenResty successfully installed *\n"
}

function runTest() {
    if [[ "$TESTS" == "true" ]]; then
        printf -- "TEST flag is set. Running OpenResty tests\n"

        # Install CPAN modules
        sudo cpanm --notest Test2::Suite Test::Nginx IPC::Run3 IPC::Run

        # Run test cases
        cd "$SOURCE_ROOT/openresty"

        nginx -V
        ldd "$(command -v nginx)" | grep -E 'luajit|ssl|pcre'

        prove -Itest-nginx/inc -Itest-nginx/lib -I. -r t/

        printf -- "\nTests completed\n"
    fi
    set -e
}
function logDetails() {
    printf -- '**************************** SYSTEM DETAILS *************************************************************\n' >>"$LOG_FILE"
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
    echo "bash build_openresty.sh  [-d debug] [-y install-without-confirmation] [-t install-with-test]"
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
    printf -- "*                     Getting Started                 * \n"
    printf -- "         You have successfully installed OpenResty. \n"
    printf -- "         To Run OpenResty run the following commands :\n"
    printf -- "         export PATH=/opt/openresty/bin:/opt/openresty/nginx/sbin:\$PATH \n"
    printf -- "         resty -V \n"
    printf -- "         resty -e 'print(\"hello, world\")' \n"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"rhel-8.10" | "rhel-9.6" | "rhel-9.8")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y openssl-devel curl tar wget make gcc dos2unix perl patch pcre-devel zlib-devel perl-App-cpanminus git iproute |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-10.0" | "rhel-10.2")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y openssl-devel openssl procps-ng curl tar wget make gcc dos2unix perl patch pcre2-devel zlib-devel perl-App-cpanminus git iproute |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-15.7" | "sles-16.0")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y binutils coreutils curl diffutils dos2unix findutils gawk gcc git gzip iproute2 make openssl openssl-devel procps patch pcre-devel perl perl-App-cpanminus tar wget which zlib-devel |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"ubuntu-22.04" | "ubuntu-24.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends axel build-essential ca-certificates cpanminus dos2unix git libgd-dev libpcre3 libpcre3-dev libpcre2-dev libpq-dev libssl-dev mercurial patch perl wget curl tar zlib1g-dev iproute2 |& tee -a "$LOG_FILE"
    if [ ! -f "/usr/bin/gmake" ]; then
        sudo ln -s /usr/bin/make /usr/bin/gmake
    fi
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
