#!/bin/bash
# © Copyright IBM Corporation 2024.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Terraform/1.9.0/build_terraform.sh
# Execute build script: bash build_terraform.sh    (provide -h for help)
#

set -e -o pipefail

PACKAGE_NAME="terraform"
PACKAGE_VERSION="1.9.0"
GO_VERSION="1.22.4"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Terraform/${PACKAGE_VERSION}/patch"
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
  printf -- '/etc/os-release file does not exist.' >>"$LOG_FILE"
fi

function checkPrequisites() {
  if command -v "sudo" >/dev/null; then
    printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
  else
    printf -- 'Sudo : No \n' >>"$LOG_FILE"
    printf -- 'You can install sudo from repository using apt, yum or zypper based on your distro. \n'
    exit 1
  fi

  if command -v "terraform" >/dev/null; then
    if terraform version | grep "Terraform v$PACKAGE_VERSION"; then
      printf -- "Version : %s (Satisfied) \n" "v${PACKAGE_VERSION}" >>"$LOG_FILE"
      printf -- "No update required for terraform \n" |& tee -a "$LOG_FILE"
      exit 0
    fi
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
  rm -rf "$GOPATH/go${GO_VERSION}.linux-s390x.tar.gz"
  printf -- 'Cleaned up the artifacts\n' >>"$LOG_FILE"
}

function installgo() {
  # Install Go
  printf -- 'Downloading go binaries \n'
  wget -q https://storage.googleapis.com/golang/go"${GO_VERSION}".linux-s390x.tar.gz |& tee -a  "$LOG_FILE"
  chmod ugo+r go"${GO_VERSION}".linux-s390x.tar.gz


  sudo rm -rf /usr/local/go /usr/bin/go
  sudo tar -C /usr/local -xzf go"${GO_VERSION}".linux-s390x.tar.gz

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
  if go version | grep -q "$GO_VERSION"
  then
    printf -- "Installed Go %s successfully \n" "$GO_VERSION"
  else
    printf -- "Error while installing Go, exiting with 127 \n";
    exit 127;
  fi
}

function configureAndInstall() {
  printf -- 'Configuration and Installation started \n'
  printf -- "Gopath is set to  %s \n" "$GOPATH"

  # Install Go
  printf -- 'Installing Go...\n'
  cd ${GOPATH}
  installgo
  go version
  printf -- "Install Go success\n"

  #Download and install terraform
  export PATH=$GOPATH/bin:$PATH
  mkdir -p $GOPATH/src/github.com/hashicorp
  cd $GOPATH/src/github.com/hashicorp
  git clone -b v"${PACKAGE_VERSION}" https://github.com/hashicorp/terraform.git
  cd terraform/
  go install .
  printf -- " Copying binary to /usr/bin \n"
  sudo cp ${GOPATH}/bin/terraform /usr/bin/
  terraform -version
  printf -- "Installed %s %s successfully \n" "$PACKAGE_NAME" "$PACKAGE_VERSION"

  #Run Test
  runTests

  cleanup

}

function run_e2e_tests() {
  printf -- 'Download and build necessary terraform provider plugins locally\n'
  PROVIDER_PLUGIN_LOCAL_MIRROR_PATH="$HOME/.terraform.d/plugins"
  mkdir -p $PROVIDER_PLUGIN_LOCAL_MIRROR_PATH

  cd $GOPATH/src/github.com/hashicorp
  git clone https://github.com/hashicorp/terraform-provider-null.git
  cd terraform-provider-null
  git checkout v3.2.2
  go build
  BIN_PATH="${PROVIDER_PLUGIN_LOCAL_MIRROR_PATH}/registry.terraform.io/hashicorp/null/3.2.2/linux_s390x"
  mkdir -p $BIN_PATH
  mv terraform-provider-null $BIN_PATH/terraform-provider-null_v3.2.2
  git checkout v3.1.0
  go build
  mv terraform-provider-null terraform-provider-null_v3.1.0_x5
  zip terraform-provider-null_3.1.0_linux_s390x.zip terraform-provider-null_v3.1.0_x5
  mv terraform-provider-null_3.1.0_linux_s390x.zip $PROVIDER_PLUGIN_LOCAL_MIRROR_PATH/registry.terraform.io/hashicorp/null/
  git checkout v2.1.0
  go build
  BIN_PATH="${PROVIDER_PLUGIN_LOCAL_MIRROR_PATH}/registry.terraform.io/hashicorp/null/2.1.0/linux_s390x"
  mkdir -p $BIN_PATH
  mv terraform-provider-null $BIN_PATH/terraform-provider-null_v2.1.0_x4
  BIN_PATH="${PROVIDER_PLUGIN_LOCAL_MIRROR_PATH}/registry.terraform.io/hashicorp/null/1.0.0+local/linux_s390x"
  mkdir -p $BIN_PATH
  cp $GOPATH/src/github.com/hashicorp/terraform/internal/command/e2etest/testdata/vendored-provider/terraform.d/plugins/registry.terraform.io/hashicorp/null/1.0.0+local/os_arch/terraform-provider-null_v1.0.0 $BIN_PATH/

  cd $GOPATH/src/github.com/hashicorp
  git clone https://github.com/hashicorp/terraform-provider-aws.git
  cd terraform-provider-aws
  git checkout v5.4.0
  go build
  BIN_PATH="${PROVIDER_PLUGIN_LOCAL_MIRROR_PATH}/registry.terraform.io/hashicorp/aws/5.4.0/linux_s390x"
  mkdir -p $BIN_PATH
  mv terraform-provider-aws $BIN_PATH/terraform-provider-aws_v5.4.0

  cd $GOPATH/src/github.com/hashicorp
  git clone https://github.com/hashicorp/terraform-provider-template.git
  cd terraform-provider-template
  git checkout v2.2.0
  go build
  BIN_PATH="${PROVIDER_PLUGIN_LOCAL_MIRROR_PATH}/registry.terraform.io/hashicorp/template/2.2.0/linux_s390x"
  mkdir -p $BIN_PATH
  mv terraform-provider-template $BIN_PATH/terraform-provider-template_v2.2.0
  BIN_PATH="${PROVIDER_PLUGIN_LOCAL_MIRROR_PATH}/registry.terraform.io/hashicorp/template/2.1.0/linux_s390x"
  mkdir -p $BIN_PATH
  mv $GOPATH/src/github.com/hashicorp/terraform/internal/command/e2etest/testdata/plugin-cache/cache/registry.terraform.io/hashicorp/template/2.1.0/os_arch/terraform-provider-template_v2.1.0_x4 $BIN_PATH/

  BIN_PATH="${PROVIDER_PLUGIN_LOCAL_MIRROR_PATH}/example.com/awesomecorp/happycloud/1.2.0/linux_s390x"
  mkdir -p $BIN_PATH
  mv $GOPATH/src/github.com/hashicorp/terraform/internal/command/e2etest/testdata/local-only-provider/terraform.d/plugins/example.com/awesomecorp/happycloud/1.2.0/os_arch/terraform-provider-happycloud_v1.2.0 $BIN_PATH/

  printf -- 'Update CLI configurations to use locally built provider plugins \n'
  cd $HOME
  wget ${PATCH_URL}/.terraformrc
  sed -i "s#HOME__PATH#$HOME#g" .terraformrc

  printf -- 'Running e2e tests now \n'
  cd $GOPATH/src/github.com/hashicorp/terraform
  TF_ACC=1 go test -v ./internal/command/e2etest

  mv $HOME/.terraformrc $HOME/.terraformrc.e2etest
}

function runTests() {
  set +e
  if [[ "$TESTS" == "true" ]]; then
    printf -- 'Running tests \n\n'
    cd $GOPATH/src/github.com/hashicorp/terraform
    printf -- 'Running unit tests \n'
    go test -v ./...
    printf -- 'Unit tests complete\n\n'
    printf -- 'Running race tests \n'
    go test -race ./internal/terraform ./internal/command ./internal/states
    printf -- 'Race tests complete\n\n'
    printf -- 'Running e2e tests \n'
    run_e2e_tests
    printf -- 'E2E tests complete\n\n'
    printf -- '**********************************************************************************************************\n'
    printf -- '\nIn case of unexpected test failures try running the test individually using command go test -v <package_name> -run <failed_test_name>\n'
    printf -- '**********************************************************************************************************\n'
  fi
  set -e
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
function printHelp() {
  echo
  echo "Usage: "
  echo "bash build_terraform.sh [-d debug] [-y install-without-confirmation] [-t run-test-cases]"
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

function gettingStarted() {

  printf -- "\n\nUsage: \n"
  printf -- "  Run terraform --help to get all options. \n"
  printf -- "  More information can be found here : https://github.com/hashicorp/terraform \n"
  printf -- '\n'
}

###############################################################################################################

logDetails
checkPrequisites #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-20.04" | "ubuntu-22.04" | "ubuntu-23.10" | "ubuntu-24.04")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  sudo apt-get update >/dev/null
  sudo apt-get install -y git wget tar gcc zip unzip |& tee -a "${LOG_FILE}"
  configureAndInstall |& tee -a "${LOG_FILE}"
  ;;

"rhel-8.8" | "rhel-8.9" | "rhel-8.10" | "rhel-9.2" | "rhel-9.3" | "rhel-9.4")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  printf -- 'Installing the dependencies for Terraform from repository \n' |& tee -a "$LOG_FILE"
  sudo yum install -y git wget tar gcc diffutils zip unzip |& tee -a "${LOG_FILE}"
  configureAndInstall |& tee -a "${LOG_FILE}"
  ;;

"sles-12.5" | "sles-15.5")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  printf -- 'Installing the dependencies for Terraform from repository \n' |& tee -a "$LOG_FILE"
  sudo zypper install -y git-core wget tar gcc gzip zip unzip |& tee -a "${LOG_FILE}"
  configureAndInstall |& tee -a "${LOG_FILE}"
  ;;

*)
  printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
  exit 1
  ;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
