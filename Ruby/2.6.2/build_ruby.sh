#!/usr/bin/env bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Ruby/2.6.2/build_ruby.sh
# Execute build script: bash build_ruby.sh    (provide -h for help)
#


set -e -o pipefail

PACKAGE_NAME="ruby"
PACKAGE_VERSION="2.6.2"
CURDIR="$PWD"
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
trap cleanup 1 2 ERR
TESTS="false"

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
}

function cleanup()
{
  cd "${CURDIR}"
  rm -rf "${PACKAGE_NAME}"-"${PACKAGE_VERSION}".tar.gz
  printf -- 'Cleaned up the artifacts\n'
}

function runTest() {
	
	if [[ "$TESTS" == "true" ]]; then
		printf -- 'Running tests \n\n'
		cd "${CURDIR}/${PACKAGE_NAME}-${PACKAGE_VERSION}"
		make test
    printf -- 'Test Completed \n\n'
	fi

}


function configureAndInstall()
{
  printf -- 'Configuration and Installation started \n'
  
  #Download the source code
  printf -- 'Downloading ruby \n'
  cd "${CURDIR}"
  wget http://cache.ruby-lang.org/pub/ruby/2.6/ruby-${PACKAGE_VERSION}.tar.gz
  tar zxf "${PACKAGE_NAME}"-"${PACKAGE_VERSION}".tar.gz
  cd "${CURDIR}/${PACKAGE_NAME}-${PACKAGE_VERSION}"

  #Building ruby
  printf -- 'Building ruby \n'
  ./configure
  make

  #Installation step
  sudo -E make install

  export PATH="$PATH:/usr/local/bin"

  #Run tests
  runTest

  
  #Verify installation
  ruby -v
  gem env


  #Clean up the downloaded zip
  cleanup
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
  echo "  build_ruby.sh [-d debug] [-t install-with-tests]" 
  echo
}

while getopts "dth?" opt; do
  case "$opt" in
  d)
    set -x
    ;;
  t)
    TESTS="true"
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
  printf -- "  Ruby installed successfully \n"
  printf -- '  Run command export PATH="$PATH:/usr/local/bin" or add it to .bashrc file for permanant changes \n'
  printf -- "  More information can be found here : https://github.com/ruby/ruby \n"
  printf -- '\n'
}

###############################################################################################################

logDetails
checkPrequisites  #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  sudo apt-get update > /dev/null
  sudo apt-get install -y  gcc make wget tar bzip2 subversion bison flex openssl |& tee -a "${LOG_FILE}"
  configureAndInstall |& tee -a "${LOG_FILE}"
  ;;

"rhel-6.x")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for Ruby from repository \n' |& tee -a "$LOG_FILE"
	sudo yum install -y bison flex openssl-devel libyaml-devel libffi-devel readline-devel zlib-devel gdbm-devel ncurses-devel tcl-devel tk-devel sqlite-devel gcc make wget tar bzip2 svn  |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
  ;;
  
"rhel-7.4" | "rhel-7.5" | "rhel-7.6")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for Ruby from repository \n' |& tee -a "$LOG_FILE"
	sudo yum install bison flex openssl-devel libyaml-devel libffi-devel readline-devel zlib-devel gdbm-devel ncurses-devel tcl-devel tk-devel sqlite-devel gcc make wget tar  |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
  ;;

"sles-12.3")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for Ruby from repository \n' |& tee -a "$LOG_FILE"

	sudo zypper install -y bison flex libopenssl-devel libyaml-devel libffi48-devel readline-devel zlib-devel gdbm-devel ncurses-devel tcl-devel tk-devel sqlite3-devel gcc make wget tar |& tee -a "${LOG_FILE}" 
	configureAndInstall |& tee -a "${LOG_FILE}"
  ;;


 "sles-15")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for Ruby from repository \n' |& tee -a "$LOG_FILE"
	sudo zypper install -y bison flex libopenssl-devel libyaml-devel libffi-devel readline-devel zlib-devel gdbm-devel ncurses-devel tcl-devel tk-devel sqlite3-devel gcc make wget tar |& tee -a "${LOG_FILE}" 
	configureAndInstall |& tee -a "${LOG_FILE}"
  ;;

*)
  printf -- "%s not supported \n" "$DISTRO"|& tee -a "$LOG_FILE"
  exit 1 ;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
