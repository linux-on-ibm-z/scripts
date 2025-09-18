#!/bin/bash
# © Copyright IBM Corporation 2025.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Fluentd/1.19.0/build_fluentd.sh
# Execute build script: bash build_fluentd.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="fluentd"
PACKAGE_VERSION="1.19.0"
CURDIR="$(pwd)"

RUBY_INSTALL_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Ruby/3.4.5/build_ruby.sh"

FORCE="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
    mkdir -p "$CURDIR/logs/"
fi

if [ -f "/etc/os-release" ]; then
    source "/etc/os-release"
fi

function prepare() {
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
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function install_ruby() {
    # Install ruby
    wget $RUBY_INSTALL_URL && bash build_ruby.sh -y
    printf -- "Installed Ruby successfully \n" |& tee -a "$LOG_FILE"
    if [[ "${ID}" == "rhel" ]]; then
        export GEM_HOME=$HOME/.gem/ruby
        export PATH=$HOME/.gem/ruby/bin:$PATH
    fi
    echo $PATH

}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"
    echo $PATH
    if [[ "${ID}" == "ubuntu" ]]; then
        printf -- "Install gems for ubuntu\n"
        #Download fluentd
        sudo gem install ${PACKAGE_NAME} -v ${PACKAGE_VERSION}
        
    elif [[ "${ID}" == "sles" ]]; then
        printf -- "Install gems for sles \n"
        #Download fluentd
        export PATH="$PATH:/usr/local/bin"
        #Install gems
        sudo env PATH=$PATH gem install ${PACKAGE_NAME} -v ${PACKAGE_VERSION}
        
    else 
        printf -- "Install gems \n"
        #Download fluentd
        export PATH="$PATH:/usr/local/bin"
        #Install gems
        gem install ${PACKAGE_NAME} -v ${PACKAGE_VERSION}
    fi
    printf -- "Installation of fluentd completed\n"

    #Verify fluentd installation
    if command -v "fluentd" >/dev/null; then
        printf -- " %s Installation verified.\n" "$PACKAGE_NAME"
    else
        printf -- "Error while installing %s, exiting with 127 \n" "$PACKAGE_NAME"
        exit 127
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
function printHelp() {
    echo
    echo "Usage: "
    echo " bash build_fluentd.sh  [-d debug] [-y install-without-confirmation] "
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

function gettingStarted() {
    printf -- '\n********************************************************************************************************\n'
    printf -- "\n*Getting Started * \n"

    if [[ "${ID}" == "rhel" ]]; then
    printf -- "\nSet GEM_HOME and PATH to start using fluentd.\n"
    printf -- "\texport GEM_HOME=$HOME/.gem/ruby\n"
    printf -- "\t"
    printf -- 'export PATH=$HOME/.gem/ruby/bin:$PATH'
    printf -- "\n\n"
    fi

    printf -- "Installing fluentd Configuration file:\n"
    printf -- "fluentd -s conf \n\n"   
    printf -- "Running fluentd: \n"
    printf -- "fluentd -c conf/fluent.conf  \n\n"
    printf -- "You have successfully started fluentd.\n"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"rhel-8.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y wget
    install_ruby
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-9.4" | "rhel-9.6" | "rhel-10.0")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y rpmdevtools zlib-devel zlib wget |& tee -a "$LOG_FILE"
    install_ruby
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-15.6")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y gzip awk zlib-devel wget |& tee -a "$LOG_FILE"
    install_ruby
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"ubuntu-22.04" | "ubuntu-24.04" | "ubuntu-25.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y zlib1g-dev wget |& tee -a "$LOG_FILE"
    install_ruby
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
