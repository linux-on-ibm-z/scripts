#!/usr/bin/env bash
# © Copyright IBM Corporation 2023
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/SaltStack/3006.3/build_salt.sh
# Execute build script: bash build_salt.sh    (provide -t for test)
#
set -e -o pipefail
PACKAGE_NAME="salt"
PACKAGE_VERSION="3006.3"
PYTHON_VERSION="3.10.2"
CURDIR="$PWD"
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
trap cleanup 1 2 ERR
TESTS="false"
FORCE="false"
BUILD_ENV="${CURDIR}/setenv.sh"
#Check if directory exsists
if [ ! -d "logs" ]; then
   mkdir -p "logs"
fi
if [ -f "/etc/os-release" ]; then
	source "/etc/os-release"
fi

function checkPrequisites()
{
  if command -v "sudo" > /dev/null ;
  then
    printf -- 'Sudo : Yes\n' >> "$LOG_FILE"
  else
    printf -- 'Sudo : No \n' >> "$LOG_FILE"
    printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n';
    exit 1;
  fi;

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

function runTest() {
if [[ "$TESTS" == "true" ]]; then
		printf -- 'Running tests \n\n'
		cd "${CURDIR}/${PACKAGE_NAME}"
    if [[ "$VERSION_ID" == "20.04" || "$VERSION_ID" == "22.04" || "$VERSION_ID" == "9.0" || "$VERSION_ID" == "9.2" ]]; then
      python3 -m pip install nox
      python3 -m nox -e "test-3(coverage=False)" -- tests/pytests/unit/cli/test_batch.py
      printf -- 'Test Completed \n\n'
    elif [[ "$VERSION_ID" == "8.8" || "$VERSION_ID" == "8.6" || "$VERSION_ID" == "15.4" ]]; then
      sudo /usr/local/bin/python3.10 -m pip install nox
      python3 -m nox -e "test-3(coverage=False)" -- tests/pytests/unit/cli/test_batch.py
      printf -- 'Test Completed \n\n'
    elif [[ "$VERSION_ID" == "12.5" ]]; then
      sudo /usr/local/bin/python3.10 -m pip install nox
      CFLAGS="-std=c99" python3 -m nox -e "test-3(coverage=False)" -- tests/pytests/unit/cli/test_batch.py
      printf -- 'Test Completed \n\n'
    elif [[ "$VERSION_ID" == "7.8" || "$VERSION_ID" == "7.9" ]]; then
      sudo /usr/local/bin/python3.10 -m pip install nox
      pip3 install cryptography
      CFLAGS="-std=c99" python3 -m nox -e "test-3(coverage=False)" -- tests/pytests/unit/cli/test_batch.py
      printf -- 'Test Completed \n\n'
    fi
	fi
}
function configureAndInstall()
{
  printf -- 'Configuration and Installation started \n'

#Building Python
if [[ "$VERSION_ID" != "22.04" && "$VERSION_ID" != "9."* ]]; then
    printf -- 'Building Python \n'
    cd "${CURDIR}"
    wget -q https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Python3/${PYTHON_VERSION}/build_python3.sh
    bash build_python3.sh -y
fi
if [[ "$VERSION_ID" == "7.8" || "$VERSION_ID" == "7.9" ]]; then
    #install Cmake
    printf -- 'Install cmake \n'
    cd "${CURDIR}"
    wget https://cmake.org/files/v3.26/cmake-3.26.0.tar.gz
    tar -xzvf cmake-3.26.0.tar.gz
    cd cmake-3.26.0
    ./bootstrap --prefix=/usr
    make
    sudo make install
fi
if [[ "$ID" == "rhel" ]]; then
    cd "${CURDIR}"
    #install M2Crypto
    printf -- 'Building M2Crypto \n'
    if [[ "$VERSION_ID" == "9."* ]]; then
      sudo -H pip install M2Crypto
    else
      sudo /usr/local/bin/python3.10 -m pip install M2Crypto
    fi
    #install zeromq
    if [[ "$VERSION_ID" != "7."* ]]; then
      printf -- 'Building ZeroMQ \n'
      wget https://github.com/zeromq/zeromq4-1/releases/download/v4.1.6/zeromq-4.1.6.tar.gz
      tar -xzvf zeromq-4.1.6.tar.gz
      cd zeromq-4.1.6
      ./configure
      make
      sudo make install
      sudo ldconfig
    else
      wget https://github.com/zeromq/zeromq4-1/releases/download/v4.1.6/zeromq-4.1.6.tar.gz
      tar -xzvf zeromq-4.1.6.tar.gz
      cd zeromq-4.1.6
      ./configure
      make
      sudo make install
    fi
fi
#Building Rust
  printf -- 'Building Rust \n'
  cd "${CURDIR}"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  source $HOME/.cargo/env
  rustup default 1.56.0

#Building Libgit2 on ubuntu
if [[ "$DISTRO" != "rhel-9."* ]]; then
    cd /usr/local
    sudo wget https://github.com/libgit2/libgit2/archive/refs/tags/v1.4.6.tar.gz -O libgit2-1.4.6.tar.gz
    sudo tar xzf libgit2-1.4.6.tar.gz
    cd libgit2-1.4.6/
    sudo cmake .
    sudo make
    sudo make install
else 
    cd /usr/local
    sudo wget https://github.com/libgit2/libgit2/archive/refs/tags/v1.1.1.tar.gz -O libgit2-1.1.1.tar.gz
    sudo tar xzf libgit2-1.1.1.tar.gz
    cd libgit2-1.1.1/
    sudo cmake .
    sudo make
    sudo make install
fi
#install Openssl
if [[ "$VERSION_ID" == "7."* ]]; then
  cd "${CURDIR}"
  wget https://www.openssl.org/source/openssl-1.1.1q.tar.gz --no-check-certificate
  tar -xzf openssl-1.1.1q.tar.gz
  cd openssl-1.1.1q
  ./config --prefix=/usr/local --openssldir=/usr/local
  make
  sudo make install
  sudo ldconfig /usr/local/lib64

  export PATH=/usr/local/bin:$PATH
  export LDFLAGS="-L/usr/local/lib/ -L/usr/local/lib64/"
  export LD_LIBRARY_PATH="/usr/local/lib/:/usr/local/lib64/"
  export PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig
  export CPPFLAGS="-I/usr/local/include/ -I/usr/local/include/openssl"

  printf -- 'export PATH="/usr/local/bin:${PATH}"\n'  >> "${BUILD_ENV}"
  printf -- "export LDFLAGS=\"$LDFLAGS\"\n" >> "${BUILD_ENV}"
  printf -- "export LD_LIBRARY_PATH=\"$LD_LIBRARY_PATH\"\n" >> "${BUILD_ENV}"
  printf -- "export CPPFLAGS=\"$CPPFLAGS\"\n" >> "${BUILD_ENV}"
fi
#Download Salt
    cd "${CURDIR}"
    printf -- 'Downloading Salt \n'
    git clone https://github.com/saltstack/salt.git
    cd salt
    git checkout v${PACKAGE_VERSION}
#Building Salt
if [[ "$ID" == "ubuntu" ]]; then
    cd "${CURDIR}/${PACKAGE_NAME}"
    sudo -H pip3 install pyzmq 'PyYAML<5.1' pycrypto msgpack-python jinja2 psutil futures==2.2.0 tornado python-dateutil genshi
    sudo -H pip3 install -e .
elif [[ "$VERSION_ID" == "9."* ]]; then
    cd "${CURDIR}/${PACKAGE_NAME}"
    sudo -H pip install pyzmq 'PyYAML<5.1' pycrypto msgpack-python jinja2 psutil futures tornado python-dateutil genshi
    sudo -H pip install -e .
else
    cd "${CURDIR}/${PACKAGE_NAME}"
    sudo /usr/local/bin/python3.10 -m pip install pyzmq 'PyYAML<5.1' pycrypto msgpack-python jinja2 psutil futures tornado python-dateutil genshi
    sudo /usr/local/bin/python3.10 -m pip install -e .
fi

#Run tests
  runTest
#Verify installation
  salt-master --version
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
  echo "bash build_salt.sh [-d debug] [-t install-with-tests] [-y install-without-confirmation]"
  echo
}
while getopts "dthy?" opt; do
  case "$opt" in
  d)
    set -x
    ;;
  t)
    TESTS="true"
    ;;
  y)
    FORCE="true"
    ;;
  h | \?)
    printHelp
    exit 0
    ;;
  esac
done
function gettingStarted()
{
  printf -- "\n\nUsage: \n"
  printf -- "  Salt installed successfully \n"
  printf -- "  More information can be found here : https://github.com/saltstack/salt \n"
  printf -- '\n'
}
###############################################################################################################
logDetails
checkPrequisites  #Check Prequisites
DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-20.04")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  sudo apt-get update
  sudo apt-get install -y wget g++ gcc git libffi-dev libsasl2-dev libssl-dev libxml2-dev libxslt1-dev libzmq3-dev make man python3-pip tar wget libz-dev pkg-config apt-utils curl cmake |& tee -a "${LOG_FILE}"
  configureAndInstall |& tee -a "${LOG_FILE}"
  ;;
"ubuntu-22.04")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  sudo apt-get update
  sudo apt-get install -y wget g++ gcc git libffi-dev libsasl2-dev libssl-dev libxml2-dev libxslt1-dev libzmq3-dev make man python3-dev python3-pip tar wget libz-dev pkg-config apt-utils curl cmake make |& tee -a "${LOG_FILE}"
  configureAndInstall |& tee -a "${LOG_FILE}"
  ;;
"rhel-7.8" | "rhel-7.9")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	sudo yum install -y procps-ng cyrus-sasl-devel gcc gcc-c++ git libffi-devel libtool libxml2-devel libxslt-devel make man swig tar wget |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
;;
"rhel-8.6" | "rhel-8.8")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	sudo yum install -y procps-ng cyrus-sasl-devel gcc gcc-c++ git libffi-devel libtool libxml2-devel libxslt-devel make man openssl-devel swig tar wget cmake |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
;;
"rhel-9.0" | "rhel-9.2")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	sudo yum install -y procps-ng cyrus-sasl-devel gcc gcc-c++ git libffi-devel libtool libxml2-devel libxslt-devel make man openssl-devel swig tar wget cmake python3-pip python3-devel |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
  ;;
"sles-12.5")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	sudo zypper install -y curl cyrus-sasl-devel gawk gcc gcc-c++ git libopenssl-devel libxml2-devel libxslt-devel make man tar wget cmake libnghttp2-devel |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
;;
"sles-15.4")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	sudo zypper install -y curl cyrus-sasl-devel gawk gcc gcc-c++ git libffi-devel libopenssl-devel libxml2-devel libxslt-devel make man tar wget zeromq-devel cmake libnghttp2-devel |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
  ;;
*)
  printf -- "%s not supported \n" "$DISTRO"|& tee -a "$LOG_FILE"
  exit 1 ;;
esac
gettingStarted |& tee -a "${LOG_FILE}"
