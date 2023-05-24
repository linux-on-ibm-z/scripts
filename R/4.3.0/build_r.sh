#!/bin/bash
# © Copyright IBM Corporation 2023.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/R/4.3.0/build_r.sh
# Execute build script: bash build_r.sh    (provide -h for help)
#

set -e -o pipefail
shopt -s extglob

PACKAGE_NAME="R"
PACKAGE_VERSION="4.3.0"
CURDIR="$(pwd)"
SOURCE_ROOT="$(pwd)"
JAVA_PROVIDED="OpenJDK"
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

   echo "Java provided by user $JAVA_PROVIDED" >> "$LOG_FILE"
    if [[ "$JAVA_PROVIDED" == "Semeru11" ]]; then
        # Install AdoptOpenJDK 11 (With OpenJ9)
        printf -- "\nInstalling IBM Semeru Runtime (previously known as AdoptOpenJDK openj9) . . . \n"
        cd "$CURDIR"
        wget https://github.com/ibmruntimes/semeru11-binaries/releases/download/jdk-11.0.18%2B10_openj9-0.36.1/ibm-semeru-open-jdk_s390x_linux_11.0.18_10_openj9-0.36.1.tar.gz
		    tar -xf ibm-semeru-open-jdk_s390x_linux_11.0.18_10_openj9-0.36.1.tar.gz
        export JAVA_HOME=$CURDIR/jdk-11.0.18+10
        printf -- "export JAVA_HOME=$CURDIR/jdk-11.0.18+10\n" >> "$BUILD_ENV"
        printf -- "Installation of IBM Semeru Runtime (previously known as AdoptOpenJDK openj9) is successful\n" >> "$LOG_FILE"
        
      elif [[ "$JAVA_PROVIDED" == "Temurin11" ]]; then
        printf -- "\nInstalling Eclipse Adoptium Temurin Runtime (previously known as AdoptOpenJDK hotspot) . . . \n"
        cd $CURDIR
        wget https://github.com/adoptium/temurin11-binaries/releases/download/jdk-11.0.18%2B10/OpenJDK11U-jdk_s390x_linux_hotspot_11.0.18_10.tar.gz
        tar -xf OpenJDK11U-jdk_s390x_linux_hotspot_11.0.18_10.tar.gz
        export JAVA_HOME=$CURDIR/jdk-11.0.18+10
        printf -- "export JAVA_HOME=$CURDIR/jdk-11.0.18+10\n" >> "$BUILD_ENV"
        printf -- "Installation of Eclipse Adoptium Temurin Runtime (previously known as AdoptOpenJDK hotspot) is successful\n" >> "$LOG_FILE"

    elif [[ "$JAVA_PROVIDED" == "OpenJDK11" ]]; then
        cd "$CURDIR"


  case "$DISTRO" in
  "ubuntu-"* )
      sudo apt-get install -y openjdk-11-jdk openjdk-11-jdk-headless
      export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x/
      printf -- "export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x/\n" >> "$BUILD_ENV"
    ;;

  "rhel-"*)
      sudo yum install -y java-11-openjdk java-11-openjdk-devel
      export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
      printf -- "export JAVA_HOME=/usr/lib/jvm/java-11-openjdk\n" >> "$BUILD_ENV"
    ;;

  "sles-"*)
      sudo zypper install -y java-11-openjdk java-11-openjdk-devel
      export JAVA_HOME=/usr/lib64/jvm/java-11-openjdk/
      printf -- "export JAVA_HOME=/usr/lib64/jvm/java-11-openjdk/\n" >> "$BUILD_ENV"
    ;;

  esac
  elif [[ "$JAVA_PROVIDED" == "Semeru17" ]]; then
                # Install AdoptOpenJDK 17 (With OpenJ9)
                printf -- "\nInstalling AdoptOpenJDK 17 (With OpenJ9) . . . \n"
                cd $SOURCE_ROOT
                wget https://github.com/ibmruntimes/semeru17-binaries/releases/download/jdk-17.0.6%2B10_openj9-0.36.0/ibm-semeru-open-jdk_s390x_linux_17.0.6_10_openj9-0.36.0.tar.gz
                tar -xzf ibm-semeru-open-jdk_s390x_linux_17.0.6_10_openj9-0.36.0.tar.gz
                export JAVA_HOME=$SOURCE_ROOT/jdk-17.0.6+10
                printf -- "Installation of AdoptOpenJDK 17 (With OpenJ9) is successful\n" >> "$LOG_FILE"
  elif [[ "$JAVA_PROVIDED" == "Temurin17" ]]; then
                # Install AdoptOpenJDK 17 (With Hotspot)
                printf -- "\nInstalling AdoptOpenJDK 17 (With Hotspot) . . . \n"
                cd $SOURCE_ROOT
                        wget https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.6%2B10/OpenJDK17U-jdk_s390x_linux_hotspot_17.0.6_10.tar.gz
                tar -xzf OpenJDK17U-jdk_s390x_linux_hotspot_17.0.6_10.tar.gz
                export JAVA_HOME=$SOURCE_ROOT/jdk-17.0.6+10
                printf -- "Installation of AdoptOpenJDK 17 (With Hotspot) is successful\n" >> "$LOG_FILE"
  elif [[ "$JAVA_PROVIDED" == "OpenJDK17" ]]; then
                if [[ "${ID}" == "ubuntu" ]]; then
                        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-17-jdk
                        export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-s390x
                elif [[ "${ID}" == "rhel" ]]; then
                        sudo yum install -y java-17-openjdk
                        if [[ "${DISTRO}" == "rhel-7."* ]]; then
                         printf "$JAVA_PROVIDED is not available on RHEL 7.  Please use use valid variant from {Semeru8, Temurin8, OpenJDK8, Semeru11, Temurin11, OpenJDK11, Semeru17, Temurin17}.\n"
                         exit 1
                        else
				export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
                        fi
                        

                elif [[ "${ID}" == "sles" ]]; then
                        if [[ "${DISTRO}" == "sles-12.5" ]]; then
                            printf "$JAVA_PROVIDED is not available on SLES 12 SP5.  Please use use valid variant from {Semeru8, Temurin8, OpenJDK8, Semeru11, Temurin11, OpenJDK11, Semeru17, Temurin17}.\n"
                            exit 1
                        fi
                        sudo zypper install -y java-17-openjdk  java-17-openjdk-devel
                        export JAVA_HOME=/usr/lib64/jvm/java-17-openjdk
                fi
                printf -- "Installation of OpenJDK 17 is successful\n" >> "$LOG_FILE"

    else
        err "$JAVA_PROVIDED is not supported, Please use valid java from {Semeru11, Temurin11, OpenJDK} only"
        exit 1
    fi

    export PATH=$JAVA_HOME/bin:/usr/local/bin:/sbin:$PATH
    printf -- 'export PATH=$JAVA_HOME/bin:/usr/local/bin:/sbin:$PATH\n'  >> "$BUILD_ENV"
    printf -- 'export JAVA_HOME for "$ID"  \n'  >> "$LOG_FILE"


  cd "$CURDIR"
  java -version
  curl -sSL $R_URL | tar xzf -
  mkdir build && cd build
  ../R-${PACKAGE_VERSION}/configure --with-x=no --with-pcre1
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
  "ubuntu-"* )
      sudo apt-get install -y texlive-latex-base texlive-latex-extra \
        texlive-fonts-recommended texlive-fonts-extra
      sudo locale-gen "en_US.UTF-8"
      sudo locale-gen "en_GB.UTF-8"
      export LANG="en_US.UTF-8"
      printf -- 'export LANG="en_US.UTF-8"\n'  >> "$BUILD_ENV" 
    ;;

  "rhel-"*)
      sudo yum install -y texlive
      export LANG="en_US.UTF-8"
      printf -- 'export LANG="en_US.UTF-8"\n'  >> "$BUILD_ENV" 
    ;;

  "sles-"*)
      sudo zypper install -y texlive-courier texlive-dvips
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
  bash build_r.sh [-y] [-d] [-t] [-j (Temurin11|Semeru11|OpenJDK)]
  where:
   -y install-without-confirmation
   -d debug
   -t test
   -j which JDK to use:
        Temurin11 - Eclipse Adoptium Temurin Runtime (previously known as AdoptOpenJDK hotspot)
        Semeru11 - IBM Semeru Runtime (previously known as AdoptOpenJDK openj9)
        OpenJDK - for OpenJDK 11
	Temurin17 - Eclipse Adoptium Temurin Runtime
        Semeru17 - IBM Semeru Runtime 
        OpenJDK - for OpenJDK 17
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
        j)
                JAVA_PROVIDED="$OPTARG"
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
"ubuntu-20.04" | "ubuntu-22.04" | "ubuntu-22.10" | "ubuntu-23.04")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  printf -- "Installing dependencies... it may take some time.\n"
  sudo DEBIAN_FRONTEND=noninteractive apt-get update -y |& tee -a "$LOG_FILE"
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    wget curl tar gcc g++ ratfor gfortran libx11-dev make r-base \
    libcurl4-openssl-dev locales \
    |& tee -a "$LOG_FILE"

  configureAndInstall |& tee -a "$LOG_FILE"
;;

"rhel-7.8" | "rhel-7.9" )
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
  sudo yum install -y \
    gcc curl wget tar make rpm-build zlib-devel xz-devel ncurses-devel \
    cairo-devel gcc-c++ libcurl-devel libjpeg-devel libpng-devel \
    libtiff-devel readline-devel texlive-helvetic texlive-metafont \
    texlive-psnfss texlive-times xdg-utils pango-devel tcl-devel \
    tk-devel perl-macros info gcc-gfortran libXt-devel \
    perl-Text-Unidecode.noarch bzip2-devel pcre-devel help2man procps glibc-common \
    |& tee -a "$LOG_FILE"

  configureAndInstall |& tee -a "$LOG_FILE"
;;

"sles-12.5" | "sles-15.4")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
  sudo zypper install -y \
    curl libnghttp2-devel wget tar rpm-build help2man zlib-devel xz-devel libyui-ncurses-devel \
    make cairo-devel gcc-c++ gcc-fortran libcurl-devel libjpeg-devel \
    libpng-devel libtiff-devel readline-devel fdupes texlive-helvetic \
    texlive-metafont texlive-psnfss texlive-times texlive-ae texlive-fancyvrb xdg-utils \
    pango-devel tcl tk xorg-x11-devel perl-macros texinfo \
    |& tee -a "$LOG_FILE"

  configureAndInstall |& tee -a "$LOG_FILE"
;;
esac

gettingStarted |& tee -a "$LOG_FILE"
