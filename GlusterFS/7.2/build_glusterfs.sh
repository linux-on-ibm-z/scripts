#!/bin/bash
# © Copyright IBM Corporation 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/GlusterFS/7.2/build_glusterfs.sh
# Execute build script: bash build_glusterfs.sh    (provide -h for help)
#

set -e

PACKAGE_NAME="glusterfs"
PACKAGE_VERSION="7.2"
CURDIR="$(pwd)"
BUILD_DIR="/usr/local"
REPO_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/GlusterFS/7.2/patch"

LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
TEST_USER="$(whoami)"
FORCE="false"
TESTS="false"

trap cleanup 0 1 2 ERR

# Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
	mkdir -p "$CURDIR/logs/"
fi

source "/etc/os-release"

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

    if [[ "${ID}" == "ubuntu" ]] || [[ "${ID}" == "sles" ]] || [[ "${DISTRO}" == "rhel-8.0" ]]; then
		rm -rf "${CURDIR}/io-threads.h.diff"
	fi

	# For RHEL
	if [[ "${ID}" == "rhel" ]]; then
		rm -rf "${CURDIR}/userspace-rcu"
	fi

	# For RHEL
	if [[ "${DISTRO}" == "rhel-8.0" ]]; then
		rm -rf "${CURDIR}/rpcsvc-proto-1.4"
		rm -rf "${CURDIR}/rpcsvc-proto-1.4.tar.gz"
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
		if [[ "${ID}" != "ubuntu" ]]; then
		  rm -rf "${CURDIR}/dbench-test-patch.diff"
		fi

		rm -rf "${CURDIR}/test-patch.diff"

		if [[ "${DISTRO}" == "sles-12.4" ||  "${DISTRO}" == "ubuntu-16.04" ]]; then
			rm -rf "${CURDIR}/run-tests.sh.diff"
		fi
	fi

	rm -rf "${CURDIR}/patch_geo-rep.diff"

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

	# Only for RHEL and SLES 12 SP4
	if [[ "${ID}" == "rhel" ]] || [[ "${DISTRO}" == "sles-12.4" ]]; then
		printf -- 'Building URCU\n' 
		wget https://lttng.org/files/urcu/userspace-rcu-0.10.2.tar.bz2
        tar xvjf userspace-rcu-0.10.2.tar.bz2
        cd userspace-rcu-0.10.2
        ./configure --prefix=/usr --libdir=/usr/lib64
        make
        make install
		printf -- 'URCU installed successfully\n' 
	fi

	#Only for RHEL 7.x, SLES 12 SP4, Ubuntu 16.04
	if [[ "${DISTRO}" == "rhel-7.5" ]] || [[ "${DISTRO}" == "rhel-7.6" ]] || [[ "${DISTRO}" == "rhel-7.7" ]] || [[ "${DISTRO}" == "sles-12.4" ]] || [[ "${DISTRO}" == "ubuntu-16.04" ]]; then
		cd $SOURCE_ROOT
		wget https://www.openssl.org/source/old/1.1.1/openssl-1.1.1d.tar.gz
		tar xvf openssl-1.1.1d.tar.gz
		cd openssl-1.1.1d
		./config --prefix=/usr/local --openssldir=/usr/local
		make
		make install
		ldconfig /usr/local/lib64
		export PATH=$PATH:/usr/local/bin
	fi

	# Only for RHEL 8
	if [[ "${DISTRO}" == "rhel-8.0" ]]; then
		printf -- 'Building rpcsvc\n' 
		wget https://github.com/thkukuk/rpcsvc-proto/releases/download/v1.4/rpcsvc-proto-1.4.tar.gz
		tar xzvf rpcsvc-proto-1.4.tar.gz
		cd rpcsvc-proto-1.4
		./configure
		make && make install
		printf -- 'rpcsvc installed successfully\n' 
	fi

	cd "${CURDIR}"

	# Download and configure GlusterFS
	printf -- '\nDownloading GlusterFS. Please wait.\n' 
	git clone -b v"${PACKAGE_VERSION}" https://github.com/gluster/glusterfs.git
	cd "${CURDIR}/glusterfs"
	./autogen.sh
	if [[ "${DISTRO}" == "sles-12.4" ]]; then
		PYTHON=`which python2` ./configure --enable-gnfs --disable-events # For SLES 12 SP4
	else
		./configure --enable-gnfs # For RHEL, SLES 15 SP1 and Ubuntu
	fi

    # Only for Ubuntu, SLES, and RHEL 8
	if [[ "${ID}" == "ubuntu" ]] || [[ "${ID}" == "sles" ]] || [[ "${DISTRO}" == "rhel-8.0" ]]; then
		#Patch to be applied here
		cd "${CURDIR}"
		curl -o io-threads.h.diff $REPO_URL/io-threads.h.diff
		patch --ignore-whitespace "${CURDIR}/glusterfs/xlators/performance/io-threads/src/io-threads.h" io-threads.h.diff
	fi

	# Patch for geo-rep failures
	cd "${CURDIR}"
	curl -o patch_geo-rep.diff $REPO_URL/patch_geo-rep.diff
	patch --ignore-whitespace "${CURDIR}/glusterfs/geo-replication/syncdaemon/monitor.py" patch_geo-rep.diff

	# Build GlusterFS
	printf -- '\nBuilding GlusterFS \n' 
	printf -- '\nBuild might take some time...........\n'
	 #Give permission to user
	chown -R "$USER" "$CURDIR/glusterfs"

	cd "${CURDIR}/glusterfs"
	make
	make install
	export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib
	ldconfig
	printenv >> "$LOG_FILE"
	printf -- 'Built GlusterFS successfully \n\n' 

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

		case "$DISTRO" in
        "ubuntu-16.04" | "ubuntu-18.04" | "ubuntu-19.10")
        	apt-get install -y acl attr bc dbench dnsutils libxml2-utils net-tools nfs-common psmisc python3-pyxattr thin-provisioning-tools vim xfsprogs yajl-tools rpm2cpio gdb cpio
        	;;
        
        "rhel-7.5" | "rhel-7.6" | "rhel-7.7")
        	yum install -y acl attr bc bind-utils boost-devel docbook-style-xsl expat-devel gcc-c++ gdb net-tools nfs-utils psmisc pyxattr vim xfsprogs yajl
        	;;
        
        "rhel-8.0")
        	yum install -y acl attr bc bind-utils boost-devel docbook-style-xsl expat-devel gcc-c++ gdb net-tools nfs-utils psmisc vim xfsprogs yajl redhat-rpm-config python3-pip python3-devel perl-Test-Harness
        	;;
        
        "sles-12.4")
        	zypper install -y acl attr bc bind-utils boost-devel gcc-c++ gdb libexpat-devel libxml2-tools net-tools nfs-utils psmisc vim xfsprogs python-xattr
        	;;
        
        "sles-15.1")
        	zypper install -y acl attr bc bind-utils gdb libxml2-tools net-tools-deprecated nfs-utils psmisc thin-provisioning-tools vim xfsprogs python3-xattr
        	;;
        esac
			
		# Install gstack command (Ubuntu only)
        if [[ "${ID}" == "ubuntu" ]]; then
			cd "${CURDIR}"
			wget http://rpmfind.net/linux/opensuse/update/leap/15.1/oss/x86_64/gdb-8.3.1-lp151.4.3.1.x86_64.rpm
			rpm2cpio gdb-8.3.1-lp151.4.3.1.x86_64.rpm| cpio -idmv
			mv ./usr/bin/gstack /usr/bin/
			rm -r ./etc ./usr
			rm gdb-8.3.1-lp151.4.3.1.x86_64.rpm
        fi
        
		# Install pyxattr (RHEL 8.0 only)
        if [[ "${DISTRO}" == "rhel-8.0" ]]; then
            ln -s /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
			pip3 install pyxattr
        fi

		# Install dbench (RHEL and SLES only)
		if [[ "${ID}" == "rhel" ]] || [[ "${ID}" == "sles" ]]; then
            # Install dbench
            cd "${CURDIR}"
            git clone https://github.com/sahlberg/dbench
            cd dbench
            ./autogen.sh
            ./configure
            make
            make install
	    export PATH=$PATH:/usr/local/bin
        fi

		# Install thin-provisioning-tools (RHEL and SLES 12 SP4 only)
        if [[ "$DISTRO" == "sles-12.4" ]]; then
            cd "${CURDIR}"
            git clone https://github.com/jthornber/thin-provisioning-tools
			cd thin-provisioning-tools
			git checkout v0.7.6
			autoreconf
			./configure
			make
			make install
        fi

		# Install yajl (SLES only)
        if [[ "$DISTRO" == "sles-12.4" || "$DISTRO" == "sles-15.1" ]]; then
            cd "${CURDIR}"
            # Install YAJL
            cd "${CURDIR}"
            git clone https://github.com/lloyd/yajl
            cd yajl
            git checkout 2.1.0
            ./configure
            make install
			ln -s /usr/local/bin/json_verify /usr/bin/json_verify
        fi
        
		# Apply 2 patches
		cd "${CURDIR}/glusterfs"

		# Patch test script for SLES 12 SP4 and Ubuntu 16.04
		if [[ "${DISTRO}" == "sles-12.4" ||  "${DISTRO}" == "ubuntu-16.04" ]]; then
			curl -o run-tests.sh.diff $REPO_URL/run-tests.sh.diff
			patch --ignore-whitespace run-tests.sh run-tests.sh.diff
			printf -- "Patch run-tests.sh.diff success\n" 
		fi

		ssh-keygen -t rsa
		cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys

		# Apply patches
		curl -o test-patch.diff $REPO_URL/test-patch.diff
		git apply --ignore-whitespace test-patch.diff
		printf -- "Patch test-patch.diff success\n" 
		if [[ "${ID}" == "rhel" ]] || [[ "${ID}" == "sles" ]]; then
			curl -o dbench-test-patch.diff $REPO_URL/dbench-test-patch.diff
			git apply --ignore-whitespace dbench-test-patch.diff
			printf -- "Patch dbench-test-patch.diff success\n" 
		fi

		./run-tests.sh

		# Test cases failure
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
"ubuntu-16.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
	apt-get update
	apt-get install -y autoconf automake bison curl flex gcc git libacl1-dev libaio-dev libfuse-dev libglib2.0-dev libibverbs-dev librdmacm-dev libreadline-dev libtool liburcu-dev libxml2-dev lvm2 make openssl pkg-config python3 uuid-dev zlib1g-dev patch
	configureAndInstall | tee -a "$LOG_FILE"
	;;

"ubuntu-18.04" | "ubuntu-19.10")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
	apt-get update
	apt-get install -y autoconf automake bison curl flex gcc git libacl1-dev libaio-dev libfuse-dev libglib2.0-dev libibverbs-dev librdmacm-dev libreadline-dev libssl-dev libtool liburcu-dev libxml2-dev lvm2 make openssl pkg-config python3 uuid-dev zlib1g-dev patch
	configureAndInstall | tee -a "$LOG_FILE"
	;;

"rhel-7.5" | "rhel-7.6" | "rhel-7.7")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
	yum install -y autoconf automake bison bzip2 curl flex fuse-devel gcc git glib2-devel libacl-devel libaio-devel libibverbs-devel librdmacm-devel libtool libxml2-devel libuuid-devel lvm2 make pkgconfig python readline-devel wget zlib-devel patch
	configureAndInstall | tee -a "$LOG_FILE"

	;;

"rhel-8.0")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
	yum install -y autoconf automake bison bzip2 flex fuse-devel gcc git glib2-devel libacl-devel libaio-devel libibverbs-devel librdmacm-devel libtool libxml2-devel libuuid-devel lvm2 make openssl-devel pkgconfig python3 readline-devel wget zlib-devel wget tar gzip libtirpc-devel patch
	configureAndInstall | tee -a "$LOG_FILE"

	;;

"sles-12.4")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
	zypper install -y autoconf automake bison cmake flex fuse-devel gcc git glib2-devel libacl-devel libaio-devel librdmacm1 libtool liburcu-devel libuuid-devel libxml2-devel lvm2 make pkg-config python2 rdma-core-devel readline-devel zlib-devel which patch gawk
	configureAndInstall | tee -a "$LOG_FILE"

	;;

"sles-15.1")
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
