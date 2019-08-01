#!/usr/bin/env bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/PostgreSQL/11.4/build_postgresql.sh
# Execute build script: bash build_postgresql.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="postgresql"
PACKAGE_VERSION="11.4"
CURDIR="$(pwd)"
POSTGRES_DIR="/home/postgres/"

FORCE="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exsists
if [ ! -d "$CURDIR/logs" ]; then
	mkdir -p "$CURDIR/logs"
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

function checkPrequisites() {
	if command -v "sudo" >/dev/null; then
		printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
	else
		printf -- 'Sudo : No \n' >>"$LOG_FILE"
		printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n'
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
	printf -- 'No artifacts to be cleaned.\n'
}

function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'

	# Create postgres user, group and home directory
	sudo groupadd -r postgres || echo "group already exist"
	sudo useradd -r -m -g postgres postgres || echo "user already exist"	
	sudo -i -u postgres /bin/bash - <<'EOF'
	  			#Change directory to postgres source code
	 			cd /home/postgres/
	 			rm -rf  postgres
	 			git clone git://github.com/postgres/postgres.git
	 			cd postgres
	 			git checkout REL_11_4
	            #Configure, build and test the build
	 			./configure
	 			make
	 			unset LANG
	 			make check
EOF

	if [[ "$ID" == "rhel" ]]; then
		sudo chown -R "$USER" $POSTGRES_DIR
	fi
	cd $POSTGRES_DIR/postgres
	sudo make install
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
	echo "  build_postgresql.sh [-d debug]"
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

	printf -- "\n\nUsage: \n"
	printf -- "  PostgreSQL installed successfully \n"
	printf -- "  Update the PATH variable using :\n"
	printf -- '    export PATH=$PATH:/usr/local/pgsql/bin \n'
	printf -- "  More information can be found here : https://www.postgresql.org/, https://github.com/postgres/postgres.git \n"
	printf -- '\n'
}

###############################################################################################################

logDetails
checkPrequisites #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04" | "ubuntu-19.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for postgresql from repository \n' |& tee -a "$LOG_FILE"
	sudo apt-get update >/dev/null
	sudo apt-get -y install bison flex wget build-essential git gcc make zlib1g-dev libreadline-dev |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"rhel-6.x" | "rhel-7.5" | "rhel-7.6" | "rhel-8.0")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for postgresql from repository \n' |& tee -a "$LOG_FILE"

	if [[ "$ID" == "rhel" && "$VERSION_ID" == "8.0" ]]; then	
	sudo yum update -y |& tee -a "$LOG_FILE"
	sudo yum install -y git wget gcc gcc-c++ make readline-devel zlib-devel bison flex  glibc-langpack-en procps-ng |& tee -a "$LOG_FILE"
	else
	sudo yum install -y git wget build-essential gcc gcc-c++ make readline-devel zlib-devel bison flex |& tee -a "$LOG_FILE"
	fi

	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"sles-12.4" | "sles-15")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for postgresql from repository \n' |& tee -a "$LOG_FILE"
	sudo zypper install -y git gcc gcc-c++ make readline-devel zlib-devel bison flex awk |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "$LOG_FILE"
