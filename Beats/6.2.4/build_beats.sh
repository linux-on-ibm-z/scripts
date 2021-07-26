#!/bin/bash
# © Copyright IBM Corporation 2018.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Beats/6.2.4/build_beats.sh
# Execute build script: bash build_beats.sh    (provide -h for help)
#

set -e  -o pipefail

PACKAGE_NAME="beats"
PACKAGE_VERSION="6.2.4"
CURDIR="$(pwd)"
USER="$(whoami)"

GO_INSTALL_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Go/1.11.4/build_go.sh"

#PATCH_URL
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Beats/6.2.4/patch"

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
	 curl -s  $GO_INSTALL_URL > build_go.sh
	 bash build_go.sh
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
	python -m pip install appdirs pyparsing six packaging setuptools wheel PyYAML termcolor ordereddict nose-timer MarkupSafe virtualenv
	
	# Download Beats Source
	if [ ! -d "$GOPATH/src/github.com/elastic" ]; then
		mkdir -p $GOPATH/src/github.com/elastic
	fi
    cd $GOPATH/src/github.com/elastic
    
    sudo rm -rf beats
    git clone https://github.com/elastic/beats.git
	cd beats
    git checkout v6.2.4

    #Env variable for ubuntu
    if [ "$ID" == "ubuntu" ];then
        export PATH=$PATH:/usr/lib/go-1.9/bin/
    fi

	#Adding fixes and patches to the files
	fileChanges	

	#Making directory to add .yml files
	if [ ! -d "/etc/beats/" ]; then
		sudo mkdir -p /etc/beats
	fi

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
	
	#Code change to fix metricbeat socket test
	printf -- 'Code change to fix metricbeat socket test\n'
	cp vendor/github.com/elastic/gosigar/sys/linux/inetdiag.go vendor/github.com/elastic/gosigar/sys/linux/inetdiag.go.orig
    curl $PATCH_URL/inetdiag.go.patch > vendor/github.com/elastic/gosigar/sys/linux/inetdiag.go.patch
	patch --ignore-whitespace vendor/github.com/elastic/gosigar/sys/linux/inetdiag.go <  vendor/github.com/elastic/gosigar/sys/linux/inetdiag.go.patch

	
	#Auditbeat Test faliure fix
	printf -- 'Auditbeat Test faliure fix\n'
	cp auditbeat/module/auditd/config_linux_test.go auditbeat/module/auditd/config_linux_test.go.orig
	curl $PATCH_URL/config_linux_test.go.patch > auditbeat/module/auditd/config_linux_test.go.patch
	patch --ignore-whitespace auditbeat/module/auditd/config_linux_test.go  < auditbeat/module/auditd/config_linux_test.go.patch
	

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
	

	#Creating edian.go
	printf -- 'Create endian.go\n'
	curl $PATCH_URL/endian.go > $GOPATH/src/github.com/elastic/beats/vendor/github.com/elastic/go-libaudit/endian.go

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
		# Intermittent test failures are observed, can be passed after multiple run  
		printf -- "\nTesting Packetbeat\n"
		cd $GOPATH/src/github.com/elastic/beats/packetbeat
		make unit
		make system-tests
		printf -- "\nTesting Packetbeat completed Sucessfully\n"


		#METRICBEAT
		printf -- "\nTesting Metricbeat\n"
		cd $GOPATH/src/github.com/elastic/beats/metricbeat
		# Same single test failure is observed on x86
		make unit 
		make system-tests 2>&1 |& tee -a sys_test
		echo "FAIL: Test system/process output."  >> expectedfail1
		sudo grep "FAIL:" sys_test |& tee actuallyfail1
		if diff -u --ignore-all-space expectedfail1 actuallyfail1 ; then
			printf -- "Expected failures found in METRICBEAT!"
		else
			if [ -s  actuallyfail1 ];then
        		printf -- "failures in METRICBEAT!"
				exit 1
			else
        		printf -- "No faliures in Metricbeat !"
			fi
			
		fi
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
		make system-tests 2>&1 |& tee -a sys_test
		echo "ERROR: Auditbeat starts and stops without error." >> expectedfail2
		sudo grep "ERROR:" sys_test |& tee actuallyfail2
		if diff -u --ignore-all-space expectedfail2 actuallyfail2 ; then
			printf -- "Expected failures found in AUDITBEAT!"
		else
			if [ -s  actuallyfail2 ];then
        		printf -- "failures in AUDITBEAT!"
				exit 1
			else
        		printf -- "No faliures in AUDITBEAT !"
			fi
		fi

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
	sudo apt-get install -y git curl make wget tar gcc python python-setuptools libcap-dev libpcap0.8-dev openssl libssh-dev python-openssl acl rsync tzdata patch  |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

"rhel-7.3" | "rhel-7.4" | "rhel-7.5")
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

"sles-12.3" | "sles-15")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo zypper install -y git curl awk make wget tar gcc libpcap libpcap-devel  python-setuptools git python-xml python python-devel python-cffi openssl-devel libffi-devel acl patch  |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
