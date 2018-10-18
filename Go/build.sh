#!/bin/bash
# © Copyright IBM Corporation 2017, 2018.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)

set -e

PACKAGE_NAME="go"
PACKAGE_VERSION="1.10.1"
LOG_FILE="logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
OVERRIDE=false


trap "" 1 2 ERR

mkdir -p "logs/"

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
    printf -- 'Sudo : Yes\n';
  else
    printf -- 'Sudo : No \n';
    printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n';
    exit 1;
  fi;

  if command -v "go" > /dev/null ;
  then
    printf -- "Go : Yes" >>  "$LOG_FILE"

    if go version | grep -q "$PACKAGE_VERSION" 
    then
      printf -- "Version : %s (Satisfied) \n" "${PACKAGE_VERSION}" | tee -a  "$LOG_FILE"
      printf -- "No update required for Go \n" | tee -a  "$LOG_FILE"
      exit 0;
    fi
  fi;
}

function cleanup()
{
  rm -rf go1.10.1.linux-s390x.tar.gz
  printf -- 'Cleaned up the artifacts\n'  >> "$LOG_FILE"
}

function configureAndInstall()
{
  printf -- 'Configuration and Installation started \n'

  if [[ "${OVERRIDE}" == "true" ]]
  then
    printf -- 'Go exists on the system. Override flag is set to true hence updating the same\n ' | tee -a "$LOG_FILE"
  fi

  # Install Go
  printf -- 'Downloading go binaries \n'
  wget -q https://storage.googleapis.com/golang/go"${PACKAGE_VERSION}".linux-s390x.tar.gz | tee -a  "$LOG_FILE"
  chmod ugo+r go1.10.1.linux-s390x.tar.gz

  #sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf go1.10.1.linux-s390x.tar.gz

  ln -sf /usr/local/go/bin/go /usr/bin/ >> "$LOG_FILE"
  printf -- 'Extracted the tar in /usr/local and created symlink\n' >>  "$LOG_FILE"

  if [[ "${ID}" != "ubuntu" ]]
  then
    sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc  > /dev/null
    printf -- 'Symlink done for gcc \n'  >> "$LOG_FILE"
  fi

  #Clean up the downloaded zip
  cleanup

  #Verify if go is configured correctly
  if go version | grep -q "$PACKAGE_VERSION"
  then
    printf -- "Installed %s %s successfully \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" | tee -a  "$LOG_FILE"
  else
    printf -- "Error while installing Go, exiting with 127 \n";
    exit 127;
  fi
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
    printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" | tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
  echo 
  echo "Usage: "
  echo "  install.sh [-s <silent>] [-d <debug>] [-v package-version] [-o override] [-p check-prequisite]"
  echo "       default: If no -v specified, latest version will be installed"
  echo
}

while getopts "h?dopv:" opt; do
  case "$opt" in
  h | \?)
    printHelp
    exit 0
    ;;
  d)
    set -x
    ;;
  v)
    PACKAGE_VERSION="$OPTARG"
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

function printSummary()
{
  
  printf -- "\n\nUsage: \n"
  printf -- "  Set GOROOT and GOPATH to get started \n"
  printf -- "  More information can be found here : https://golang.org/cmd/go/ \n"
  printf -- '\n'
}

###############################################################################################################

logDetails
checkPrequisites  #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
  sudo apt-get update > /dev/null

  if [[ "${VERSION_ID}" == "18.04" ]] 
  then
    printf -- 'Detected 18.04 version hence installing from repository \n' | tee -a "$LOG_FILE"
    printf -- 'Installing golang from repository' | tee -a "$LOG_FILE"
    sudo apt-get install -y -qq golang > /dev/null
 
 else
    printf -- 'Installing the dependencies for Go from repository \n' | tee -a "$LOG_FILE"
    sudo apt-get install -y -qq wget tar gcc > /dev/null
    configureAndInstall 
  fi
  ;;

"rhel-7.3" | "rhel-7.4" | "rhel-7.5" | "rhel-6.x")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
  printf -- 'Installing the dependencies for Go from repository \n' | tee -a "$LOG_FILE"
  sudo yum install -y -q tar wget gcc  > /dev/null
  configureAndInstall
  ;;

"sles-12.3" | "sles-15")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
  printf -- 'Installing the dependencies for Go from repository \n' | tee -a "$LOG_FILE"
  sudo zypper -q install -y  tar wget gcc > /dev/null
  configureAndInstall
  ;;

*)
  printf -- "%s not supported \n" "$DISTRO"| tee -a "$LOG_FILE"
  exit 1 ;;
esac

printSummary
