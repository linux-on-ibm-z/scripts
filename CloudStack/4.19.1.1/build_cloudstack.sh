#!/bin/bash
# © Copyright IBM Corporation 2024
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: curl -sSLO https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/CloudStack/4.19.1.1/build_cloudstack.sh
# Execute build script: bash build_cloudstack.sh    (provide -h for help)

set -e  -o pipefail

PACKAGE_NAME="cloudstack"
PACKAGE_VERSION="4.19.1.1"
LIBVIRT_PACKAGE_VERSION=0.5.3

SOURCE_ROOT="$(pwd)"
export PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/cloudstack/4.19.1.1/patch/"
FORCE="false"

source /etc/os-release
DISTRO="$ID-$VERSION_ID"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

error() { echo "Error: ${*}"; exit 1; }

mkdir -p "$SOURCE_ROOT/logs/"

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
        printf -- "\nAs part of the installation, dependencies would be installed/upgraded.\n"
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
    rm -rf $SOURCE_ROOT/libvirt-java
    rm -rf $SOURCE_ROOT/rpmbuild
    rm -rf $SOURCE_ROOT/cloudstack/master.patch
    printf -- "Cleaned up the artifacts\n" | tee -a "$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

    # Build & Install Libvirt
    printf -- 'Installing Libvirt\n'
    mkdir -p /${SOURCE_ROOT}/.m2/repository/org/libvirt/libvirt/${LIBVIRT_PACKAGE_VERSION}/
    cd $SOURCE_ROOT
    git clone -b v${LIBVIRT_PACKAGE_VERSION} https://github.com/libvirt/libvirt-java.git
    cd libvirt-java
    curl -sSL $PATCH_URL/libvirt_0_5_3_java_s390x.patch | git apply -
    sudo bash autobuild.sh
    sudo cp -f target/libvirt-${LIBVIRT_PACKAGE_VERSION}.jar /${SOURCE_ROOT}/.m2/repository/org/libvirt/libvirt/${LIBVIRT_PACKAGE_VERSION}/

    # Build & Install CloudStack
    printf -- 'Installing CloudStack\n'
    arch=$(uname -m)
    cd $SOURCE_ROOT
    rm -rf cloudstack
    git clone -b $PACKAGE_VERSION "https://github.com/apache/cloudstack.git"
    cd cloudstack
    curl -sSL $PATCH_URL/master.patch | git apply -
    cd packaging

    search_line="cd ui && npm install && npm run build && cd .."
    if [[ $DISTRO == rhel-9.* ]]; then
        replacement_line='cd ui && sudo rm -rf /${SOURCE_ROOT}/cloudstack/dist/rpmbuild/BUILD/${PACKAGE_NAME}-${PACKAGE_VERSION}/ui/node_modules && npm install --force && NODE_OPTIONS="--max-old-space-size=4096 --openssl-legacy-provider" npm run build && cd ..'
    else
        replacement_line='cd ui && sudo rm -rf /${SOURCE_ROOT}/cloudstack/dist/rpmbuild/BUILD/${PACKAGE_NAME}-${PACKAGE_VERSION}/ui/node_modules && npm install --force && NODE_OPTIONS="--max-old-space-size=4096" npm run build && cd ..'
    fi
    replace_line_in_file centos8/cloud.spec "$search_line" "$replacement_line"

    # Build rpm
    sudo ./package.sh -d centos8

    # Install rpm
    cd ../dist/rpmbuild/RPMS/${arch}/
    sudo rpm -i cloudstack-common-${PACKAGE_VERSION}-1.${arch}.rpm cloudstack-management-${PACKAGE_VERSION}-1.${arch}.rpm cloudstack-ui-${PACKAGE_VERSION}-1.${arch}.rpm cloudstack-baremetal-agent-${PACKAGE_VERSION}-1.${arch}.rpm cloudstack-integration-tests-${PACKAGE_VERSION}-1.${arch}.rpm cloudstack-marvin-${PACKAGE_VERSION}-1.${arch}.rpm cloudstack-usage-${PACKAGE_VERSION}-1.${arch}.rpm cloudstack-agent-${PACKAGE_VERSION}-1.${arch}.rpm
    printf -- "Build and install CloudStack success\n"

    cd $SOURCE_ROOT
    # Verify cloudstack installation
    installed_version=$(rpm -qa cloudstack-agent*)
    version=$(echo "$installed_version" | grep -oP '\d+\.\d+\.\d+\.\d+')
    if [ "$version" == "$PACKAGE_VERSION" ]; then
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
    echo " bash build_cloudstack.sh  [-d debug] [-y install-without-confirmation]"
    echo "  default: OpenJDK 11 will be installed"
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
    esac
done




setupJava() {
    export JAVA_HOME=$(find /usr/lib/jvm -type d -name 'java-11-*' | sort -V | tail -n 1)
    echo "Setting up Java = $JAVA_HOME"
    if ! grep -qF "export PATH=${JAVA_HOME}/bin:\$PATH" ~/.bash_profile; then
        echo "export PATH=${JAVA_HOME}/bin:\$PATH" >> ~/.bash_profile
        echo "Updated PATH in ~/.bash_profile"
        source ~/.bash_profile || true
    fi

    echo "Setting up Java conf"
    # Setting Java before building CloudStack
    CONF_FILE="/etc/java/java.conf"
    if grep -q '^JAVA_HOME=' $CONF_FILE; then
        echo "JAVA_HOME entry already exists in $CONF_FILE"
        sudo sed -i "s|^JAVA_HOME=.*|JAVA_HOME='${JAVA_HOME}'|" "$CONF_FILE"
    else
        echo "JAVA_HOME='${JAVA_HOME}'" >> $CONF_FILE
        echo "JAVA_HOME has been added to $CONF_FILE"
    fi

    sudo update-alternatives --install /usr/bin/java java $JAVA_HOME/bin/java 40
    sudo update-alternatives --set java $JAVA_HOME/bin/java

    sudo update-alternatives --install /usr/bin/javac javac $JAVA_HOME/bin/javac 40
    sudo update-alternatives --set javac $JAVA_HOME/bin/javac

    java -version
    javac -version
    echo "Java setup done"
}

setupNodejs() {
    if command -v nvm &> /dev/null; then
        echo "nvm is already installed."
    else
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.4/install.sh | bash
        export NVM_DIR="$SOURCE_ROOT/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        nvm install 12
        nvm use 12
        printf -- "\n Installation of Node.js 12 was successful \n"
    fi
    node -v
}

replace_line_in_file() {
    if [[ ! -f "$1" ]]; then
        echo "Error: File '$1' not found!"
        return 1
    fi

    sed -i.bak "/$2/c\\$3" "$1"

    if [[ $? -eq 0 ]]; then
        echo "Line replaced successfully in $1."
        rm -f "$1.bak"
    else
        echo "Error: Failed to replace the line in $1."
    fi
}


function gettingStarted() {
    printf -- '\n********************************************************************************************************\n'
    printf -- "\n* Getting Started * \n"
    printf -- "You have successfully installed cloudstack.\n"
    printf -- "Please follow this installation guide now: https://docs.cloudstack.apache.org/en/latest/installguide/#general-installation \n"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare # Check Prequisites

case "$DISTRO" in

    "rhel-8.8" | "rhel-8.10" | "rhel-9.2" | "rhel-9.4")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo yum groupinstall -y "Development Tools" |& tee -a "$LOG_FILE"
        sudo yum install -y git python3 python3-pip java-11-openjdk-devel maven genisoimage mysql mysql-server createrepo \
        nfs-utils qemu-img ipmitool python3-devel python3-libvirt libvirt perl qemu-kvm rng-tools dhcp-server httpd \
        syslinux-tftpboot tftp-server libffi-devel ant curl chkconfig |& tee -a "$LOG_FILE"
        sudo yum update -y |& tee -a "$LOG_FILE"
        setupNodejs |& tee -a "$LOG_FILE"
        sudo yum install -y nodejs |& tee -a "$LOG_FILE"
        setupJava |& tee -a "$LOG_FILE"
        sudo pip3 install mysql-connector-python
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

    *)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
        exit 1
        ;;
esac

gettingStarted |& tee -a "$LOG_FILE"