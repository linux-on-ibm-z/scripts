#!/bin/bash
# ©  Copyright IBM Corporation 2025.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/PHP/8.4.11/build_php.sh
# Execute build script: bash build_php.sh    (provide -h for help)
#
#==============================================================================
set -e -o pipefail
PACKAGE_NAME="PHP"
PACKAGE_VERSION="8.4.11"
SOURCE_ROOT="$(pwd)"
FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/$PACKAGE_NAME-$PACKAGE_VERSION-$(date +"%F-%T").log"

PHP_URL="https://www.php.net/distributions"
PHP_URL+="/php-$PACKAGE_VERSION.tar.gz"

PREFIX=/usr/local
#==============================================================================
mkdir -p "$SOURCE_ROOT/logs"
error() {
    echo "Error: ${*}"
    exit 1
}
errlog() {
    echo "Error: ${*}" |& tee -a "$LOG_FILE"
    exit 1
}


msg() { echo "${*}"; }
log() { echo "${*}" >>"$LOG_FILE"; }
msglog() { echo "${*}" |& tee -a "$LOG_FILE"; }

trap cleanup 0 1 2 ERR
#==============================================================================
#Set the Distro ID
if [ -f "/etc/os-release" ]; then
    source "/etc/os-release"
else
    error "Unknown distribution"
fi
DISTRO="$ID-$VERSION_ID"
#==============================================================================
checkPrequisites() {
    if command -v "sudo" >/dev/null; then
        msglog "Sudo : Yes"
    else
        msglog "Sudo : No "
        error "sudo is required. Install using apt, yum or zypper based on your distro."
    fi


    if [[ "$FORCE" == "true" ]]; then
        msglog "Force - install without confirmation message"
    else
        # Ask user for prerequisite installation
        msg "As part of the installation , dependencies would be installed/upgraded."
        while true; do
            read -r -p "Do you want to continue (y/n) ? : " yn
            case $yn in
            [Yy]*)
                log "User responded with Yes."
                break
                ;;
            [Nn]*) exit ;;
            *) msg "Please provide confirmation to proceed." ;;
            esac
        done
    fi
}
#==============================================================================
cleanup() {
    echo "Cleaned up the artifacts."
}
#==============================================================================
# Build and install PHP package to all distros.
#
configureAndInstall() {
    local ver=$PACKAGE_VERSION
    msg "Configuration and Installation started"
    msg "Building PHP $ver"

    #----------------------------------------------------------
    cd "$SOURCE_ROOT"

    wget -qO- $PHP_URL | tar xzf - || error "PHP $ver"
    cd php-$ver

    ./configure --prefix=$PREFIX \
        --without-pcre-jit --without-pear \
        --enable-mysqlnd --with-pdo-mysql --with-pdo-pgsql=/usr/bin/pg_config \
        --enable-bcmath --enable-fpm --enable-mbstring --enable-phpdbg --enable-shmop \
        --enable-sockets --enable-sysvmsg --enable-sysvsem --enable-sysvshm \
        --with-zlib --with-curl --with-openssl --enable-pcntl --with-readline
    make -j$(nproc)
    sudo make install
    if [ "$?" -ne "0" ]; then
        error "Build for $PACKAGE_NAME failed. Please check the error logs."
    else
        msg "Build for $PACKAGE_NAME completed successfully. "
    fi
    sudo cp php.ini-development $PREFIX/lib/
    runTest
}

#==============================================================================
# Start MySql and Postgres servers before testing modules pdo_mysql,ext/mysqli
# and ext/pdo_pgsql. Ensure a test DB exists and required env variables are set.
runTest() {
    local ver=$PACKAGE_VERSION
    set +e
    if [[ "$TESTS" == "true" ]]; then
        log "TEST Flag is set, continue with running test "
        cd "$SOURCE_ROOT/php-$ver"
        rm ./ext/opcache/tests/log_verbosity_bug.phpt
        sed -i 's/run-tests.php -n -c/run-tests.php -q -n -c/' Makefile
        make TEST_PHP_ARGS=-j$(nproc) test
        msg "Test execution completed. "
        sed -i 's/run-tests.php -q -n -c/run-tests.php -n -c/' Makefile
    fi
    set -e
}

#==============================================================================
logDetails() {
    log "**************************** SYSTEM DETAILS ***************************"
    cat "/etc/os-release" >>"$LOG_FILE"
    cat /proc/version >>"$LOG_FILE"
    log "***********************************************************************"

    msg "Detected $PRETTY_NAME"
    msglog "Request details: PACKAGE NAME=$PACKAGE_NAME, VERSION=$PACKAGE_VERSION"
}

#==============================================================================
printHelp() {
    cat <<eof
  Usage:
  bash build_php.sh [-y] [-d] [-t]
  where:
   -y install-without-confirmation
   -d debug
   -t test
eof
}

###############################################################################
while getopts "h?dyt?" opt; do
    case "$opt" in
    h | \?)
        printHelp
        exit 0
        ;;
    d) set -x ;;
    y) FORCE="true" ;;
    t) TESTS="true" ;;
    esac
done

#==============================================================================
gettingStarted() {
    cat <<-eof
    ***********************************************************************
    Usage:
    ***********************************************************************
      PHP installed successfully.
      Set the environment variables:
      export PATH=$PREFIX/bin:\$PATH
eof

    case "$DISTRO" in
    "sles-15.6")
        cat <<-eof
	  export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig:$PREFIX/lib64/pkgconfig:\$PKG_CONFIG_PATH
	  export LD_LIBRARY_PATH=$PREFIX/lib:$PREFIX/lib64:\$LD_LIBRARY_PATH
	  export LD_RUN_PATH=$PREFIX/lib:\$LD_RUN_PATH
eof
        ;;
    esac

    cat <<-eof
      Run the following commands to check PHP version:
      $PREFIX/bin/php -v
      More information can be found here:
      https://www.php.net/
eof
}

#==============================================================================
logDetails
checkPrequisites

msglog "Installing $PACKAGE_NAME $PACKAGE_VERSION for $DISTRO"
msglog "Installing the dependencies for $PACKAGE_NAME"

case "$DISTRO" in
#----------------------------------------------------------
#----------------------------------------------------------
"rhel-8.10")

    sudo yum install -y \
        autoconf curl libtool openssl-devel \
        libcurl libcurl-devel libxml2 libxml2-devel readline \
        readline-devel libzip-devel libzip nginx openssl \
        pkgconf zlib-devel sqlite-libs sqlite-devel \
        oniguruma oniguruma-devel libpq-devel git curl \
        tar make binutils gcc-toolset-13-gcc \
        gcc-toolset-13-gcc-c++ bzip2 \
        binutils wget glibc-langpack-en |& tee -a "$LOG_FILE"
    #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    source /opt/rh/gcc-toolset-13/enable
    PATH=$PREFIX/bin${PATH:+:$PATH}
    export PATH
    export LANG=en_US.UTF-8
    #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

    #----------------------------------------------------------
"rhel-9.4" | "rhel-9.6" | "rhel-10.0")

    sudo yum install -y \
        autoconf libtool openssl-devel \
        libcurl-devel libxml2 libxml2-devel readline \
        readline-devel libzip-devel libzip nginx openssl \
        pkgconf zlib-devel sqlite-libs sqlite-devel \
        oniguruma oniguruma-devel libpq-devel git \
        tar make binutils bzip2 gcc gcc-c++ \
        binutils wget glibc-gconv-extra |& tee -a "$LOG_FILE"
    if [[ "$DISTRO" == "rhel-10.*" ]]; then
            sudo yum swap libcurl-minimal libcurl --allowerasing
        fi
    #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    PATH=$PREFIX/bin${PATH:+:$PATH}
    export PATH
    export LANG=en_US.UTF-8
    #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
    #----------------------------------------------------------
"sles-15.6")

    sudo zypper install -y \
        autoconf curl libtool openssl-devel libxml2 \
        libxml2-devel readline readline-devel \
        libcurl4 libcurl-devel libreadline7 openssl \
        libzip-devel pkg-config oniguruma-devel git \
        tar sqlite3-devel zlib-devel gcc13 gcc13-c++ \
        libzip5 postgresql16 nginx postgresql16-server-devel bzip2 \
        make gzip gawk gmp-devel mpfr-devel mpc-devel wget |& tee -a "$LOG_FILE"

    #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    export CC=/usr/bin/gcc-13
    export CXX=/usr/bin/g++-13
    PATH=$PREFIX/bin${PATH:+:$PATH}
    export PATH
    [ -f /usr/bin/pg_config ] || sudo ln -s /usr/lib/postgresql12/bin/pg_config /usr/bin/pg_config

    PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig:$PREFIX/lib64/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}
    export PKG_CONFIG_PATH
    LD_LIBRARY_PATH=$PREFIX/lib:$PREFIX/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    export LD_LIBRARY_PATH
    LD_RUN_PATH=$PREFIX/lib:$PREFIX/lib64${LD_RUN_PATH:+:$LD_RUN_PATH}
    export LD_RUN_PATH
    #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"ubuntu-22.04" | "ubuntu-24.04" | "ubuntu-25.04")

    sudo apt-get update >/dev/null
    sudo apt-get install -y locales language-pack-de \
        autoconf build-essential curl libtool \
        libssl-dev libcurl4-openssl-dev libxml2-dev \
        libreadline8 libreadline-dev libzip-dev \
        nginx openssl pkg-config zlib1g-dev \
        libsqlite3-dev libonig-dev libpq-dev \
        gcc g++ git curl tar gcc make bzip2 wget \
        |& tee -a "$LOG_FILE"

    PATH=$PREFIX/bin${PATH:+:$PATH}
    export PATH
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
#----------------------------------------------------------
*)
    errlog "$DISTRO not supported"
    ;;
esac
gettingStarted |& tee -a "$LOG_FILE"
