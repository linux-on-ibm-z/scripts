#!/bin/bash
# © Copyright IBM Corporation 2022.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/CouchDB/3.2.2/build_couchdb.sh
# Execute build script: bash build_couchdb.sh  (provide -h for help)
#

set -e -o pipefail

PACKAGE_NAME="couchdb"
PACKAGE_VERSION="3.2.2"
CURDIR="$(pwd)"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/CouchDB/3.2.2/patch"
DATE_AND_TIME="$(date +"%F-%T")"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-${DATE_AND_TIME}.log"
FORCE="false"
TESTS="false"
trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
	mkdir -p "$CURDIR/logs/"
fi

if [ -f "/etc/os-release" ]; then
	source "/etc/os-release"
else
    printf -- "%s Package with version %s is currently not supported for %s .\n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
fi

function prepare() {

	if command -v "sudo" >/dev/null; then
		printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
	else
		printf -- 'Sudo : No \n' >>"$LOG_FILE"
		printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n'
		exit 1
	fi

	if [[ "$FORCE" == "true" ]]; then
		printf -- 'Force attribute provided hence continuing with install without confirmation message'
	else
		printf -- '\nBuild might take some time...'
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

function runTest() {
	set +e
	cd "${CURDIR}"/couchdb
	
    if [[ "$TESTS" == "true" ]]; then
    export PATH=$PATH:/usr/local/bin
    export LD_LIBRARY_PATH=/usr/lib
    case "$DISTRO" in
    "ubuntu-20.04")
      ./configure --spidermonkey-version 68
      ;;
    "ubuntu-22.04")
      ./configure --spidermonkey-version 78
      ;;
    "rhel-8.4" | "rhel-8.6")
      ./configure --spidermonkey-version 60
      ;;
    *)
      ./configure
      ;;
    esac
		make check
	fi
	set -e
}

function cleanup() {
	printf -- '\nCleaned up the artifacts\n' |& tee -a "$LOG_FILE"
	rm -rf "${CURDIR}/jsval.h.diff"
	rm -rf "${CURDIR}/jsvalue.h.diff"
	rm -rf "${CURDIR}/Makefile.in.diff"
	rm -rf "${CURDIR}/couch_compress_tests.erl.diff"
}

function installPython() {
  cd "${CURDIR}"
  printf -- 'Installing python3 from source:\n' |& tee -a "$LOG_FILE"
  wget https://www.python.org/ftp/python/3.8.2/Python-3.8.2.tgz
  tar -xzf Python-3.8.2.tgz
  cd Python-3.8.2
  ./configure --prefix=/usr --exec-prefix=/usr
  make
  sudo make install
  printf -- 'Python installed, version:\n' |& tee -a "$LOG_FILE"
  python3 -V |& tee -a "$LOG_FILE"
}

function configureAndInstall() {
	printf -- '\nConfiguration and Installation started \n'
	#Installing dependencies
	printf -- 'User responded with Yes. \n'
	sudo pip3 install --upgrade wheel sphinx==3.5.4 sphinx_rtd_theme docutils==0.16 nose requests hypothesis virtualenv jinja2==3.0.0

	#only for rhel 7.x
	if [[ "${DISTRO}" == "rhel-7.*" ]]; then
		cd "${CURDIR}"
		wget https://github.com/git/git/archive/v2.34.0.tar.gz
		tar -zxf v2.34.0.tar.gz
		cd git-2.34.0
		make configure
		./configure --prefix=/usr
		make
		sudo make install
	fi


  #Install Erlang
  cd "${CURDIR}"
  wget http://www.erlang.org/download/otp_src_24.2.tar.gz
  tar zxf otp_src_24.2.tar.gz
  cd otp_src_24.2
  export ERL_TOP="${CURDIR}/otp_src_24.2"
  ./configure --prefix=/usr
  make
  sudo make install
	
  
  #Install elixir
  cd "${CURDIR}"
  git clone https://github.com/elixir-lang/elixir.git
  cd elixir
  git checkout v1.12.3
  export LANG=en_US.UTF-8 
  if [[ "${ID}" == "ubuntu" ]]; then
  sudo locale-gen en_US.UTF-8
  fi
  printf -- 'Installing and testing elixir\n'
  make
  sudo make install
  printf -- 'Elixir installed, version:\n'
  elixir -v


  #Install nodejs
  cd "${CURDIR}"
  printf -- 'Installing nodejs\n'
  sudo mkdir -p /usr/local/lib/nodejs
  wget https://nodejs.org/dist/v16.13.0/node-v16.13.0-linux-s390x.tar.gz
  sudo tar xzvf node-v16.13.0-linux-s390x.tar.gz -C /usr/local/lib/nodejs
  sudo ln -s /usr/local/lib/nodejs/node-v16.13.0-linux-s390x/bin/* /usr/bin/
  printf -- 'node version\n'
  node -v
  printf -- 'npm version\n'
  npm -v

	#Install SpiderMonkey 1.8.5 (Only for Ubuntu 18.04)
	if [ ${DISTRO} == "ubuntu-18.04" ]; then
		printf -- '\nDownloading SpiderMonkey source\n'
		cd "${CURDIR}"
		wget http://ftp.mozilla.org/pub/spidermonkey/releases/1.8.5/js185-1.0.0.tar.gz
		tar zxf js185-1.0.0.tar.gz
		cd js-1.8.5

		cd "${CURDIR}"
		curl -o jsval.h.diff $PATCH_URL/jsval.h.diff
		patch "${CURDIR}/js-1.8.5/js/src/jsval.h" jsval.h.diff

		curl -o jsvalue.h.diff $PATCH_URL/jsvalue.h.diff
		patch "${CURDIR}/js-1.8.5/js/src/jsvalue.h" jsvalue.h.diff

		curl -o Makefile.in.diff $PATCH_URL/Makefile.in.diff
		patch "${CURDIR}/js-1.8.5/js/src/Makefile.in" Makefile.in.diff

		#Preparing the source code
		cd "${CURDIR}/js-1.8.5/js/src"

		autoconf2.13
	
		#Configure, build & install SpiderMonkey
		mkdir -p "${CURDIR}/js-1.8.5/js/src/build_OPT.OBJ"
		cd "${CURDIR}/js-1.8.5/js/src/build_OPT.OBJ"
		../configure --prefix=/usr
		make
		sudo make install

		printf -- 'SpiderMonkey installed succesfully\n'
	fi
	#Download the CouchDB source code
	cd "${CURDIR}"
	printf -- '\nDownloading  CouchDB. Please wait.\n'
	git clone -b $PACKAGE_VERSION https://github.com/apache/couchdb.git

	#Configure and build CouchDB
	cd "${CURDIR}/couchdb"
	export LD_LIBRARY_PATH=/usr/lib

	case "$DISTRO" in
	"ubuntu-20.04")
	  ./configure  --spidermonkey-version 68
	  ;;
	"rhel-8.4" | "rhel-8.6")
	  ./configure  --spidermonkey-version 60
	  ;;
	"ubuntu-22.04")
	  ./configure  --spidermonkey-version 78
	  ;;
	*)
	  ./configure 
	  ;;
	esac

  	make release
	
	# Add CouchDB group 
	sudo groupadd couchdb 
	sudo usermod -aG couchdb $(whoami)

	#copy couchdb folder to default location
	sudo cp -r "${CURDIR}/couchdb/rel/couchdb" /opt/
	
	# Permissions
	sudo chown "$(whoami)":couchdb -R /opt/couchdb
	
	sudo find /opt/couchdb -type d -exec chmod 0770 {} \;
	
	chmod 0644 /opt/couchdb/etc/*
	
	sed -i 's/;admin = mysecretpassword/admin = mysecretpassword/' /opt/couchdb/etc/local.ini


	printf -- 'Build process completed successfully\n' | tee -a "$LOG_FILE"
	
	#Run tests
	runTest |& tee -a "$LOG_FILE"
	printf -- 'Couchdb built succesfully\n'
}

function logDetails() {
	printf -- 'SYSTEM DETAILS\n' >"$LOG_FILE"
	if [ -f "/etc/os-release" ]; then
		cat "/etc/os-release" >>"$LOG_FILE"
	fi

	cat /proc/version >>"$LOG_FILE"
	printf -- "\nDetected %s \n" "$PRETTY_NAME"
	printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" |& tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
	echo
	echo "Usage: "
	echo "bash build_couchdb.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests]"
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

function printSummary() {
	printf -- '\n\nRun following command to run couchdb server.\n' |& tee -a "$LOG_FILE"
	printf -- '\n\n  /opt/couchdb/bin/couchdb & \n' |& tee -a "$LOG_FILE"
	printf -- '\nFor more help visit http://docs.couchdb.org/en/3.2.2/index.html \n' |& tee -a "$LOG_FILE"
}

logDetails
#checkPrequisites
prepare |& tee -a "$LOG_FILE"

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-18.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
	sudo apt-get update
	sudo DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential pkg-config ncurses-base g++-5 gcc-5 python python3 python3-pip python3-venv python3-markupsafe hostname curl git patch wget tar make zip autoconf2.13 automake libicu-dev libcurl4-openssl-dev libncurses5-dev locales libncurses-dev libssl-dev unixodbc-dev libwxgtk3.0-dev openjdk-8-jdk xsltproc libxml2-utils |& tee -a "$LOG_FILE"

	sudo rm -rf /usr/bin/gcc /usr/bin/g++ /usr/bin/cc
	sudo ln -s /usr/bin/gcc-5 /usr/bin/gcc
	sudo ln -s /usr/bin/g++-5 /usr/bin/g++
	sudo ln -s /usr/bin/gcc /usr/bin/cc
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"ubuntu-20.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
	sudo apt-get update
	sudo DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential pkg-config ncurses-base g++ gcc python python3 python3-pip python3-venv hostname curl git patch wget tar make zip libicu-dev libcurl4-openssl-dev libncurses5-dev locales libncurses-dev libssl-dev unixodbc-dev libwxgtk3.0-gtk3-dev openjdk-8-jdk xsltproc libxml2-utils libmozjs-68-dev |& tee -a "$LOG_FILE"

	configureAndInstall |& tee -a "$LOG_FILE"
	;;
"ubuntu-22.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
	sudo apt-get update
	sudo DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential pkg-config ncurses-base g++ gcc hostname curl git patch wget tar make zip libicu-dev libcurl4-openssl-dev libncurses5-dev locales libncurses-dev libssl-dev unixodbc-dev libwxgtk3.0-gtk3-dev openjdk-8-jdk xsltproc libxml2-utils libmozjs-78-dev libbz2-dev libdb-dev libffi-dev libgdbm-dev liblzma-dev libncurses-dev libreadline-dev libsqlite3-dev libssl-dev make tar tk-dev uuid-dev wget xz-utils zlib1g-dev  |& tee -a "$LOG_FILE"
        installPython
	configureAndInstall |& tee -a "$LOG_FILE"
	;;	
"rhel-7.8" | "rhel-7.9")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for couchdb from repository \n' |& tee -a "$LOG_FILE"
	sudo yum install -y libicu-devel libcurl-devel wget tar m4 pkgconfig make libtool which gcc-c++ gcc openssl openssl-devel patch js-devel java-1.8.0-openjdk-devel perl-devel gettext-devel unixODBC-devel |&  tee -a "$LOG_FILE"
	# For Python
	sudo yum install -y bzip2-devel gdbm-devel libdb-devel libffi-devel libuuid-devel ncurses-devel readline-devel sqlite-devel tk-devel xz xz-devel zlib-devel |& tee -a "$LOG_FILE"
	installPython
	configureAndInstall |&  tee -a "$LOG_FILE"
	;;
"rhel-8.4"  | "rhel-8.6")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for couchdb from repository \n' |& tee -a "$LOG_FILE"
	sudo yum install -y autoconf flex flex-devel gawk gzip hostname libxml2-devel libxslt libicu-devel libcurl-devel wget tar m4 pkgconfig make libtool which gcc-c++ gcc openssl openssl-devel patch mozjs60-devel java-1.8.0-openjdk-devel perl-devel gettext-devel unixODBC-devel python38 python38-devel git ncurses-devel glibc-common |& tee -a "$LOG_FILE"
	configureAndInstall |&  tee -a "$LOG_FILE"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

# Print Summary
printSummary |& tee -a "$LOG_FILE"
