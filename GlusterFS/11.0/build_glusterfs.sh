#!/bin/bash
# © Copyright IBM Corporation 2023.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/GlusterFS/11.0/build_glusterfs.sh
# Execute build script: bash build_glusterfs.sh (provide -h for help)
#

set -e -o pipefail

PACKAGE_NAME="glusterfs"
PACKAGE_VERSION="11.0"
SOURCE_ROOT="$(pwd)"
PREFIX="/usr/local"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/GlusterFS/11.0/patch"

LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
TEST_USER="$(whoami)"
FORCE="false"

trap cleanup 0 1 2 ERR

# Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
	mkdir -p "$SOURCE_ROOT/logs/"
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
	# Cleanup source dependencies
	rm -rf "${SOURCE_ROOT}/dbench"
	rm -rf "${SOURCE_ROOT}/thin-provisioning-tools"
	rm -rf "${SOURCE_ROOT}/yajl"
	rm -rf "${SOURCE_ROOT}/userspace-rcu"

	printf -- '\nCleaned up the artifacts\n'
}

function configureAndInstall() {

	if command -v "$PACKAGE_NAME" > /dev/null; then
		if "$PACKAGE_NAME" -V | grep "$PACKAGE_NAME $PACKAGE_VERSION"
		then
			printf -- "Version : %s (Satisfied) \n" "${PACKAGE_VERSION}" |& tee -a  "$LOG_FILE"
			printf -- "No update required for %s \n" "$PACKAGE_NAME" |& tee -a  "$LOG_FILE"
			exit 0;
		fi
	fi 

	printf -- '\n\nConfiguration and Installation started \n\n' 

	# Installing dependencies
	printf -- 'User responded with Yes. \n' 
	printf -- 'Building dependencies\n' 

	cd "${SOURCE_ROOT}"

	# Install gcc11 for rhel-7.x
	if [[ "${DISTRO}" == "rhel-7.8" ]] || [[ "${DISTRO}" == "rhel-7.9" ]]; then
		yum install -y devtoolset-11-gcc
		source /opt/rh/devtoolset-11/enable
	fi

	# Install gcc11 for rhel-8.x
	if [[ "${DISTRO}" == "rhel-8.6" ]] || [[ "${DISTRO}" == "rhel-8.8" ]]; then
		yum install -y gcc-toolset-11-gcc-c++
		source /opt/rh/gcc-toolset-11/enable
	fi

	# Install gcc11 for sles-12.5
	if [[ "${DISTRO}" == "sles-12.5" ]]; then
		zypper ref -s
		zypper addrepo https://download.opensuse.org/repositories/devel:gcc/SLE-12/devel:gcc.repo
		zypper --gpg-auto-import-keys ref
		zypper install -y gcc11
		update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-11 50
		gcc --version
	fi

	cd "${SOURCE_ROOT}"
	# Install userspace-rcu for rhel-7.x and sles-12.5
	if [[ "${DISTRO}" == "rhel-7.8" ]] || [[ "${DISTRO}" == "rhel-7.9" ]] || [[ "${DISTRO}" == "sles-12.5" ]]; then
		cd "${SOURCE_ROOT}"
		git clone git://git.liburcu.org/userspace-rcu.git
		cd userspace-rcu/
		git checkout v0.7.14
		./bootstrap
		./configure
		make
		make install
		ldconfig
	fi

	cd "${SOURCE_ROOT}"
	
	# Install Openssl 1.1.1 for rhel-7.x and sles-12.5
	if [[ "${DISTRO}" == "rhel-7.8" ]] || [[ "${DISTRO}" == "rhel-7.9" ]] || [[ "${DISTRO}" == "sles-12.5" ]]; then
		cd "${SOURCE_ROOT}"
		git clone https://github.com/openssl/openssl.git
		cd openssl/
		git checkout OpenSSL_1_1_1k
		./config --prefix=/usr
		make
		make install
		ldconfig
		openssl version -a
	fi

	cd "${SOURCE_ROOT}"	

  # Download and configure GlusterFS
	printf -- '\n-----------------------------------\nDownloading GlusterFS. Please wait.\n-----------------------------------\n' 
	git clone https://github.com/gluster/glusterfs.git
	cd "${SOURCE_ROOT}/glusterfs"
	git checkout v$PACKAGE_VERSION
	./autogen.sh

	if [[ "${DISTRO}" == "rhel-7.8" ]] || [[ "${DISTRO}" == "rhel-7.9" ]]; then
		./configure --enable-gnfs --enable-debug --disable-linux-io_uring --without-libtirpc
	elif [[ "${DISTRO}" == "sles-12.5" ]]; then
		./configure --enable-gnfs --disable-linux-io_uring
	else
		./configure --enable-gnfs
	fi
	printf -- '\n-------------------------------\n Applying patches.\n--------------------------------\n' 
    # Apply patches
	cd "${SOURCE_ROOT}/glusterfs"
	if [[ "${DISTRO}" == "rhel-7.8" ]] || [[ "${DISTRO}" == "rhel-7.9" ]]; then
		wget -qO GFS_RH7.patch $PATCH_URL/GFS_RH7.patch
		git apply ${SOURCE_ROOT}/glusterfs/GFS_RH7.patch
		rm ${SOURCE_ROOT}/glusterfs/GFS_RH7.patch
		printf -- '\n---Patches are applied-----\n'
	fi
        if [[ "${DISTRO}" == "sles-12.5" ]]; then
		wget -qO GFS_SL12.patch $PATCH_URL/GFS_SL12.patch
		git apply ${SOURCE_ROOT}/glusterfs/GFS_SL12.patch
		rm ${SOURCE_ROOT}/glusterfs/GFS_SL12.patch
		printf -- '\n---Patches are applied-----\n'
	fi
	
    # Build GlusterFS
	printf -- '\nBuilding GlusterFS \n' 
	printf -- '\nBuild might take some time...........\n'

	cd "${SOURCE_ROOT}/glusterfs"
	make -j $(nproc)
	make install
	printenv >> "$LOG_FILE"
	printf -- 'Built GlusterFS successfully \n\n' 

	cd "${HOME}"
	if [[ "$(grep LD_LIBRARY_PATH .bashrc)" ]]; then
		printf -- '\nChanging LD_LIBRARY_PATH\n' 
		sed -n 's/^.*\bLD_LIBRARY_PATH\b.*$/export LD_LIBRARY_PATH=\/usr\/local\/lib:\/usr\/local\/lib64/p' .bashrc
	else
		echo "export LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64" >>.bashrc
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
	echo " bash build_glusterfs.sh  "
	echo "[-d debug]"
	echo "[-y install-without-confirmation]"
	echo "[-t install-with-tests]"
	echo "[	true 	Run the whole test suite for GlusterFS even if failure is encountered.]"
	echo "[	false 	Run the test suite with exit_on_failure enabled.]"
	echo
}

function runTest() {
	set +e
		
		if [[ "$TESTS" == "true" ]]; then
    		
			echo "Running Tests: "

			case "$DISTRO" in	
			"rhel-7.8" | "rhel-7.9")
				yum install -y acl attr bc bind-utils boost-devel docbook-style-xsl expat-devel gdb net-tools nfs-utils psmisc vim xfsprogs yajl redhat-rpm-config perl-Test-Harness popt-devel procps-ng pyxattr python3-pip
				pip3 install prettytable
				;;

			"rhel-8.6" | "rhel-8.8")
				yum install -y dbench perl-Test-Harness yajl nfs-utils
				;;

			"rhel-9.0" | "rhel-9.2")
				yum install -y dbench perl-Test-Harness yajl net-tools psmisc nfs-utils xfsprogs attr procps-ng
				;;

			"sles-12.5")
				zypper install -y acl attr bc bind-utils gdb libxml2-tools net-tools nfs-utils psmisc vim xfsprogs python-PrettyTable libselinux-devel selinux-tools popt-devel sysvinit-tools libexpat-devel boost-devel
				;;
			
			"sles-15.4" | "sles-15.5")
				zypper install -y acl attr bc bind-utils gdb libxml2-tools net-tools-deprecated nfs-utils psmisc thin-provisioning-tools vim xfsprogs python3-PrettyTable libselinux-devel selinux-tools popt-devel libyajl2 libyajl-devel sysvinit-tools
				wget https://ftp.lysator.liu.se/pub/opensuse/ports/aarch64/distribution/leap/15.4/repo/oss/s390x/yajl-2.1.0-2.12.s390x.rpm
				rpm -ivh yajl-2.1.0-2.12.s390x.rpm
				;;
			esac

			# link the gstack command to pstack for sles
			if [[ "${ID}" == "sles" ]]; then
				ln -sf `which gstack` /usr/bin/pstack
			fi
						
			# Install dbench
			if [[ "${DISTRO}" != "rhel-9.0" ]] && [[ "${DISTRO}" != "rhel-9.2" ]] && [[ "${DISTRO}" != "rhel-8.6" ]] && [[ "${DISTRO}" != "rhel-8.8" ]]; then
				cd "${SOURCE_ROOT}"
				git clone https://github.com/sahlberg/dbench
				cd dbench
				git checkout caa52d347171f96eef5f8c2d6ab04a9152eaf113
				./autogen.sh
				./configure --datadir=/usr/local/share/doc/loadfiles/
				make
				make install
			fi
			
			# Install thin-provisioning-tools (RHEL 7.x and SLES12SP5 only)
			if [[ "${DISTRO}" == "rhel-7.8" || "${DISTRO}" == "rhel-7.9" || "${DISTRO}" == "sles-12.5" ]]; then
				cd "${SOURCE_ROOT}"
				git clone https://github.com/jthornber/thin-provisioning-tools
				cd thin-provisioning-tools
				git checkout v0.7.6
				autoreconf
				./configure
				make
				make install
			fi

			# Install yajl (SLES 12.x only)
			if [[ "${DISTRO}" == "sles-12.5" ]]; then
				cd "${SOURCE_ROOT}"
				# Install YAJL
				git clone https://github.com/lloyd/yajl
				cd yajl
				git checkout 2.1.0
				./configure
				make install
			fi
			printf -- '\n-------------------\nRunning Test Suite\n-------------------\n'
			# Run the Test Suite
			cd $SOURCE_ROOT/glusterfs
			sed -i 's/exit_on_failure="yes"/exit_on_failure="no"/g' run-tests.sh
			sed -i 's/run_timeout=200/run_timeout=900/g' run-tests.sh
			sed -i 's/kill_after_time=5/kill_after_time=10/g' run-tests.sh
			./run-tests.sh
			
			# Test cases failure
			if [[ "$(grep -wq 'FAILED' ${LOG_FILE})" ]]; then
				printf -- 'Test cases failing. Please check the logs. \n\n' 
			fi
		fi

	set -e
}

while getopts "h?dyt:" opt; do
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
		export USEAS=$OPTARG
		;;
	esac
done

function printSummary() {

	printf -- '\n********************************************************************************************************\n'
	printf -- "\n* Getting Started * \n"	
	printf -- '\nSet LD_LIBRARY_PATH and PATH to start using GlusterFS right away.'
	printf -- "\nexport LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64 \n" 
  	printf -- '\nOR Restart the session to apply the changes'
	printf -- '\ncommand to run the GlusterFS Daemon : glusterd' 
	printf -- '\nFor more information on GlusterFS visit https://www.gluster.org/ \n\n'
	printf -- '**********************************************************************************************************\n'
}

logDetails
prepare

PATH=${PREFIX}/bin:${PREFIX}/sbin${PATH:+:${PATH}}
export PATH
  
PKG_CONFIG_PATH=${PREFIX}/lib/pkgconfig:${PREFIX}/lib64/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}
export PKG_CONFIG_PATH

LD_LIBRARY_PATH=${PREFIX}/lib:${PREFIX}/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
export LD_LIBRARY_PATH

LD_RUN_PATH=${PREFIX}/lib:${PREFIX}/lib64${LD_RUN_PATH:+:${LD_RUN_PATH}}
export LD_RUN_PATH

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"rhel-7.8" | "rhel-7.9")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
	yum install -y rpcgen libtirpc-devel g++ gcc-c++ langpacks-en glibc-langpack-en automake autoconf libtool flex bison openssl-devel libxml2-devel python-devel libaio-devel libibverbs-devel librdmacm-devel readline-devel lvm2-devel glib2-devel userspace-rcu-devel libcmocka-devel libacl-devel sqlite-devel fuse-devel libuuid-devel redhat-rpm-config git gperftools-devel gperftools-libs openssl popt-devel gperf gperftools-devel
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"rhel-8.6" | "rhel-8.8")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
	yum install -y autoconf automake bison dos2unix flex fuse-devel glib2-devel libacl-devel libaio-devel libattr-devel libcurl-devel libibverbs-devel librdmacm-devel libtirpc-devel libuuid-devel libtool libxml2-devel make openssl-devel pkgconfig xz-devel  python3-devel python3-netifaces  readline-devel rpm-build sqlite-devel systemtap-sdt-devel tar git lvm2-devel python3-paste-deploy python3-simplejson python3-sphinx python3-webob python3-pyxattr userspace-rcu-devel rpcgen liburing-devel gperf gperftools-devel
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"rhel-9.0" | "rhel-9.2")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
	yum install -y autoconf automake bison dos2unix flex fuse-devel glib2-devel libacl-devel libaio-devel libattr-devel libcurl-devel libibverbs-devel librdmacm-devel libtirpc-devel libuuid-devel libtool libxml2-devel make openssl-devel pkgconfig xz-devel  python3-devel python3-netifaces  readline-devel rpm-build sqlite-devel systemtap-sdt-devel tar git lvm2-devel python3-paste-deploy python3-simplejson python3-sphinx python3-webob python3-pyxattr userspace-rcu-devel rpcgen liburing-devel gperf gperftools-devel iproute
    configureAndInstall |& tee -a "$LOG_FILE"
	;;

"sles-12.5")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
	zypper install -y wget curl tar autoconf automake bison cmake flex fuse-devel gcc-c++ git-core glib2-devel libacl-devel libaio-devel librdmacm1 libtool liburcu-devel libuuid-devel libxml2-devel lvm2 make pkg-config python3 python3-xattr rdma-core-devel readline-devel openssl-devel zlib-devel which gawk dmraid popt-devel gperftools-devel gperf gperftools libtirpc-devel util-linux iproute util-linux-systemd keyutils-devel
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"sles-15.4" | "sles-15.5")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
	zypper install -y autoconf automake bison cmake flex fuse-devel gcc-c++ git-core glib2-devel libacl-devel libaio-devel librdmacm1 libtool liburcu-devel libuuid-devel libxml2-devel lvm2 make pkg-config python3 python3-xattr rdma-core-devel readline-devel openssl-devel zlib-devel which wget gawk dmraid popt-devel gperftools-devel gperf gperftools libtirpc-devel rpcgen liburing-devel util-linux hostname iproute util-linux-systemd keyutils-devel
	configureAndInstall |& tee -a "$LOG_FILE"
	;;
*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

printSummary | tee -a "$LOG_FILE"
