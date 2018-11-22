#!/bin/bash
# © Copyright IBM Corporation 2018.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/GlusterFS/build_glusterfs.sh
# Execute build script: bash build_glusterfs.sh    (provide -h for help)
#

set -e

PACKAGE_NAME="glusterfs"
PACKAGE_VERSION="4.1.5"
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

	#for sles
	if [[ "${ID}" == "sles" ]]; then
		rm -rf "${CURDIR}/userspace-rcu"
	fi

	if [[ "${TESTS}" == "true" ]]; then

		rm -rf "${CURDIR}/xfsprogs-4.15.1.tar.gz"
		rm -rf "${CURDIR}/xfsprogs-4.15.1"
		rm -rf "${CURDIR}/dbench"
		rm -rf "${CURDIR}/yajl"

		#cleaning patches
		rm -rf "${CURDIR}/throttle-rebal.t.diff"
		rm -rf "${CURDIR}/mount-nfs-auth.t.diff"
		rm -rf "${CURDIR}/frequency-counters.t.diff"
		rm -rf "${CURDIR}/namespace.t.diff"

		if [[ "${ID}" == "sles" ||  "${ID}" == "ubuntu" ]]; then
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

	#only for sles and rhel
	if [[ "${ID}" != "ubuntu" ]]; then
		printf -- 'Building URCU\n' 
		git clone git://git.liburcu.org/userspace-rcu.git
		cd userspace-rcu
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
	if [[ "${ID}" == "sles" ]]; then
		./configure --enable-gnfs --disable-events # for SLES
	else
		./configure --enable-gnfs # for RHEL and Ubuntu
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
		#Building xfsprogs

		printf -- 'Running test as TEST flag is enabled \n\n' 
		if [[ "${ID}" == "ubuntu" ]]; then
			sudo apt-get install -y gettext libblkid-dev
		fi

		if [[ "${ID}" == "sles" ]]; then
			sudo zypper --non-interactive install libblkid-devel gettext-tools
		fi

		if [[ "${ID}" == "rhel" ]]; then
			sudo yum install -y gettext libblkid-devel
		fi

		cd "${CURDIR}"
		wget -c https://mirrors.edge.kernel.org/pub/linux/utils/fs/xfs/xfsprogs/xfsprogs-4.15.1.tar.gz
		tar -xvf xfsprogs-4.15.1.tar.gz
		cd xfsprogs-4.15.1
		make
		make install

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
			mkdir build
			cd build/
			cmake ..
			make
			export PATH=$PATH:$PWD/yajl-2.1.0/bin
		fi

		#Apply 3 patches
		cd "${CURDIR}"

		curl -o throttle-rebal.t.diff $REPO_URL/throttle-rebal.t.diff
		patch "${CURDIR}/glusterfs/tests/basic/distribute/throttle-rebal.t" throttle-rebal.t.diff

		curl -o mount-nfs-auth.t.diff $REPO_URL/mount-nfs-auth.t.diff
		patch "${CURDIR}/glusterfs/tests/basic/mount-nfs-auth.t" mount-nfs-auth.t.diff

		curl -o frequency-counters.t.diff $REPO_URL/frequency-counters.t.diff
		patch "${CURDIR}/glusterfs/tests/basic/tier/frequency-counters.t" frequency-counters.t.diff

		curl -o namespace.t.diff $REPO_URL/namespace.t.diff
		patch "${CURDIR}/glusterfs/tests/basic/namespace.t" namespace.t.diff

		if [[ "${ID}" == "sles" ||  "${ID}" == "ubuntu" ]]; then
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
	sudo apt-get install -y make automake patch curl autoconf libtool flex bison pkg-config libssl-dev libxml2-dev python-dev libaio-dev libibverbs-dev librdmacm-dev libreadline-dev liblvm2-dev libglib2.0-dev liburcu-dev libcmocka-dev libsqlite3-dev libacl1-dev wget tar dbench git xfsprogs attr nfs-common yajl-tools sqlite3 libxml2-utils thin-provisioning-tools bc uuid-dev
	configureAndInstall | tee -a "$LOG_FILE"
	;;

"rhel-7.3" | "rhel-7.4" | "rhel-7.5")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
	sudo yum install -y wget patch git curl make gcc-c++ libaio-devel boost-devel expat-devel autoconf autoheader automake libtool flex bison openssl-devel libacl-devel sqlite-devel libxml2-devel python-devel python attr yajl nfs-utils xfsprogs popt-static sysvinit-tools psmisc libibverbs-devel librdmacm-devel readline-devel lvm2-devel glib2-devel fuse-devel bc libuuid-devel
	configureAndInstall | tee -a "$LOG_FILE"

	;;

"sles-12.3" | "sles-15")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
	sudo zypper --non-interactive install curl wget patch which git make gcc-c++ libaio-devel boost-devel autoconf automake cmake libtool flex bison lvm2-devel libacl-devel python-devel python attr xfsprogs sysvinit-tools psmisc bc libopenssl-devel libxml2-devel sqlite3 sqlite3-devel popt-devel nfs-utils libyajl2 python-xml net-tools libuuid-devel
	configureAndInstall | tee -a "$LOG_FILE"

	;;

*)
	printf -- "%s not supported \n" "$DISTRO" | tee -a "$LOG_FILE"
	exit 1
	;;
esac

printSummary | tee -a "$LOG_FILE"
