#!/bin/bash
# © Copyright IBM Corporation 2026.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Doxygen/1.16.1/build_doxygen.sh
# Execute build script: bash build_doxygen.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="doxygen"
PACKAGE_VERSION="1.16.1"
GITHUB_PACKAGE_VERSION="1_16_1"
SOURCE_ROOT="$(pwd)"
TESTS="false"
FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
    mkdir -p "$SOURCE_ROOT/logs/"
fi

# Need handling for os-release file
if [ -f "/etc/os-release" ]; then
    source "/etc/os-release"
else
  printf -- '/etc/os-release file does not exist.' >>"$LOG_FILE"
fi

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
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function installFlex() {
    wget https://github.com/westes/flex/releases/download/v2.6.4/flex-2.6.4.tar.gz
    tar xf flex-2.6.4.tar.gz
    cd flex-2.6.4
    ./configure --prefix=/usr/
    make -j$(nproc)
    sudo make install
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

    #  Download source code
    cd $SOURCE_ROOT
    git clone -b Release_${GITHUB_PACKAGE_VERSION} https://github.com/doxygen/doxygen.git

    # Create a build directory
    cd $SOURCE_ROOT/doxygen
    mkdir build

    # Build and install
    cd $SOURCE_ROOT/doxygen/build
    cmake -G "Unix Makefiles" -Dbuild_doc=YES -Dbuild_wizard=YES ..
    make -j$(nproc)

    # Download manual and install
    wget https://github.com/doxygen/doxygen/releases/download/Release_${GITHUB_PACKAGE_VERSION}/doxygen_manual-${PACKAGE_VERSION}.pdf.zip
    unzip doxygen_manual-${PACKAGE_VERSION}.pdf.zip
    mkdir -p latex
    mv doxygen_manual-${PACKAGE_VERSION}.pdf latex/doxygen_manual.pdf
    sudo make install

    printf -- "Installation of doxygen completed\n"

    #Run Test
    runTests

    cleanup
}

function runTests() {
  set +e
  if [[ "$TESTS" == "true" ]]; then
    printf -- 'Running tests \n'
    printf -- 'Run the functional test suite \n'
    cd $SOURCE_ROOT/doxygen/build
    sudo make tests
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
    echo " bash build_doxygen.sh  [-d debug] [-y install-without-confirmation] [-t run-test-cases]"
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
    printf -- "You have successfully installed %s %s on %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"rhel-8.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y gcc gcc-c++ python3 cmake bison qt5-devel diffutils unzip texlive |& tee -a "$LOG_FILE"
    installFlex |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-9.4" | "rhel-9.6" | "rhel-9.7")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y gcc gcc-c++ python3 flex cmake bison qt5-devel diffutils unzip texlive |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-10.0" | "rhel-10.1")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y gcc gcc-c++ flex cmake bison qt5-qtbase-devel qt5-qtsvg-devel diffutils unzip texlive |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;		
"sles-15.7" | "sles-16.0")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y gcc gcc-c++ flex cmake bison libqt5-qtsvg-devel libqt5-qtbase-devel libxml2-devel unzip texlive-bibtex-bin |& tee -a "$LOG_FILE"
    if [[ $DISTRO == "sles-15.7" ]]; then
        sudo zypper install -y gcc14 gcc14-c++ |& tee -a "$LOG_FILE"
        sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-14 14 |& tee -a "$LOG_FILE"
        sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-14 14 |& tee -a "$LOG_FILE"
        sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-14 14 |& tee -a "$LOG_FILE"
        sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-14 14 |& tee -a "$LOG_FILE"
    fi
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"ubuntu-22.04" | "ubuntu-24.04" | "ubuntu-25.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y unzip cmake flex bison build-essential libqt5svg5-dev qtbase5-dev libxml2-utils texlive-bibtex-extra |& tee -a "${LOG_FILE}" 
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
