#!/bin/bash
# © Copyright IBM Corporation 2026.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/GlusterFS/11.2/build_glusterfs.sh
# Execute build script: bash build_glusterfs.sh (provide -h for help, -t true for executing build with tests])
#

set -e -o pipefail

PACKAGE_NAME="glusterfs"
PACKAGE_VERSION="11.2"
SOURCE_ROOT="$(pwd)"
PREFIX="/usr/local"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/GlusterFS/11.2/patch"

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
	
	# Install gcc11 for rhel-8.x
	if [[ "${DISTRO}" == "rhel-8.10" ]]; then
		yum install -y gcc-toolset-11-gcc-c++
		source /opt/rh/gcc-toolset-11/enable
	fi

	cd "${SOURCE_ROOT}"	

        # Download and configure GlusterFS
	printf -- '\n-----------------------------------\nDownloading GlusterFS. Please wait.\n-----------------------------------\n' 
        git clone --depth 1 -b v$PACKAGE_VERSION https://github.com/gluster/glusterfs.git
	
	printf -- '\n-------------------------------\n Applying patches.\n--------------------------------\n' 
  
        # Apply patches
	cd "${SOURCE_ROOT}/glusterfs"
	if [[ "${DISTRO}" == "rhel-9.6" ]]  ||  [[ "${DISTRO}" == "rhel-9.7" ]] || [[ "${DISTRO}" == "ubuntu-22.04" ]]; then
		curl -sSL $PATCH_URL/UB22RHEL9.patch | git apply
	elif [[ "${DISTRO}" == "ubuntu-24.04" ]]; then
		curl -sSL $PATCH_URL/UB24.patch | git apply
	elif [[ "${DISTRO}" == "rhel-8.10" ]]; then
		curl -sSL $PATCH_URL/RHEL8.patch | git apply
	elif [[ "${DISTRO}" == "sles-15.7" ]]; then
		curl -sSL $PATCH_URL/SLES.patch | git apply
	fi

	printf -- '\n---Patches are applied-----\n'
	./autogen.sh
      if [[ "${DISTRO}" == "ubuntu-22.04" ]] || [[ "${DISTRO}" == "ubuntu-24.04" ]]; then
	       ./configure CFLAGS="-DUSE_URCU_QSBR" --enable-debug --enable-gnfs --without-tcmalloc
      else	   
	     ./configure --enable-debug --enable-gnfs --without-tcmalloc
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
	echo
}

function runTest() {
	set +e
		
    if [[ "$TESTS" == "true" ]]; then
    		
	echo "Running Tests: "

        case "$DISTRO" in			
        "rhel-8.10" | "rhel-9.6" | "rhel-9.7")
            yum install -y dbench perl-Test-Harness yajl net-tools psmisc nfs-utils xfsprogs attr procps-ng gdb python3 iproute
				pip3 install prettytable
	    ;;
        "sles-15.7")
	    zypper install -y acl attr bc bind-utils gdb libxml2-tools net-tools-deprecated nfs-utils psmisc thin-provisioning-tools vim xfsprogs python3-PrettyTable libselinux-devel selinux-tools popt-devel libyajl2 libyajl-devel sysvinit-tools python3-pip procps e2fsprogs
	    pip3 install prettytable
	    wget https://www.rpmfind.net/linux/opensuse/distribution/leap/15.6/repo/oss/s390x/yajl-2.1.0-150000.4.6.1.s390x.rpm
	    rpm -ivh yajl-2.1.0-150000.4.6.1.s390x.rpm
            ;;
        "ubuntu-22.04" | "ubuntu-24.04")
            apt install -y dbench yajl-tools net-tools psmisc libnfs-utils xfsprogs attr procps gdb iproute2 nfs-common python3 python3-pip python3-prettytable libxml2-utils bc zfsutils-linux acl xdg-utils uuid-runtime

            cat /proc/sys/kernel/yama/ptrace_scope
            echo 0 | sudo tee /proc/sys/kernel/yama/ptrace_scope

            echo -e '#!/bin/sh\n[ -z "$1" ] && echo "Usage: pstack <pid>" && exit 1\ngdb -ex "thread apply all bt" -batch -p "$1" -ex detach' | sudo tee /usr/bin/gstack
            sudo chmod +x /usr/bin/gstack
            ln -sf `which gstack` /usr/bin/pstack
         ;;
	 esac

	   # link the gstack command to pstack for sles
	   if [[ "${ID}" == "sles" ]]; then
		ln -sf `which gstack` /usr/bin/pstack
	   fi
						
	   # Install dbench SLES only
    if [[ "${DISTRO}" == "sles-15.7" ]]; then
		   cd "${SOURCE_ROOT}"
		   git clone https://github.com/sahlberg/dbench
		   cd dbench
		   git checkout caa52d347171f96eef5f8c2d6ab04a9152eaf113
		   ./autogen.sh
		   ./configure --datadir=/usr/local/share/doc/loadfiles/
		   make
		   make install
	  fi

	   # Apply patches for testcase fix
	   cd $SOURCE_ROOT/glusterfs	 
			
	   if [[ "${DISTRO}" == "rhel-8."* ]] || [[ "${DISTRO}" == "rhel-9."* ]]; then
	      ln -s /usr/local/lib/libgfchangelog.so.0 /lib64/libgfchangelog.so
	      ldconfig /usr/local/lib
	      ldconfig /usr/local/lib64
	   fi
	   if [[ "${ID}" == "sles" ]]; then
	     curl -sSL $PATCH_URL/test-sles.patch | git apply 
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
"rhel-8.10")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
	yum install -y autoconf automake bison dos2unix flex fuse-devel glib2-devel libacl-devel libaio-devel libattr-devel libcurl-devel libibverbs-devel librdmacm-devel libtirpc-devel libuuid-devel libtool libxml2-devel make openssl-devel pkgconfig xz-devel  python3-devel python3-netifaces readline-devel rpm-build sqlite-devel systemtap-sdt-devel tar git lvm2-devel python3-paste-deploy python3-simplejson python3-sphinx python3-webob python3-pyxattr userspace-rcu-devel rpcgen liburing-devel gperf gperftools-devel |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

 "rhel-9.6" | "rhel-9.7")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
	yum install -y curl autoconf automake bison dos2unix flex fuse-devel glib2-devel libacl-devel libaio-devel libattr-devel libcurl-devel libibverbs-devel librdmacm-devel libtirpc-devel libuuid-devel libtool libxml2-devel make openssl-devel pkgconfig xz-devel  python3-devel python3-netifaces readline-devel rpm-build sqlite-devel systemtap-sdt-devel tar git lvm2-devel python3-paste-deploy python3-simplejson python3-sphinx python3-webob python3-pyxattr userspace-rcu-devel rpcgen liburing-devel gperf gperftools-devel iproute |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
	;;

 "sles-15.7")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
	zypper install -y curl autoconf automake bison cmake flex fuse-devel gcc-c++ git-core glib2-devel libacl-devel libaio-devel librdmacm1 libtool liburcu-devel libuuid-devel libxml2-devel lvm2 make pkg-config python3 python3-xattr rdma-core-devel readline-devel openssl-devel zlib-devel which wget gawk dmraid popt-devel gperftools-devel gperf gperftools libtirpc-devel rpcgen liburing-devel util-linux hostname iproute util-linux-systemd keyutils-devel |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"ubuntu-22.04" | "ubuntu-24.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
    apt-get update && apt-get install -y gcc g++ make automake autoconf libtool flex bison pkg-config libssl-dev libxml2-dev python3-dev libaio-dev libibverbs-dev librdmacm-dev libreadline-dev liblvm2-dev libglib2.0-dev liburcu-dev libcmocka-dev libsqlite3-dev libacl1-dev liburing-dev google-perftools libgoogle-perftools-dev libtirpc-dev |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

printSummary | tee -a "$LOG_FILE"

