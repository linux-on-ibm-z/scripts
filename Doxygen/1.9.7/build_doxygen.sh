#!/bin/bash
# © Copyright IBM Corporation 2023.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Doxygen/1.9.7/build_doxygen.sh
# Execute build script: bash build_doxygen.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="doxygen"
PACKAGE_VERSION="1.9.7"
GITHUB_PACKAGE_VERSION="1_9_7"
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

function install_cmake() {
    # Install cmake only for RHEL and SLES
    printf -- "Installing cmake... \n" |& tee -a "$LOG_FILE"
    cd $SOURCE_ROOT
    wget https://cmake.org/files/v3.26/cmake-3.26.4.tar.gz
    tar xzf cmake-3.26.4.tar.gz
    cd cmake-3.26.4
    ./configure --prefix=/usr/local
    make && sudo make install
    printf -- "Installed cmake successfully \n" |& tee -a "$LOG_FILE"
    export PATH=$PATH:/usr/local/bin
    echo $PATH
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"
    echo $PATH

    #  Download source code
    cd $SOURCE_ROOT
    git clone https://github.com/doxygen/doxygen.git
    cd doxygen
    git checkout Release_${GITHUB_PACKAGE_VERSION}

    # Create a build directory
    cd $SOURCE_ROOT/doxygen
    mkdir build

    # Build and install
    cd $SOURCE_ROOT/doxygen/build
    cmake -G "Unix Makefiles" -Dbuild_doc=ON -Dbuild_wizard=YES ..
    make

    # Download manual and install
    wget https://sourceforge.net/projects/doxygen/files/doxygen_manual-${PACKAGE_VERSION}.pdf.zip
    unzip  doxygen_manual-${PACKAGE_VERSION}.pdf.zip
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
    make tests
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
"ubuntu-20.04") 
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y git flex bison wget unzip python qt5-default build-essential libxml2-utils cmake texlive-full texlive-latex-extra |& tee -a "${LOG_FILE}"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"ubuntu-22.04" | "ubuntu-22.10" | "ubuntu-23.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y git flex bison wget unzip python-is-python3 qtbase5-dev qtchooser qt5-qmake qtbase5-dev-tools build-essential libxml2-utils cmake texlive-latex-extra texlive-full |& tee -a "${LOG_FILE}"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-7.8" | "rhel-7.9")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo subscription-manager repos --enable=rhel-7-server-for-system-z-devtools-rpms
    sudo yum install -y git flex bison make wget unzip tar qt5-qtbase-devel texlive devtoolset-7 openssl-devel |& tee -a "${LOG_FILE}"
    source /opt/rh/devtoolset-7/enable
    install_cmake |& tee -a "${LOG_FILE}"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-8.6" | "rhel-8.7" | "rhel-9.0" | "rhel-9.1")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y git flex bison wget unzip gcc gcc-c++ python3 make qt5-devel texlive diffutils openssl-devel |& tee -a "$LOG_FILE"
    install_cmake |& tee -a "${LOG_FILE}"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-12.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y git flex bison wget tar unzip gcc8 gcc8-c++ curl libnghttp2-devel libxml2-devel texlive-bibtex-bin make libqt5-qtbase-devel texlive openssl-devel |& tee -a "$LOG_FILE"
    sudo ln -sf /usr/bin/g++-8 /usr/bin/c++
    sudo ln -sf /usr/bin/g++-8 /usr/bin/g++
    sudo ln -sf /usr/bin/gcc-8 /usr/bin/cc
    install_cmake |& tee -a "${LOG_FILE}"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-15.4")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y git flex bison wget tar unzip gcc gcc-c++ libxml2-devel glibc-locale texlive-bibtex-bin make libqt5-qtbase-devel cmake openssl-devel |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
