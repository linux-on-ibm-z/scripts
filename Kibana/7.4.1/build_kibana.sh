#!/bin/bash
# ©  Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Kibana/7.4.1/build_kibana.sh
# Execute build script: bash build_kibana.sh    (provide -h for help)
#
set -e -o pipefail

PACKAGE_NAME="kibana"
PACKAGE_VERSION="7.4.1"

FORCE=false
CURDIR="$(pwd)"
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
REPO_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Kibana/${PACKAGE_VERSION}/patch"
NON_ROOT_USER="$(whoami)"

trap cleanup 1 2 ERR

# Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
   mkdir -p "$CURDIR/logs/"
fi

# Need handling for RHEL 6.10 as it doesn't have os-release file
if [ -f "/etc/os-release" ]; then
	source "/etc/os-release"
else
	cat /etc/redhat-release >>"${LOG_FILE}"
	export ID="rhel"
	export VERSION_ID="6.x"
	export PRETTY_NAME="Red Hat Enterprise Linux 6.x"
fi

function prepare() {
	if command -v "sudo" > /dev/null; then
		printf -- 'Sudo : Yes\n' >> "$LOG_FILE"
	else
		printf -- 'Sudo : No \n' >> "$LOG_FILE"
		printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n'
		exit 1
	fi

	if [[ "$FORCE" == "true" ]]; then
		printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "${LOG_FILE}"
	else
		# Ask user for prerequisite installation
		printf -- "\nAs part of the installation , dependencies would be installed/upgraded, \n"
		while true; do
			read -r -p "Do you want to continue (y/n) ? :  " yn
			case $yn in
			[Yy]*)
				printf -- 'User responded with Yes. \n' >> "${LOG_FILE}"
				break
				;;
			[Nn]*) exit ;;
			*) echo "Please provide confirmation to proceed." ;;
			esac
		done
	fi
}

function cleanup() {
	sudo rm -rf "${CURDIR}/node-v10.15.2-linux-s390x.tar.gz" "${CURDIR}/gcc-4.9.4.tar.gz" "${CURDIR}/kibana"
	printf -- 'Cleaned up the artifacts\n' >>"${LOG_FILE}"
}

function configureAndInstall() {
	printf -- '\nConfiguration and Installation started.\n'

    # Install gcc 4.9.4
    if [[ "$ID" == "rhel" ]]; then
        printf -- 'Building GCC 4.9.4.\n'
        cd "${CURDIR}"
        wget http://ftp.gnu.org/gnu/gcc/gcc-4.9.4/gcc-4.9.4.tar.gz
        tar xzf gcc-4.9.4.tar.gz
        cd gcc-4.9.4/
        ./contrib/download_prerequisites
        mkdir build
        cd build/
        ../configure --enable-shared --disable-multilib --enable-threads=posix --with-system-zlib --enable-languages=c,c++
        make
        sudo make install
        export PATH=/usr/local/bin:$PATH
        export LD_LIBRARY_PATH=/usr/local/lib64:$LD_LIBRARY_PATH
        printf -- 'Built GCC 4.9.4 successfully. \n'
    fi

    # Installing Node.js
    printf -- 'Downloading and installing Node.js.\n'
    cd "${CURDIR}"
    sudo mkdir -p /usr/local/lib/nodejs
    wget https://nodejs.org/dist/v10.15.2/node-v10.15.2-linux-s390x.tar.gz
    sudo tar xzvf node-v10.15.2-linux-s390x.tar.gz -C /usr/local/lib/nodejs
    sudo ln -s /usr/local/lib/nodejs/node-v10.15.2-linux-s390x/bin/* /usr/bin/
    node -v  >> "${LOG_FILE}"

    # Installing Yarn
    printf -- 'Downloading and installing Yarn.\n'
    cd "${CURDIR}"
    curl -o- -L https://yarnpkg.com/install.sh | bash
    export PATH="$HOME/.yarn/bin:$HOME/.config/yarn/global/node_modules/.bin:$PATH"
    yarn -v  >> "${LOG_FILE}"

    # Downloading and installing Kibana
    printf -- '\nDownloading and installing Kibana.\n'
    cd "${CURDIR}"
    git clone -b v$PACKAGE_VERSION https://github.com/elastic/kibana.git
    cd kibana

    # Applying patch
    wget $REPO_URL/kibana_patch.diff
    git apply kibana_patch.diff

    # Bootstrap Kibana
    yarn kbn bootstrap --oss

    # Installing Elastic NodeGit
    cd node_modules/@elastic/
    git clone -b v0.25.0-alpha.22 https://github.com/elastic/nodegit.git
    cd nodegit

    # Patching NodeGit
    wget $REPO_URL/nodegit_patch.diff
    git apply nodegit_patch.diff

    # Building NodeGit
    npm install

    # Building Kibana
    cd "${CURDIR}"/kibana
    yarn build --skip-os-packages --oss

    # Installing Kibana
    sudo mkdir /usr/share/kibana/
    sudo tar -xzf target/kibana-oss-"$PACKAGE_VERSION"-SNAPSHOT-linux-x86_64.tar.gz -C /usr/share/kibana --strip-components 1
    sudo ln -sf /usr/share/kibana/bin/* /usr/bin/

    if ([[ -z "$(cut -d: -f1 /etc/group | grep elastic)" ]]); then
        printf -- '\nCreating group elastic.\n'
        sudo /usr/sbin/groupadd elastic # If group is not already created
    fi
    sudo chown "$NON_ROOT_USER:elastic" -R /usr/share/kibana

    cd /usr/share/kibana/

	printf -- 'Installed Kibana successfully.\n'

	# Cleanup
	cleanup

	# Verify kibana installation
	if command -v "$PACKAGE_NAME" >/dev/null; then
		printf -- "%s installation completed. Please check the Usage to start the service.\n" "$PACKAGE_NAME"
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
	echo "  install.sh  [-d debug] [-y install-without-confirmation]"
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
	printf -- '\n*********************************************************************************************\n'
	printf -- "Getting Started:\n\n"
	printf -- "Kibana requires an Elasticsearch instance to be running. \n"
	printf -- "Set Kibana home directory:\n"
	printf -- "     export KIBANA_HOME=/usr/share/kibana\n"
	printf -- "     export LD_LIBRARY_PATH=/usr/local/lib64:\$LD_LIBRARY_PATH (RHEL only)\n\n"
	printf -- "Update the Kibana configuration file \$KIBANA_HOME/config/kibana.yml accordingly.\n"
	printf -- "Start Kibana: \n"
	printf -- "     kibana & \n\n"
	printf -- "Access the Kibana UI using the below link: "
	printf -- "https://<Host-IP>:<Port>/    [Default Port = 5601] \n"
	printf -- '*********************************************************************************************\n'
	printf -- '\n'
}

###############################################################################################################

logDetails
prepare

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04")
	printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
	sudo apt-get update
	sudo apt-get install -y curl git g++ gzip libssl-dev make python tar wget |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

"rhel-7.5" | "rhel-7.6" | "rhel-7.7")
	printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
	sudo yum install -y autoconf automake bzip2 gcc-c++ git gzip libtool make openssl-devel python tar wget zlib-devel |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

"sles-12.4")
	printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
	sudo zypper install -y curl git gcc-c++ gzip libopenssl-devel make python tar wget |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "${LOG_FILE}"
	exit 1
	;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
