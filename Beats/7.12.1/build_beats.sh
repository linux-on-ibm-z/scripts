#!/bin/bash
# © Copyright IBM Corporation 2021.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Beats/7.12.1/build_beats.sh
# Execute build script: bash build_beats.sh    (provide -h for help)
#

set -e  -o pipefail

PACKAGE_NAME="beats"
PACKAGE_VERSION="7.12.1"
CURDIR="$(pwd)"
USER="$(whoami)"

#PATCH_URL
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Beats/${PACKAGE_VERSION}/patch"
#Default GOPATH if not present already.
GO_DEFAULT="$HOME/go"

FORCE="false"
TESTS="false"
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
BUILD_ENV="${CURDIR}/setenv.sh"

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

    if [[ "${ID}" == "rhel" ]]; then
      case "$VERSION_ID" in
        "7.8" | "7.9")
                  printf -- "Reverting to system python and check if yum is working. \n"
                  sudo /usr/sbin/update-alternatives --install /usr/bin/python python /usr/bin/python2.7 15
                  sudo /usr/sbin/update-alternatives --display python
                  yum info python
                  ;;
      esac
    fi
    # Remove artifacts
    printf -- "Cleaned up the artifacts\n" >> "$LOG_FILE"

}
function configureAndInstallPython() {
        printf -- 'Configuration and Installation of Python started\n'

        if [[ "${DISTRO}" == "rhel-7.8" ]] || [[ "${DISTRO}" == "rhel-7.9" ]] || [[ "${DISTRO}" == "sles-12.5" ]]; then
                source "${BUILD_ENV}"
        fi

        cd $CURDIR
        #Install Python 3.x
        sudo rm -rf Python*
        wget https://www.python.org/ftp/python/3.9.4/Python-3.9.4.tgz
        tar -xzf Python-3.9.4.tgz
        cd Python-3.9.4
        ./configure --prefix=/usr/local --exec-prefix=/usr/local
        make
        sudo make install
        export PATH=/usr/local/bin:$PATH

        if [[ "${ID}" == "sles" ]]
        then
                sudo /usr/sbin/update-alternatives --install /usr/bin/python3 python3 /usr/local/bin/python3.9 10
                sudo /usr/sbin/update-alternatives --display python3
        else
                if [[ "${ID}" == "rhel" ]]
                then
                        case "$VERSION_ID" in
                        "7.8" | "7.9")
                                sudo /usr/sbin/update-alternatives --install /usr/bin/python python3 /usr/local/bin/python3.9 10
                                sudo /usr/sbin/update-alternatives --display python3
                                ;;
                        "8.1" | "8.2" | "8.3")
                                sudo /usr/sbin/update-alternatives --install /usr/bin/python3 python3 /usr/local/bin/python3.9 10
                                sudo /usr/sbin/update-alternatives --set python3 /usr/local/bin/python3.9
                                sudo /usr/sbin/update-alternatives --display python3
                                ;;
                        esac
                fi
        fi
        python3 -V

}

function configureAndInstall() {
        printf -- 'Configuration and Installation started \n'

        if [[ "${DISTRO}" == "rhel-7.8" ]] || [[ "${DISTRO}" == "rhel-7.9" ]] || [[ "${DISTRO}" == "sles-12.5" ]]; then
                source "${BUILD_ENV}"
        fi

        cd $CURDIR
        # Install go
        printf -- "Installing Go... \n"
        curl -SLO https://dl.google.com/go/go1.15.8.linux-s390x.tar.gz
        chmod ugo+r go1.15.8.linux-s390x.tar.gz
        sudo tar -C /usr/local -xzf go1.15.8.linux-s390x.tar.gz
        export PATH=$PATH:/usr/local/go/bin

        if [[ "${ID}" != "ubuntu" ]]
        then
                sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
                printf -- 'Symlink done for gcc \n'
        fi
        go version

        # Set GOPATH if not already set
        if [[ -z "${GOPATH}" ]]; then
                printf -- "Setting default value for GOPATH \n"

                #Check if go directory exists
                if [ ! -d "$HOME/go" ]; then
                 mkdir "$HOME/go"
                fi
                export GOPATH="${GO_DEFAULT}"
                export PATH=$PATH:$GOPATH/bin
        else
                printf -- "GOPATH already set : Value : %s \n" "$GOPATH"
        fi

        # Install beats
        printf -- '\nInstalling beats..... \n'

        #Checking permissions
        sudo setfacl -dm u::rwx,g::r,o::r $GOPATH
        cd $GOPATH
        touch test && ls -la test && rm test

        #Installing pip
        wget https://bootstrap.pypa.io/get-pip.py
        sudo env PATH=$PATH python3 get-pip.py
        rm get-pip.py


        echo "Installing RUST!!!"
        cd $CURDIR
        wget -O rustup-init.sh https://sh.rustup.rs
        bash rustup-init.sh -y
        export PATH=$PATH:$HOME/.cargo/bin
        rustup toolchain install 1.49.0
        rustup default 1.49.0
        rustc --version | grep "1.49.0"


        if  [[ "${ID}" == "sles" || "${DISTRO}" == "rhel-7."* ]]; then
                python3 -m pip install cryptography
        fi

        sudo env PATH=$PATH python3 -m pip install appdirs pyparsing packaging setuptools wheel PyYAML termcolor ordereddict nose-timer MarkupSafe virtualenv pillow

        # The upgrade of six may fail in certain distros, discard upgrade in such cases
        sudo env PATH=$PATH python3 -m pip install --upgrade six || true

        # Download Beats Source
        if [ ! -d "$GOPATH/src/github.com/elastic" ]; then
                mkdir -p $GOPATH/src/github.com/elastic
        fi
        cd $GOPATH/src/github.com/elastic
        sudo rm -rf beats
        git clone https://github.com/elastic/beats.git
        cd beats
        git checkout v$PACKAGE_VERSION

        #Adding fixes and patches for cross-compilation and to packetbeat
        fileChanges

        #Making directory to add .yml files
        if [ ! -d "/etc/beats/" ]; then
                sudo mkdir -p /etc/beats
        fi

        export PATH=$PATH:$GOPATH/bin

        #Building packetbeat and adding to usr/bin
        printf -- "Installing packetbeat \n" |& tee -a "$LOG_FILE"
        cd $GOPATH/src/github.com/elastic/beats/packetbeat
        make packetbeat
        ./packetbeat version
        make update
        make fmt
        sudo cp "./packetbeat" /usr/bin/
        sudo cp "./packetbeat.yml" /etc/beats/
        sudo chown -R $USER "$GOPATH/src/github.com/elastic/beats/"

        #Building filebeat and adding to usr/bin
        printf -- "Installing filebeat \n" |& tee -a "$LOG_FILE"
        cd $GOPATH/src/github.com/elastic/beats/filebeat
        make filebeat
        ./filebeat version
        make update
        make fmt
        sudo cp "./filebeat" /usr/bin/
        sudo cp "./filebeat.yml" /etc/beats/

        #Building metricbeat and adding to usr/bin
        printf -- "Installing metricbeat \n" |& tee -a "$LOG_FILE"
        cd $GOPATH/src/github.com/elastic/beats/metricbeat
        mage build
        ./metricbeat version
        mage update
        mage fmt
        sudo cp "./metricbeat" /usr/bin/
        sudo cp "./metricbeat.yml" /etc/beats/

        #Building libbeat and adding to usr/bin
        printf -- "Installing libbeat \n" |& tee -a "$LOG_FILE"
        cd $GOPATH/src/github.com/elastic/beats/libbeat
        make libbeat
        ./libbeat version
        make update
        make fmt
        sudo cp "./libbeat" /usr/bin/
        sudo cp "./libbeat.yml" /etc/beats/

        # heartbeat is not supported on ubuntu20.04
        if [[ "${DISTRO}" != "ubuntu-20.04" ]]
		    then
			    # Building heartbeat and adding to usr/bin
			    printf -- "Installing heartbeat \n" |& tee -a "$LOG_FILE"
			    cd $GOPATH/src/github.com/elastic/beats/heartbeat
			    make heartbeat
			    ./heartbeat version
			    make update
			    make fmt
			    sudo cp "./heartbeat" /usr/bin/
			    sudo cp "./heartbeat.yml" /etc/beats/
		    fi

        #Building journalbeat and adding to usr/bin
        printf -- "Installing journalbeat \n" |& tee -a "$LOG_FILE"
        cd $GOPATH/src/github.com/elastic/beats/journalbeat
        make journalbeat
        ./journalbeat version
        make update
        make fmt
        sudo cp "./journalbeat" /usr/bin/
        sudo cp "./journalbeat.yml" /etc/beats/

        #Building auditbeat and adding to usr/bin
        printf -- "Installing auditbeat \n" |& tee -a "$LOG_FILE"
        cd $GOPATH/src/github.com/elastic/beats/auditbeat
        make auditbeat
        ./auditbeat version
        make update
        make fmt
        sudo cp "./auditbeat" /usr/bin/
        sudo cp "./auditbeat.yml" /etc/beats/

        # Run Tests
        runTest

        #Cleanup
        cleanup

        printf -- "\n Installation of %s %s was successful \n\n" $PACKAGE_NAME $PACKAGE_VERSION
}

function fileChanges(){
        cd $GOPATH/src/github.com/elastic/beats

        printf -- 'change files with git apply <patch_diff>\n'
        wget $PATCH_URL/beats.patch -O - | git apply

}

function installOpenssl(){
      cd $CURDIR
      wget https://www.openssl.org/source/openssl-1.1.1h.tar.gz
      tar -xzf openssl-1.1.1h.tar.gz
      cd openssl-1.1.1h
      ./config --prefix=/usr/local --openssldir=/usr/local
      make
      sudo make install
      sudo ldconfig /usr/local/lib64
      export PATH=/usr/local/bin:$PATH
      export LDFLAGS="-L/usr/local/lib/ -L/usr/local/lib64/"
      export LD_LIBRARY_PATH="/usr/local/lib/:/usr/local/lib64/"
      export CPPFLAGS="-I/usr/local/include/ -I/usr/local/include/openssl"

      printf -- 'export PATH="/usr/local/bin:${PATH}"\n'  >> "${BUILD_ENV}"
      printf -- "export LDFLAGS=\"$LDFLAGS\"\n" >> "${BUILD_ENV}"
      printf -- "export LD_LIBRARY_PATH=\"$LD_LIBRARY_PATH\"\n" >> "${BUILD_ENV}"
      printf -- "export CPPFLAGS=\"$CPPFLAGS\"\n" >> "${BUILD_ENV}"
}

function runTest() {
        set +e

        if [[ "$TESTS" == "true" ]]; then
                printf -- "TEST Flag is set , Continue with running test \n"
                sudo chown -R $USER "$GOPATH/src/github.com/elastic/beats/"

                #FILEBEAT
                printf -- "\nTesting Filebeat\n"
                cd $GOPATH/src/github.com/elastic/beats/filebeat
                make unit
                make system-tests
                printf -- "\nTesting Filebeat completed successfully\n"

                #PACKETBEAT
                printf -- "\nTesting Packetbeat\n"
                cd $GOPATH/src/github.com/elastic/beats/packetbeat
                make unit
                make system-tests
                printf -- "\nTesting Packetbeat completed successfully\n"

                #METRICBEAT
                printf -- "\nTesting Metricbeat\n"
                cd $GOPATH/src/github.com/elastic/beats/metricbeat
                mage test
                printf -- "\nTesting Metricbeat completed successfully\n"

                #LIBBEAT
                printf -- "\nTesting Libbeat\n"
                cd $GOPATH/src/github.com/elastic/beats/libbeat
                make unit
                make system-tests
                printf -- "\nTesting Libbeat Completed Successfully\n"

                # heartbeat is not supported on ubuntu20.04
                if [[ "${DISTRO}" != "ubuntu-20.04" ]]
                then
                  #HEARTBEAT
                  printf -- "\nTesting Heartbeat\n"
                  cd $GOPATH/src/github.com/elastic/beats/heartbeat
                  make unit
                  make system-tests
                  printf -- "\nTesting Heartbeat completed successfully\n"
                fi

                #JOURNALBEAT
                printf -- "\nTesting journalbeat\n"
                cd $GOPATH/src/github.com/elastic/beats/journalbeat
                make unit
                make system-tests
                printf -- "\nTesting journalbeat completed successfully\n"

                #AUDIBEAT
                printf -- "\nTesting Auditbeat\n"
                cd $GOPATH/src/github.com/elastic/beats/auditbeat
                make unit
                make system-tests

                printf -- "Tests completed. \n"
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
        echo "  bash build_beats.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests]"
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
        printf -- '\n***********************************************************************************************\n'
        printf -- "Getting Started: \n"
        printf -- "To run a particular beat , run the following command : \n"
        printf -- '   sudo <beat_name> -e -c /etc/beats/<beat_name>.yml -d "publish"  \n'
        printf -- '    Example: sudo packetbeat -e -c /etc/beats/packetbeat.yml -d "publish"  \n\n'
        printf -- '*************************************************************************************************\n'
        printf -- '\n'
}

###############################################################################################################

logDetails
prepare #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-18.04" | "ubuntu-20.04")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo apt-get update -y
        sudo apt-get install -y git curl make wget tar gcc libcap-dev libpcap0.8-dev openssl libssh-dev acl rsync tzdata patch fdclone libsystemd-dev libjpeg-dev python3.8 libffi-dev libpython3-dev python3.8-dev python3.8-venv python3.8-distutils python3-lib2to3 |& tee -a "${LOG_FILE}"
        sudo /usr/bin/update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.8 10
        sudo /usr/bin/update-alternatives --set python3 /usr/bin/python3.8
        sudo /usr/bin/update-alternatives --display python3
        python3 -V
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"rhel-7.8" | "rhel-7.9")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo yum install -y git curl make wget tar gcc libpcap libpcap-devel which acl zlib-devel patch  systemd-devel libjpeg-devel|& tee -a "${LOG_FILE}"
        #Installing Python 3.x
        sudo yum install -y bzip2-devel gcc gcc-c++ gdbm-devel libdb-devel libffi-devel libuuid-devel make ncurses-devel openssl-devel readline-devel sqlite-devel tar tk-devel wget xz xz-devel zlib-devel
        # Install openssl
        installOpenssl |& tee -a "${LOG_FILE}"
        configureAndInstallPython |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"rhel-8.1" | "rhel-8.2" | "rhel-8.3" )
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo yum install -y git curl make wget tar gcc libpcap-devel openssl openssl-devel which acl zlib-devel patch  systemd-devel libjpeg-devel |& tee -a "${LOG_FILE}"
        #Installing Python 3.x
        sudo yum install -y bzip2-devel gcc gcc-c++ gdbm-devel libdb libffi-devel libuuid make ncurses openssl readline sqlite tar tk wget xz zlib-devel glibc-langpack-en diffutils xz-devel
        configureAndInstallPython |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"sles-12.5")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo zypper install -y git curl gawk make wget tar gcc libpcap1 libpcap-devel git libffi48-devel libsystemd0 systemd-devel acl patch libjpeg62-devel  |& tee -a "${LOG_FILE}"
        #Installing Python 3.x
        sudo zypper install -y gawk gcc gcc-c++ gdbm-devel libbz2-devel libdb-4_8-devel libffi48-devel libopenssl-devel libuuid-devel make ncurses-devel readline-devel sqlite3-devel tar tk-devel wget xz-devel zlib-devel
        # Install openssl
        installOpenssl |& tee -a "${LOG_FILE}"
        configureAndInstallPython |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

esac

gettingStarted |& tee -a "${LOG_FILE}"
