#!/usr/bin/env bash
# © Copyright IBM Corporation 2018, 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Go/1.13.5/build_go.sh
# Execute build script: bash build_go.sh    (provide -h for help)
#


set -e -o pipefail

PACKAGE_NAME="go"
PACKAGE_VERSION="1.13.5"
LOG_FILE="logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
OVERRIDE=false
FORCE="false"
trap cleanup 1 2 ERR

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
    printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n';
    exit 1;
  fi;

  if command -v "go" > /dev/null ;
  then
    printf -- "Go : Yes" >>  "$LOG_FILE"

    if go version | grep -q "$PACKAGE_VERSION" 
    then
      printf -- "Version : %s (Satisfied) \n" "${PACKAGE_VERSION}" |& tee -a  "$LOG_FILE"
      printf -- "No update required for Go \n" |& tee -a  "$LOG_FILE"
      exit 0;
    fi
  fi;
}

function cleanup()
{
  rm -rf go"${PACKAGE_VERSION}".linux-s390x.tar.gz*
  printf -- 'Cleaned up the artifacts\n'  >> "$LOG_FILE"
}

function configureAndInstall()
{
  printf -- 'Configuration and Installation started \n'

  if [[ "${OVERRIDE}" == "true" ]]
  then
    printf -- 'Go exists on the system. Override flag is set to true hence updating the same\n ' |& tee -a "$LOG_FILE"
  fi

  # Install Go
  printf -- 'Downloading go binaries \n'
  wget -q https://storage.googleapis.com/golang/go"${PACKAGE_VERSION}".linux-s390x.tar.gz |& tee -a  "$LOG_FILE"
  chmod ugo+r go"${PACKAGE_VERSION}".linux-s390x.tar.gz


  sudo rm -rf /usr/local/go /usr/bin/go
  sudo tar -C /usr/local -xzf go"${PACKAGE_VERSION}".linux-s390x.tar.gz

  sudo ln -sf /usr/local/go/bin/go /usr/bin/ 
  sudo ln -sf /usr/local/go/bin/gofmt /usr/bin/

  printf -- 'Extracted the tar in /usr/local and created symlink\n'

  if [[ "${ID}" != "ubuntu" ]]
  then
    sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc 
    printf -- 'Symlink done for gcc \n' 
  fi

  #Clean up the downloaded zip
  cleanup

  #Verify if go is configured correctly
  if go version | grep -q "$PACKAGE_VERSION"
  then
    printf -- "Installed %s %s successfully \n" "$PACKAGE_NAME" "$PACKAGE_VERSION"
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
    printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" |& tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
  echo 
  echo "Usage: "
  echo "  install.sh [-d debug] [-v package-version] [-o override] [-p check-prequisite] [-y install-without-confirmation]"
  echo "       default: If no -v specified, latest version will be installed"
  echo
}

while getopts "h?dopyv:" opt; do
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
  y)
    FORCE="true"
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
  printf -- "  Set GOROOT and GOPATH to get started \n"
  printf -- "  More information can be found here : https://golang.org/cmd/go/ \n"
  printf -- '\n'
}

###############################################################################################################

logDetails
checkPrequisites  #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04" | "ubuntu-19.10")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  sudo apt-get update > /dev/null
  sudo apt-get install -y  wget tar gcc |& tee -a "${LOG_FILE}"
  configureAndInstall |& tee -a "${LOG_FILE}"
  ;;

"rhel-7.5" | "rhel-7.6" | "rhel-7.7" | "rhel-8.0" | "rhel-8.1")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for Go from repository \n' |& tee -a "$LOG_FILE"
	sudo yum install -y  tar wget gcc  |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
  ;;

"sles-12.4" | "sles-15.1")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for Go from repository \n' |& tee -a "$LOG_FILE"
	sudo zypper  install -y  tar wget gcc gzip |& tee -a "${LOG_FILE}" 
	configureAndInstall |& tee -a "${LOG_FILE}"
  ;;

*)
  printf -- "%s not supported \n" "$DISTRO"|& tee -a "$LOG_FILE"
  exit 1 ;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
