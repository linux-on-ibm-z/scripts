#!/bin/bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/bazel/build_go.sh
# Execute build script: bash build_bazel.sh    (provide -h for help)
#


set -e -o pipefail
BAZEL_REPO_URL="https://github.com/bazelbuild/bazel/releases/download"
REPO_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Bazel/patch"
PACKAGE_NAME="bazel"
PACKAGE_VERSION="0.15.2"
CURDIR=$PWD
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
OVERRIDE=false


trap cleanup 1 2 ERR

#Check if directory exsists
if [ ! -d "logs" ]; then
   mkdir -p "logs"
fi


# Need handling for RHEL 6.10 as it doesn't have os-release file
if [ -f "/etc/os-release" ]; then
	source "/etc/os-release"
else
  cat /etc/redhat-release >> "${LOG_FILE}"
	export ID="rhel"
  export VERSION_ID="6.x"
  export PRETTY_NAME="Red Hat Enterprise Linux 6.x"
fi

function checkPrequisites()
{
  if command -v "sudo" > /dev/null ;
  then
    printf -- 'Sudo : Yes\n' >> "$LOG_FILE" 
  else
    printf -- 'Sudo : No \n' >> "$LOG_FILE"  
    printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n';
    exit 1;
  fi;

  if command -v "bazel" > /dev/null ;
  then
    printf -- "Bazel : Yes" >>  "$LOG_FILE"
    set +e
    if [[ $(bazel version | grep "$PACKAGE_VERSION") ]] 
    then
      printf -- "Version : %s (Satisfied) \n" "${PACKAGE_VERSION}" 
      printf -- "No update required for Bazel \n"
      exit 0;
    fi
    set -e
  fi;
}

function cleanup()
{
  sudo rm -rf "${CURDIR}/compile.sh.diff"
  printf -- 'Cleaned up the artifacts\n'  >> "$LOG_FILE"

}

function buildGCC() {

	printf -- 'Building GCC \n'
	cd "${CURDIR}"
	wget ftp://gcc.gnu.org/pub/gcc/releases/gcc-6.3.0/gcc-6.3.0.tar.gz
	tar -xvzf gcc-6.3.0.tar.gz
	cd gcc-6.3.0/
	./contrib/download_prerequisites
	cd "${CURDIR}"
	mkdir -p gcc_build
	cd gcc_build/
	../gcc-6.3.0/configure --prefix="/opt/gcc" --enable-shared --with-system-zlib --enable-threads=posix --enable-__cxa_atexit --enable-checking --enable-gnu-indirect-function --enable-languages="c,c++" --disable-bootstrap --disable-multilib
	make
	sudo make install
	export PATH=/opt/gcc/bin:$PATH
	sudo ln -sf /opt/gcc/bin/gcc /usr/bin/gcc
	export C_INCLUDE_PATH=/opt/gcc/lib/gcc/s390x-ibm-linux-gnu/6.3.0/include
	export CPLUS_INCLUDE_PATH=/opt/gcc/lib/gcc/s390x-ibm-linux-gnu/6.3.0/include
	#for rhel
	if [[ "${ID}" == "rhel" ]]; then
		sudo ln -sf /opt/gcc/lib64/libstdc++.so.6.0.22 /lib64/libstdc++.so.6
	else
		sudo ln -sf /opt/gcc/lib64/libstdc++.so.6.0.22 /usr/lib/s390x-linux-gnu/libstdc++.so.6
	fi
	export LD_LIBRARY_PATH='/opt/gcc/$LIB'
	printf -- 'Built GCC successfully \n'

}

function configureAndInstall()
{
  printf -- 'Configuration and Installation started \n'

  if [[ "${OVERRIDE}" == "true" ]]
  then
    printf -- 'Bazel exists on the system. Override flag is set to true hence updating the same\n '
  fi

  if [[ "${ID}" == "rhel" ]]; then
		cd "${CURDIR}"
		wget https://cmake.org/files/v3.7/cmake-3.7.2.tar.gz
		tar xzf cmake-3.7.2.tar.gz
		cd cmake-3.7.2
		./configure --prefix=/usr/local
		make && sudo make install
	fi

  mkdir -p "${CURDIR}/bazel"
  cd "${CURDIR}/bazel"
  # Install Bazel
  printf -- 'Downloading bazel \n'
  wget "${BAZEL_REPO_URL}/${PACKAGE_VERSION}/${PACKAGE_NAME}-${PACKAGE_VERSION}-dist.zip"
  #unzip bazel-0.18.0-dist.zip
  unzip "${PACKAGE_NAME}"-"${PACKAGE_VERSION}"-"dist.zip"
  printf -- 'Compiling \n'
  sleep 2s
  chmod -R +w .
  #Apply patch
  cd "${CURDIR}"

  if [[ "${PACKAGE_VERSION}" == "0.15.2" ]]; then 
    curl -o compile.sh.diff $REPO_URL/compile1.sh.diff
  else
    curl -o compile.sh.diff $REPO_URL/compile.sh.diff
  fi
	patch "${CURDIR}/bazel/scripts/bootstrap/compile.sh" compile.sh.diff
  cd "${CURDIR}/bazel"
  bash ./compile.sh
  sudo cp "${CURDIR}/bazel/output/bazel" /usr/bin/

  #Clean up the downloaded zip
  cleanup

  #Verify if bazel is configured correctly
  set +e
  if [[ $(bazel version | grep "$PACKAGE_VERSION") ]] 
  then
    printf -- "Installed %s %s successfully \n" "$PACKAGE_NAME" "$PACKAGE_VERSION"
  else
    printf -- "Error while installing bazel, exiting with 127 \n";
    exit 127;
  fi
  set -e
}

function logDetails()
{
    printf -- '**************************** SYSTEM DETAILS *************************************************************\n' > "$LOG_FILE";
    
    if [ -f "/etc/os-release" ]; then
	    cat "/etc/os-release" >> "$LOG_FILE"
    fi
    
    cat /proc/version >> "$LOG_FILE"
    printf -- '*********************************************************************************************************\n' >> "$LOG_FILE";

    printf -- "Detected %s \n" "$PRETTY_NAME"
    printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" |& tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
  echo 
  echo "Usage: "
  echo "  build_bazel.sh [-d debug] [-o override] [-p check-prequisite]"
  echo
}

while getopts "h?dop" opt; do
  case "$opt" in
  h | \?)
    printHelp
    exit 0
    ;;
  d)
    set -x
    ;;
  o)
    OVERRIDE=true
    ;;
  p) 
    checkPrequisites
    exit 0
    ;;
  esac
done

function gettingStarted()
{
  
  printf -- "\n\nUsage: \n"
  printf -- "  Bazel has been installed and binary has been placed in /usr/bin \n"
  printf -- "  Run : bazel version to check the version or Run bazel --help for help. \n"
  printf -- '\n'
}

###############################################################################################################

logDetails
checkPrequisites  #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04")
  	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	sudo apt-get update
  	sudo apt-get install -y  curl wget patch build-essential openjdk-8-jdk python zip unzip |& tee -a "$LOG_FILE"
  	buildGCC |& tee -a "$LOG_FILE"
  	configureAndInstall |& tee -a "$LOG_FILE"
  	;;

"ubuntu-18.04")
  	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  	sudo apt-get update
  	sudo apt-get install -y git openjdk-8-jdk pkg-config zip zlib1g-dev unzip python libtool automake cmake curl wget build-essential rsync clang g++-6 libgtk2.0-0 clang-format-5.0  |& tee -a "$LOG_FILE"
  	sudo rm -rf /usr/bin/gcc /usr/bin/g++ /usr/bin/cc
  	sudo ln -sf /usr/bin/gcc-6 /usr/bin/gcc
  	sudo ln -sf /usr/bin/g++-6 /usr/bin/g++
  	sudo ln -sf /usr/bin/gcc /usr/bin/cc
  	configureAndInstall |& tee -a "$LOG_FILE"
  	;;

"rhel-7.3" | "rhel-7.4" | "rhel-7.5")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for bazel from repository \n' |& tee -a "$LOG_FILE"
	sudo yum install -y  git tar java-1.8.0-openjdk java-1.8.0-openjdk-devel zip gcc-c++ unzip python libtool automake cmake golang curl wget gcc vim patch binutils-devel bzip2 make  |& tee -a "$LOG_FILE"
  buildGCC |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
  ;;

"sles-12.3")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for bazel from repository \n' |& tee -a "$LOG_FILE"
	sudo zypper install -y pkg-config python libtool automake cmake zlib-devel gcc6 gcc6-c++ binutils-devel patch which curl curl unzip zip patch which tar wget gcc java-1_8_0-openjdk java-1_8_0-openjdk-devel |& tee -a "$LOG_FILE" 
	sudo ln -sf /usr/bin/gcc-6 /usr/bin/gcc
	sudo ln -sf /usr/bin/g++-6 /usr/bin/g++
  	sudo ln -sf /usr/bin/gcc /usr/bin/cc
  	configureAndInstall |& tee -a "$LOG_FILE"
  	;;
 
 "sles-15")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for bazel from repository \n' |& tee -a "$LOG_FILE"
	sudo zypper install -y pkg-config python libtool automake cmake zlib-devel gcc6 gcc6-c++ binutils-devel patch which curl curl unzip zip patch which tar wget gcc java-1_8_0-openjdk java-1_8_0-openjdk-devel |& tee -a "$LOG_FILE" 
	configureAndInstall |& tee -a "$LOG_FILE"
  ;;

*)
  	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
  	exit 1 ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
