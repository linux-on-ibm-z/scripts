#!/bin/bash
# © Copyright IBM Corporation 2021.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Terraform/1.0.7/build_terraform.sh
# Execute build script: bash build_terraform.sh    (provide -h for help)
#

set -e -o pipefail

PACKAGE_NAME="terraform"
PACKAGE_VERSION="1.0.7"
GO_VERSION="1.16.5"
LOG_FILE="$(pwd)/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
FORCE="false"
TESTS="false"

export GOPATH="$(pwd)"

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
    printf -- 'You can install sudo from repository using apt, yum or zypper based on your distro. \n';
    exit 1;
  fi;

  if command -v "terraform" > /dev/null; then
      if terraform version | grep "Terraform v$PACKAGE_VERSION"
      then
        printf -- "Version : %s (Satisfied) \n" "v${PACKAGE_VERSION}" >>  "$LOG_FILE"
        printf -- "No update required for terraform \n" |& tee -a  "$LOG_FILE"
        exit 0;
      fi
  fi

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
  rm -rf "$GOPATH/go${GO_VERSION}.linux-s390x.tar.gz"
  printf -- 'Cleaned up the artifacts\n'  >> "$LOG_FILE"
}

function configureAndInstall()
{
  printf -- 'Configuration and Installation started \n'
  printf -- "Gopath is set to  %s \n" "$GOPATH"

  # Install go
  if [[ "${DISTRO}" != "sles-15.3" ]]
  then
    printf -- 'Installing Go...\n'
    cd ${GOPATH}
    wget https://golang.org/dl/go${GO_VERSION}.linux-s390x.tar.gz
    chmod ugo+r go${GO_VERSION}.linux-s390x.tar.gz
    sudo tar -C /usr/local -xvzf go${GO_VERSION}.linux-s390x.tar.gz
    export PATH=/usr/local/go/bin:$PATH
    if [[ "${ID}" == "rhel" ]] || [[ "${ID}" == "sles" ]] ; 
    then
      sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
    fi 
  fi
  go version

  #Download and install terraform
  export PATH=$GOPATH/bin:$PATH
  mkdir -p $GOPATH/src/github.com/hashicorp
  cd $GOPATH/src/github.com/hashicorp
  git clone https://github.com/hashicorp/terraform.git
  cd terraform/
  git checkout v"${PACKAGE_VERSION}"
  go install .
  printf -- " Copying binary to /usr/bin \n"
  sudo cp ${GOPATH}/bin/terraform /usr/bin/
  terraform -version
  printf -- "Installed %s %s successfully \n" "$PACKAGE_NAME" "$PACKAGE_VERSION"

  #Run Test
  runTests

  cleanup

}

function runTests() {
  set +e
  if [[ "$TESTS" == "true" ]]; then
	printf -- 'Running test \n'
	go test ./...
	printf -- '**********************************************************************************************************\n'
	printf -- '\nIn case of unexpected test failures try running the test individually using command go test -v <package_name> -run <failed_test_name>\n'
	printf -- '**********************************************************************************************************\n'
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
  echo "  build_terraform.sh [-d debug] [-y install-without-confirmation] [-t run-test-cases]"
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
"ubuntu-18.04" | "ubuntu-20.04" | "ubuntu-21.04")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  sudo apt-get update > /dev/null
  sudo apt-get install -y git wget tar gcc |& tee -a "${LOG_FILE}"
  configureAndInstall |& tee -a "${LOG_FILE}"
  ;;

"rhel-7.8" | "rhel-7.9")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  printf -- 'Installing the dependencies for Terraform from repository \n' |& tee -a "$LOG_FILE"
  sudo yum install -y git wget tar gcc |& tee -a "${LOG_FILE}"
  configureAndInstall |& tee -a "${LOG_FILE}"
  ;;

"rhel-8.2" | "rhel-8.3" | "rhel-8.4")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  printf -- 'Installing the dependencies for Terraform from repository \n' |& tee -a "$LOG_FILE"
  sudo yum install -y git wget tar gcc diffutils |& tee -a "${LOG_FILE}"
  configureAndInstall |& tee -a "${LOG_FILE}"
  ;;

"sles-12.5" | "sles-15.2")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  printf -- 'Installing the dependencies for Terraform from repository \n' |& tee -a "$LOG_FILE"
  sudo zypper install -y git-core wget tar gcc gzip |& tee -a "${LOG_FILE}"
  configureAndInstall |& tee -a "${LOG_FILE}"
  ;;
  
"sles-15.3")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  printf -- 'Installing the dependencies for Terraform from repository \n' |& tee -a "$LOG_FILE"
  sudo zypper install -y git-core wget tar gcc gzip go1.16 |& tee -a "${LOG_FILE}"
  configureAndInstall |& tee -a "${LOG_FILE}"
  ;;

*)
  printf -- "%s not supported \n" "$DISTRO"|& tee -a "$LOG_FILE"
  exit 1 ;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
