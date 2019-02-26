#!/bin/bash
# © Copyright IBM Corporation 2018, 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/GlusterFS/build_glusterfs.sh
# Execute build script: bash build_glusterfs.sh    (provide -h for help)
#

set -e

PACKAGE_NAME="glusterfs"
PACKAGE_VERSION="5.3"
CURDIR="$(pwd)"

REPO_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/GlusterFS/patch/"

LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
TEST_USER="$(whoami)"
FORCE="false"
TESTS="false"

trap cleanup 0 1 2 ERR

#Check if directory exists
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

	rm -rf "${CURDIR}/io-threads.h.diff"

	#for rhel
	if [[ "${ID}" == "rhel" ]]; then
		rm -rf "${CURDIR}/userspace-rcu"
		rm -rf "${CURDIR}/thin-provisioning-tools"
	fi

	if [[ "${TESTS}" == "true" ]]; then

		if [[ "${ID}" == "rhel" ]]; then
			rm -rf "${CURDIR}/dbench"
			if [[ "${ID}" == "sles" ]]; then
				rm -rf "${CURDIR}/yajl"
			fi
		fi

		#cleaning patches
		rm -rf "${CURDIR}/throttle-rebal.t.diff"
		rm -rf "${CURDIR}/mount-nfs-auth.t.diff"
		rm -rf "${CURDIR}/bug-847622.t.diff"
		rm -rf "${CURDIR}/bug-1161311.t.diff"
		rm -rf "${CURDIR}/bug-1193636.t.diff"

		if [[ "${DISTRO}" == "sles-12.3" ||  "${DISTRO}" == "ubuntu-16.04" ]]; then
			rm -rf "${CURDIR}/run-tests.sh.diff"
		fi
	fi
	printf -- '\nCleaned up the artifacts\n'
}

function configureAndInstall() {
	printf -- '\nConfiguration and Installation started \n' 

	#Installing dependencies
	printf -- 'User responded with Yes. \n' 
	printf -- 'Building dependencies\n' 

	cd "${CURDIR}"

	#only for rhel
	if [[ "${ID}" == "rhel" ]]; then
		printf -- 'Building URCU\n' 
		git clone git://git.liburcu.org/userspace-rcu.git
		cd userspace-rcu
		git checkout v0.10.2
		./bootstrap
		./configure
		make
		make install
		ldconfig
		printf -- 'URCU installed successfully\n' 
	fi

	cd "${CURDIR}"

	#only for rhel
	if [[ "${ID}" == "rhel" ]]; then
		printf -- 'Building thin-provisioning-tools\n' 
		git clone https://github.com/jthornber/thin-provisioning-tools
		cd thin-provisioning-tools
		git checkout v0.7.6
		autoreconf
		./configure
		make
		make install
		printf -- 'thin-provisioning-tools installed\n'
	fi

	cd "${CURDIR}"

	# Download and configure GlusterFS
	printf -- '\nDownloading GlusterFS. Please wait.\n' 
	git clone -b v"${PACKAGE_VERSION}" https://github.com/gluster/glusterfs.git
	sleep 2
	cd "${CURDIR}/glusterfs"
	./autogen.sh
	if [[ "${DISTRO}" == "sles-12.3" ]]; then
		./configure --enable-gnfs --disable-events # for SLES 12 SP3
	else
		./configure --enable-gnfs # for RHEL, SLES 15 and Ubuntu
	fi

	if [[ "${ID}" == "rhel" ]]; then
		rm contrib/userspace-rcu/rculist-extra.h
		cp /usr/local/include/urcu/rculist.h contrib/userspace-rcu/rculist-extra.h
	else
		#Patch to be applied here
		cd "${CURDIR}"
		curl -o io-threads.h.diff $REPO_URL/io-threads.h.diff
		patch "${CURDIR}/glusterfs/xlators/performance/io-threads/src/io-threads.h" io-threads.h.diff
	fi

	#Build GlusterFS
	printf -- '\nBuilding GlusterFS \n' 
	printf -- '\nBuild might take some time...........\n'
	cd "${CURDIR}/glusterfs"
	make
	make install
	export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib
	ldconfig
	printenv >>"$LOG_FILE"
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

		#Building DBENCH (Only for RHEL and SLES)
		if [[ "${ID}" != "ubuntu" ]]; then
			cd "${CURDIR}"
			git clone https://github.com/sahlberg/dbench
			cd dbench
			./autogen.sh
			./configure
			make
			make install
		fi

		#Building yajl (Only for SLES)
		if [[ "${ID}" == "sles" ]]; then
			cd "${CURDIR}"
			git clone https://github.com/lloyd/yajl
			cd yajl
			git checkout 2.1.0
			./configure
			make install
		fi

		#Apply 6 patches
		cd "${CURDIR}"

		curl -o throttle-rebal.t.diff $REPO_URL/throttle-rebal.t.diff
		patch "${CURDIR}/glusterfs/tests/basic/distribute/throttle-rebal.t" throttle-rebal.t.diff

		curl -o mount-nfs-auth.t.diff $REPO_URL/mount-nfs-auth.t.diff
		patch "${CURDIR}/glusterfs/tests/basic/mount-nfs-auth.t" mount-nfs-auth.t.diff

		curl -o bug-847622.t.diff $REPO_URL/bug-847622.t.diff
		patch "${CURDIR}/glusterfs/tests/bugs/nfs/bug-847622.t" bug-847622.t.diff

		curl -o bug-1161311.t.diff $REPO_URL/bug-1161311.t.diff
		patch "${CURDIR}/glusterfs/tests/bugs/distribute/bug-1161311.t" bug-1161311.t.diff
		
		curl -o bug-1193636.t.diff $REPO_URL/bug-1193636.t.diff
		patch "${CURDIR}/glusterfs/tests/bugs/distribute/bug-1193636.t" bug-1193636.t.diff

		if [[ "${DISTRO}" == "sles-12.3" ||  "${DISTRO}" == "ubuntu-16.04" ]]; then
			curl -o run-tests.sh.diff $REPO_URL/run-tests.sh.diff
			patch "${CURDIR}/glusterfs/run-tests.sh" run-tests.sh.diff
		fi

		ssh-keygen -t rsa
		cat /root/.ssh/id_rsa.pub | cat >>/root/.ssh/authorized_keys

		#Run the test cases
		cd "${CURDIR}/glusterfs"
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
		if command -v "$PACKAGE_NAME" > /dev/null; then
			printf -- "%s is detected with version %s .\n" "$PACKAGE_NAME" "$PACKAGE_VERSION" | tee -a "$LOG_FILE"
			TESTS="true"
			runTest
			exit 0

		else

			TESTS="true"
		fi

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
"ubuntu-16.04" | "ubuntu-18.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
	sudo apt-get update 
	sudo apt-get install -y make automake autoconf libtool flex bison pkg-config libssl-dev libxml2-dev python3-dev libaio-dev libibverbs-dev librdmacm-dev libreadline-dev liblvm2-dev libglib2.0-dev liburcu-dev libcmocka-dev libsqlite3-dev libacl1-dev wget tar dbench git xfsprogs attr nfs-common yajl-tools sqlite3 libxml2-utils thin-provisioning-tools bc uuid-dev net-tools vim-common
	configureAndInstall | tee -a "$LOG_FILE"
	;;

"rhel-7.4" | "rhel-7.5" | "rhel-7.6")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
	sudo yum install -y wget git make gcc-c++ libaio-devel boost-devel expat-devel autoconf autoheader automake libtool flex bison openssl-devel libacl-devel sqlite-devel libxml2-devel python-devel python pyxattr attr yajl-devel nfs-utils xfsprogs-devel popt-static sysvinit-tools psmisc libibverbs-devel librdmacm-devel readline-devel lvm2-devel glib2-devel fuse-devel bc libuuid-devel net-tools vim-common gdb
	configureAndInstall | tee -a "$LOG_FILE"

	;;

"sles-12.3")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
	sudo zypper --non-interactive install wget which git make gcc-c++ libaio-devel boost-devel autoconf automake cmake libtool flex bison lvm2-devel libacl-devel python-devel python python-xattr attr xfsprogs-devel sysvinit-tools psmisc bc libopenssl-devel libxml2-devel sqlite3 sqlite3-devel popt-devel nfs-utils python-xml net-tools libuuid-devel liburcu-devel libyajl-devel gdb acl
	configureAndInstall | tee -a "$LOG_FILE"

	;;

"sles-15")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
	sudo zypper --non-interactive install wget which git make gcc-c++ libaio-devel boost-devel autoconf automake cmake libtool flex bison lvm2-devel libacl-devel python3-devel python3 python3-xattr attr xfsprogs-devel sysvinit-tools psmisc bc libopenssl-devel libxml2-devel sqlite3 sqlite3-devel popt-devel nfs-utils python-xml net-tools-deprecated libuuid-devel liburcu-devel libyajl-devel gdb acl
	configureAndInstall | tee -a "$LOG_FILE"

	;;

*)
	printf -- "%s not supported \n" "$DISTRO" | tee -a "$LOG_FILE"
	exit 1
	;;
esac

printSummary | tee -a "$LOG_FILE"
