#!/bin/bash
# © Copyright IBM Corporation 2024,2025
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: curl -sSLO https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/CloudStack/4.19.1.1/build_cloudstack.sh
# Execute build script: bash build_cloudstack.sh    (provide -h for help)

set -e  -o pipefail

PACKAGE_NAME="cloudstack"
PACKAGE_VERSION="4.19.1.1"
LIBVIRT_PACKAGE_VERSION=0.5.3
PYTHON2_VERSION=2.7.18
ARCH="s390x"

SOURCE_ROOT="$(pwd)"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/CloudStack/${PACKAGE_VERSION}/patch/"
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
    sudo rm -rf /opt/maven/apache-maven-3.8.8
    sudo rm -rf $SOURCE_ROOT/libvirt-java
    sudo rm -rf $SOURCE_ROOT/rpmbuild
    sudo rm -rf $SOURCE_ROOT/cloudstack/master.patch
    sudo rm -rf $SOURCE_ROOT/Python-${PYTHON2_VERSION}
    sudo rm -rf $SOURCE_ROOT/Python-${PYTHON2_VERSION}.tgz
    printf -- "Cleaned up the artifacts\n" | tee -a "$LOG_FILE"
}

function installLibvirt() {
    # Build & Install Libvirt
    printf -- 'Installing Libvirt\n'
    mkdir -p /${SOURCE_ROOT}/.m2/repository/org/libvirt/libvirt/${LIBVIRT_PACKAGE_VERSION}/
    cd $SOURCE_ROOT
    git clone -b v${LIBVIRT_PACKAGE_VERSION} https://github.com/libvirt/libvirt-java.git
    cd libvirt-java
    if [[ $DISTRO == sles* ]]; then
        mkdir -p lib && cd lib && wget -O jna.jar https://repo1.maven.org/maven2/net/java/dev/jna/jna/5.5.0/jna-5.5.0.jar && wget -O junit.jar https://repo1.maven.org/maven2/junit/junit/4.13.2/junit-4.13.2.jar  && cd ..;
        sed -i '0,/\${jar.dir}/s/\${jar.dir}/lib/; 0,/\${jar.dir}/s/\${jar.dir}/lib/' build.xml
    fi
    curl -sSL $PATCH_URL/libvirt_0_5_3_java_s390x.patch | git apply -
    ./autobuild.sh
    sudo cp -f target/libvirt-${LIBVIRT_PACKAGE_VERSION}.jar /${SOURCE_ROOT}/.m2/repository/org/libvirt/libvirt/${LIBVIRT_PACKAGE_VERSION}/
}


function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

    installLibvirt
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
    ./package.sh -d centos8

    # Install rpm
    cd ../dist/rpmbuild/RPMS/${arch}/
    sudo rpm --nodeps -i cloudstack-common-${PACKAGE_VERSION}-1.${arch}.rpm cloudstack-management-${PACKAGE_VERSION}-1.${arch}.rpm cloudstack-ui-${PACKAGE_VERSION}-1.${arch}.rpm cloudstack-baremetal-agent-${PACKAGE_VERSION}-1.${arch}.rpm cloudstack-usage-${PACKAGE_VERSION}-1.${arch}.rpm cloudstack-agent-${PACKAGE_VERSION}-1.${arch}.rpm
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

function configureAndInstallUb() {
    printf -- "Configuration and Installation started \n"

    installLibvirt
    # Build & Install CloudStack
    printf -- 'Installing CloudStack\n'
    cd $SOURCE_ROOT
    rm -rf cloudstack
    git clone -b $PACKAGE_VERSION "https://github.com/apache/cloudstack.git"
    cd cloudstack
    curl -sSL $PATCH_URL/master.patch | git apply -
    replacement_line="$(printf '\t')cd ui && npm install --force && NODE_OPTIONS=\"--max-old-space-size=4096\" npm run build && cd .."
    search="Depends: \${misc:Depends}, \${python3:Depends}, genisoimage, nfs-common, python3-pip, python3-distutils \| python3-distutils-extra, python3-netaddr, uuid-runtime"

    replace_line_in_file debian/control " nodejs (>= 12), lsb-release, dh-systemd | debhelper (>= 13)" " lsb-release, dh-systemd | debhelper (>= 13)"
    replace_line_in_file debian/control " python (>= 2.7) | python2 (>= 2.7), python3 (>= 3), python-setuptools, python3-setuptools," " python3 (>= 3), python3-setuptools,"
    replace_line_in_file debian/control "$search" "Depends: \${misc:Depends}, \${python3:Depends}, genisoimage, nfs-common, python3-netaddr"
    replace_line_in_file debian/control "Depends: \${misc:Depends}, python3-pip, python3-dev, libffi-dev" "Depends: \${misc:Depends}, libffi-dev"
    replace_line_in_file debian/rules "$(printf '\t')cd ui && npm install && npm run build && cd .." "$replacement_line"

    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
    # Build deb
    if [[ $DISTRO == ubuntu-24.* ]]; then
        nvm exec 10 sudo -E dpkg-buildpackage -d
    else
        nvm exec 12 sudo -E dpkg-buildpackage -d
    fi

    # Install deb
    cd $SOURCE_ROOT
    sudo dpkg --force-all -i ./cloudstack-common_${PACKAGE_VERSION}_all.deb ./cloudstack-management_${PACKAGE_VERSION}_all.deb ./cloudstack-ui_${PACKAGE_VERSION}_all.deb ./cloudstack-usage_${PACKAGE_VERSION}_all.deb ./cloudstack-agent_${PACKAGE_VERSION}_all.deb || true
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -f -y || true
    printf -- "Build and install CloudStack success\n"

    cd $SOURCE_ROOT
    # Verify cloudstack installation
    installed_version=$(dpkg -l | grep cloudstack-agent)
    version=$(echo "$installed_version" | grep -oP '\d+\.\d+\.\d+\.\d+')
    if [ "$version" == "$PACKAGE_VERSION" ]; then
        printf -- " %s Installation verified.\n" "$PACKAGE_NAME"
    else
        printf -- "Error while installing %s, exiting with 127 \n" "$PACKAGE_NAME"
        exit 127
    fi
}

function configureAndInstallSLES() {
    printf -- "Configuration and Installation started \n"

    installLibvirt
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
    replacement_line='cd ui && sudo rm -rf /${SOURCE_ROOT}/cloudstack/dist/rpmbuild/BUILD/${PACKAGE_NAME}-${PACKAGE_VERSION}/ui/node_modules && npm install --force && NODE_OPTIONS="--max-old-space-size=4096" npm run build && cd ..'
    replace_line_in_file centos8/cloud.spec "$search_line" "$replacement_line"
    replace_line_in_file centos8/cloud.spec "BuildRequires: nodejs" "#BuildRequires: nodejs"

    # Build rpm
    ./package.sh -d centos8

    # Install rpm
    cd ../dist/rpmbuild/RPMS/${arch}/
    sudo rpm --nodeps -i cloudstack-common-${PACKAGE_VERSION}-1.${arch}.rpm cloudstack-management-${PACKAGE_VERSION}-1.${arch}.rpm cloudstack-ui-${PACKAGE_VERSION}-1.${arch}.rpm cloudstack-baremetal-agent-${PACKAGE_VERSION}-1.${arch}.rpm cloudstack-usage-${PACKAGE_VERSION}-1.${arch}.rpm cloudstack-agent-${PACKAGE_VERSION}-1.${arch}.rpm
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


setupNodejs() {
    if command -v nvm &> /dev/null; then
        echo "nvm is already installed."
    else
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.4/install.sh | bash
    fi
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    if [[ $DISTRO == ubuntu-24.* ||  $DISTRO == sles* ]]; then
        nvm install 10
        nvm use 10

        NVM_BIN=$(nvm which current | xargs dirname)
        sudo ln -sf "$NVM_BIN/node" /usr/local/bin/node
        sudo ln -sf "$NVM_BIN/npm" /usr/local/bin/npm
        printf -- "\n Installation of Node.js 10 was successful \n"
    else
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

setupPython2() {
  cd $SOURCE_ROOT
  if [[ $DISTRO == ubuntu-24.* ]]; then
    curl -O https://www.python.org/ftp/python/${PYTHON2_VERSION}/Python-${PYTHON2_VERSION}.tgz
    sudo tar -xvf Python-${PYTHON2_VERSION}.tgz
    cd Python-${PYTHON2_VERSION} || exit
    sudo bash configure && sudo make && sudo make install
    cd ..
    sudo rm /usr/local/bin/python
    sudo ln -s /usr/bin/python3 /usr/local/bin/python
    sudo apt-get install -y python3-pip |& tee -a "$LOG_FILE"
  else
    sudo apt-get install -y python2 python-setuptools
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

    "rhel-8.8" | "rhel-8.10" | "rhel-9.2" | "rhel-9.4" | "rhel-9.5")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo yum groupinstall -y "Development Tools" |& tee -a "$LOG_FILE"
        sudo yum install -y git python3 python3-pip java-11-openjdk java-11-openjdk-devel maven genisoimage mysql mysql-server createrepo \
        nfs-utils qemu-img ipmitool python3-devel python3-libvirt libvirt perl qemu-kvm rng-tools dhcp-server httpd \
        syslinux-tftpboot tftp-server libffi-devel ant curl chkconfig |& tee -a "$LOG_FILE"
        export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
        export PATH="${JAVA_HOME}/bin:${PATH}"
        sudo yum update -y |& tee -a "$LOG_FILE"
        setupNodejs |& tee -a "$LOG_FILE"
        sudo yum install -y nodejs |& tee -a "$LOG_FILE"
        
        sudo pip3 install mysql-connector-python
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

    "sles-15.6")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        for pkg in sudo wget git java-11-openjdk java-11-openjdk-devel ant ant-junit python3-libvirt-python libvirt selinux-tools dhcp-server qemu-img qemu-kvm dhcp \
        python3 python2 ipmitool python3-pip unzip cryptsetup ethtool ipset python3-setuptools mkisofs tftp mariadb mysql httpd qemu-tools timezone-java nfs-utils libffi-devel libopenssl-devel rpm-build python3-devel; do
            sudo zypper -n install "$pkg" || true;
        done
        export JAVA_HOME=/usr/lib64/jvm/java-11-openjdk
        export PATH="${JAVA_HOME}/bin:${PATH}"
        wget https://dlcdn.apache.org/maven/maven-3/3.8.8/binaries/apache-maven-3.8.8-bin.tar.gz
        tar -xvzf apache-maven-3.8.8-bin.tar.gz
        sudo mv apache-maven-3.8.8 /opt/maven
        echo -e "\nexport M2_HOME=/opt/maven\nexport MAVEN_HOME=/opt/maven\nexport PATH=\$PATH:\$M2_HOME/bin" | sudo tee -a /etc/environment > /dev/null
        source /etc/environment
        setupNodejs |& tee -a "$LOG_FILE"
        configureAndInstallSLES |& tee -a "$LOG_FILE"
    ;;

   "ubuntu-20.04" | "ubuntu-22.04" | "ubuntu-24.04" | "ubuntu-24.10")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo apt-get install -y curl dpkg-dev debhelper openjdk-11-jdk genisoimage build-essential python3 python3-setuptools python3-mysql.connector \
        maven ant libjna-java nodejs npm mysql-client augeas-tools mysql-client qemu-utils rng-tools python3-dnspython qemu-kvm libvirt-daemon-system \
        ebtables vlan ipset python3-libvirt ethtool iptables cpu-checker libffi-dev rustc cargo |& tee -a "$LOG_FILE"
        export DEBIAN_FRONTEND=noninteractive
        echo "ufw ufw/configuration-changed boolean true" | sudo debconf-set-selections
        sudo apt-get install -y ufw |& tee -a "$LOG_FILE"
        sudo apt-get update -y |& tee -a "$LOG_FILE"
        export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x
        export PATH="${JAVA_HOME}/bin:${PATH}"
        setupPython2 |& tee -a "$LOG_FILE"
        setupNodejs |& tee -a "$LOG_FILE"
        configureAndInstallUb |& tee -a "$LOG_FILE"
        ;;

    *)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
        exit 1
        ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
