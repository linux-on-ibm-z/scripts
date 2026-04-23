#!/bin/bash
# © Copyright IBM Corporation 2026.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Keystone/29.0.0/build_keystone.sh
# Execute build script: bash build_keystone.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="keystone"
PACKAGE_VERSION="29.0.0"

export SOURCE_ROOT="$(pwd)"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

function log() {
	printf -- "[$(date +'%Y-%m-%d %H:%M:%S')] %s\n" "$1" | tee -a "$LOG_FILE"
}

TEST_USER="$(whoami)"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
	mkdir -p "$SOURCE_ROOT/logs/"
fi

if [ -f "/etc/os-release" ]; then
	source "/etc/os-release"
fi

DISTRO="$ID-$VERSION_ID"

function prepare() {

	if [[ "$FORCE" == "true" ]]; then
		printf -- 'Force attribute provided hence continuing with install without confirmation message\n' | tee -a "$LOG_FILE"
	else
		printf -- 'As part of the installation, dependencies would be installed/upgraded.\n'
		while true; do
			read -r -p "Do you want to continue (y/n) ? :  " yn
			case $yn in
			[Yy]*)

				break
				;;
			[Nn]*) exit ;;
			*) echo "Please provide correct input to proceed." ;;
			esac
		done
	fi
}

function cleanup() {
	printf -- '\nCleaned up the artifacts\n'
}

function logDetails() {
	printf -- 'SYSTEM DETAILS\n' >"$LOG_FILE"
	if [ -f "/etc/os-release" ]; then
		cat "/etc/os-release" >>"$LOG_FILE"
	fi

	cat /proc/version >>"$LOG_FILE"
	printf -- "\nDetected %s \n" "$PRETTY_NAME"
	printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" | tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
	echo
	echo "Usage: "
	echo " bash build_keystone.sh  [-d debug] [-y install-without-confirmation] [-t run-check-after]"
	echo
}

function printSummary() {

	printf -- '\n********************************************************************************************************\n'
	printf -- "\n* Getting Started * \n"
	printf -- "\nRun openstack --help for a full list of available commands\n"
	printf -- "\nFor more information on Keystone please visit https://docs.openstack.org/developer/keystone/installing.html \n\n"
	printf -- '**********************************************************************************************************\n'
    disown -a
}

configureLibexpat() {
  local SRC_DIR="${SRC_DIR:-$HOME/src}"
  local REPO_DIR="$SRC_DIR/libexpat"
  local BUILD_DIR="$REPO_DIR/expat/build"

  mkdir -p "$SRC_DIR"
  cd "$SRC_DIR"

  if [[ ! -d "$REPO_DIR/.git" ]]; then
    git clone https://github.com/libexpat/libexpat.git "$REPO_DIR"
  fi

  rm -rf "$BUILD_DIR"
  mkdir -p "$BUILD_DIR"
  cd "$BUILD_DIR"

  cmake .. \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DEXPAT_BUILD_TESTS=OFF \
    -DEXPAT_BUILD_EXAMPLES=OFF

  make -j"$(nproc)"
  sudo make install
  echo "/usr/local/lib64" | sudo tee /etc/ld.so.conf.d/00-local-expat.conf >/dev/null
  sudo /sbin/ldconfig || sudo /usr/sbin/ldconfig
}

install_venv() {

    sudo mkdir -p /opt/openstack
    sudo chown -R "$(whoami):$(id -gn)" /opt/openstack

    #Activate the python env
    python3 -m venv /opt/openstack/venv

    source /opt/openstack/venv/bin/activate

    pip install -U pip setuptools wheel
    pip install bcrypt==4.0.1 keystone==${PACKAGE_VERSION} python-openstackclient uwsgi

    deactivate

    echo "export PATH=/opt/openstack/venv/bin:\$PATH" | sudo tee /etc/profile.d/openstack-venv.sh >/dev/null

    export PATH="/opt/openstack/venv/bin:$PATH"
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
		if [ -d "/etc/keystone" ]; then
			printf -- "%s is detected in the system. Skipping build and running check .\n" "$PACKAGE_NAME" | tee -a "$LOG_FILE"
			TESTS="true"
			printSummary
			exit 0
		else
			TESTS="true"
		fi
		;;
	esac
done

logDetails
prepare
export PATH="$HOME/.local/bin:$PATH"
hash -r

case "$DISTRO" in
"rhel-8.10" | "rhel-9.4" | "rhel-9.6" | "rhel-9.7" | "rhel-10.0" | "rhel-10.1")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

        sudo dnf install -y python3.12 python3.12-pip python3.12-devel gcc gcc-c++ make rust cargo openssl-devel libffi-devel
        python3.12 -m pip install -U pip setuptools wheel
        python3.12 -m pip install keystone==${PACKAGE_VERSION} uwsgi python-openstackclient
	;;

"sles-15.7" | "sles-16.0")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

	sudo zypper -n in python313 python313-devel python313-pip gcc gcc-c++ make cmake git wget gawk libopenssl-devel libffi-devel rust cargo
	configureLibexpat
	python3.13 -m pip install -U pip setuptools wheel
	python3.13 -m pip install keystone==${PACKAGE_VERSION} uwsgi python-openstackclient
	;;

"ubuntu-22.04" | "ubuntu-24.04" | "ubuntu-25.10")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

		sudo apt update && sudo apt-get install -y python3-pip python3-dev python3-venv wget curl rustc cargo librust-openssl-dev
	    sudo apt-get remove -y --ignore-missing python3-bcrypt
		install_venv
    	
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" | tee -a "$LOG_FILE"
	exit 1
	;;
esac

printSummary |& tee -a "$LOG_FILE"
INSTALLED_VERSION=$(keystone-manage --version 2>/dev/null | awk '{print $NF}')
if [[ "$INSTALLED_VERSION" == "$PACKAGE_VERSION" ]]; then
    echo "Keystone version $PACKAGE_VERSION installed successfully" | tee -a "$LOG_FILE"
else
    echo "Keystone version mismatch! Expected $PACKAGE_VERSION but got $INSTALLED_VERSION" | tee -a "$LOG_FILE"
    exit 1
fi
