#!/bin/bash
# © Copyright IBM Corporation 2025.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/R/4.5.0/build_r.sh
# Execute build script: bash build_r.sh    (provide -h for help)
#

set -e -o pipefail
shopt -s extglob

PACKAGE_NAME="R"
PACKAGE_VERSION="4.5.0"
CURDIR="$(pwd)"
FORCE="false"
TESTS="false"

LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

R_URL="https://cran.r-project.org/src/base/R-4"
R_URL+="/R-${PACKAGE_VERSION}.tar.gz"

BUILD_ENV="$HOME/setenv.sh"

trap cleanup 0 1 2 ERR

#Check if directory exsists
if [ ! -d "$CURDIR/logs" ]; then
        mkdir -p "$CURDIR/logs"
fi

if [ -f "/etc/os-release" ]; then
        source "/etc/os-release"
fi

DISTRO="$ID-$VERSION_ID"

function checkPrequisites() {
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
    printf -- "Cleaned up the artifacts\n" >> "$LOG_FILE"
}

function configureAndInstall(){
  printf -- 'Configuration and Installation started \n'
  printf -- "Building R %s \n,$PACKAGE_VERSION"   
  cd "$CURDIR"
  java -version
  curl -sSL $R_URL | tar xzf -
  mkdir build && cd build
  ../R-${PACKAGE_VERSION}/configure --with-x=no --with-pcre1 --disable-java
  make -j$(nproc)
  sudo make install

  # Run Tests
  runTest

  #Cleanup
  cleanup

  printf -- "\n Installation of %s %s was successful \n\n" $PACKAGE_NAME $PACKAGE_VERSION
}

function runTest() {
  if [[ "$TESTS" == "true" ]]; then
    printf -- "TEST Flag is set , Continue with running test \n"
    printf -- "Installing the dependencies for testing %s,$PACKAGE_NAME \n"

  case "$DISTRO" in
  "sles-"*)
      sudo zypper install -y texlive-courier texlive-dvips
      export LANG="en_US.UTF-8"
      printf -- 'export LANG="en_US.UTF-8"\n'  >> "$BUILD_ENV" 
    ;;

  "ubuntu-"* )
      sudo apt-get install -y texlive-latex-base texlive-latex-extra \
        texlive-fonts-recommended texlive-fonts-extra
      sudo locale-gen "en_US.UTF-8"
      sudo locale-gen "en_GB.UTF-8"
      export LANG="en_US.UTF-8"
      printf -- 'export LANG="en_US.UTF-8"\n'  >> "$BUILD_ENV" 
    ;;

  esac

  cd "$CURDIR/build"
  set +e
  make check
  set -e
  printf -- "\nTest execution completed.\n"
  fi
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
function printHelp(){
  cat <<-eof
  Usage:
  bash build_r.sh [-y] [-d] [-t] 
  where:
   -y install-without-confirmation
   -d debug
   -t test
eof
}

while getopts "h?dytj:" opt; do
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

function gettingStarted()
{
  cat <<-eof
        ***********************************************************************
        Usage:
        *Getting Started * 
        Run following commands to get started: 
        Note: Environmental Variable needed have been added to $HOME/setenv.sh
        Note: To set the Environmental Variable needed for R, please run: source $HOME/setenv.sh
        ***********************************************************************
          R installed successfully.
          More information can be found here:
          https://www.r-project.org/
eof
}

logDetails
checkPrequisites

case "$DISTRO" in
"sles-15.6")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
  sudo zypper install -y \
    curl libnghttp2-devel wget tar rpm-build help2man zlib-devel xz-devel libyui-ncurses-devel \
    make cairo-devel gcc-c++ gcc-fortran libcurl-devel libjpeg-devel \
    libpng-devel libtiff-devel readline-devel fdupes texlive-helvetic java-11-openjdk \
    texlive-metafont texlive-psnfss texlive-times texlive-ae texlive-fancyvrb xdg-utils \
    pango-devel tcl tk xorg-x11-devel perl-macros texinfo \
    |& tee -a "$LOG_FILE"

  configureAndInstall |& tee -a "$LOG_FILE"
;;

"ubuntu-22.04" | "ubuntu-24.04" | "ubuntu-24.10" | "ubuntu-25.04")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  printf -- "Installing dependencies... it may take some time.\n"
  sudo DEBIAN_FRONTEND=noninteractive apt-get update -y |& tee -a "$LOG_FILE"
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    wget curl tar gcc g++ ratfor gfortran libx11-dev make r-base \
    libcurl4-openssl-dev locales openjdk-11-jdk \
    |& tee -a "$LOG_FILE"

  configureAndInstall |& tee -a "$LOG_FILE"
;;
esac

gettingStarted |& tee -a "$LOG_FILE"
