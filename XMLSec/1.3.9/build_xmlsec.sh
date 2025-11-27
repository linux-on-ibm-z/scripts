#!/bin/bash
# © Copyright IBM Corporation 2024,2025
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/XMLSec/1.3.9/build_xmlsec.sh
# Execute build script: bash build_xmlsec.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="xmlsec"
PACKAGE_VERSION="xmlsec_1_3_9"
AUTOMAKE_PACKAGE_VERSION="1.16.5"
LIBXML2_PACKAGE_VERSION="2.10.4"
SOURCE_ROOT="$(pwd)"

FORCE="false"
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
	cd $SOURCE_ROOT
	rm -rf  openssl-1.1.1h.tar.gz 
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}
function configureAndInstall() {
    printf -- "Configuration and Installation started \n"
  
    #Download the XMLSec source code from Github
    cd $SOURCE_ROOT
    export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
    git clone https://github.com/lsh123/xmlsec.git
    cd xmlsec
    git checkout $PACKAGE_VERSION

    #Configure, build and install XMLSec
    if [[ "$DISTRO" == "ubuntu-22.04" || "$DISTRO" == "ubuntu-24.04" || "$DISTRO" == "ubuntu-25.04" ]]; then
        ./autogen.sh
    else
        ./autogen.sh --without-gcrypt --with-openssl 
    fi
    sed -i '697s/xmlSecOpenSSLKeyValueRsaCheckKeyType(pKey)/xmlSecOpenSSLKeyValueRsaCheckKeyType(ctx->pKey)/' src/openssl/kt_rsa.c
    make
    sudo make install
    
    printf -- "XMLSec build completed successfully. \n"
	
  # Run Tests
    runTest 

  # Cleanup
    cleanup
}
function installAutomake(){
    cd $SOURCE_ROOT
    git clone https://github.com/autotools-mirror/automake.git
    cd automake
    git checkout v$AUTOMAKE_PACKAGE_VERSION
    ./bootstrap
    ./configure
    make
    sudo make install
    automake --version
}
function installLibxml2(){
    cd $SOURCE_ROOT
    git clone https://github.com/GNOME/libxml2.git
    cd libxml2
    git checkout v$LIBXML2_PACKAGE_VERSION
    ./autogen.sh
    make
    sudo make install 
    xml2-config --version
}
function installOpenssl(){
    cd $SOURCE_ROOT
    wget https://www.openssl.org/source/openssl-1.1.1h.tar.gz --no-check-certificate
    tar -xzvf openssl-1.1.1h.tar.gz
    cd openssl-1.1.1h
    ./config --prefix=/usr/local --openssldir=/usr/local
    make
    sudo make install
}
function runTest() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- "TEST Flag is set, continue with running test \n"  >> "$LOG_FILE"
        make check
        printf -- "Tests completed. \n" 
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
    echo "bash build_xmlsec.sh  [-d debug] [-y install-without-confirmation] [-t install and run tests]"
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
    printf -- "                                       Getting Started                                       \n"
    printf -- "          To check XMLSec is successfully installed, execute below command        \n"
    printf -- "          xmlsec1 --version or xmlsec1-config --version                                      \n"
    printf -- " \n"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"rhel-8.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y git make libtool libxslt-devel libtool-ltdl-devel diffutils openssl-devel wget tar texinfo gettext python2-devel |& tee -a "$LOG_FILE"
    export ACLOCAL_PATH=/usr/share/aclocal
    export PKG_CONFIG_PATH=/usr/lib64/pkgconfig
    installAutomake |& tee -a "$LOG_FILE"
    installLibxml2 |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    	;;
"rhel-9.4" | "rhel-9.6" | "rhel-10.0")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y git make libtool libxslt-devel libtool-ltdl-devel diffutils tar wget perl-CPAN |& tee -a "$LOG_FILE"
    installOpenssl |& tee -a "$LOG_FILE"
    export LDFLAGS="-L/usr/local/lib/ -L/usr/local/lib64/"
    export LD_LIBRARY_PATH=/usr/local/lib/:/usr/local/lib64/:/usr/lib/:/usr/lib64/${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
    export CPPFLAGS="-I/usr/local/include/ -I/usr/local/include/openssl" 
    configureAndInstall |& tee -a "$LOG_FILE"
    	;;
"sles-15.6" | "sles-15.7")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y git-core gcc make libtool libxslt-devel libopenssl-devel gawk libxmlsec1-openssl1 |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    export PATH=/usr/local/bin:$PATH
    export LD_LIBRARY_PATH=/usr/local/lib
    	;;
"ubuntu-22.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y git make libtool libxslt1-dev autoconf libssl-dev libtool-bin pkg-config libxmlsec1-openssl |& tee -a "$LOG_FILE"
    installOpenssl |& tee -a "$LOG_FILE"
    export LDFLAGS="-L/usr/local/lib/ -L/usr/local/lib64/"
    export LD_LIBRARY_PATH=/usr/local/lib/:/usr/local/lib64/:/usr/lib/:/usr/lib64/${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
    export CPPFLAGS="-I/usr/local/include/ -I/usr/local/include/openssl" 
    configureAndInstall |& tee -a "$LOG_FILE"
	;;
"ubuntu-24.04" | "ubuntu-25.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y git make libtool libxslt1-dev autoconf libssl-dev libtool-bin pkg-config libxmlsec1-openssl |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
	;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
