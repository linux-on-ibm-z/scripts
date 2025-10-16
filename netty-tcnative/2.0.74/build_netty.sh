#!/bin/bash
# © Copyright IBM Corporation 2025.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/netty-tcnative/2.0.74/build_netty.sh
# Execute build script: bash build_netty.sh    (provide -h for help)
#
set -e  -o pipefail
PACKAGE_NAME="netty-tcnative"
PACKAGE_VERSION="2.0.74"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/netty-tcnative/2.0.74/patch"
SOURCE_ROOT="$(pwd)"
USER="$(whoami)"
FORCE="false"
LOG_FILE="${SOURCE_ROOT}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
JAVA_PROVIDED="OpenJDK11"
trap cleanup 0 1 2 ERR
#Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
   mkdir -p "$SOURCE_ROOT/logs/"
fi
source "/etc/os-release"
function prepare() {
        if command -v "sudo" >/dev/null; then
                printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
        else
                printf -- 'Sudo : No \n' >>"$LOG_FILE"
                printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n'
                exit 1
        fi
        if [[ "$JAVA_PROVIDED" != "Semeru8" && "$JAVA_PROVIDED" != "OpenJDK8"  && "$JAVA_PROVIDED" != "Temurin8" && "$JAVA_PROVIDED" != "Semeru11" && "$JAVA_PROVIDED" != "Temurin11" && "$JAVA_PROVIDED" != "OpenJDK11" && "$JAVA_PROVIDED" != "Semeru17" && "$JAVA_PROVIDED" != "Temurin17" && "$JAVA_PROVIDED" != "OpenJDK17" ]]; then
                printf "$JAVA_PROVIDED is not supported, Please use valid java from {Semeru8, OpenJDK8, Temurin8, Semeru11, Temurin11, OpenJDK11, Semeru17, Temurin17, OpenJDK17} only"
                exit 1
        fi
        if [[ "$FORCE" == "true" ]]; then
                printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
        else
                # Ask user for prerequisite installation
                printf -- "\nAs part of the installation, dependencies would be installed/upgraded. \n"
                while true; do
                        read -r -p "Do you want to continue (y/n) ? :  " yn
                        case $yn in
                        [Yy]*)
                                printf -- 'User responded with Yes. \n' >> "$LOG_FILE"
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
        cd $SOURCE_ROOT
        if [[ $JAVA_PROVIDED == *11 ]]; then
                rm -rf  ibm-semeru-open-jdk_s390x_linux_11.0.28_6_openj9-0.53.0.tar.gz
                rm -rf  OpenJDK11U-jdk_s390x_linux_hotspot_11.0.28_6.tar.gz
        elif [[ $JAVA_PROVIDED == *17 ]]; then
                rm -rf  ibm-semeru-open-jdk_s390x_linux_17.0.16_8_openj9-0.53.0.tar.gz
                rm -rf  OpenJDK17U-jdk_s390x_linux_hotspot_17.0.16_8.tar.gz
        
        else
                rm -rf  OpenJDK8U-jdk_s390x_linux_hotspot_8u282b08.tar.gz 
                rm -rf  ibm-semeru-open-jdk_s390x_linux_8u422b05_openj9-0.46.0.tar.gz
        fi
        printf -- "Cleaned up the artifacts\n" >> "$LOG_FILE"
}

function configureAndInstall() {
        printf -- 'Configuration and Installation started \n'
        # Install JDK 8/11/17 and set environment variables
        echo "Java provided by user: $JAVA_PROVIDED" >> "$LOG_FILE"
        if [[ "$JAVA_PROVIDED" == "Semeru11" ]]; then
                if [[ "$DISTRO" == "ubuntu-25.04" ]]; then
                     printf -- "$JAVA_PROVIDED is not supported, Please use valid java from {OpenJDK8, Temurin11, OpenJDK11, Temurin17, OpenJDK17} only"
                     exit 1
                fi
                # Install AdoptOpenJDK 11 (With OpenJ9)
                printf -- "\nInstalling AdoptOpenJDK 11 (With OpenJ9) . . . \n"
                cd $SOURCE_ROOT
                wget https://github.com/ibmruntimes/semeru11-binaries/releases/download/jdk-11.0.28%2B6_openj9-0.53.0/ibm-semeru-open-jdk_s390x_linux_11.0.28_6_openj9-0.53.0.tar.gz
                tar -xzf ibm-semeru-open-jdk_s390x_linux_11.0.28_6_openj9-0.53.0.tar.gz
                export JAVA_HOME=$SOURCE_ROOT/jdk-11.0.28+6
                printf -- "Installation of AdoptOpenJDK 11 (With OpenJ9) is successful\n" >> "$LOG_FILE"
        elif [[ "$JAVA_PROVIDED" == "Temurin11" ]]; then
                # Install AdoptOpenJDK 11 (With Hotspot)
                printf -- "\nInstalling AdoptOpenJDK 11 (With Hotspot) . . . \n"
                cd $SOURCE_ROOT
                wget https://github.com/adoptium/temurin11-binaries/releases/download/jdk-11.0.28%2B6/OpenJDK11U-jdk_s390x_linux_hotspot_11.0.28_6.tar.gz
                tar -xzf OpenJDK11U-jdk_s390x_linux_hotspot_11.0.28_6.tar.gz
                export JAVA_HOME=$SOURCE_ROOT/jdk-11.0.28+6
                printf -- "Installation of AdoptOpenJDK 11 (With Hotspot) is successful\n" >> "$LOG_FILE"
        elif [[ "$JAVA_PROVIDED" == "OpenJDK11" ]]; then
                if [[ "${ID}" == "ubuntu" ]]; then
                        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-11-jdk
                        export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x
                elif [[ "${ID}" == "rhel" ]]; then
                        sudo yum install -y java-11-openjdk-devel
                        export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
                elif [[ "${ID}" == "sles" ]]; then
                        sudo zypper install -y java-11-openjdk-devel
                        export JAVA_HOME=/usr/lib64/jvm/java-11-openjdk
                fi
                printf -- "Installation of OpenJDK 11 is successful\n" >> "$LOG_FILE"
        elif [[ "$JAVA_PROVIDED" == "Semeru17" ]]; then
                if [[ "$DISTRO" == "ubuntu-25.04" ]]; then
                     printf -- "$JAVA_PROVIDED is not supported, Please use valid java from {OpenJDK8, Temurin11, OpenJDK11, Temurin17, OpenJDK17} only"
                     exit 1
                fi
                # Install AdoptOpenJDK 17 (With OpenJ9)
                printf -- "\nInstalling AdoptOpenJDK 17 (With OpenJ9) . . . \n"
                cd $SOURCE_ROOT
                wget https://github.com/ibmruntimes/semeru17-binaries/releases/download/jdk-17.0.16%2B8_openj9-0.53.0/ibm-semeru-open-jdk_s390x_linux_17.0.16_8_openj9-0.53.0.tar.gz
                tar -xzf ibm-semeru-open-jdk_s390x_linux_17.0.16_8_openj9-0.53.0.tar.gz
                export JAVA_HOME=$SOURCE_ROOT/jdk-17.0.16+8
                printf -- "Installation of AdoptOpenJDK 17 (With OpenJ9) is successful\n" >> "$LOG_FILE"
        elif [[ "$JAVA_PROVIDED" == "Temurin17" ]]; then
                # Install AdoptOpenJDK 17 (With Hotspot)
                printf -- "\nInstalling AdoptOpenJDK 17 (With Hotspot) . . . \n"
                cd $SOURCE_ROOT
                wget https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.16%2B8/OpenJDK17U-jdk_s390x_linux_hotspot_17.0.16_8.tar.gz
                tar -xzf OpenJDK17U-jdk_s390x_linux_hotspot_17.0.16_8.tar.gz
                export JAVA_HOME=$SOURCE_ROOT/jdk-17.0.16+8
                printf -- "Installation of AdoptOpenJDK 17 (With Hotspot) is successful\n" >> "$LOG_FILE"
        elif [[ "$JAVA_PROVIDED" == "OpenJDK17" ]]; then
                if [[ "${ID}" == "ubuntu" ]]; then
                        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-17-jdk
                        export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-s390x
                elif [[ "${ID}" == "rhel" ]]; then
                        sudo yum install -y java-17-openjdk java-17-openjdk-devel
			java_version=`ls /usr/lib/jvm/ | grep java-17-openjdk-17.*`
			export JAVA_HOME=/usr/lib/jvm/`echo $java_version | cut -d' ' -f1`
                elif [[ "${ID}" == "sles" ]]; then
                        sudo zypper install -y java-17-openjdk-devel
                        export JAVA_HOME=/usr/lib64/jvm/java-17-openjdk
                fi
                printf -- "Installation of OpenJDK 17 is successful\n" >> "$LOG_FILE"
        elif [[ "$JAVA_PROVIDED" == "Semeru8" ]]; then
                if [[ "$DISTRO" == "ubuntu-25.04" ]]; then
                     printf -- "$JAVA_PROVIDED is not supported, Please use valid java from {OpenJDK8, Temurin11, OpenJDK11, Temurin17, OpenJDK17} only"
                     exit 1
                fi
                # Install AdoptOpenJDK 8 (With OpenJ9)
                printf -- "\nInstalling AdoptOpenJDK 8 (With OpenJ9) . . . \n"
                cd $SOURCE_ROOT
                wget https://github.com/ibmruntimes/semeru8-binaries/releases/download/jdk8u462-b08_openj9-0.53.0/ibm-semeru-open-jdk_s390x_linux_8u462b08_openj9-0.53.0.tar.gz
                tar -xzf ibm-semeru-open-jdk_s390x_linux_8u462b08_openj9-0.53.0.tar.gz
                export JAVA_HOME=$SOURCE_ROOT/jdk8u462-b08
                printf -- "Installation of AdoptOpenJDK 8 (With OpenJ9) is successful\n" >> "$LOG_FILE"
        elif [[ "$JAVA_PROVIDED" == "OpenJDK8" ]]; then
                if [[ "${ID}" == "ubuntu" ]]; then
                        sudo apt-get install -y openjdk-8-jre openjdk-8-jdk
                        sudo update-alternatives --install "/usr/bin/java" "java" "/usr/lib/jvm/java-8-openjdk-s390x/bin/java" 20
                        sudo update-alternatives --install "/usr/bin/javac" "javac" "/usr/lib/jvm/java-8-openjdk-s390x/bin/javac" 20
                        sudo update-alternatives --set java "/usr/lib/jvm/java-8-openjdk-s390x/bin/java"
                        sudo update-alternatives --set javac "/usr/lib/jvm/java-8-openjdk-s390x/bin/javac"
                        export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-s390x
                elif [[ "${ID}" == "rhel" ]]; then
                        sudo yum install -y java-1.8.0-openjdk-devel.s390x
                        sudo update-alternatives --install "/usr/bin/java" "java" "/usr/lib/jvm/java-1.8.0-openjdk/bin/java" 20
                        sudo update-alternatives --install "/usr/bin/javac" "javac" "/usr/lib/jvm/java-1.8.0-openjdk/bin/javac" 20
                        sudo update-alternatives --set java "/usr/lib/jvm/java-1.8.0-openjdk/bin/java"
                        sudo update-alternatives --set javac "/usr/lib/jvm/java-1.8.0-openjdk/bin/javac"
                        export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk
                elif [[ "${ID}" == "sles" ]]; then
                        sudo zypper install -y java-1_8_0-openjdk-devel
                        sudo update-alternatives --install "/usr/bin/java" "java" "/usr/lib64/jvm/java-1.8.0-openjdk/bin/java" 20
                        sudo update-alternatives --install "/usr/bin/javac" "javac" "/usr/lib64/jvm/java-1.8.0-openjdk/bin/javac" 20
                        sudo update-alternatives --set java "/usr/lib64/jvm/java-1.8.0-openjdk/bin/java"
                        sudo update-alternatives --set javac "/usr/lib64/jvm/java-1.8.0-openjdk/bin/javac"
                        export JAVA_HOME=/usr/lib64/jvm/java-1.8.0-openjdk
                fi
                printf -- "Installation of OpenJDK 8 is successful\n" >> "$LOG_FILE"
        elif [[ "$JAVA_PROVIDED" == "Temurin8" ]]; then
                if [[ "${DISTRO}" == ubuntu* || "${DISTRO}" == rhel-9*  || "${DISTRO}" == sles* ]] ;then
                        cd $SOURCE_ROOT/
                        wget ftp://sourceware.org/pub/libffi/libffi-3.2.1.tar.gz
                        tar xvfz libffi-3.2.1.tar.gz
                        cd libffi-3.2.1
                        ./configure --prefix=/usr/local
                        make
                        sudo make install
                        sudo ldconfig
                        sudo ldconfig /usr/local/lib64
                fi
                printf -- "Installing AdoptOpenJDK8 + OpenJ9 \n"
                cd $SOURCE_ROOT
                wget https://github.com/AdoptOpenJDK/openjdk8-binaries/releases/download/jdk8u282-b08/OpenJDK8U-jdk_s390x_linux_hotspot_8u282b08.tar.gz
                sudo tar xzf OpenJDK8U-jdk_s390x_linux_hotspot_8u282b08.tar.gz -C /opt/
                export JAVA_HOME=/opt/jdk8u282-b08
                export JAVA_TOOL_OPTIONS='-Xmx2048M'

                printf -- "Installation of AdoptOpenJDK 8 (With Hotspot) is successful\n" >> "$LOG_FILE"   
                        
        else
            printf "$JAVA_PROVIDED is not supported, Please use valid java from {Semeru8, OpenJDK8, Temurin8, Semeru11, Temurin11, OpenJDK11, Semeru17, Temurin17, OpenJDK17} only"
            exit 1
        fi
        export PATH=$JAVA_HOME/bin:$PATH
        printf -- "Java version is :\n"
        java -version
        # Build netty-tcnative
        cd $SOURCE_ROOT
        git clone -b netty-tcnative-parent-${PACKAGE_VERSION}.Final https://github.com/netty/netty-tcnative.git
        cd $SOURCE_ROOT/netty-tcnative
        
	printf -- "\nApplying  patch . . . \n"
        # Apply patch
	wget -O boringssl-compat.patch ${PATCH_URL}/boringssl-compat.patch
	patch -p1 < $SOURCE_ROOT/netty-tcnative/boringssl-compat.patch       
        ./mvnw clean install
        #Cleanup
        printf -- "\n Installation of netty was successfull \n\n"
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
        echo "  bash build_netty.sh  [-d debug] [-y install-without-confirmation] [-j Java to be used from {Semeru8, OpenJDK8, Temurin8, Semeru11, Temurin11, OpenJDK11, Semeru17, Temurin17, OpenJDK17}]"
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
        printf -- '\n***********************************************************************************************\n'
        printf -- "Getting Started: \n"
        printf -- "Set LD_LIBRARY_PATH : \n"
        printf -- "  $ export LD_LIBRARY_PATH=$SOURCE_ROOT/netty-tcnative/openssl-dynamic/target/native-build/.libs/:\$LD_LIBRARY_PATH  \n\n"
        printf -- " \n\n"
        printf -- '*************************************************************************************************\n'
        printf -- '\n'
}
###############################################################################################################
logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"rhel-8.10" | "rhel-9.4" | "rhel-9.6")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo yum install -y ninja-build cmake perl gcc gcc-c++ libarchive  openssl-devel apr-devel autoconf automake libtool make tar git wget curl golang libstdc++-static.s390x xz-devel gzip libcryptui-devel python3-devel patch |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;
"sles-15.6" | "sles-15.7")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y gawk ninja cmake perl libopenssl-devel apr-devel autoconf automake libtool make tar git wget gcc gcc-c++ gzip maven go curl xz python3 patch|& tee -a "${LOG_FILE}"
    configureAndInstall |& tee -a "${LOG_FILE}"
    ;;
"ubuntu-22.04" | "ubuntu-24.04" | "ubuntu-25.04")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo apt-get update -y
        sudo apt-get install -y ninja-build cmake patch perl golang libssl-dev libapr1-dev autoconf automake libtool make tar git wget curl libtool-bin xz-utils gzip python3 |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;
*)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
        exit 1
        ;;
esac
gettingStarted |& tee -a "${LOG_FILE}"
