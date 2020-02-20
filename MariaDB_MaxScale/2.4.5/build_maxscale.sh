#!/bin/bash
# © Copyright IBM Corporation 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/MariaDB_MaxScale/2.4.5/build_maxscale.sh
# Execute build script: bash build_maxscale.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="maridb-maxscale"
PACKAGE_VERSION="2.4.5"
SOURCE_ROOT="$(pwd)"

FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
CONF_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/MariaDB_MaxScale/2.4.5/patch"


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
        printf -- "\nAs part of the installation , dependencies would be installed/upgraded.\n"
        while true; do
            read -r -p "Do you want to continue (y/n) ? :  " yn
            case $yn in
            [Yy]*)
                printf -- 'User responded with Yes. \n' >>"$LOG_FILE"
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
	cd $SOURCE_ROOT/MaxScale
	rm -rf patch_install.diff
	rm -rf patch_maxctrl_build.diff
	rm -rf maxctrl/pkg-fetch_build.diff
	rm -rf maxctrl/pkg-fetch_system.diff
	
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function configureAndInstall() {
    	printf -- "\n Configuration and Installation started \n"
	printf -- " Build and install MariaDB MaxScale \n"
	
	#Download MariaDB MaxScale source code
	cd $SOURCE_ROOT
	git clone https://github.com/mariadb-corporation/MaxScale.git
	cd MaxScale
	git checkout maxscale-${PACKAGE_VERSION}
	export CFLAGS=-fsigned-char
	
	#Apply patch to BUILD/install_build_deps.sh
	curl -o patch_install.diff $CONF_URL/patch_install.diff
	patch --ignore-whitespace BUILD/install_build_deps.sh < patch_install.diff
	
	curl -o maxctrl/pkg-fetch_build.diff $CONF_URL/pkg-fetch_build.diff
	curl -o maxctrl/pkg-fetch_system.diff $CONF_URL/pkg-fetch_system.diff
	
	curl -o patch_maxctrl_build.diff $CONF_URL/patch_maxctrl_build.diff
	patch --ignore-whitespace maxctrl/build.sh < patch_maxctrl_build.diff
	
	#Build MariaDB MaxScale
	
	cd $SOURCE_ROOT
	mkdir build && cd build	 
	sed -i 's,https://www-eu.apache.org/dist/avro/stable/c,https://downloads.apache.org/avro/stable/c/,g'  ../MaxScale/BUILD/install_build_deps.sh
	../MaxScale/BUILD/install_build_deps.sh
	
	cd $SOURCE_ROOT/MaxScale/pcre2
	./configure --without-pcre2-jit
	
	cd $SOURCE_ROOT/build
	cmake ../MaxScale -DBUILD_TESTS=Y
	
	make
	sudo make install
	
	printf -- 'MariaDB Maxscale build completed successfully. \n'
	
	#runTests
	runTest
     
}

function runTest() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- "\n\n TEST Flag is set, continue with running test. \n"  >> "$LOG_FILE"
		cd $SOURCE_ROOT/build
		make test
        	printf -- "Tests completed. \n" 
	fi
	set -e
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
    echo " build_maxscale.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests] "
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

function gettingStarted() {
		
    printf -- '\n********************************************************************************************************\n'
    printf -- "\n*Getting Started* \n"
    printf -- "\n Copy the required config files to /usr/local/share using below commands:"
    printf -- "\n   cd $SOURCE_ROOT/build"
    printf -- "\n   sudo cp maxscale /usr/local/share/maxscale/ "
    printf -- "\n   sudo cp maxscale.conf /usr/local/share/maxscale/"
    printf -- "\n Initialize and start the server as below:"
    printf -- "\n   sudo ./postinst"
    printf -- "\n   sudo /usr/local/bin/maxscale --user=maxscale \n"
    printf -- "This will start the Maridb Maxscale Server.\n"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04" | "ubuntu-19.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
	
	if [[ "$DISTRO" == "ubuntu-16.04" ]]; then
		sudo apt-get install -y gcc bison flex cmake perl libtool openssl libaio-dev git-core wget tar vim coreutils plotutils libc6 libssl-dev sqlite3 libmysqlclient20 libmysqlclient-dev pandoc mariadb-client libmariadb2 libmariadbd-dev librabbitmq-dev valgrind  libsqlite3-dev libsqlite3-0 tcl tcl-dev libuuid-perl libgnutls-dev libgnutls-openssl27 libgcrypt11-dev libdmalloc-dev libdmalloc5 libjemalloc-dev uuid uuid-dev libeditline-dev doxygen libedit-dev libpam0g-dev libpam-modules curl patch python |& tee -a "$LOG_FILE"
    elif [[ "$DISTRO" == "ubuntu-18.04" ]]; then
		sudo apt-get install -y gcc bison flex cmake perl libtool openssl libaio-dev git wget tar vim coreutils plotutils libc6 libssl-dev sqlite3 libmysqlclient20 pandoc mariadb-client libmariadb3 libmariadbd-dev librabbitmq-dev valgrind libsqlite3-dev libsqlite3-0 tcl tcl-dev libuuid-perl libcurl4-gnutls-dev libgnutls-openssl27 libgcrypt11-dev libdmalloc-dev libdmalloc5 libjemalloc-dev uuid uuid-dev libeditline-dev doxygen libedit-dev libpam0g-dev libpam-modules libmariadbclient-dev curl patch python |& tee -a "$LOG_FILE"
	else
		sudo apt-get install -y gcc bison flex cmake perl libtool openssl libaio-dev git-core wget tar vim coreutils plotutils libc6 libssl-dev sqlite3 pandoc mariadb-client libmariadb-dev  librabbitmq-dev valgrind  libsqlite3-dev libsqlite3-0 tcl tcl-dev libuuid-perl libgnutls28-dev libgnutls-openssl27 libdmalloc-dev libdmalloc5 libjemalloc-dev uuid uuid-dev libeditline-dev doxygen libedit-dev libpam0g-dev libpam-modules curl patch python |& tee -a "$LOG_FILE"
	fi
	configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-7.5" | "rhel-7.6" | "rhel-7.7")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y flex bison gcc gcc-c++ cmake perl libtool openssl-devel libaio-devel git-core wget tar coreutils sqlite-devel.s390 sqlite-devel.s390x sqlite.s390x tcl tcl-devel libuuid-devel libgcrypt-devel make ncurses-devel libcurl-devel mariadb-devel mariadb-embedded-devel lua-static.s390 lua-static.s390x lua-devel.s390x pam-devel.s390x pam.s390x pam-devel.s390 pam-devel.s390x redhat-lsb.s390x gnutls-devel.s390x valgrind libedit.s390x doxygen.s390x patch python |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-12.4" | "sles-15.1")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
 
	if [[ "$DISTRO" == "sles-12.4" ]]; then
		sudo zypper install -y gcc gcc-c++ bison flex cmake perl libtool openssl-devel libaio-devel git-core libmysqlclient18-32bit libmysqlclient18 mariadb-client mariadb-tools wget tar vim coreutils plotutils sqlite3-devel sqlite3 sqlite2-devel sqlite2 libsqlite3-0 tcl tcl-devel libuuid-devel libgnutls-openssl-devel libgnutls-devel libgcrypt-devel valgrind pam-devel doxygen libedit-devel patch curl python |& tee -a "$LOG_FILE"
	else
		sudo zypper install -y gcc gcc-c++ bison flex cmake perl libtool openssl-devel libaio-devel git-core mariadb libmariadb-devel mariadb-client mariadb-tools wget tar vim coreutils sqlite3-devel sqlite3 libsqlite3-0 tcl tcl-devel libuuid-devel libgnutls-devel libopenssl-devel libgcrypt-devel valgrind pam-devel doxygen libedit-devel patch curl python |& tee -a "$LOG_FILE"
	fi
	
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
