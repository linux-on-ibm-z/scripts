#!/bin/bash
# ©  Copyright IBM Corporation 2022.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/PHP/8.1.6/build_php.sh
# Execute build script: bash build_php.sh    (provide -h for help)
#

#==============================================================================
set -e -o pipefail

PACKAGE_NAME="PHP"
PACKAGE_VERSION="8.1.6"
SOURCE_ROOT="$(pwd)"

FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

PHP_URL="https://www.php.net/distributions"
PHP_URL+="/php-${PACKAGE_VERSION}.tar.gz"

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
    cd php-${ver}

    ./configure --prefix=${PREFIX} \
        --without-pcre-jit --without-pear \
        --enable-mysqlnd --with-pdo-mysql --with-pdo-pgsql=/usr/bin/pg_config \
        --enable-bcmath --enable-fpm --enable-mbstring --enable-phpdbg --enable-shmop \
        --enable-sockets --enable-sysvmsg --enable-sysvsem --enable-sysvshm \
        --with-zlib --with-curl --with-openssl --enable-pcntl --with-readline

    make -j 8
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
        cd "$SOURCE_ROOT/php-${ver}"

        rm ./ext/opcache/tests/log_verbosity_bug.phpt
        sed -i 's/run-tests.php -n -c/run-tests.php -q -n -c/' Makefile
        make test

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
	  export PATH=${PREFIX}/bin:\${PATH}
eof

    case "$DISTRO" in
    "rhel-7.8" | "rhel-7.9" | "sles-12.5")
        cat <<-eof
	  export PKG_CONFIG_PATH=${PREFIX}/lib/pkgconfig:${PREFIX}/lib64/pkgconfig:\${PKG_CONFIG_PATH}
	  export LD_LIBRARY_PATH=${PREFIX}/lib:${PREFIX}/lib64:\${LD_LIBRARY_PATH}
	  export LD_RUN_PATH=${PREFIX}/lib:\${LD_RUN_PATH}
	  export SSL_CERT_FILE=/usr/local/etc/openssl/cacert.pem
eof
        ;;

    "sles-15.3")
        cat <<-eof
	  export PKG_CONFIG_PATH=${PREFIX}/lib/pkgconfig:${PREFIX}/lib64/pkgconfig:\${PKG_CONFIG_PATH}
	  export LD_LIBRARY_PATH=${PREFIX}/lib:${PREFIX}/lib64:\${LD_LIBRARY_PATH}
	  export LD_RUN_PATH=${PREFIX}/lib:\${LD_RUN_PATH}
eof
        ;;
    esac

    cat <<-eof
	  Run the following commands to check PHP version:
	  ${PREFIX}/bin/php -v
	  More information can be found here:
	  https://www.php.net/
eof
}

#==============================================================================
buildOniguruma() {
    local ver=v6.9.5
    msg "Building oniguruma $ver"

    cd "$SOURCE_ROOT"
    git clone https://github.com/kkos/oniguruma
    cd oniguruma
    git checkout ${ver}
    autoreconf -vfi
    ./configure --prefix=${PREFIX}
    make
    sudo make install
}

#==============================================================================
buildOpenssl() {
    local ver=1.1.1g
    msg "Building openssl $ver"

    cd $SOURCE_ROOT
    wget https://www.openssl.org/source/old/1.1.1/openssl-${ver}.tar.gz --no-check-certificate
    tar xvf openssl-${ver}.tar.gz
    cd openssl-${ver}
    ./config --prefix=${PREFIX}
    make
    sudo make install

    sudo mkdir -p /usr/local/etc/openssl
    cd /usr/local/etc/openssl
    sudo wget https://curl.se/ca/cacert.pem --no-check-certificate
}

#==============================================================================
buildSqlite3() {
    local ver=version-3.35.0
    msg "Building Sqlite $ver"

    cd "$SOURCE_ROOT"
    git clone https://github.com/sqlite/sqlite.git
    cd sqlite
    git checkout ${ver}
    CFLAGS="-DSQLITE_ENABLE_COLUMN_METADATA=1" ./configure --prefix=${PREFIX}
    make
    sudo make install
}

buildReadline8() {
    local ver=8.1
    msg "Building Readline $ver"

    cd "$SOURCE_ROOT"
    curl ftp://ftp.cwru.edu/pub/bash/readline-${ver}.tar.gz -o readline-${ver}.tar.gz
    tar xvf readline-${ver}.tar.gz
    cd readline-${ver}
    ./configure --prefix=${PREFIX}
    make
    sudo make install
}

buildcurl760() {
    local ver=7.60.0
    msg "Building curl $ver"

    cd "$SOURCE_ROOT"
    wget https://github.com/curl/curl/releases/download/curl-7_60_0/curl-${ver}.tar.gz
    tar xvf curl-${ver}.tar.gz
    cd curl-${ver}
    ./configure --prefix=${PREFIX}
    make
    sudo make install
}

#==============================================================================
buildGCC() {
    local ver=10.3.0
    local url
    msg "Building gcc $ver"

    cd "$SOURCE_ROOT"
    url=http://ftp.mirrorservice.org/sites/sourceware.org/pub/gcc/releases/gcc-${ver}/gcc-${ver}.tar.gz
    curl -sSL $url | tar xzf - || error "gcc $ver"

    cd gcc-${ver}
    ./contrib/download_prerequisites
    mkdir build-gcc
    cd build-gcc
    ../configure --enable-languages=c,c++ --disable-multilib
    make -j$(nproc)
    sudo make install
}

installWget() {
    cd $HOME
    wget https://ftp.gnu.org/gnu/wget/wget-1.20.3.tar.gz
    tar -xzf  wget-1.20.3.tar.gz
    cd wget-1.20.3
    ./configure
    make
    sudo make install
}

#==============================================================================
logDetails
checkPrequisites

msglog "Installing $PACKAGE_NAME $PACKAGE_VERSION for $DISTRO"
msglog "Installing the dependencies for $PACKAGE_NAME"

case "$DISTRO" in

#----------------------------------------------------------
"ubuntu-18.04")

    sudo apt-get update >/dev/null

    sudo apt-get install -y software-properties-common
    sudo add-apt-repository -y ppa:ubuntu-toolchain-r/test
    sudo apt-get update >/dev/null

    sudo apt-get install -y locales language-pack-de \
        autoconf build-essential curl libtool \
        libssl-dev libcurl4-openssl-dev libxml2-dev \
        libreadline7 libreadline-dev libzip-dev libzip4 \
        nginx openssl pkg-config zlib1g-dev libsqlite3-dev \
        libonig-dev libpq-dev git gcc g++ curl tar bzip2 \
        make wget libgnutls28-dev |& tee -a "$LOG_FILE"

    #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    buildGCC |& tee -a "$LOG_FILE"
    sudo update-alternatives --install /usr/bin/cc cc /usr/local/bin/gcc 40

    PATH=${PREFIX}/bin${PATH:+:${PATH}}
    export PATH
    installWget
    PATH=/usr/local/bin:$PATH
    export PATH

    #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

    #----------------------------------------------------------
"ubuntu-20.04" | "ubuntu-21.10" | "ubuntu-22.04")

    sudo apt-get update >/dev/null

    sudo apt-get install -y locales language-pack-de \
        autoconf build-essential curl libtool \
        libssl-dev libcurl4-openssl-dev libxml2-dev \
        libreadline8 libreadline-dev libzip-dev \
        nginx openssl pkg-config zlib1g-dev \
        libsqlite3-dev libonig-dev libpq-dev \
        gcc-10 g++-10 git curl tar gcc make bzip2 wget \
        |& tee -a "$LOG_FILE"

    #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    if [ "$DISTRO"x = "ubuntu-20.04"x ]; then
        buildGCC |& tee -a "$LOG_FILE"
        sudo update-alternatives --install /usr/bin/cc cc /usr/local/bin/gcc 40
    fi

    PATH=${PREFIX}/bin${PATH:+:${PATH}}
    export PATH

    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

    #----------------------------------------------------------
"rhel-7.8" | "rhel-7.9")

    #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    sudo yum install -y \
        autoconf curl libcurl libcurl-devel \
        libtool wget libxml2 libxml2-devel ncurses \
        ncurses-devel libzip-devel libzip zlib-devel \
        bzip2 git tar gcc gcc-c++ postgresql \
        postgresql-devel pkgconfig make tcl |& tee -a "$LOG_FILE"

    #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    buildGCC |& tee -a "$LOG_FILE"
    sudo update-alternatives --install /usr/bin/cc cc /usr/local/bin/gcc 40

    PATH=${PREFIX}/bin${PATH:+:${PATH}}
    export PATH

    PKG_CONFIG_PATH=${PREFIX}/lib/pkgconfig:${PREFIX}/lib64/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}
    export PKG_CONFIG_PATH

    LD_LIBRARY_PATH=${PREFIX}/lib:${PREFIX}/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
    export LD_LIBRARY_PATH

    LD_RUN_PATH=${PREFIX}/lib:${PREFIX}/lib64${LD_RUN_PATH:+:${LD_RUN_PATH}}
    export LD_RUN_PATH

    buildOniguruma |& tee -a "$LOG_FILE"
    buildReadline8 |& tee -a "$LOG_FILE"
    buildOpenssl |& tee -a "$LOG_FILE"
    buildSqlite3 |& tee -a "$LOG_FILE"

    export SSL_CERT_FILE=/usr/local/etc/openssl/cacert.pem

    #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

    #----------------------------------------------------------
"rhel-8.4"| "rhel-8.5" | "rhel-8.6")

    sudo yum install -y \
        autoconf curl libtool openssl-devel \
        libcurl libcurl-devel libxml2 libxml2-devel readline \
        readline-devel libzip-devel libzip nginx openssl \
        pkgconf zlib-devel sqlite-libs sqlite-devel \
        oniguruma oniguruma-devel libpq-devel git curl \
        tar make binutils gcc-toolset-10-gcc \
        gcc-toolset-10-gcc-c++ bzip2 \
        binutils wget |& tee -a "$LOG_FILE"

    #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    source /opt/rh/gcc-toolset-10/enable

    PATH=${PREFIX}/bin${PATH:+:${PATH}}
    export PATH

    #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

    #----------------------------------------------------------
"sles-12.5")

    sudo zypper install -y \
        autoconf curl libtool libxml2 \
        libxml2-devel readline readline-devel libcurl4 \
        libcurl-devel libreadline6 nginx \
        libzip-devel libzip2 pkg-config oniguruma-devel git \
        tar postgresql10-devel postgresql10 \
        sqlite3-devel zlib-devel gcc gcc-c++ bzip2 \
        make gmp-devel mpfr-devel mpc-devel wget |& tee -a "$LOG_FILE"

    #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    buildGCC |& tee -a "$LOG_FILE"
    sudo update-alternatives --install /usr/bin/cc cc /usr/local/bin/gcc 40

    buildcurl760 |& tee -a "$LOG_FILE"
    buildOpenssl |& tee -a "$LOG_FILE"

    PATH=${PREFIX}/bin${PATH:+:${PATH}}
    export PATH

    PKG_CONFIG_PATH=${PREFIX}/lib/pkgconfig:${PREFIX}/lib64/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}
    export PKG_CONFIG_PATH

    LD_LIBRARY_PATH=${PREFIX}/lib:${PREFIX}/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
    export LD_LIBRARY_PATH

    LD_RUN_PATH=${PREFIX}/lib:${PREFIX}/lib64${LD_RUN_PATH:+:${LD_RUN_PATH}}
    export LD_RUN_PATH

    export SSL_CERT_FILE=/usr/local/etc/openssl/cacert.pem
    #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

    #----------------------------------------------------------
"sles-15.3")

    sudo zypper install -y \
        autoconf curl libtool openssl-devel libxml2 \
        libxml2-devel readline readline-devel \
        libcurl4 libcurl-devel libreadline7 openssl \
        libzip-devel pkg-config oniguruma-devel git \
        tar sqlite3-devel zlib-devel gcc gcc-c++ \
        libzip5 postgresql12 nginx postgresql12-server-devel bzip2 \
        make gzip gawk gmp-devel mpfr-devel mpc-devel wget |& tee -a "$LOG_FILE"

    #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    buildGCC |& tee -a "$LOG_FILE"
    sudo update-alternatives --install /usr/bin/cc cc /usr/local/bin/gcc 40

    buildcurl760 |& tee -a "$LOG_FILE"

    PATH=${PREFIX}/bin${PATH:+:${PATH}}
    export PATH
    [ -f /usr/bin/pg_config ] || sudo ln -s /usr/lib/postgresql12/bin/pg_config /usr/bin/pg_config

    PKG_CONFIG_PATH=${PREFIX}/lib/pkgconfig:${PREFIX}/lib64/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}
    export PKG_CONFIG_PATH

    LD_LIBRARY_PATH=${PREFIX}/lib:${PREFIX}/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
    export LD_LIBRARY_PATH

    LD_RUN_PATH=${PREFIX}/lib:${PREFIX}/lib64${LD_RUN_PATH:+:${LD_RUN_PATH}}
    export LD_RUN_PATH

    #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

#----------------------------------------------------------
*)
    errlog "$DISTRO not supported"
    ;;

esac

gettingStarted |& tee -a "$LOG_FILE"
