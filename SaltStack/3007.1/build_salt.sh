#!/usr/bin/env bash
# © Copyright IBM Corporation 2024, 2025
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/SaltStack/3007.1/build_salt.sh
# Execute build script: bash build_salt.sh    (provide -t for test)
#
set -e -o pipefail
PACKAGE_NAME="salt"
PACKAGE_VERSION="3007.1"
PYTHON_VERSION="3.10.12"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/SaltStack/3007.1/patch/"
CURDIR="$PWD"
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
trap cleanup 1 2 ERR
TESTS="false"
FORCE="false"
BUILD_ENV="${CURDIR}/setenv.sh"
#Check if directory exists
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

function cleanup()
{
	rm -rf ${CURDIR}/Python-${PYTHON_VERSION}.tgz ${CURDIR}/v1.7.0.tar.gz
	printf -- 'Cleaned up the artifacts\n'  >> "$LOG_FILE"
}

function runTest() {
if [[ "$TESTS" == "true" ]]; then
	printf -- 'Running tests \n\n'		
	cd "${CURDIR}/${PACKAGE_NAME}"
	pip3 install nox       
    python3 -m nox -e "test-3(coverage=False)" -- --core-tests --slow-tests || true
	printf -- 'Test Completed \n\n'
fi
}

function configureAndInstall()
{
  printf -- 'Configuration and Installation started \n'
  
	printf -- 'Building Python \n'
	cd "${CURDIR}"
	wget https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz 
	tar -xzf Python-${PYTHON_VERSION}.tgz
	cd Python-${PYTHON_VERSION}
	./configure --prefix=/usr/local --exec-prefix=/usr/local --enable-loadable-sqlite-extensions
	make
	sudo make install
	export PATH=/usr/local/bin/python3.10:$PATH
	python3 -V	

    	if [[ "$ID" == "rhel" ]]; then
		pip3 install M2Crypto		
	fi	

	printf -- 'Building Rust \n'
	cd "${CURDIR}"
	curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
	source $HOME/.cargo/env
	rustup default 1.78.0

	printf -- 'Building Libgit2 \n'
    	cd "${CURDIR}"  
	wget https://github.com/libgit2/libgit2/archive/refs/tags/v1.7.0.tar.gz 
	tar xzf v1.7.0.tar.gz
	cd libgit2-1.7.0/
	cmake .
	make
	sudo make install
	
	#Install python packages
	if [[ "$ID" == "ubuntu" ]]; then
		pip3 install pyzmq 'PyYAML<5.1' pycrypto msgpack-python jinja2 psutil futures==2.2.0 tornado python-dateutil genshi looseversion packaging distro
	else
		pip3 install pyzmq 'PyYAML<5.1' pycrypto msgpack-python jinja2 psutil futures tornado python-dateutil genshi looseversion packaging distro
	fi	
	
	#Download Salt
	cd "${CURDIR}"
	printf -- 'Downloading Salt \n'
	git clone --depth 1 -b v${PACKAGE_VERSION} https://github.com/saltstack/salt.git
	cd salt
	curl -sSL $PATCH_URL/salt.patch |  git apply -
	pip3 install -e .

#Run tests
  runTest

#Verify installation
  export PATH=${CURDIR}/.local/bin:$PATH
  printf -- 'path for Salt : $PATH \n'
  echo $PATH
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
"rhel-8.8" | "rhel-8.10")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    sudo yum install -y procps-ng zeromq-devel cyrus-sasl-devel gcc gcc-c++ git libffi-devel libtool libxml2-devel libxslt-devel make man swig tar wget cmake bzip2-devel gdbm-devel libdb-devel libnsl2-devel libuuid-devel ncurses-devel openssl openssl-devel readline-devel sqlite-devel tk-devel xz xz-devel zlib-devel glibc-langpack-en diffutils |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
;;
"rhel-9.2" | "rhel-9.4" | "rhel-9.5")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	sudo yum install -y procps-ng zeromq-devel cyrus-sasl-devel gcc gcc-c++ git libffi-devel libtool libxml2-devel libxslt-devel make man openssl-devel swig tar wget cmake python3-devel python3-pip bzip2-devel sqlite-devel |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
;;
"sles-15.6")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    sudo zypper install -y curl cyrus-sasl-devel gawk gcc gcc-c++ git libopenssl-devel libxml2-devel libxslt-devel make man tar wget cmake libnghttp2-devel gdbm-devel libbz2-devel libdb-4_8-devel libffi-devel libuuid-devel ncurses-devel readline-devel sqlite3-devel tk-devel xz-devel zlib-devel gzip bzip2 |& tee -a "${LOG_FILE}"
    configureAndInstall |& tee -a "${LOG_FILE}"
;;
"ubuntu-20.04")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  sudo apt-get update
  sudo apt-get install -y wget g++ gcc git libffi-dev libsasl2-dev libssl-dev libxml2-dev libxslt1-dev libzmq3-dev make man python3-dev python3-pip tar libz-dev pkg-config apt-utils curl cmake libbz2-dev libsqlite3-dev |& tee -a "${LOG_FILE}"
  configureAndInstall |& tee -a "${LOG_FILE}"
;;
"ubuntu-22.04" | "ubuntu-24.04" | "ubuntu-24.10")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  sudo apt-get update
  sudo apt-get install -y wget g++ gcc git libffi-dev libsasl2-dev libssl-dev libxml2-dev libxslt1-dev libzmq3-dev make man tar libz-dev pkg-config apt-utils curl cmake libbz2-dev libdb-dev libgdbm-dev liblzma-dev libncurses-dev libreadline-dev libsqlite3-dev tk-dev uuid-dev xz-utils zlib1g-dev |& tee -a "${LOG_FILE}"
  configureAndInstall |& tee -a "${LOG_FILE}"
;;
*)
  printf -- "%s not supported \n" "$DISTRO"|& tee -a "$LOG_FILE"
  exit 1 ;;
esac
gettingStarted |& tee -a "${LOG_FILE}"
