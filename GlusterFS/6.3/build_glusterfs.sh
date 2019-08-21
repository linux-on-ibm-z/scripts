#!/bin/bash
# © Copyright IBM Corporation 2018, 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/GlusterFS/6.3/build_glusterfs.sh
# Execute build script: bash build_glusterfs.sh    (provide -h for help)
#

set -e

PACKAGE_NAME="glusterfs"
PACKAGE_VERSION="6.3"
CURDIR="$(pwd)"
BUILD_DIR="/usr/local"
REPO_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/GlusterFS/6.3/patch/"

LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
TEST_USER="$(whoami)"
FORCE="false"
TESTS="false"

trap cleanup 0 1 2 ERR

# Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
	mkdir -p "$CURDIR/logs/"
fi

# Need handling for RHEL 6.10 as it doesn't have os-release file
if [ -f "/etc/os-release" ]; then
	source "/etc/os-release"
else
	cat /etc/redhat-release >>"$LOG_FILE"
	export ID="rhel"
	export VERSION_ID="6.x"
	export PRETTY_NAME="Red Hat Enterprise Linux 6.x"
fi

function prepare() {

	if [[ "${TEST_USER}" != "root" ]]; then
		printf -- 'Cannot run GlusterFS as non-root . Please switch to superuser \n' | tee -a "$LOG_FILE"
		exit 1
	fi

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
			*) echo "Please provide Correct input to proceed." ;;
			esac
		done
	fi
}

function cleanup() {

    if [[ "${ID}" != "rhel" ]]; then
		rm -rf "${CURDIR}/io-threads.h.diff"
	fi

	# For RHEL
	if [[ "${ID}" == "rhel" ]]; then
		rm -rf "${CURDIR}/userspace-rcu"
	fi

	if [[ "${TESTS}" == "true" ]]; then

		if [[ "${ID}" == "rhel" ]]; then
			rm -rf "${CURDIR}/dbench"
            rm -rf "${CURDIR}/thin-provisioning-tools"
        fi

		if [[ "${ID}" == "sles" ]]; then
            rm -rf "${CURDIR}/dbench"
			rm -rf "${CURDIR}/yajl"

            if [[ "$DISTRO" == "sles-12.4" ]]; then
                rm -rf "${CURDIR}/thin-provisioning-tools"
            fi
		fi

		#cleaning patches
		rm -rf "${CURDIR}/throttle-rebal.t.diff"
		rm -rf "${CURDIR}/bug-847622.t.diff"

		if [[ "${DISTRO}" == "sles-12.4" ||  "${DISTRO}" == "ubuntu-16.04" ]]; then
			rm -rf "${CURDIR}/run-tests.sh.diff"
		fi
	fi
	printf -- '\nCleaned up the artifacts\n'
}

function configureAndInstall() {
	if command -v "$PACKAGE_NAME" > /dev/null; then
			printf -- "%s is detected with version %s .\n" "$PACKAGE_NAME" "$PACKAGE_VERSION" | tee -a "$LOG_FILE"
			runTest
			exit 0
	fi 

	printf -- '\nConfiguration and Installation started \n' 

	# Installing dependencies
	printf -- 'User responded with Yes. \n' 
	printf -- 'Building dependencies\n' 

	cd "${CURDIR}"

	# Only for RHEL
	if [[ "${ID}" == "rhel" ]]; then
		printf -- 'Building URCU\n' 
		wget https://lttng.org/files/urcu/userspace-rcu-0.10.2.tar.bz2
        tar xvjf userspace-rcu-0.10.2.tar.bz2
        cd userspace-rcu-0.10.2
        ./configure --prefix=/usr --libdir=/usr/lib64
        make
        make install
		printf -- 'URCU installed successfully\n' 
	fi

	cd "${CURDIR}"

	# Download and configure GlusterFS
	printf -- '\nDownloading GlusterFS. Please wait.\n' 
	git clone -b v"${PACKAGE_VERSION}" https://github.com/gluster/glusterfs.git
	cd "${CURDIR}/glusterfs"
	./autogen.sh
	if [[ "${DISTRO}" == "sles-12.4" ]]; then
		./configure --enable-gnfs --disable-events # For SLES 12 SP4
	else
		./configure --enable-gnfs # For RHEL, SLES 15 and Ubuntu
	fi

	if [[ "${ID}" != "rhel" ]]; then
		#Patch to be applied here
		cd "${CURDIR}"
		curl -o io-threads.h.diff $REPO_URL/io-threads.h.diff
		patch "${CURDIR}/glusterfs/xlators/performance/io-threads/src/io-threads.h" io-threads.h.diff
	fi

	# Build GlusterFS
	printf -- '\nBuilding GlusterFS \n' 
	printf -- '\nBuild might take some time...........\n'
	 #Give permission to user
	sudo chown -R "$USER" "$CURDIR/glusterfs"

	cd "${CURDIR}/glusterfs"
	make
	make install
	export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib
	ldconfig
	printenv >>"$LOG_FILE"
	printf -- 'Built GlusterFS successfully \n\n' 

	sudo chmod -Rf 755 glusterfs
    sudo cp -Rf glusterfs "$BUILD_DIR"/glusterfs

	 #Add haproxy to /usr/bin
	cd "$BUILD_DIR"/glusterfs
    sudo cp glusterfs /usr/bin/


	cd "${HOME}"
	if [[ "$(grep LD_LIBRARY_PATH .bashrc)" ]]; then
		printf -- '\nChanging LD_LIBRARY_PATH\n' 
		sed -n 's/^.*\bLD_LIBRARY_PATH\b.*$/export LD_LIBRARY_PATH=\/usr\/local\/lib/p' .bashrc 

	else
		echo "export LD_LIBRARY_PATH=/usr/local/lib" >>.bashrc
	fi

	# Run Tests
	runTest
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
	echo "  install.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests]"
	echo
}

function runTest() {
	set +e

	if [[ "$TESTS" == "true" ]]; then
		echo "Running Tests: "
        if [[ "${ID}" == "ubuntu" ]]; then
            sudo apt-get install -y acl attr bc dbench dnsutils libxml2-utils net-tools nfs-common psmisc python3-pyxattr thin-provisioning-tools vim xfsprogs yajl-tools
        fi
        
        if [[ "${ID}" == "rhel" ]]; then
            sudo yum install -y acl attr bc bind-utils boost-devel docbook-style-xsl expat-devel gcc-c++ gdb net-tools nfs-utils psmisc pyxattr vim xfsprogs yajl
             # Install dbench
            cd "${CURDIR}"
            git clone https://github.com/sahlberg/dbench
            cd dbench
            ./autogen.sh
            ./configure
            make
            make install
            # Install thin provisioning tools
            cd "${CURDIR}"
            git clone https://github.com/jthornber/thin-provisioning-tools
            cd thin-provisioning-tools
            git checkout v0.7.6
            autoreconf
            ./configure
            make
            make install
        fi

        if [[ "$DISTRO" == "sles-12.4" ]]; then
            sudo zypper install -y acl attr bc bind-utils boost-devel gcc-c++ gdb libexpat-devel libxml2-tools net-tools nfs-utils psmisc vim xfsprogs which yajl
            # Install dbench
            cd "${CURDIR}"
            git clone https://github.com/sahlberg/dbench
            cd dbench
            ./autogen.sh
            ./configure
            make
            make install
			sudo ln -s /usr/local/bin/dbench /usr/bin/dbench
            # Install thin provisioning tools
            cd "${CURDIR}"
            git clone https://github.com/jthornber/thin-provisioning-tools
            cd thin-provisioning-tools
            git checkout v0.7.6
            autoreconf
            ./configure
            make
            make install
            # Install YAJL
            cd "${CURDIR}"
            git clone https://github.com/lloyd/yajl
            cd yajl
            git checkout 2.1.0
            ./configure
            make install
			sudo ln -s /usr/local/bin/json_verify /usr/bin/json_verify
        fi
        
        if [[ "$DISTRO" == "sles-15" ]] || [[ "$DISTRO" == "sles-15.1" ]]; then
            sudo zypper install -y acl attr bc bind-utils gdb libxml2-tools net-tools-deprecated nfs-utils psmisc thin-provisioning-tools vim xfsprogs yajl 
            # Install dbench            
            cd "${CURDIR}"
            git clone https://github.com/sahlberg/dbench
            cd dbench
            ./autogen.sh
            ./configure
            make
            make install
			sudo ln -s /usr/local/bin/dbench /usr/bin/dbench
            # Install YAJL
            cd "${CURDIR}"
            git clone https://github.com/lloyd/yajl
            cd yajl
            git checkout 2.1.0
            ./configure
            make install
			sudo ln -s /usr/local/bin/json_verify /usr/bin/json_verify
        fi
        
		# Apply 2 patches
		cd "${CURDIR}"

		# Patch test script for SLES 12 SP4 and Ubuntu 16.04
		
		if [[ "${DISTRO}" == "sles-12.4" ||  "${DISTRO}" == "ubuntu-16.04" ]]; then
			curl -o run-tests.sh.diff $REPO_URL/run-tests.sh.diff
			patch "${CURDIR}/glusterfs/run-tests.sh" run-tests.sh.diff
			printf -- "Patch run-tests.sh.diff success\n" 

		fi



		ssh-keygen -t rsa
		cat /root/.ssh/id_rsa.pub | cat >>/root/.ssh/authorized_keys

		# Run the test cases
		cd "${CURDIR}/glusterfs"

		# Apply patch 
			curl -o test-patch.diff $REPO_URL/test-patch.diff
			git apply test-patch.diff
			printf -- "Patch test-patch.diff success\n" 

		./run-tests.sh 

		#test cases failure
		if [[ "$(grep -q 'FAILED COMMAND' ${LOG_FILE})" ]]; then
			printf -- 'Test cases failed with unknown failures. \n\n' 
		fi

	fi

	set -e

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

function printSummary() {

	printf -- '\n********************************************************************************************************\n'
	printf -- "\n* Getting Started * \n"	
	printf -- '\nSet LD_LIBRARY_PATH to start using GlusterFS right away.'
	printf -- "\nexport LD_LIBRARY_PATH=/usr/local/lib \n" 
	printf -- '\nOR Restart the session to apply the changes'
	printf -- '\ncommand to run the GlusterFS Daemon : glusterd' 
	printf -- '\nFor more information on GlusterFS visit https://www.gluster.org/ \n\n'
	printf -- '**********************************************************************************************************\n'
}

logDetails
prepare

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04" | "ubuntu-19.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
	apt-get update
	apt-get install -y autoconf automake bison curl flex gcc git libacl1-dev libaio-dev libfuse-dev libglib2.0-dev libibverbs-dev librdmacm-dev libreadline-dev libssl-dev libtool liburcu-dev libxml2-dev lvm2 make openssl pkg-config python3 uuid-dev zlib1g-dev patch
	configureAndInstall | tee -a "$LOG_FILE"
	;;

"rhel-7.5" | "rhel-7.6")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
	yum install -y autoconf automake bison bzip2 curl flex fuse-devel gcc git glib2-devel libacl-devel libaio-devel libibverbs-devel librdmacm-devel libtool libxml2-devel libuuid-devel lvm2 make openssl-devel pkgconfig python readline-devel wget zlib-devel patch
	configureAndInstall | tee -a "$LOG_FILE"

	;;

"sles-12.4" | "sles-15" | "sles-15.1")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
	zypper install -y autoconf automake bison cmake curl flex fuse-devel gcc git glib2-devel libacl-devel libaio-devel librdmacm1 libopenssl-devel libtool liburcu-devel libuuid-devel libxml2-devel lvm2 make pkg-config python3 rdma-core-devel readline-devel zlib-devel patch gawk
	configureAndInstall | tee -a "$LOG_FILE"

	;;

*)
	printf -- "%s not supported \n" "$DISTRO" | tee -a "$LOG_FILE"
	exit 1
	;;
esac

printSummary | tee -a "$LOG_FILE"
