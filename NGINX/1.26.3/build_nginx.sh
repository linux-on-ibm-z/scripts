#!/bin/bash
# © Copyright IBM Corporation 2025.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/NGINX/1.26.3/build_nginx.sh
# Execute build script: bash build_nginx.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="nginx"
PACKAGE_VERSION="1.26.3"
SOURCE_ROOT="$(pwd)"

FORCE="false"
TESTS="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
    mkdir -p "$SOURCE_ROOT/logs/"
fi

source "/etc/os-release"

function prepare() {
    if command -v "sudo" >/dev/null; then
        printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
    else
        printf -- 'Sudo : No \n' >>"$LOG_FILE"
        printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n'
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

    if [ -f "$SOURCE_ROOT/nginx-${PACKAGE_VERSION}.tar.gz" ]; then
        rm -rf "$SOURCE_ROOT/nginx-${PACKAGE_VERSION}.tar.gz"
    fi

    rm -rf $SOURCE_ROOT/nginx-tests

    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

  # Download nginx
    cd "$SOURCE_ROOT"
    wget http://nginx.org/download/nginx-${PACKAGE_VERSION}.tar.gz
    tar xvf nginx-${PACKAGE_VERSION}.tar.gz
    cd nginx-${PACKAGE_VERSION}
    ./configure
    make
    sudo make install

    printf -- "Build nginx success\n\n"

    # Add binary to /usr/sbin
    sudo cp  /usr/local/nginx/sbin/nginx /usr/sbin/

    printf -- "Installation nginx success\n\n"

    # Run Tests
    runTest

    # Cleanup
    cleanup

    # Verify nginx installation
    if command -v "/usr/sbin/nginx" >/dev/null; then
        printf -- " %s Installation verified.\n" "$PACKAGE_NAME"
    else
        printf -- "Error while installing %s, exiting with 127 \n" "$PACKAGE_NAME"
        exit 127
    fi
}

function runTest() {
    set +e
    if [[ "$TESTS" == "true" ]]; then
        printf -- "TEST Flag is set , Continue with running test \n"
        cd $SOURCE_ROOT
        git clone https://github.com/nginx/nginx-tests.git
        cd nginx-tests
        TEST_NGINX_BINARY=$SOURCE_ROOT/nginx-1.26.3/objs/nginx prove .
        printf -- "Tests completed. \n"
    fi
    set -e
}

function logDetails() {
    printf -- '**************************** SYSTEM DETAILS *************************************************************\n' >"$LOG_FILE"
    if [ -f "/etc/os-release" ]; then
        cat "/etc/os-release" >>"$LOG_FILE"
    else
        cat /etc/redhat-release >>"${LOG_FILE}"
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
    echo "  bash build_nginx.sh  [-d debug] [-y install-without-confirmation]  [-t install-with-tests]"
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
    printf -- "\n*Getting Started * \n"
    printf -- "Note: for suse, run command .\n"
    printf -- 'export PATH=$PATH:/usr/sbin \n'
    printf -- "Running nginx: \n"
    printf -- "nginx -c nginx.conf \n\n"
    printf -- "Note that this will normally need to be done as root, NGINX will not have authority to access one or more ports, such as 80 and 8080.\n"
    printf -- "You have successfully started nginx.\n"
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
    sudo apt-get install -y curl wget tar gcc make libpcre3-dev openssl libssl-dev zlib1g zlib1g-dev |& tee -a "$LOG_FILE"
    if [[ "$TESTS" == "true" ]]; then
        sudo apt-get install -y libedit-dev libgd-dev libgeoip-dev libpcre2-dev libperl-dev libssl-dev libxml2-dev libxslt1-dev zlib1g-dev ffmpeg libcache-memcached-perl libcryptx-perl libgd-perl libio-socket-ssl-perl libtest-harness-perl libprotocol-websocket-perl libhttp-request-ascgi-perl uwsgi uwsgi-plugin-python3 |& tee -a "$LOG_FILE"
        if [[ $DISTRO != "ubuntu-20.04" ]]; then
            sudo apt-get install -y libscgi-perl |& tee -a "$LOG_FILE"
        fi
    fi

    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-8.8" | "rhel-8.10" | "rhel-9.2" | "rhel-9.4" | "rhel-9.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y pcre-devel wget tar xz gcc make zlib-devel diffutils |& tee -a "$LOG_FILE"
    if [[ "$TESTS" == "true" ]]; then
        sudo yum install -y libedit-devel gd-devel pcre2-devel perl perl-devel openssl-devel libxml2-devel libxslt-devel perl-Cache-Memcached perl-CryptX perl-GD perl-IO-Socket-SSL perl-Test-Harness perl-HTTP-Request-AsCGI perl-FCGI uwsgi uwsgi-plugin-python3 |& tee -a "$LOG_FILE"
        if [[ $DISTRO = "rhel-9."* ]]; then
            sudo yum install -y ffmpeg-free |& tee -a "$LOG_FILE"
        fi
    fi
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-15.6")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y pcre-devel curl wget tar xz gcc make zlib-devel diffutils gzip |& tee -a "$LOG_FILE"
    if [[ "$TESTS" == "true" ]]; then
        sudo zypper install -y libedit-devel gd-devel libGeoIP-devel pcre2-devel libopenssl-devel libxml2-devel libxslt-devel ffmpeg perl-Cache-Memcached perl-CryptX perl-GD perl-IO-Socket-SSL perl-Test-Harness perl-Protocol-WebSocket perl-HTTP-Request-AsCGI perl-FCGI uwsgi uwsgi-python3 |& tee -a "$LOG_FILE"
    fi
    export PATH=$PATH:/usr/sbin # for uwsgi
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
