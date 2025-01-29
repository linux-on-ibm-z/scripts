#!/bin/bash
# ©  Copyright IBM Corporation 2025.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Logstash/8.17.1/build_logstash.sh
# Execute build script: bash build_logstash.sh    (provide -h for help)0
#

set -e -o pipefail

PACKAGE_NAME="logstash"
PACKAGE_VERSION="8.17.1"
FORCE=false
CURDIR="$(pwd)"
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
NON_ROOT_USER="$(whoami)"
JAVA_PROVIDED="OpenJDK11"
BUILD_ENV="$HOME/setenv.sh"

trap cleanup 1 2 ERR

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
        mkdir -p "$CURDIR/logs/"
fi

if [ -f "/etc/os-release" ]; then
        source "/etc/os-release"
fi

function prepare() {
        if command -v "sudo" >/dev/null; then
                printf -- 'Sudo : Yes\n'
        else
                printf -- 'Sudo : No \n'
                printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n'
                exit 1
        fi

        if [[ "$JAVA_PROVIDED" != "Temurin11" && "$JAVA_PROVIDED" != "Temurin17" && "$JAVA_PROVIDED" != "Temurin21" && "$JAVA_PROVIDED" != "OpenJDK11" && "$JAVA_PROVIDED" != "OpenJDK17" && "$JAVA_PROVIDED" != "OpenJDK21" ]]; then
                printf "$JAVA_PROVIDED is not supported, Please use valid java from {Temurin11, Temurin17, Temurin21, OpenJDK11, OpenJDK17, OpenJDK21} only"
                exit 1
        fi
        LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-${JAVA_PROVIDED}-$(date +"%F-%T").log"

        if [[ "$FORCE" == "true" ]]; then
                printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "${LOG_FILE}"
        else
                # Ask user for prerequisite installation
                printf -- "\nAs part of the installation, dependencies would be installed/upgraded. \n"
                while true; do
                        read -r -p "Do you want to continue (y/n) ? :  " yn
                        case $yn in
                        [Yy]*)
                                printf -- 'User responded with Yes. \n' |& tee -a "${LOG_FILE}"
                                break
                                ;;
                        [Nn]*) exit ;;
                        *) echo "Please provide confirmation to proceed." ;;
                        esac
                done
        fi

        # zero out
        true > "$BUILD_ENV"
}

function cleanup() {
        sudo rm -rf "${CURDIR}/logstash-oss-${PACKAGE_VERSION}-linux-aarch64.tar.gz" "${CURDIR}/temurin11.tar.gz" "${CURDIR}/temurin17.tar.gz" "${CURDIR}/temurin21.tar.gz"
        printf -- 'Cleaned up the artifacts\n' >>"${LOG_FILE}"
}

function configureAndInstall() {

    printf -- 'Configuration and Installation started \n'

    if [[ "$JAVA_PROVIDED" == "Temurin11" ]]; then
        # Install Temurin 11
        printf -- "\nInstalling Temurin 11 . . . \n"
        cd $SOURCE_ROOT
        wget -O temurin11.tar.gz https://github.com/adoptium/temurin11-binaries/releases/download/jdk-11.0.25%2B9/OpenJDK11U-jdk_s390x_linux_hotspot_11.0.25_9.tar.gz
        sudo mkdir -p /opt/temurin11
        sudo tar -zxf temurin11.tar.gz -C /opt/temurin11 --strip-components 1
        export LS_JAVA_HOME=/opt/temurin11
        printf -- "Installation of Temurin 11 is successful\n" >> "$LOG_FILE"

    elif [[ "$JAVA_PROVIDED" == "Temurin17" ]]; then
        # Install Temurin 17
        printf -- "\nInstalling Temurin 17 . . . \n"
        cd $SOURCE_ROOT
        wget -O temurin17.tar.gz https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.13%2B11/OpenJDK17U-jdk_s390x_linux_hotspot_17.0.13_11.tar.gz
        sudo mkdir -p /opt/temurin17
        sudo tar -zxf temurin17.tar.gz -C /opt/temurin17 --strip-components 1
        export LS_JAVA_HOME=/opt/temurin17
        printf -- "Installation of Temurin17 is successful\n" >> "$LOG_FILE"

    elif [[ "$JAVA_PROVIDED" == "Temurin21" ]]; then
        # Install Temurin 21
        printf -- "\nInstalling Temurin 21 . . . \n"
        cd $SOURCE_ROOT
        wget -O temurin21.tar.gz https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.5%2B11/OpenJDK21U-jdk_s390x_linux_hotspot_21.0.5_11.tar.gz
        sudo mkdir -p /opt/temurin21
        sudo tar -zxf temurin21.tar.gz -C /opt/temurin21 --strip-components 1
        export LS_JAVA_HOME=/opt/temurin21
        printf -- "Installation of Temurin21 is successful\n" >> "$LOG_FILE"

    elif [[ "$JAVA_PROVIDED" == "OpenJDK21" ]]; then
        printf -- "\nInstalling OpenJDK 21 . . . \n"
        if [[ "${ID}" == "rhel" ]]; then
             sudo yum install -y java-21-openjdk-devel
             export LS_JAVA_HOME=/usr/lib/jvm/java-21-openjdk
        elif [[ "${ID}" == "sles" ]]; then
             sudo zypper install -y java-21-openjdk java-21-openjdk-devel
             export LS_JAVA_HOME=/usr/lib64/jvm/java-21-openjdk
        elif [[ "${ID}" == "ubuntu" ]]; then
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-21-jre openjdk-21-jdk
            export LS_JAVA_HOME=/usr/lib/jvm/java-21-openjdk-s390x
        fi
        printf -- "Installation of OpenJDK 21 is successful\n" >> "$LOG_FILE"
    elif [[ "$JAVA_PROVIDED" == "OpenJDK17" ]]; then
        printf -- "\nInstalling OpenJDK 17 . . . \n"
        if [[ "${ID}" == "ubuntu" ]]; then
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-17-jre openjdk-17-jdk
            export LS_JAVA_HOME=/usr/lib/jvm/java-17-openjdk-s390x
        elif [[ "${ID}" == "rhel" ]]; then
             sudo yum install -y java-17-openjdk-devel
             export LS_JAVA_HOME=/usr/lib/jvm/java-17-openjdk
        elif [[ "${ID}" == "sles" ]]; then
            sudo zypper install -y java-17-openjdk java-17-openjdk-devel
            export LS_JAVA_HOME=/usr/lib64/jvm/java-17-openjdk
        fi
        printf -- "Installation of OpenJDK 17 is successful\n" >> "$LOG_FILE"
    elif [[ "$JAVA_PROVIDED" == "OpenJDK11" ]]; then
         printf -- "\nInstalling OpenJDK 11 . . . \n"
        if [[ "${ID}" == "rhel" ]]; then
            sudo yum install -y java-11-openjdk-devel
            export LS_JAVA_HOME=/usr/lib/jvm/java-11-openjdk
        elif [[ "${ID}" == "sles" ]]; then
            sudo zypper install -y java-11-openjdk java-11-openjdk-devel
            export LS_JAVA_HOME=/usr/lib64/jvm/java-11-openjdk
        elif [[ "${ID}" == "ubuntu" ]]; then
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-11-jre openjdk-11-jdk
            export LS_JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x
        fi
        printf -- "Installation of OpenJDK 11 is successful\n" >> "$LOG_FILE"
    else
        printf "$JAVA_PROVIDED is not supported, Please use valid variant from {Temurin11, Temurin17, Temurin21, OpenJDK11, OpenJDK17, OpenJDK21} only"
        exit 1
    fi

    printf -- "export LS_JAVA_HOME=$LS_JAVA_HOME\n" >> "$BUILD_ENV"

    export PATH=$LS_JAVA_HOME/bin:$PATH
    printf -- "export PATH=$PATH\n" >> "$BUILD_ENV"
    java -version |& tee -a "$LOG_FILE"

    # Downloading and installing Logstash
    printf -- 'Downloading and installing Logstash.\n'
    cd "${CURDIR}"
    wget -q https://artifacts.elastic.co/downloads/logstash/logstash-oss-"$PACKAGE_VERSION"-linux-aarch64.tar.gz
    sudo mkdir -p /usr/share/logstash
    sudo tar -xzf logstash-oss-"$PACKAGE_VERSION"-linux-aarch64.tar.gz -C /usr/share/logstash --strip-components 1
    sudo ln -sf /usr/share/logstash/bin/* /usr/bin

    if ([[ -z "$(cut -d: -f1 /etc/group | grep elastic)" ]]); then
        printf -- '\nCreating group elastic.\n'
        sudo /usr/sbin/groupadd elastic # If group is not already created
    fi

    sudo chown "$NON_ROOT_USER:elastic" -R /usr/share/logstash

    # Cleanup
    cleanup

    # Verifying Logstash installation
    if command -v "$PACKAGE_NAME" >/dev/null; then
        printf -- "%s installation completed. Please check the Usage to start the service.\n\n" "$PACKAGE_NAME"
        printf -- "%s -V\n" "$PACKAGE_NAME"
        $PACKAGE_NAME -V
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
        echo "  bash build_logstash.sh  [-d debug] [-y install-without-confirmation] [-j Java to use from {Temurin11, Temurin17, Temurin21, OpenJDK11, OpenJDK17, OpenJDK21}]"
        echo "  default: If no -j specified, OpenJDK 11 will be installed"
        echo
}

while getopts "h?dyj:" opt; do
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
        j)
                JAVA_PROVIDED="$OPTARG"
                ;;
        esac
done

function gettingStarted() {
        printf -- '\n********************************************************************************************************\n'
        printf -- "\n* Getting Started * \n"
        printf -- "Note: Environmental Variables needed have been added to $HOME/setenv.sh\n"
        printf -- "Note: To set the Environmental Variables needed for Logstash, please run: source $HOME/setenv.sh \n"
        printf -- "Run Logstash: \n"
        printf -- "    logstash -V \n\n"
        printf -- "Visit https://www.elastic.co/support/matrix#matrix_jvm for more information.\n\n"
        printf -- '********************************************************************************************************\n'
}

###############################################################################################################

prepare
logDetails

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"rhel-8.8" | "rhel-8.10" | "rhel-9.2" | "rhel-9.4" | "rhel-9.5")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo yum install -y gcc make tar wget |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"sles-15.6")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo zypper install -y gawk gcc gzip make tar wget |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"ubuntu-20.04" | "ubuntu-22.04" | "ubuntu-24.04")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo apt-get update
        sudo apt-get install -y make tar wget gzip curl |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

*)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "${LOG_FILE}"
        exit 1

        ;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
