#!/bin/bash
# © Copyright IBM Corporation 2024.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/OpenResty/1.27.1.1/build_openresty.sh
# Execute build script: bash build_openresty.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="openresty"
PACKAGE_VERSION="1.27.1.1"
SOURCE_ROOT="$(pwd)"
FORCE="false"
TESTS="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
OPENSSL_PREFIX=/usr/local
OPENSSL_INC=$OPENSSL_PREFIX/include
OPENSSL_LIB=$OPENSSL_PREFIX/lib
OPENRESTY_PREFIX=/usr/local/openresty
trap cleanup 0 1 2 ERR

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
    rm -rf "$SOURCE_ROOT/openssl-${OPENSSL_VER}.tar.gz"
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

    # Clone Openresty repo
    cd $SOURCE_ROOT
    git clone -b v${PACKAGE_VERSION} https://github.com/openresty/openresty.git

    # Download openresty Source code
    cd $SOURCE_ROOT/openresty
    wget --no-check-certificate https://openresty.org/download/openresty-${PACKAGE_VERSION}.tar.gz
    tar xvf openresty-${PACKAGE_VERSION}.tar.gz
    # Build and install OpenResty
    cd openresty-${PACKAGE_VERSION}
    if [[ "${ID}" == "sles" ]]; then
        export PATH=$PATH:/sbin
    fi
    ./configure --prefix=$OPENRESTY_PREFIX \
                --with-cc-opt="-I$OPENSSL_INC" \
                --with-ld-opt="-L$OPENSSL_LIB -Wl,-rpath,$OPENSSL_LIB" \
                --with-http_ssl_module \
                --with-http_iconv_module \
                --with-debug \
                -j$(nproc)
    make -j$(nproc)
    sudo make install

    # Set Environment Variable
    export PATH=$OPENRESTY_PREFIX/bin:$OPENRESTY_PREFIX/nginx/sbin:$PATH

    # Verify the installation
    nginx -V
    ldd `which nginx`|grep -E 'luajit|ssl|pcre'

    # Run Tests
    runTest

    printf -- "\n* OpenResty successfully installed *\n"
}

function runTest() {
    set +e
    if [[ "$TESTS" == "true" ]]; then
        printf -- "TEST Flag is set, continue with running test \n"
        # Install cpan modules
        sudo cpanm --notest Test::Nginx IPC::Run3
        # The test expects different module versions than those being installed by the Makefile.
        cd $SOURCE_ROOT/openresty/t/; sed -i 's/lua-resty-lrucache-0.14/lua-resty-lrucache-0.15/g' 000-sanity.t
        cd $SOURCE_ROOT/openresty/t/; sed -i 's/lua-resty-core-0.1.29/lua-resty-core-0.1.30/g' 000-sanity.t
        
        # Run test cases
        cd $SOURCE_ROOT/openresty
        printf -- "Start running tests for openresty \n"
        prove -I. -r t/
        printf -- "Tests completed \n"
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
    printf -- "         export PATH=/usr/local/openresty/nginx/sbin:/usr/local/openresty/bin:\$PATH \n"
    printf -- "         resty -V \n"
    printf -- "         resty -e 'print(\"hello, world\")' \n"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"ubuntu-20.04" | "ubuntu-22.04" | "ubuntu-24.04" | "ubuntu-24.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y openssl libssl-dev git curl tar wget make gcc build-essential dos2unix patch libpcre3-dev libpq-dev perl cpanminus zlib1g-dev |& tee -a "$LOG_FILE"
    if [ ! -f "/usr/bin/gmake" ]; then
        sudo ln -s /usr/bin/make /usr/bin/gmake
    fi
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-8.8" | "rhel-8.10" | "rhel-9.2" | "rhel-9.4")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y openssl-devel curl tar wget make gcc dos2unix perl patch pcre-devel zlib-devel perl-App-cpanminus git |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-15.5" | "sles-15.6")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y openssl-devel git curl tar wget make gcc dos2unix perl patch pcre-devel gzip zlib-devel perl-App-cpanminus |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
