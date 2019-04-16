#!/bin/bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Beats/build_beats.sh
# Execute build script: bash build_beats.sh    (provide -h for help)
#

set -e  -o pipefail

PACKAGE_NAME="beats"
PACKAGE_VERSION="6.6.0"
CURDIR="$(pwd)"
USER="$(whoami)"

GO_INSTALL_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Go/build_go.sh"

#PATCH_URL
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Beats/6.6.0/patch"

#Default GOPATH if not present already.
GO_DEFAULT="$HOME/go"

FORCE="false"
TESTS="false"
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exists
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
    printf -- "Cleaned up the artifacts\n" >> "$LOG_FILE"

}
function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'
	

	 # Install go
	 
	 printf -- "Installing Go... \n" 
	 curl $GO_INSTALL_URL | bash -s -- -v 1.10.8
	 rm build_go.sh
	
    # Set GOPATH if not already set
	if [[ -z "${GOPATH}" ]]; then
		printf -- "Setting default value for GOPATH \n"

		#Check if go directory exists
		if [ ! -d "$HOME/go" ]; then
	    	 mkdir "$HOME/go"
		fi
		export GOPATH="${GO_DEFAULT}"
		export PATH=$PATH:$GOPATH/bin
		export PATH=$PATH:/usr/local/go/bin
	else
		printf -- "GOPATH already set : Value : %s \n" "$GOPATH"
	fi
    
	# Install beats
	printf -- '\nInstalling beats..... \n'

    #Checking permissions
    setfacl -dm u::rwx,g::r,o::r $GOPATH
    cd $GOPATH
    touch test && ls -la test && rm test

	#Install Python modules
	
	sudo python -m easy_install pip
	sudo python -m pip install appdirs pyparsing six packaging setuptools wheel PyYAML termcolor ordereddict nose-timer MarkupSafe virtualenv
	
	# Download Beats Source
	if [ ! -d "$GOPATH/src/github.com/elastic" ]; then
		mkdir -p $GOPATH/src/github.com/elastic
	fi
    cd $GOPATH/src/github.com/elastic
    
    sudo rm -rf beats
    git clone https://github.com/elastic/beats.git
	cd beats
    git checkout v$PACKAGE_VERSION

	#Adding fixes and patches to the files
	fileChanges	

	#Making directory to add .yml files
	if [ ! -d "/etc/beats/" ]; then
		sudo mkdir -p /etc/beats
	fi

	# Install mage build dependency
	cd $GOPATH
	go get -u -d github.com/magefile/mage
	cd $GOPATH/src/github.com/magefile/mage
	go run bootstrap.go
	export PATH=$PATH:$GOPATH/bin

	#Building packetbeat and adding to usr/bin
	cd $GOPATH/src/github.com/elastic/beats/packetbeat
	make
    ./packetbeat --version
	make update
	sudo cp "./packetbeat" /usr/bin/
	sudo cp "./packetbeat.yml" /etc/beats/
	
	
	sudo chown -R $USER "$GOPATH/src/github.com/elastic/beats/"
	#Building filebeat and adding to usr/bin
	cd $GOPATH/src/github.com/elastic/beats/filebeat
    make
    ./filebeat --version
	make update
	sudo cp "./filebeat" /usr/bin/
	sudo cp "./filebeat.yml" /etc/beats/

	#Building metricbeat and adding to usr/bin
	cd $GOPATH/src/github.com/elastic/beats/metricbeat
	make
    ./metricbeat --version
	make update
	sudo cp "./metricbeat" /usr/bin/
	sudo cp "./metricbeat.yml" /etc/beats/

	#Building libbeat and adding to usr/bin
	cd $GOPATH/src/github.com/elastic/beats/libbeat
    make
    ./libbeat --version
	make update
	sudo cp "./libbeat" /usr/bin/
 	sudo cp "./libbeat.yml" /etc/beats/


	#Building heartbeat and adding to usr/bin
	cd $GOPATH/src/github.com/elastic/beats/heartbeat
    make
    ./heartbeat --version
	make update
	sudo cp "./heartbeat" /usr/bin/
	sudo cp "./heartbeat.yml" /etc/beats/

	#Building auditbeat and adding to usr/bin
	cd $GOPATH/src/github.com/elastic/beats/auditbeat
    make
    ./auditbeat --version
	sudo cp "./auditbeat" /usr/bin/
	sudo cp "./auditbeat.yml" /etc/beats/
		
	# Run Tests
	runTest

	#Cleanup
	cleanup

	printf -- "\n Installation of %s %s was sucessfull \n\n" $PACKAGE_NAME $PACKAGE_VERSION
}

function fileChanges(){

	cd $GOPATH/src/github.com/elastic/beats


	#Fix Failed to get audit error
	printf -- 'Fix Failed to get audit error : Edited audit.go\n'
	cp vendor/github.com/elastic/go-libaudit/audit.go vendor/github.com/elastic/go-libaudit/audit.go.orig
	curl $PATCH_URL/audit.go.patch > vendor/github.com/elastic/go-libaudit/audit.go.patch
	patch --ignore-whitespace vendor/github.com/elastic/go-libaudit/audit.go < vendor/github.com/elastic/go-libaudit/audit.go.patch
	

	#Edit netlink.go
	printf -- 'Edit netlink.go\n'
	cp vendor/github.com/elastic/go-libaudit/netlink.go vendor/github.com/elastic/go-libaudit/netlink.go.orig
	curl $PATCH_URL/netlink.go.patch > vendor/github.com/elastic/go-libaudit/netlink.go.patch
	patch --ignore-whitespace vendor/github.com/elastic/go-libaudit/netlink.go < vendor/github.com/elastic/go-libaudit/netlink.go.patch
	

	#Edit file binary.go
	printf -- 'Edit binary.go\n'
	cp vendor/github.com/elastic/go-libaudit/rule/binary.go vendor/github.com/elastic/go-libaudit/rule/binary.go.orig
	curl $PATCH_URL/binary.go.patch > vendor/github.com/elastic/go-libaudit/rule/binary.go.patch
	patch --ignore-whitespace vendor/github.com/elastic/go-libaudit/rule/binary.go < vendor/github.com/elastic/go-libaudit/rule/binary.go.patch
	

	#Creating endian.go
	printf -- 'Create endian.go\n'
	curl $PATCH_URL/endian.go > $GOPATH/src/github.com/elastic/beats/vendor/github.com/elastic/go-libaudit/endian.go


	#Edit file test_harvester.py
	printf -- 'Edit test_harvester.py\n'
	cp filebeat/tests/system/test_harvester.py filebeat/tests/system/test_harvester.py.orig
	curl $PATCH_URL/test_harvester.py.patch > filebeat/tests/system/test_harvester.py.patch
	patch --ignore-whitespace filebeat/tests/system/test_harvester.py < filebeat/tests/system/test_harvester.py.patch


	#Edit file xxhash_safe.go
	printf -- 'Edit xxhash_safe.go\n'
	cp vendor/github.com/OneOfOne/xxhash/xxhash_safe.go vendor/github.com/OneOfOne/xxhash/xxhash_safe.go.orig
	curl $PATCH_URL/xxhash_safe.go.patch > vendor/github.com/OneOfOne/xxhash/xxhash_safe.go.patch
	patch --ignore-whitespace vendor/github.com/OneOfOne/xxhash/xxhash_safe.go < vendor/github.com/OneOfOne/xxhash/xxhash_safe.go.patch


	#Edit file xxhash_unsafe.go
	printf -- 'Edit xxhash_unsafe.go\n'
	cp vendor/github.com/OneOfOne/xxhash/xxhash_unsafe.go vendor/github.com/OneOfOne/xxhash/xxhash_unsafe.go.orig
	curl $PATCH_URL/xxhash_unsafe.go.patch > vendor/github.com/OneOfOne/xxhash/xxhash_unsafe.go.patch
	patch --ignore-whitespace vendor/github.com/OneOfOne/xxhash/xxhash_unsafe.go < vendor/github.com/OneOfOne/xxhash/xxhash_unsafe.go.patch

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
		printf -- "\nTesting Filebeat Completed Sucessfully\n"

		#PACKETBEAT
		printf -- "\nTesting Packetbeat\n"
		cd $GOPATH/src/github.com/elastic/beats/packetbeat
		make unit
		make system-tests
		printf -- "\nTesting Packetbeat completed Sucessfully\n"


		#METRICBEAT
		printf -- "\nTesting Metricbeat\n"
		cd $GOPATH/src/github.com/elastic/beats/metricbeat
		make unit 
		make system-tests
		printf -- "\nTesting Metricbeat Completed Sucessfully\n"

		#LIBBEAT
		printf -- "\nTesting Libbeat\n"
		cd $GOPATH/src/github.com/elastic/beats/libbeat
		make unit
		make system-tests 
		printf -- "\nTesting Libbeat Completed Sucessfully\n"
		
		#HEARTBEAT
		printf -- "\nTesting Heartbeat\n"
		cd $GOPATH/src/github.com/elastic/beats/heartbeat
		make unit
		make system-tests
		printf -- "\nTesting Heartbeat Completed Sucessfully\n"

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
	echo "  install.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests]"
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
"ubuntu-16.04" | "ubuntu-18.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo apt-get update 
	sudo apt-get install -y git curl make wget tar gcc python python-setuptools libcap-dev libpcap0.8-dev openssl libssh-dev python-openssl acl rsync tzdata patch fdclone  |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

"rhel-7.4" | "rhel-7.5" | "rhel-7.6")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo yum install -y git curl make wget tar gcc libpcap libpcap-devel openssl openssl-devel which acl zlib-devel patch   |& tee -a "${LOG_FILE}"
	sudo yum install -y python
    #Installing pip
    wget https://bootstrap.pypa.io/get-pip.py
    sudo python get-pip.py
    rm get-pip.py
    
    configureAndInstall |& tee -a "${LOG_FILE}"
	;;

"sles-12.4" | "sles-15")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo zypper install -y git curl awk make wget tar gcc libpcap libpcap-devel python-setuptools git python-xml python python-devel python-cffi openssl-devel libffi-devel acl patch  |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
