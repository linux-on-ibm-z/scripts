#!/bin/bash
# © Copyright IBM Corporation 2022.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/GlusterFS/10.2/build_glusterfs.sh
# Execute build script: bash build_glusterfs.sh (provide -h for help)
#

set -e -o pipefail

PACKAGE_NAME="glusterfs"
PACKAGE_VERSION="10.2"
SOURCE_ROOT="$(pwd)"
PREFIX="/usr/local"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/GlusterFS/10.2/patch"

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
	
  # Download and configure GlusterFS
	printf -- '\nDownloading GlusterFS. Please wait.\n' 
	git clone https://github.com/gluster/glusterfs.git
	cd "${SOURCE_ROOT}/glusterfs"
	git checkout v$PACKAGE_VERSION
	./autogen.sh

	if [[ "${ID}" == "sles" ]]; then
		./configure --enable-gnfs --disable-linux-io_uring
	else
		./configure --enable-gnfs 
	fi

   # Apply patches
	cd "${SOURCE_ROOT}/glusterfs"
	wget --no-check-certificate $PATCH_URL/io-threads.h.diff
	git apply io-threads.h.diff
	
	wget --no-check-certificate $PATCH_URL/bit-rot-stub.c.diff 
	git apply bit-rot-stub.c.diff

  # Use the following patch to fix uatomic_xchg() related issue
	wget --no-check-certificate $PATCH_URL/nfs.diff 
	git apply nfs.diff

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
			"rhel-8.4" | "rhel-8.6")
				yum install -y acl attr bc bind-utils boost-devel docbook-style-xsl expat-devel gdb net-tools nfs-utils psmisc vim xfsprogs yajl redhat-rpm-config python3-devel python3-pyxattr python3-prettytable perl-Test-Harness popt-devel procps-ng
				;;
			
			"sles-15.3")
				zypper install -y acl attr bc bind-utils gdb libxml2-tools net-tools-deprecated nfs-utils psmisc thin-provisioning-tools vim xfsprogs python3-xattr python3-PrettyTable libselinux-devel selinux-tools popt-devel
				;;
			esac

			# link the gstack command to pstack for sles
			if [[ "${ID}" == "sles" ]]; then
				ln -sf `which gstack` /usr/bin/pstack
			fi
						
			# Install dbench
			cd "${SOURCE_ROOT}"
			git clone https://github.com/sahlberg/dbench
			cd dbench
			git checkout caa52d347171f96eef5f8c2d6ab04a9152eaf113
			./autogen.sh
			./configure --datadir=/usr/local/share/doc/loadfiles/
			make
			make install
			
			# Install thin-provisioning-tools (RHEL only)
			if [[ "${ID}" == "rhel" ]]; then
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

			# Apply hash test patches
			wget --no-check-certificate $PATCH_URL/hash-tests.diff 
			git apply hash-tests.diff 
			printf -- "Patch hash-tests.diff success\n" 
			
            # Apply system configuration patches
			wget --no-check-certificate $PATCH_URL/test-patch.diff 
			git apply test-patch.diff
            printf -- "Patch test-patch.diff success\n"
			
			# Fix the 00-georep-verify-non-root-setup.t TC failure
			if [[ "${ID}" == "rhel" ]]; then
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
"rhel-8.4" | "rhel-8.6")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
	yum install -y autoconf automake bison bzip2 flex fuse-devel gcc-c++ git glib2-devel libacl-devel libaio-devel libibverbs-devel librdmacm-devel libtool libxml2-devel libuuid-devel liburing-devel lvm2 make binutils openssl-devel pkgconfig python3 readline-devel wget zlib-devel tar gzip libtirpc-devel patch rpcgen userspace-rcu-devel which diffutils xz gperftools gperf
	installGCC | tee -a "$LOG_FILE"
	update-alternatives --install /usr/bin/cc cc ${PREFIX}/bin/gcc 40
	update-alternatives --install /usr/bin/gcc gcc ${PREFIX}/bin/gcc 40
	update-alternatives --install /usr/bin/g++ g++ ${PREFIX}/bin/g++ 40
	update-alternatives --install /usr/bin/c++ c++ ${PREFIX}/bin/g++ 40
	configureAndInstall | tee -a "$LOG_FILE"
	;;

"sles-15.3")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
	zypper install -y autoconf automake bison cmake flex fuse-devel gcc-c++ git-core glib2-devel libacl-devel libaio-devel librdmacm1 libtool liburcu-devel libuuid-devel libxml2-devel lvm2 make pkg-config python3 python3-xattr rdma-core-devel readline-devel openssl-devel zlib-devel which gawk dmraid popt-devel gperftools-devel gperf gperftools libtirpc-devel rpcgen
 	git config --global http.sslVerify false
	configureAndInstall | tee -a "$LOG_FILE"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" | tee -a "$LOG_FILE"
	exit 1
	;;
esac

printSummary | tee -a "$LOG_FILE"
