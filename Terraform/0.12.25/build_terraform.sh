#!/bin/bash
# © Copyright IBM Corporation 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Terraform/0.12.25/build_terraform.sh
# Execute build script: bash build_terraform.sh    (provide -h for help)
#

set -e -o pipefail

PACKAGE_NAME="terraform"
PACKAGE_VERSION="0.12.25"
LOG_FILE="$(pwd)/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
OVERRIDE=false

export GOPATH="$(pwd)"
FORCE="false"

trap cleanup 1 2 ERR

#Check if directory exsists
if [ ! -d "logs" ]; then
   mkdir -p "logs"
fi


# Need handling for os-release file
if [ -f "/etc/os-release" ]; then
        source "/etc/os-release"
else
        printf -- '/etc/os-release file does not exist.' >> "$LOG_FILE"
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

  if command -v "terraform" > /dev/null ;
  then
    printf -- "terraform : Yes" >>  "$LOG_FILE"

    if terraform version | grep "Terraform v$PACKAGE_VERSION"
    then
      printf -- "Version : %s (Satisfied) \n" "v${PACKAGE_VERSION}" |& tee -a  "$LOG_FILE"
      printf -- "No update required for terraform \n" |& tee -a  "$LOG_FILE"
      exit 0;
    fi
  fi;

  if [[ "$FORCE" == "true" ]] ;
    then
        printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
    else
        # Ask user for prerequisite installation
        printf -- "\nAs part of the installation , dependencies would be installed/upgraded.\n";
        while true; do
                    read -r -p "Do you want to continue (y/n) ? :  " yn
                    case $yn in
                            [Yy]* ) printf -- 'User responded with Yes. \n' >> "$LOG_FILE";
                            break;;
                    [Nn]* ) exit;;
                    *)  echo "Please provide confirmation to proceed.";;
                    esac
        done
  fi;

}

function cleanup()
{
  if [ -d "${GOPATH}/src" ]; then
    sudo rm -rf ${GOPATH}/src
  fi
  printf -- 'Cleaned up the artifacts\n'  >> "$LOG_FILE"
}

function installGo()
{
  # Install Go
  printf -- 'Installing go\n' |& tee -a "$LOG_FILE"
  cd "${GOPATH}"
  wget "https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Go/1.14.2/build_go.sh"
  bash build_go.sh -y -v 1.14.2
  go version  |& tee -a "$LOG_FILE"
  printf -- 'go installed\n' |& tee -a "$LOG_FILE"
  #set environment variables
  export PATH=$GOPATH/bin:$PATH
}

function configureAndInstall()
{
  printf -- 'Configuration and Installation started \n'

  if [[ "${OVERRIDE}" == "true" ]]
  then
    printf -- 'Terraform exists on the system. Override flag is set to true hence updating the same\n '
  fi

  printf -- "Gopath is set to  %s \n" "$GOPATH"

  #Download and install terraform
  cd "${GOPATH}"
  printf -- 'Downloading Terraform binaries \n'
  export GO111MODULE=on
  export GOPROXY=https://proxy.golang.org/
  mkdir -p $GOPATH/src/github.com/hashicorp
  cd $GOPATH/src/github.com/hashicorp
  git clone https://github.com/hashicorp/terraform.git
  cd terraform/
  git checkout v"${PACKAGE_VERSION}"

  printf -- 'Compiling the code and then Running test \n'
  set +e
  make 2>&1| tee -a test_logs
  cat test_logs | grep "FAIL" | grep github.com | awk '{print $2}' >> test.txt
  if [ -s $GOPATH/src/github.com/hashicorp/terraform/test.txt ]; then
        printf -- '**********************************************************************************************************\n'
        grep -c "github.com" test.txt
        if [ $? == 1 ]; then
          grep "github.com/hashicorp/terraform/internal/getproviders" $GOPATH/src/github.com/hashicorp/terraform/test.txt
          printf -- '\ngithub.com/hashicorp/terraform/internal/getproviders test module is failing on intel too, and can be ignored.'
        else
          printf -- '\nTest failures detected. Tip : Try running the individual module as go test -v <test_module>
          or increasing the timeout using -timeout option to go test command\n'
          if cat $GOPATH/src/github.com/hashicorp/terraform/test.txt | grep -q "github.com/hashicorp/terraform/internal/getproviders"; then
            printf -- '\ngithub.com/hashicorp/terraform/internal/getproviders test module is failing on intel too, and can be ignored.'
          fi
        fi
        printf -- '\n**********************************************************************************************************\n'
  fi
  #Creating binary at location $GOPATH/src/github.com/hashicorp/terraform/pkg/linux_s390x/
  XC_OS=linux XC_ARCH=s390x make bin
  printf -- ' Creating binary at location "${GOPATH}"/src/github.com/hashicorp/terraform/pkg/linux_s390x/ \n'
  printf -- " Copying binary to /usr/bin \n"
  sudo mv ${GOPATH}/src/github.com/hashicorp/terraform/pkg/linux_s390x/terraform /usr/bin/

  if [ ! -s $GOPATH/src/github.com/hashicorp/terraform/test.txt ]; then
        cleanup
  fi
  set -e
  printf -- "Installed %s %s successfully \n" "$PACKAGE_NAME" "$PACKAGE_VERSION"
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
  echo "  build_terraform.sh [-d debug] [-y install-without-confirmation]"
  echo
}

while getopts "h?dy" opt; do
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
  esac
done

function gettingStarted()
{
  printf -- "\n\nUsage: \n"
  printf -- "  Run terraform --help to get all options. \n"
  printf -- "  More information can be found here : https://github.com/hashicorp/terraform \n"
  printf -- '\n'
}

###############################################################################################################

logDetails
checkPrequisites  #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04" | "ubuntu-20.04")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  sudo apt-get update > /dev/null
  sudo apt-get install -y git wget make zip tar gcc |& tee -a "${LOG_FILE}"
  installGo
  configureAndInstall |& tee -a "${LOG_FILE}"
  ;;

"rhel-7.6" | "rhel-7.7" | "rhel-7.8")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  printf -- 'Installing the dependencies for Terraform from repository \n' |& tee -a "$LOG_FILE"
  sudo yum install -y git wget make zip which tar gcc |& tee -a "${LOG_FILE}"
  installGo
  configureAndInstall |& tee -a "${LOG_FILE}"
  ;;

"rhel-8.1" | "rhel-8.2")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  printf -- 'Installing the dependencies for Terraform from repository \n' |& tee -a "$LOG_FILE"
  sudo yum install -y git wget make zip which tar gcc diffutils |& tee -a "${LOG_FILE}"
  installGo
  configureAndInstall |& tee -a "${LOG_FILE}"
  ;;

"sles-12.4" | "sles-12.5" |  "sles-15.1")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  printf -- 'Installing the dependencies for Terraform from repository \n' |& tee -a "$LOG_FILE"
  sudo zypper install -y git wget tar make zip which gawk gzip tar gcc |& tee -a "${LOG_FILE}"
  installGo
  configureAndInstall |& tee -a "${LOG_FILE}"
  ;;

*)
  printf -- "%s not supported \n" "$DISTRO"|& tee -a "$LOG_FILE"
  exit 1 ;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
