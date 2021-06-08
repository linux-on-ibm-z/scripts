#!/bin/bash
# © Copyright IBM Corporation 2021.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/GlusterFS/9.2/build_glusterfs.sh
# Execute build script: bash build_glusterfs.sh (provide -h for help)
#

set -e -o pipefail

PACKAGE_NAME="glusterfs"
PACKAGE_VERSION="9.2"
SOURCE_ROOT="$(pwd)"
PREFIX="/usr/local"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/GlusterFS/9.2/patch"

LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
TEST_USER="$(whoami)"
FORCE="false"
TESTS="true"

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
	rm -rf "${SOURCE_ROOT}/userspace-rcu"
	rm -rf "${SOURCE_ROOT}/dbench"
	rm -rf "${SOURCE_ROOT}/thin-provisioning-tools"
	rm -rf "${SOURCE_ROOT}/dbench"
	rm -rf "${SOURCE_ROOT}/yajl"

	printf -- '\nCleaned up the artifacts\n'
}

function installGCC() {
	set +e
	printf -- "Installing GCC 7 \n"
	cd $SOURCE_ROOT
	mkdir gcc
	cd gcc
	wget --no-check-certificate https://ftpmirror.gnu.org/gcc/gcc-7.5.0/gcc-7.5.0.tar.xz
	tar -xf gcc-7.5.0.tar.xz
	cd gcc-7.5.0
	./contrib/download_prerequisites
	mkdir objdir
	cd objdir
	../configure --prefix=${PREFIX} --enable-languages=c,c++ --with-arch=zEC12 --with-long-double-128 --build=s390x-linux-gnu --host=s390x-linux-gnu --target=s390x-linux-gnu --enable-threads=posix --with-system-zlib --disable-multilib
	make -j 8
	make install
	printf -- "\nGCC v7.5.0 installed successfully. \n"
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

	printf -- '\nConfiguration and Installation started \n' 

	# Installing dependencies
	printf -- 'User responded with Yes. \n' 
	printf -- 'Building dependencies\n' 

	cd "${SOURCE_ROOT}"

	#Only for RHEL 7 and SLES 12 SP5
	if [[ ${DISTRO} == rhel-7\.[8-9] ]] || [[ "${DISTRO}" == "sles-12.5" ]]; then
		printf -- 'Building URCU\n' 
		wget --no-check-certificate https://lttng.org/files/urcu/userspace-rcu-0.10.2.tar.bz2
		tar xvjf userspace-rcu-0.10.2.tar.bz2
		cd userspace-rcu-0.10.2
		./configure --prefix=${PREFIX}
		make
		make install
		printf -- 'URCU installed successfully\n' 
	fi

	#Only for RHEL 7 and SLES 12.5
	if [[ ${DISTRO} == rhel-7\.[8-9] ]] || [[ "${DISTRO}" == "sles-12.5" ]]; then
		cd $SOURCE_ROOT
		wget --no-check-certificate https://www.openssl.org/source/old/1.1.1/openssl-1.1.1d.tar.gz
		tar xvf openssl-1.1.1d.tar.gz
		cd openssl-1.1.1d
		./config --prefix=${PREFIX} --openssldir=${PREFIX} no-weak-ssl-ciphers no-tls1 no-tls1-method
		make
		make install
		printf -- 'OpenSSL installed successfully\n' 
	fi
    
	#Only for RHEL 7 and SLES
	if [[ ! ${DISTRO} == rhel-8\.[1-3] ]]; then
		cd $SOURCE_ROOT
		wget --no-check-certificate https://github.com/axboe/liburing/archive/refs/tags/liburing-2.0.tar.gz
		tar xvf liburing-2.0.tar.gz
		cd liburing-liburing-2.0
		if [[ ${DISTRO} == rhel-7\.[8-9] ]] || [[ "${DISTRO}" == "sles-12.5" ]]; then
			wget --no-check-certificate $PATCH_URL/liburing.diff
			patch -p1 < liburing.diff
		fi
		./configure --prefix=${PREFIX}
		make
		make install
		printf -- 'LIBURING installed successfully\n' 
	fi

	cd "${SOURCE_ROOT}"

	# Download and configure GlusterFS
	printf -- '\nDownloading GlusterFS. Please wait.\n' 
	git clone https://github.com/gluster/glusterfs.git
	cd "${SOURCE_ROOT}/glusterfs"
	git checkout v$PACKAGE_VERSION
	./autogen.sh

	if [[ "${DISTRO}" == "sles-12.5" ]]; then
		./configure --enable-gnfs --disable-events # For SLES 12 SP5
	else
		./configure --enable-gnfs # For RHEL and SLES 15.x
	fi

    # Only for SLES, and RHEL 8.x
	if [[ "${ID}" == "sles" ]] || [[ ${DISTRO} == rhel-8\.[1-3] ]]; then
		cd "${SOURCE_ROOT}/glusterfs"
		wget --no-check-certificate $PATCH_URL/io-threads.h.diff
		git apply io-threads.h.diff
	fi

	cd "${SOURCE_ROOT}/glusterfs"
	wget --no-check-certificate $PATCH_URL/bit-rot-stub.c.diff 
	git apply bit-rot-stub.c.diff

    # Only for RHEL 8.x
	if [[ ${DISTRO} == rhel-8\.[1-3] ]]; then
		cd "${SOURCE_ROOT}/glusterfs"
		wget --no-check-certificate $PATCH_URL/nfs.c.diff
		git apply nfs.c.diff
	fi

	# Build GlusterFS
	printf -- '\nBuilding GlusterFS \n' 
	printf -- '\nBuild might take some time...........\n'

	cd "${SOURCE_ROOT}/glusterfs"
	make
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
	echo "  build_glusterfs.sh  "
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
    		log "TEST Flag is set, continue with running test "
			echo "Running Tests: "

			case "$DISTRO" in	
			"rhel-7.8" | "rhel-7.9")
				yum install -y acl attr bc bind-utils boost-devel docbook-style-xsl expat-devel gdb net-tools nfs-utils psmisc pyxattr vim xfsprogs yajl popt-devel python3-pip
				;;
			
			"rhel-8.1" | "rhel-8.2" | "rhel-8.3")
				yum install -y acl attr bc bind-utils boost-devel docbook-style-xsl expat-devel gdb net-tools nfs-utils psmisc vim xfsprogs yajl redhat-rpm-config python3-devel python3-pyxattr python3-prettytable perl-Test-Harness popt-devel
				;;
			
			"sles-12.5")
				zypper install -y acl attr bc bind-utils boost-devel gdb libexpat-devel libxml2-tools net-tools nfs-utils psmisc vim xfsprogs python3-xattr popt-devel python3-pip
				;;
			
			"sles-15.2")
				zypper install -y acl attr bc bind-utils gdb libxml2-tools net-tools-deprecated nfs-utils psmisc thin-provisioning-tools vim xfsprogs python3-xattr python3-PrettyTable libselinux-devel selinux-tools thin-provisioning-tools popt-devel
				;;
			esac

			# link the gstack command to pstack for sles
			if [[ "${ID}" == "sles" ]]; then
				ln -sf `which gstack` /usr/bin/pstack
			fi
			
			# Install prettytable (SLES 12 SP5 and RHEL 7.x)
			if [[ ${DISTRO} == rhel-7\.[8-9] ]] || [[ "${DISTRO}" == "sles-12.5" ]]; then
				pip3 install prettytable
			fi

			# Install dbench (RHEL and SLES only)
			if [[ "${ID}" == "rhel" ]] || [[ "${ID}" == "sles" ]]; then
				# Install dbench
				cd "${SOURCE_ROOT}"
				git clone https://github.com/sahlberg/dbench
				cd dbench
				git checkout caa52d347171f96eef5f8c2d6ab04a9152eaf113
				./autogen.sh
				./configure --datadir=/usr/local/share/doc/loadfiles/
				make
				make install
			fi

			# Install thin-provisioning-tools (RHEL and SLES 12 SP5 only)
			if [[ "${ID}" == "rhel" ]] || [[ "$DISTRO" == "sles-12.5" ]]; then
				cd "${SOURCE_ROOT}"
				git clone https://github.com/jthornber/thin-provisioning-tools
				cd thin-provisioning-tools
				git checkout v0.7.6
				autoreconf
				./configure
				make
				make install
			fi

			# Install yajl (SLES only)
			if [[ "${ID}" == "sles" ]]; then
				cd "${SOURCE_ROOT}"
				# Install YAJL
				git clone https://github.com/lloyd/yajl
				cd yajl
				git checkout 2.1.0
				./configure
				make install
			fi
			
			# Apply patches
			cd "${SOURCE_ROOT}/glusterfs"

			# Patch test script patch for SLES 12 SP5
			if [[ "$DISTRO" == "sles-12.5" ]]; then
				wget --no-check-certificate $PATCH_URL/run-tests.sh.diff 
				git apply run-tests.sh.diff 
				printf -- "Patch run-tests.sh.diff success\n" 
			fi

			# Apply hash test patches
			wget --no-check-certificate $PATCH_URL/hash-tests.diff 
			git apply hash-tests.diff 
			printf -- "Patch hash-tests.diff success\n" 
			# Apply system configuration patches
			wget --no-check-certificate $PATCH_URL/test-patch.diff 
			git apply test-patch.diff
			printf -- "Patch test-patch.diff success\n" 

			# Fix the 00-georep-verify-non-root-setup.t TC failure
			if [[ ${DISTRO} == rhel-7\.[8-9] ]] || [[ "$DISTRO" == "rhel-8.2" ]]; then
				ln -s /usr/local/lib/libgfchangelog.so.0 /lib64/libgfchangelog.so
				ldconfig /usr/local/lib
				ldconfig /usr/local/lib64
			fi
			
			if [ "$USEAS" = "true" ]; then
				printf -- 'Running the whole test suite.\n' 
				sed -i "18s/yes/no/" ${SOURCE_ROOT}/glusterfs/run-tests.sh
				./run-tests.sh 2>&1| tee -a test_suite.log
			elif [ "$USEAS" = "false" ]; then
				printf -- 'Running test cases with exit_on_failure enabled.\n'
				./run-tests.sh
			fi

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
	printf -- '\nSet LD_LIBRARY_PATH to start using GlusterFS right away.'
	printf -- "\nexport LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64 \n" 
	printf -- '\nOR Restart the session to apply the changes'
	printf -- '\ncommand to run the GlusterFS Daemon : glusterd' 
	printf -- '\nFor more information on GlusterFS visit https://www.gluster.org/ \n\n'
	printf -- '**********************************************************************************************************\n'
}

logDetails
prepare

PATH=${PREFIX}/bin${PATH:+:${PATH}}
export PATH
  
PKG_CONFIG_PATH=${PREFIX}/lib/pkgconfig:${PREFIX}/lib64/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}
export PKG_CONFIG_PATH

LD_LIBRARY_PATH=${PREFIX}/lib:${PREFIX}/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
export LD_LIBRARY_PATH

LD_RUN_PATH=${PREFIX}/lib:${PREFIX}/lib64${LD_RUN_PATH:+:${LD_RUN_PATH}}
export LD_RUN_PATH

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"rhel-7.8" | "rhel-7.9" )
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
	yum install -y autoconf automake bison bzip2 curl flex fuse-devel devtoolset-7 git glib2-devel libacl-devel libaio-devel libibverbs-devel librdmacm-devel libtool libxml2-devel libuuid-devel lvm2 make pkgconfig python python3 readline-devel wget zlib-devel patch which
    source /opt/rh/devtoolset-7/enable
	configureAndInstall | tee -a "$LOG_FILE"
	;;

"rhel-8.1" | "rhel-8.2" | "rhel-8.3")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
	yum install -y autoconf automake bison bzip2 flex fuse-devel gcc-c++ git glib2-devel libacl-devel libaio-devel libibverbs-devel librdmacm-devel libtool libxml2-devel libuuid-devel liburing-devel lvm2 make openssl-devel pkgconfig python3 readline-devel wget zlib-devel tar gzip libtirpc-devel patch rpcgen userspace-rcu-devel which diffutils xz
	installGCC | tee -a "$LOG_FILE"
	update-alternatives --install /usr/bin/cc cc ${PREFIX}/bin/gcc 40
	update-alternatives --install /usr/bin/gcc gcc ${PREFIX}/bin/gcc 40
	update-alternatives --install /usr/bin/g++ g++ ${PREFIX}/bin/g++ 40
	update-alternatives --install /usr/bin/c++ c++ ${PREFIX}/bin/g++ 40
	configureAndInstall | tee -a "$LOG_FILE"
	;;

"sles-12.5")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
	zypper install -y autoconf automake bison cmake flex fuse-devel gcc7 gcc7-c++ git glib2-devel libacl-devel libaio-devel librdmacm1 libtool libuuid-devel libxml2-devel lvm2 make pkg-config python2 rdma-core-devel readline-devel zlib-devel which patch gawk wget popt-devel
	update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-7 40
	update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-7 40
	update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-7 40
	update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-7 40
	configureAndInstall | tee -a "$LOG_FILE"
	;;

"sles-15.2")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
	zypper install -y autoconf automake bison cmake flex fuse-devel gcc-c++ git-core glib2-devel libacl-devel libaio-devel librdmacm1 libtool liburcu-devel libuuid-devel libxml2-devel lvm2 make pkg-config python3 python3-xattr rdma-core-devel readline-devel openssl-devel zlib-devel which gawk dmraid popt-devel
 	git config --global http.sslVerify false
	configureAndInstall | tee -a "$LOG_FILE"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" | tee -a "$LOG_FILE"
	exit 1
	;;
esac

printSummary | tee -a "$LOG_FILE"
