#!/bin/bash
# © Copyright IBM Corporation 2026
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/MySQL/9.7.1/build_mysql.sh
# Execute build script: bash build_mysql.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="mysql"
PACKAGE_VERSION="9.7.1"
SOURCE_ROOT="$(pwd)"
MYSQL_INSTALL="${SOURCE_ROOT}/mysql-install"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/MySQL/9.7.1/patch"

FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
BUILD_ENV="$HOME/setenv.sh"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
    mkdir -p "$SOURCE_ROOT/logs/"
fi

source "/etc/os-release"

function prepare() {
    if command -v "sudo" >/dev/null; then
        printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
    else
        printf -- 'Sudo : No \n' >>"$LOG_FILE"
        printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n'
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
    cd $SOURCE_ROOT
    rm -rf duktape-2.7.0  duktape-2.7.0.tar.xz
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

    #Download the MySQL source code from Github
    cd $SOURCE_ROOT
    git clone -b mysql-$PACKAGE_VERSION --depth 1 https://github.com/mysql/mysql-server.git
    cd mysql-server
    curl -sSL "${PATCH_URL}/mt-asm.patch" | git apply -
    curl -sSL "${PATCH_URL}/NdbHW.patch" | git apply -
    curl -sSL "${PATCH_URL}/router-test.patch" | git apply -
    curl -sSL "${PATCH_URL}/ut0rnd.patch" | git apply -
    curl -sSL "${PATCH_URL}/type-vector.patch" | git apply -
	curl -sSL "${PATCH_URL}/loaddata.patch" | git apply -
	curl -sSL "${PATCH_URL}/gunit-test.patch" | git apply -
    
    # Create a clean build and user-owned installation directory.
    rm -rf build "$MYSQL_INSTALL"
    mkdir -p build "$MYSQL_INSTALL"

    cd build

    #Configure, build and install MySQL
    if [[ "$ID" == "ubuntu" || "$DISTRO" =~ ^rhel-9 ]]; then
        cmake .. \
            -DWITH_SSL=system \
            -DWITH_PROTOBUF=system \
            -DCMAKE_INSTALL_PREFIX="$MYSQL_INSTALL"
    else
        cmake .. \
            -DWITH_SSL=system \
            -DCMAKE_INSTALL_PREFIX="$MYSQL_INSTALL"
    fi

    # Use lower parallelism on RHEL 10.x to reduce LTO temporary-space usage.
    if [[ "$DISTRO" =~ ^rhel-10 ]]; then
        make -j 2
    else
        make -j "$(nproc)"
    fi

    printf -- "MySQL build completed successfully. \n"
    if [[ "$TESTS" == "true" ]]; then
        # runTest handles unit tests, installation and integration tests.
        runTest
    else
        # Install as the current user. Do not use sudo.
        make install
        if [[ ! -x "$MYSQL_INSTALL/bin/mysqld" ]]; then
            printf -- "ERROR: MySQL installation verification failed.\n"
            return 1
        fi

        printf -- "MySQL installed successfully at %s.\n" "$MYSQL_INSTALL"
    fi
  # Cleanup
    cleanup
}

function buildPython2(){
    cd $SOURCE_ROOT
    wget https://www.python.org/ftp/python/2.7.18/Python-2.7.18.tar.xz
    tar -xvf Python-2.7.18.tar.xz
    cd $SOURCE_ROOT/Python-2.7.18
    ./configure --prefix=/usr/local --exec-prefix=/usr/local
    make
    sudo make install   
    sudo ln -sf /usr/local/bin/python /usr/bin/python2
    python2 -V
}

function runTest() {
    local unit_test_status=0
    local install_status=0
    local integration_test_status=0

    printf -- "TEST flag is set. Continuing with test execution.\n" \
        >>"$LOG_FILE"

    cd "$SOURCE_ROOT/mysql-server/build"

    # Required for distros using the bundled protobuf library.
    if [[ ! ( "$ID" == "ubuntu" || "$DISTRO" =~ ^rhel-9 ) ]]; then
        export LD_PRELOAD="$SOURCE_ROOT/mysql-server/build/library_output_directory/libprotobuf-lite.so.24.4.0${LD_PRELOAD:+:${LD_PRELOAD}}"

        printf -- "export LD_PRELOAD=\"${LD_PRELOAD}\"\n" \
            >>"$BUILD_ENV"
    fi

    set +e

    # Run unit tests before installation.
    printf -- "Running Unit Tests.\n"

    make test
    unit_test_status=$?

    if [[ "$unit_test_status" -eq 0 ]]; then
        printf -- "Unit Tests completed successfully.\n"
    else
        printf -- "Unit Tests completed with failures. Exit code: %s\n" \
            "$unit_test_status"
    fi

    # Install MySQL as the current user into the user-owned directory.
    printf -- "Installing MySQL at %s.\n" "$MYSQL_INSTALL"

    make install
    install_status=$?

    if [[ "$install_status" -ne 0 ]]; then
        printf -- "ERROR: MySQL installation failed. Exit code: %s\n" \
            "$install_status"

        set -e
        return "$install_status"
    fi

    # Verify the installation.
    if [[ ! -x "$MYSQL_INSTALL/bin/mysqld" ]]; then
        printf -- "ERROR: Installed mysqld binary was not found at %s.\n" \
            "$MYSQL_INSTALL/bin/mysqld"

        set -e
        return 1
    fi

    if [[ ! -x "$MYSQL_INSTALL/mysql-test/mysql-test-run.pl" ]]; then
        printf -- "ERROR: mysql-test-run.pl was not found at %s.\n" \
            "$MYSQL_INSTALL/mysql-test/mysql-test-run.pl"

        set -e
        return 1
    fi

    printf -- "MySQL installation completed successfully.\n"
    "$MYSQL_INSTALL/bin/mysqld" --version

    # Run integration tests from the user-owned installation.
    printf -- "Running Integration Tests.\n"

    rm -rf "$SOURCE_ROOT/mysql-test/var"
    mkdir -p "$SOURCE_ROOT/mysql-test/var/tmp"

    cd "$MYSQL_INSTALL/mysql-test"

    ./mysql-test-run.pl \
        --vardir="$SOURCE_ROOT/mysql-test/var" \
        --tmpdir="$SOURCE_ROOT/mysql-test/var/tmp" \
        --suite=main \
        --force \
        --skip-test=file_contents \
        --testcase-timeout=3600 \
        --suite-timeout=600

    integration_test_status=$?

    if [[ "$integration_test_status" -eq 0 ]]; then
        printf -- "Integration Tests completed successfully.\n"
    else
        printf -- "Integration Tests completed with failures. Exit code: %s\n" \
            "$integration_test_status"
    fi

    set -e

    # Report failure only after both test suites have completed.
    if [[ "$unit_test_status" -ne 0 ||
          "$integration_test_status" -ne 0 ]]; then
        return 1
    fi

    return 0
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
    echo "bash build_mysql.sh  [-d debug] [-y install-without-confirmation] [-t install and run tests]"
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
    printf -- "                       Getting Started                \n"
    printf -- " MySQL ${PACKAGE_VERSION} installed successfully.       \n"
    printf -- " Information regarding the post-installation steps can be found here : https://dev.mysql.com/doc/refman/9.7/en/postinstallation.html\n"
    printf -- " Starting MySQL Server: \n"
    printf -- " sudo useradd mysql   \n"
    printf -- " sudo groupadd mysql \n"
	printf -- " cd ${MYSQL_INSTALL}  \n"
    printf -- " sudo mkdir mysql-files \n"
    printf -- " sudo chown mysql:mysql mysql-files \n"
    printf -- " sudo chmod 750 mysql-files \n"
    printf -- " sudo bin/mysqld --initialize --user=mysql \n"
    printf -- " sudo bin/mysqld_safe --user=mysql & \n"
    printf -- "           You have successfully started MySQL Server.\n"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare
DISTRO="$ID-$VERSION_ID"

rm -rf ${BUILD_ENV}

case "$DISTRO" in
"rhel-8.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y curl libcurl-devel wget bison bzip2 gcc gcc-c++ git hostname ncurses-devel openssl openssl-devel pkgconfig tar procps wget zlib-devel \
        doxygen cmake diffutils rpcgen make libtirpc-devel libarchive net-tools \
        gcc-toolset-14-gcc gcc-toolset-14-gcc-c++ gcc-toolset-14-binutils gcc-toolset-14-annobin-plugin-gcc \
        cpan perl-JSON perl-Memoize psmisc zip mecab-ipadic |& tee -a "$LOG_FILE"
    sudo PERL_MM_USE_DEFAULT=1 cpan Expect |& tee -a "$LOG_FILE"
    sudo yum install -y xz python2 python2-pyyaml |& tee -a "$LOG_FILE"
    source /opt/rh/gcc-toolset-14/enable

    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-9.6" | "rhel-9.7" | "rhel-9.8")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y curl libcurl-devel
        sudo yum install -y wget bison bzip2 bzip2-devel gcc gcc-c++ git xz xz-devel hostname ncurses ncurses-devel openssl procps openssl-devel \
        pkgconfig tar wget zlib-devel doxygen cmake diffutils rpcgen make libtirpc-devel libarchive tk-devel gdb gdbm-devel sqlite-devel \
        readline-devel libdb-devel libffi-devel libuuid-devel libnsl2-devel net-tools \
        gcc-toolset-14-gcc gcc-toolset-14-gcc-c++ gcc-toolset-14-binutils gcc-toolset-14-annobin-plugin-gcc \
        cpan perl-JSON perl-Memoize psmisc zip mecab-ipadic |& tee -a "$LOG_FILE"
    sudo yum install -y protobuf-c-compiler protobuf-compiler protobuf-lite protobuf-c-devel protobuf-devel protobuf-lite-devel |& tee -a "$LOG_FILE"
    sudo PERL_MM_USE_DEFAULT=1 cpan Expect |& tee -a "$LOG_FILE"
    source /opt/rh/gcc-toolset-14/enable

    buildPython2 |& tee -a "$LOG_FILE"
    curl https://bootstrap.pypa.io/pip/2.7/get-pip.py --output get-pip.py
    sudo python2 get-pip.py |& tee -a "$LOG_FILE"
    python2 -m pip install --upgrade pip setuptools --force-reinstall
    python2 -m pip install PyYAML==3.13 |& tee -a "$LOG_FILE"

    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-10.0" | "rhel-10.1" | "rhel-10.2")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y curl libcurl-devel
        sudo yum install -y wget bison bzip2 bzip2-devel gcc gcc-c++ git xz xz-devel hostname ncurses ncurses-devel openssl procps openssl-devel \
        pkgconfig tar wget zlib-devel doxygen cmake diffutils rpcgen make libtirpc-devel libarchive tk-devel gdb gdbm-devel sqlite-devel \
        readline-devel libdb-devel libffi-devel libuuid-devel libnsl2-devel net-tools \
        cpan perl-JSON perl-Memoize psmisc zip mecab-ipadic |& tee -a "$LOG_FILE"
    sudo yum install -y protobuf-c-compiler protobuf-compiler protobuf-lite protobuf-c-devel protobuf-devel protobuf-lite-devel |& tee -a "$LOG_FILE"
	# Prefer the distribution packages. Fall back to CPAN without
	# executing the platform-sensitive Expect test suite.
	if ! sudo dnf install -y perl-Expect perl-IO-Tty \
		|& tee -a "$LOG_FILE"; then

		printf -- "RPM packages unavailable; installing Expect through CPAN.\n" \
			|& tee -a "$LOG_FILE"

		sudo env PERL_MM_USE_DEFAULT=1 cpan -T Expect \
			|& tee -a "$LOG_FILE"
	fi

	# Verify that the Perl modules are usable.
	perl -MExpect -e \
		'print "Expect version: $Expect::VERSION\n"' \
		|& tee -a "$LOG_FILE"

	perl -MIO::Pty -e \
		'print "IO::Pty module is available\n"' \
		|& tee -a "$LOG_FILE"

    buildPython2 |& tee -a "$LOG_FILE"
    curl https://bootstrap.pypa.io/pip/2.7/get-pip.py --output get-pip.py
    sudo python2 get-pip.py |& tee -a "$LOG_FILE"
    python2 -m pip install --upgrade pip setuptools --force-reinstall
    python2 -m pip install PyYAML==3.13 |& tee -a "$LOG_FILE" # for Duktape

    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-15.7")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y curl libcurl-devel make cmake bison gcc14 gcc14-c++ git-core hostname ncurses-devel openssl procps \
        openssl-devel pkg-config gawk doxygen libtirpc-devel rpcgen tar wget net-tools-deprecated \
        xz timezone gzip unzip perl-JSON perl-Expect |& tee -a "$LOG_FILE"
    sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-14 14
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-14 14
    sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-14 14
    sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-14 14
    sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
    sudo ln -sf /usr/bin/cpp-14 /usr/bin/cpp

    buildPython2 |& tee -a "$LOG_FILE"
    curl https://bootstrap.pypa.io/pip/2.7/get-pip.py --output get-pip.py
    sudo python2 get-pip.py |& tee -a "$LOG_FILE"
    python2 -m pip install --upgrade pip setuptools --force-reinstall
    python2 -m pip install PyYAML==3.13 |& tee -a "$LOG_FILE" # for Duktape

    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"ubuntu-22.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y curl libcurl4-openssl-dev dpkg-dev wget tar bison cmake gcc g++ git hostname \
        libncurses-dev libssl-dev make openssl pkg-config gawk procps doxygen python-is-python3 python2 net-tools \
        libtirpc-dev libarchive-tools xz-utils libjson-perl libexpect-perl mecab-ipadic-utf8 psmisc zip \
        |& tee -a "$LOG_FILE"
    sudo apt-get install -y libprotoc-dev libprotobuf-c-dev libprotobuf-dev protobuf-c-compiler protobuf-compiler |& tee -a "$LOG_FILE"
    curl https://bootstrap.pypa.io/pip/2.7/get-pip.py --output get-pip.py
    sudo python2 get-pip.py |& tee -a "$LOG_FILE"
    python2 -m pip install --upgrade pip setuptools --force-reinstall
    python2 -m pip install PyYAML==3.13 |& tee -a "$LOG_FILE" # for Duktape
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"ubuntu-24.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y curl libcurl4-openssl-dev dpkg-dev wget tar bison cmake gcc g++ git hostname \
        libncurses-dev libssl-dev make openssl pkg-config gawk procps doxygen python-is-python3 net-tools \
        libtirpc-dev libarchive-tools xz-utils libjson-perl libexpect-perl mecab-ipadic-utf8 psmisc zip \
        |& tee -a "$LOG_FILE"
    sudo apt-get install -y libprotoc-dev libprotobuf-c-dev libprotobuf-dev protobuf-c-compiler protobuf-compiler |& tee -a "$LOG_FILE"
    buildPython2 |& tee -a "$LOG_FILE"
    curl https://bootstrap.pypa.io/pip/2.7/get-pip.py --output get-pip.py
    sudo python2 get-pip.py |& tee -a "$LOG_FILE"
    python2 -m pip install --upgrade pip setuptools --force-reinstall
    python2 -m pip install PyYAML==3.13 |& tee -a "$LOG_FILE"

    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"


