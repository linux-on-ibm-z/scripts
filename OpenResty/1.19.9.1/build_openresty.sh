#!/bin/bash
# © Copyright IBM Corporation 2021.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/OpenResty/1.19.9.1/build_openresty.sh
# Execute build script: bash build_openresty.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="openresty"
PACKAGE_VERSION="1.19.9.1"
SOURCE_ROOT="$(pwd)"

FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/OpenResty/1.19.9.1/patch"
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
    rm -rf "$SOURCE_ROOT/openresty-${PACKAGE_VERSION}.tar.gz"
    rm -rf "$SOURCE_ROOT/openresty-${PACKAGE_VERSION}/t/Config.pm.diff"
    if [[ "$VERSION_ID" == "7.8" || "$VERSION_ID" == "7.9" || "$VERSION_ID" == "12.5" ]]; then
    	rm -rf $SOURCE_ROOT/openresty-${PACKAGE_VERSION}/configure.diff
    fi
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

    #Download Source code
    export PATH=$PATH:/sbin
    cd $SOURCE_ROOT
    wget https://openresty.org/download/openresty-${PACKAGE_VERSION}.tar.gz
    tar -xvf openresty-${PACKAGE_VERSION}.tar.gz
    # Replace source luajit2 with latest luajit2
    rm -rf $SOURCE_ROOT/openresty-${PACKAGE_VERSION}/bundle/LuaJIT-2.1-20210510
    mkdir $SOURCE_ROOT/openresty-${PACKAGE_VERSION}/bundle/LuaJIT-2.1-20210510
    wget https://github.com/openresty/luajit2/archive/refs/tags/v2.1-20211210.tar.gz
    tar -xvzf v2.1-20211210.tar.gz
    mv luajit2-2.1-20211210/* openresty-${PACKAGE_VERSION}/bundle/LuaJIT-2.1-20210510/

    # Apply configure file patch for older GCC
    cd $SOURCE_ROOT/openresty-${PACKAGE_VERSION}
    if [[ "$VERSION_ID" == "7.8" || "$VERSION_ID" == "7.9" || "$VERSION_ID" == "12.5" ]]; then
	curl -o "configure.diff" $PATCH_URL/configure.diff
        patch -l $SOURCE_ROOT/openresty-${PACKAGE_VERSION}/configure configure.diff
    fi
    
    #Build and install OpenResty
    cd $SOURCE_ROOT/openresty-${PACKAGE_VERSION}
    ./configure --with-pcre-jit \
                --with-ipv6 \
                --without-http_redis2_module \
                --with-http_iconv_module \
                --with-http_postgres_module
    make -j2
    sudo make install

    #Set Environment Variable
    export PATH=/usr/local/openresty/bin:$PATH
    sudo cp -r /usr/local/openresty/ /usr/local/bin

    #Run Tests
    runTest

    printf -- "\n* OpenResty successfully installed *\n"
}

function runTest() {
    set +e
    if [[ "$TESTS" == "true" ]]; then
        printf -- "TEST Flag is set, continue with running test \n"  >> "$LOG_FILE"

        export PATH=/usr/local/openresty/nginx/sbin:/usr/local/openresty/bin:$PATH
        export PATH=$PATH:/sbin

        #Install cpan modules
        sudo PERL_MM_USE_DEFAULT=1 cpan Cwd IPC::Run3 Test::Base Test::Nginx
        cd $SOURCE_ROOT/openresty-${PACKAGE_VERSION}
        #Download files and modify to run sanity tests
	mkdir t && cd t
        wget https://raw.githubusercontent.com/openresty/openresty/v${PACKAGE_VERSION}/t/Config.pm
        wget https://raw.githubusercontent.com/openresty/openresty/v${PACKAGE_VERSION}/t/000-sanity.t
    
        curl -o "Config.pm.diff"  $PATCH_URL/Config.pm.diff
        patch -l $SOURCE_ROOT/openresty-1.19.9.1/t/Config.pm Config.pm.diff
	printf -- "Updated openresty-${PACKAGE_VERSION}/t/Config.pm \n"
	
	cd $SOURCE_ROOT/openresty-${PACKAGE_VERSION}
        #Revert configure file patch for older GCC
        if [[ "$VERSION_ID" == "7.8" || "$VERSION_ID" == "7.9" || "$VERSION_ID" == "12.5" ]]; then
            patch -l -R $SOURCE_ROOT/openresty-${PACKAGE_VERSION}/configure configure.diff
        fi
	
        prove -r t |& tee -a "$LOG_FILE"
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
"ubuntu-18.04" | "ubuntu-20.04" | "ubuntu-21.04" | "ubuntu-21.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y curl tar wget make gcc build-essential dos2unix patch libpcre3-dev libpq-dev openssl libssl-dev perl zlib1g-dev |& tee -a "$LOG_FILE"
    sudo ln -sf make /usr/bin/gmake
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-7.8" | "rhel-7.9" | "rhel-8.2" | "rhel-8.4" | "rhel-8.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y curl tar wget make gcc dos2unix cpan perl postgresql-devel patch pcre-devel openssl-devel |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;	
"sles-12.5" | "sles-15.2" | "sles-15.3")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y curl tar wget make gcc dos2unix perl postgresql10-devel patch pcre-devel openssl libopenssl-devel gzip |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
