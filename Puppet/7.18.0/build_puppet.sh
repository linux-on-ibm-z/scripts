#!/usr/bin/env bash
# © Copyright IBM Corporation 2022.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Puppet/7.18.0/build_puppet.sh
# Execute build script: bash build_puppet.sh    (provide -h for help)

set -e -o pipefail

SOURCE_ROOT="$(pwd)"
PACKAGE_NAME="Puppet"
PACKAGE_VERSION="7.18.0"
SERVER_VERSION="7.9.0"
AGENT_VERSION="7.18.0"
RUBY_VERSION="2.7"
RUBY_FULL_VERSION="2.7.6"
JAVA_PROVIDED="Eclipse_Adoptium_Temurin_runtime_11"
FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

TEMURIN_JDK11_URL="https://github.com/adoptium/temurin11-binaries/releases/download/jdk-11.0.15%2B10/OpenJDK11U-jdk_s390x_linux_hotspot_11.0.15_10.tar.gz"
SEMERU_JDK11_URL="https://github.com/ibmruntimes/semeru11-certified-binaries/releases/download/jdk-11.0.15%2B10_openj9-0.32.0/ibm-semeru-certified-jdk_s390x_linux_11.0.15.0.tar.gz"

trap cleanup 1 2 ERR

function cleanup() {
        if [[ -f "ruby"-${RUBY_FULL_VERSION}.tar.gz ]]; then
                sudo rm "ruby"-${RUBY_FULL_VERSION}.tar.gz
        fi
        if [[ -f adoptium.tar.gz ]]; then
                sudo rm adoptium.tar.gz
        fi
        if [[ -f semeru.tar.gz ]]; then
                sudo rm semeru.tar.gz
        fi
        printf -- '\nCleaned up the artifacts.\n' >>"$LOG_FILE"
}

# Print the usage message
function printHelp() {
        echo
        echo "Usage: "
        echo "  bash build_puppet.sh [-s server/agent] [-j Java to be used from {Eclipse_Adoptium_Temurin_runtime_11, OpenJDK11, SemeruJDK11}] "
        echo
}

function checkPrequisites() {
        printf -- "Checking Prequisites\n"

        if [ -z "$USEAS" ]; then
                printf "Option -s must be specified with argument server/agent \n"
                exit
        fi

        if command -v "sudo" >/dev/null; then
                printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
        else
                printf -- 'Sudo : No \n' >>"$LOG_FILE"
                printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n'
                exit 1
        fi

        if [[ "$JAVA_PROVIDED" != "Eclipse_Adoptium_Temurin_runtime_11" && "$JAVA_PROVIDED" != "OpenJDK11" && "$JAVA_PROVIDED" != "SemeruJDK11" ]]; then
                printf "$JAVA_PROVIDED is not supported, Please use valid java from {Eclipse_Adoptium_Temurin_runtime_11, OpenJDK11, SemeruJDK11} only"
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

function buildAgent() {
        #Install Puppet
        cd "$SOURCE_ROOT"
        sudo -E env PATH="$PATH" gem install puppet -v $AGENT_VERSION

        if [[ "$DISTRO" == "sles-15.3" || "$DISTRO" == "sles-15.4" ]]; then
                sudo ln -s /usr/lib64/ruby/gems/2.5.0/gems/puppet-$AGENT_VERSION/bin/puppet /usr/local/bin/puppet
        fi
        printf -- 'Completed Puppet agent setup \n'
}

function buildServer() {
        printf -- 'Build puppetserver and Installation started \n'

        if [[ "$JAVA_PROVIDED" == "Eclipse_Adoptium_Temurin_runtime_11" ]]; then
                # Install Eclipse Adoptium Temurin Runtime (Java 11)
                cd $SOURCE_ROOT
                wget -O adoptium.tar.gz ${TEMURIN_JDK11_URL}
                mkdir -p adoptium11
                tar -zxvf adoptium.tar.gz -C adoptium11/ --strip-components 1
                export JAVA_HOME=$SOURCE_ROOT/adoptium11
                printf -- "Installation of Eclipse_Adoptium_Temurin_runtime_11 is successful\n" >> "$LOG_FILE"

        elif [[ "$JAVA_PROVIDED" == "OpenJDK11" ]]; then
                if [[ "${ID}" == "ubuntu" ]]; then
                        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-11-jdk
                        export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x
                elif [[ "${ID}" == "rhel" ]]; then
                        sudo yum install -y java-11-openjdk-devel
                        export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
                elif [[ "${ID}" == "sles" ]]; then
                        sudo zypper install -y java-11-openjdk-devel
                        export JAVA_HOME=/usr/lib64/jvm/java-11-openjdk-11
                fi
                printf -- "Installation of OpenJDK 11 is successful\n" >> "$LOG_FILE"

        elif [[ "$JAVA_PROVIDED" == "SemeruJDK11" ]]; then
                # Install Semeru Runtime (Java 11)
                cd $SOURCE_ROOT
                wget -O semeru.tar.gz ${SEMERU_JDK11_URL}
                mkdir -p semeru11
                tar -zxvf semeru.tar.gz -C semeru11/ --strip-components 1
                export JAVA_HOME=$SOURCE_ROOT/semeru11
                printf -- "Installation of SemeruJDK11 is successful\n" >> "$LOG_FILE"

        else
                printf "$JAVA_PROVIDED is not supported, Please use valid java from {Eclipse_Adoptium_Temurin_runtime_11, OpenJDK11} only"
                exit 1
        fi

        export PATH=$JAVA_HOME/bin:$PATH

        printf -- 'Install lein \n'
        cd $SOURCE_ROOT
        wget https://raw.githubusercontent.com/technomancy/leiningen/stable/bin/lein
        chmod +x lein
        sudo mv lein /usr/bin/

        printf -- 'Get puppetserver \n'
        cd $SOURCE_ROOT
        git clone --recursive --branch $SERVER_VERSION https://github.com/puppetlabs/puppetserver
        cd puppetserver

        printf -- 'Setup config files \n'
        export LANG="en_US.UTF-8"
        ./dev-setup

        printf -- 'Completed Puppet server setup \n'

        runTest

}

function runTest() {
        set +e
        if [[ "$TEST" == "true" ]]; then
        printf -- "TEST Flag is set, continue with running test \n"
                cd $SOURCE_ROOT/puppetserver
                PUPPETSERVER_HEAP_SIZE=6G lein test
        printf -- "Test suite execution completed \n"
        fi
        set -e
}

function configureAndInstall() {
        printf -- 'Configuration and Installation started \n'
        # Download and install Ruby
        if [[ "$DISTRO" == "rhel-7.8" || "$DISTRO" == "rhel-7.9" || "$DISTRO" == "sles-12.5" ]]; then
                cd "$SOURCE_ROOT"
                wget http://cache.ruby-lang.org/pub/ruby/$RUBY_VERSION/ruby-$RUBY_FULL_VERSION.tar.gz
                # Avoid conflict when script runs twice
                rm -rf ruby-$RUBY_FULL_VERSION
                tar -xzf ruby-$RUBY_FULL_VERSION.tar.gz
                cd ruby-$RUBY_FULL_VERSION
                ./configure && make && sudo -E env PATH="$PATH" make install
        fi

        # Install bundler
        sudo -E env PATH="$PATH" gem install bundler rake-compiler

        # Build server or agent
        if [ "$USEAS" = "server" ]; then
                buildServer
        elif [ "$USEAS" = "agent" ]; then
                buildAgent
        else
                printf -- "please enter the argument (server/agent) with option -s "
                exit
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

function gettingStarted() {
        # Need to retrieve $JAVA_HOME for final output
        if [[ "$JAVA_PROVIDED" == "Eclipse_Adoptium_Temurin_runtime_11" ]]; then
                JAVA_HOME=$SOURCE_ROOT/adoptium11
        elif [[ "$JAVA_PROVIDED" == "OpenJDK11" ]]; then
                if [[ "${ID}" == "ubuntu" ]]; then
                        JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x
                elif [[ "${ID}" == "rhel" ]]; then
                        JAVA_HOME=/usr/lib/jvm/java-11-openjdk
                elif [[ "${ID}" == "sles" ]]; then
                        JAVA_HOME=/usr/lib64/jvm/java-11-openjdk-11
                fi
        elif [[ "$JAVA_PROVIDED" == "SemeruJDK11" ]]; then
                JAVA_HOME=$SOURCE_ROOT/semeru11
        fi

        printf -- "Puppet installed successfully. \n"
        if [ "$USEAS" = "server" ]; then
                printf -- '\n'
                printf -- "     To run Puppet server, set the environment variables below and follow from step 2.10 in build instructions.\n"
                printf -- "             export JAVA_HOME=$JAVA_HOME\n"
                printf -- "             export PATH=\$JAVA_HOME/bin:\$PATH\n"
                printf -- '\n'
        elif [ "$USEAS" = "agent" ]; then
                printf -- '\n'
                printf -- "     To run Puppet agent, follow from step 3.4 in build instructions.\n"
                printf -- '\n'
                printf -- "More information can be found here : https://puppetlabs.com/\n"
                printf -- '\n'
        fi
}

###############################################################################################################

while getopts "h?dyt?s:j:" opt; do
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
                TEST="true"
                ;;
        s)
                export USEAS=$OPTARG
                ;;
        j)
                export JAVA_PROVIDED="$OPTARG"
                ;;
        esac
done

mkdir -p "$SOURCE_ROOT/logs"

source "/etc/os-release"

logDetails
DISTRO="$ID-$VERSION_ID"
checkPrequisites #Check Prequisites

if [[ "$USEAS" == "server" ]]; then
        case "$DISTRO" in
        "ubuntu-18.04" | "ubuntu-20.04")
                printf -- "Installing %s Server %s for %s \n" "$PACKAGE_NAME" "$SERVER_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
                printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
                sudo apt-get update >/dev/null
                sudo apt-get install -y g++ tar git make wget locales locales-all unzip ruby-dev zip gzip gawk |& tee -a "$LOG_FILE"
                configureAndInstall |& tee -a "$LOG_FILE"
                ;;

        "rhel-7.8" | "rhel-7.9")
                printf -- "Installing %s Server %s for %s \n" "$PACKAGE_NAME" "$SERVER_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
                printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
                sudo yum install -y gcc-c++ tar unzip openssl-devel make git wget zip gzip gawk |& tee -a "$LOG_FILE"
                configureAndInstall |& tee -a "$LOG_FILE"
                ;;

        "rhel-8.4" | "rhel-8.6")
                printf -- "Installing %s Server %s for %s \n" "$PACKAGE_NAME" "$SERVER_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
                printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
                sudo yum install -y gcc-c++ tar unzip openssl-devel make git wget zip ruby gzip gawk |& tee -a "$LOG_FILE"
                configureAndInstall |& tee -a "$LOG_FILE"
                ;;

        "sles-12.5")
                printf -- "Installing %s Server %s for %s \n" "$PACKAGE_NAME" "$SERVER_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
                printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
                sudo zypper install -y gcc-c++ tar unzip libopenssl-devel make git wget zip gzip gawk |& tee -a "$LOG_FILE"
                configureAndInstall |& tee -a "$LOG_FILE"
                ;;

        "sles-15.3" | "sles-15.4")
                printf -- "Installing %s Server %s for %s \n" "$PACKAGE_NAME" "$SERVER_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
                printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
                sudo zypper install -y gcc-c++ tar unzip libopenssl-devel make git wget zip ruby gzip gawk |& tee -a "$LOG_FILE"
                configureAndInstall |& tee -a "$LOG_FILE"
                ;;

        *)
                printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
                exit 1
                ;;
        esac

elif [[ "$USEAS" == "agent" ]]; then
        case "$DISTRO" in
        "ubuntu-18.04" | "ubuntu-20.04" | "ubuntu-22.04")
                printf -- "Installing %s Agent %s for %s \n" "$PACKAGE_NAME" "$AGENT_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
                printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
                sudo apt-get update >/dev/null
                sudo apt-get install -y g++ tar make wget ruby-dev gzip gawk |& tee -a "$LOG_FILE"
                configureAndInstall |& tee -a "$LOG_FILE"
                ;;

        "rhel-7.8" | "rhel-7.9")
                printf -- "Installing %s Agent %s for %s \n" "$PACKAGE_NAME" "$AGENT_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
                printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
                sudo yum install -y gcc-c++ tar openssl-devel make wget gzip gawk |& tee -a "$LOG_FILE"
                configureAndInstall |& tee -a "$LOG_FILE"
                ;;

        "rhel-8.4" | "rhel-8.5" | "rhel-8.6" | "rhel-9.0")
                printf -- "Installing %s Agent %s for %s \n" "$PACKAGE_NAME" "$AGENT_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
                printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
                sudo yum install -y gcc-c++ tar make wget ruby-devel gzip gawk |& tee -a "$LOG_FILE"
                configureAndInstall |& tee -a "$LOG_FILE"
                ;;

        "sles-12.5")
                printf -- "Installing %s Agent %s for %s \n" "$PACKAGE_NAME" "$AGENT_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
                printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
                sudo zypper install -y gcc-c++ tar openssl-devel make wget gzip gawk |& tee -a "$LOG_FILE"
                configureAndInstall |& tee -a "$LOG_FILE"
                ;;

        "sles-15.3" | "sles-15.4")
                printf -- "Installing %s Agent %s for %s \n" "$PACKAGE_NAME" "$AGENT_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
                printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
                sudo zypper install -y gcc-c++ tar make wget ruby-devel gzip gawk |& tee -a "$LOG_FILE"
                configureAndInstall |& tee -a "$LOG_FILE"
                ;;

        *)
                printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
                exit 1
                ;;
        esac

else
        printf -- "please enter the argument (server/agent) with option -s "
        exit
fi

gettingStarted |& tee -a "$LOG_FILE"
cleanup
