#!/bin/bash
# © Copyright IBM Corporation 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/netty-tcnative/2.0.28/build_netty.sh
# Execute build script: bash build_netty.sh    (provide -h for help)
#

set -e  -o pipefail

PACKAGE_NAME="netty-tcnative"
PACKAGE_VERSION="2.0.28"
SOURCE_ROOT="$(pwd)"
USER="$(whoami)"

FORCE="false"
LOG_FILE="${SOURCE_ROOT}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
   mkdir -p "$SOURCE_ROOT/logs/"
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
	cd $SOURCE_ROOT
	rm -rf  apache-maven-3.6.3-bin.tar.gz go1.13.1.linux-s390x.tar.gz cmake-3.7.2.tar.gz gcc-7.4.0.tar.xz
    printf -- "Cleaned up the artifacts\n" >> "$LOG_FILE"

}
function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'

	#Set environment variables
	printf -- "\nSet environment variables . . . \n"
	if [[ "$ID" == "rhel"  ]] ;then
		export JAVA_HOME=/usr/lib/jvm/java-1.8.0 
	fi
    		
    if [[ "$ID" == "sles"  ]] ;then
		if [[ "$VERSION_ID" == "12.4"  ]] ;then
			export JAVA_HOME=/usr/lib64/jvm/jre-1.8.0-openjdk
		else
			export JAVA_HOME=/usr/lib64/jvm/java-1.8.0       
		fi
    fi
	
    if [[ "$ID" == "ubuntu"  ]] ;then	
		export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk-s390x		
    fi
		
	
	export PATH=$JAVA_HOME/bin:$PATH
	printf -- "Java version is :\n"
	java -version
	
	#Install ninja (for SLES 12 SP4 , RHEL )
	if [[ "$ID" == "rhel" || "$VERSION_ID" == "12.4" ]]  ;then
		
		printf -- "\nInstalling ninja . . . \n"
		cd $SOURCE_ROOT
		git clone https://github.com/ninja-build/ninja
		cd ninja
		git checkout v1.8.2		
		./configure.py --bootstrap
		export PATH=$SOURCE_ROOT/ninja:$PATH		
	fi
	
	#Install maven (for SLES , RHEL  only)
	if [[ "$VERSION_ID" == "7.5" || "$VERSION_ID" == "7.6" || "$VERSION_ID" == "7.7" || "$ID" == "sles" ]]  ;then
		printf -- "\nInstalling maven . . . \n"
		cd $SOURCE_ROOT
		wget http://www.eu.apache.org/dist/maven/maven-3/3.6.3/binaries/apache-maven-3.6.3-bin.tar.gz
		tar -xvzf apache-maven-3.6.3-bin.tar.gz
		export PATH=$PATH:$SOURCE_ROOT/apache-maven-3.6.3/bin/
	
	fi
	
	#Install GO (for SLES)
	if [[ "$ID" == "sles" ]]  ;then
		cd $SOURCE_ROOT
		wget https://storage.googleapis.com/golang/go1.13.1.linux-s390x.tar.gz
		tar -xzf go1.13.1.linux-s390x.tar.gz
		export PATH=$SOURCE_ROOT/go/bin:$PATH
		export GOROOT=$SOURCE_ROOT/go
		export GOPATH=$SOURCE_ROOT/go/bin	
	fi
	
	#Install cmake 3.7 (RHEL 7.x  only)
	if [[ "$VERSION_ID" == "7.5" || "$VERSION_ID" == "7.6" || "$VERSION_ID" == "7.7" ]]  ;then
		cd $SOURCE_ROOT
		wget https://cmake.org/files/v3.7/cmake-3.7.2.tar.gz
		tar xzf cmake-3.7.2.tar.gz
		cd cmake-3.7.2
		./configure --prefix=/usr/local
		make && sudo make install	
	fi
	
	#Install gcc 7.5.0 (RHEL 7.6 and RHEL 7.7 only)
	if [[ "$VERSION_ID" == "7.5" || "$VERSION_ID" == "7.6" || "$VERSION_ID" == "7.7" ]]  ;then
		cd $SOURCE_ROOT
		mkdir gcc
		cd gcc
		wget https://ftpmirror.gnu.org/gcc/gcc-7.4.0/gcc-7.4.0.tar.xz
		tar -xf gcc-7.4.0.tar.xz
		cd gcc-7.4.0
		./contrib/download_prerequisites
		mkdir objdir
		cd objdir
		../configure --prefix=/opt/gcc --enable-languages=c,c++ --with-arch=zEC12 --with-long-double-128 \
		--build=s390x-linux-gnu --host=s390x-linux-gnu --target=s390x-linux-gnu                  \
		--enable-threads=posix --with-system-zlib --disable-multilib
		make -j 8
		sudo make install
		sudo ln -sf /opt/gcc/bin/gcc /usr/bin/gcc
		sudo ln -sf /opt/gcc/bin/g++ /usr/bin/g++
		sudo ln -sf /opt/gcc/bin/g++ /usr/bin/c++
		export PATH=/opt/gcc/bin:"$PATH"
		export LD_LIBRARY_PATH=/opt/gcc/lib64:"$LD_LIBRARY_PATH"
		export C_INCLUDE_PATH=/opt/gcc/lib/gcc/s390x-linux-gnu/7.4.0/include
		export CPLUS_INCLUDE_PATH=/opt/gcc/lib/gcc/s390x-linux-gnu/7.4.0/include
		sudo ln -sf /opt/gcc/lib64/libstdc++.so.6.0.24 /lib64/libstdc++.so.6
	fi
	
	#Build netty-tcnative
	cd $SOURCE_ROOT
	git clone https://github.com/netty/netty-tcnative.git
	cd netty-tcnative
	git checkout netty-tcnative-parent-${PACKAGE_VERSION}.Final
	
	cd $SOURCE_ROOT/netty-tcnative
	printf -- "\nApplying  patch . . . \n"
	# Apply patch
	sed -i '58,58 s/chromium-stable/patch-s390x-Aug2019/g'    pom.xml
	sed -i '82,82 s/boringssl.googlesource.com/github.com\/linux-on-ibm-z/g'  boringssl-static/pom.xml
	mvn install 
	

	#Cleanup

	printf -- "\n Installation of netty was sucessfull \n\n" 
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
	echo "  bash build_netty.sh  [-d debug] [-y install-without-confirmation] "
	echo
}

while getopts "h?dy" opt; do
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
	esac
done

function gettingStarted() {
	printf -- '\n***********************************************************************************************\n'
	printf -- "Getting Started: \n"
	printf -- "Set LD_LIBRARY_PATH : \n"
	printf -- "  $ export LD_LIBRARY_PATH=$SOURCE_ROOT/netty-tcnative/openssl-dynamic/target/native-build/.libs/:\$LD_LIBRARY_PATH  \n\n"
	printf -- " \n\n"
	printf -- '*************************************************************************************************\n'
	printf -- '\n'
}

###############################################################################################################

logDetails
prepare #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04" | "ubuntu-19.10")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo apt-get update -y
	sudo apt-get install -y ninja-build cmake perl golang libssl-dev libapr1-dev autoconf automake libtool make tar git openjdk-8-jdk maven patch |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;
"rhel-7.5" | "rhel-7.6" | "rhel-7.7")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo yum install -y perl gcc gcc-c++ openssl-devel apr-devel autoconf automake libtool make tar git java-1.8.0-openjdk-devel wget bzip2  zlib-devel golang patch |& tee -a "${LOG_FILE}"
    configureAndInstall |& tee -a "${LOG_FILE}"
	;;
"rhel-8.0")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo yum install -y cmake perl gcc gcc-c++ openssl-devel apr-devel autoconf automake libtool make tar git java-1.8.0-openjdk-devel wget python2 bzip2 zlib zlib-devel git xz diffutils  maven golang patch |& tee -a "${LOG_FILE}"
	sudo ln /usr/bin/python2 /usr/bin/python
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;
"sles-12.4")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo zypper install -y cmake perl libopenssl-devel libapr1-devel autoconf automake libtool make tar git java-1_8_0-openjdk-devel gcc-c++ wget  which patch |& tee -a "${LOG_FILE}"
    configureAndInstall |& tee -a "${LOG_FILE}"
	;;
"sles-15.1")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo zypper install -y ninja cmake perl  libopenssl-devel autoconf automake libtool make tar git java-1_8_0-openjdk-devel wget apr-devel zlib-devel gcc gcc-c++ patch gzip |& tee -a "${LOG_FILE}"
	if [[ "$VERSION_ID" == "15.1" ]] ;then
		sudo zypper install -y awk |& tee -a "${LOG_FILE}"
	fi
	sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
    configureAndInstall |& tee -a "${LOG_FILE}"
	;;
*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
