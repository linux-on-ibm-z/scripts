#!/bin/bash
# ©  Copyright IBM Corporation 2020, 2021.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/PHP/7.4.11/build_php.sh
# Execute build script: bash build_php.sh    (provide -h for help)
#


#==============================================================================
set -e -o pipefail

PACKAGE_NAME="PHP"
PACKAGE_VERSION="7.4.11"
SOURCE_ROOT="$(pwd)"

FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

PHP_URL="https://www.php.net/distributions"
PHP_URL+="/php-${PACKAGE_VERSION}.tar.gz"

PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/"
PATCH_URL+="${PACKAGE_NAME}/${PACKAGE_VERSION}/patch"


PREFIX=/usr/local
CMAKE=$PREFIX/bin/cmake

IDIR=/usr
ZLIB_DIR=${IDIR}
TIDY_DIR=${IDIR}
PSPELL_DIR=${IDIR}
ENCHANT_DIR=${IDIR}

#==============================================================================
mkdir -p "$SOURCE_ROOT/logs"

error() { echo "Error: ${*}"; exit 1; }
errlog() { echo "Error: ${*}" |& tee -a "$LOG_FILE"; exit 1; }

msg() { echo "${*}"; }
log() { echo "${*}" >> "$LOG_FILE"; }
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
checkPrequisites()
{
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
cleanup()
{
  echo "Cleaned up the artifacts."
}


#==============================================================================
# Build and install pkgs common to all distros.
#
configureAndInstall()
{
  local ver=$PACKAGE_VERSION
  local url=${PATCH_URL}
  msg "Configuration and Installation started"
  msg "Building PHP $ver"

#----------------------------------------------------------
  cd "$SOURCE_ROOT"

  curl -sSL $PHP_URL | tar xzf - || error "PHP $ver"
  cd php-${ver}

  # backport NAN and infinity handling
  curl -sSL ${PATCH_URL}/nan.diff | patch -p1 || error "${PATCH_URL}/nan.diff"
  curl -sSL ${PATCH_URL}/infinity.diff | patch -p1 || error "${PATCH_URL}/infinity.diff"

  # fix reflection
  curl -sSL ${PATCH_URL}/reflection.diff | patch -p1 || error "${PATCH_URL}/reflection.diff"

  icupkg -tb ext/intl/tests/_files/resourcebundle/root.res
  icupkg -tb ext/intl/tests/_files/resourcebundle/es.res
  icupkg -tb ext/intl/tests/_files/resourcebundle/res_index.res

  ./configure --prefix=${PREFIX} \
    --without-pcre-jit --without-pear \
    --with-pdo-mysql=mysqlnd --with-mysqli=mysqlnd \
    --with-pgsql --with-pdo-pgsql --with-pdo-sqlite \
    --with-readline --with-gettext \
    --enable-gd --with-jpeg --with-freetype --with-xpm \
    --with-kerberos --with-openssl \
    --with-xsl --with-xmlrpc --with-bz2 --with-gmp --with-zip \
    --with-mhash --disable-inline-optimization \
    --enable-intl --enable-fpm --enable-exif \
    --enable-xmlreader --enable-sockets \
    --enable-sysvsem --enable-sysvshm --enable-sysvmsg --enable-shmop \
    --enable-pcntl --enable-mbstring --enable-soap \
    --enable-bcmath --enable-calendar --enable-ftp \
    --enable-zend-test=shared \
    --with-curl=${IDIR} \
    --with-zlib --with-zlib-dir=${ZLIB_DIR} \
    --with-tidy=${TIDY_DIR} \
    --with-pspell=${PSPELL_DIR} \
    --with-enchant=${ENCHANT_DIR}

  make -j 8
  sudo make install

  if [ "$?" -ne "0" ]; then
    error "Build for $PACKAGE_NAME failed. Please check the error logs."
  else
    msg "Build for $PACKAGE_NAME completed successfully. "
  fi

  sudo install -m644 php.ini-production ${PREFIX}/lib/php.ini
  sudo sed -i "s@php/includes\"@&\ninclude_path = \".:$PREFIX/lib/php\"@" ${PREFIX}/lib/php.ini

  sudo sed -i "s/;mysqli.allow_local_infile = On/mysqli.allow_local_infile = On/" ${PREFIX}/lib/php.ini

  sudo sed -i "s/;opcache.enable=1/opcache.enable=1/" ${PREFIX}/lib/php.ini
  sudo sed -i "s/;opcache.enable_cli=0/opcache.enable_cli=1/" ${PREFIX}/lib/php.ini

  patchTest
  runTest
}



#==============================================================================
patchTest()
{
  local ver=$PACKAGE_VERSION
  local url=""

  msg "Patch PHP $ver test"

  cd "$SOURCE_ROOT/php-${ver}"

  case "$DISTRO" in
    "rhel-7.9" | "rhel-7.7" | "rhel-7.8") url=${PATCH_URL}/rhel7-test.diff ;;
    "rhel-8.1" | "rhel-8.2") url=${PATCH_URL}/rhel8-test.diff ;;
    "sles-12.5" | "sles-15.1" | "sles-15.2") url=${PATCH_URL}/sles-test.diff ;;
  esac

  if [[ -n "${url}" ]]; then
    curl -sSL ${url} | patch -p1 || error "${url}"
  fi
}


#==============================================================================
# Start MySql and Postgres servers before testing modules pdo_mysql,ext/mysqli
# and ext/pdo_pgsql. Ensure a test DB exists and required env variables are set.
runTest()
{
  local ver=$PACKAGE_VERSION
  set +e
  if [[ "$TESTS" == "true" ]]; then
    log "TEST Flag is set, continue with running test "
    cd "$SOURCE_ROOT/php-${ver}"

    rm ./ext/opcache/tests/log_verbosity_bug.phpt

    TERM=vt100 ./sapi/cli/php run-tests.php -P -q \
      -d zend_extension=$SOURCE_ROOT/php-${ver}/modules/opcache.so \
      -d extension=$SOURCE_ROOT/php-${ver}/modules/zend_test.so \
      -g "FAIL,XFAIL,BORK,WARN,LEAK,SKIP" --offline

    msg "Test execution completed. "
  fi
  set -e
}


#==============================================================================
logDetails()
{
  log "**************************** SYSTEM DETAILS ***************************"
  cat "/etc/os-release" >>"$LOG_FILE"
  cat /proc/version >>"$LOG_FILE"
  log "***********************************************************************"

  msg "Detected $PRETTY_NAME"
  msglog "Request details: PACKAGE NAME=$PACKAGE_NAME, VERSION=$PACKAGE_VERSION"
}


#==============================================================================
printHelp()
{
  cat <<eof

  Usage:
  build_php.sh [-y] [-d] [-t]
  where:
   -y install-without-confirmation
   -d debug
   -t test
eof
}

###############################################################################
while getopts "h?dyt?" opt
do
  case "$opt" in
    h | \?) printHelp; exit 0; ;;
    d) set -x; ;;
    y) FORCE="true"; ;;
    t) TESTS="true"; ;;
  esac
done


#==============================================================================
gettingStarted()
{
  cat <<-eof
	***********************************************************************
	Usage:
	***********************************************************************
	  PHP installed successfully.
	  Set the environment variables:

	  export PATH=${PREFIX}/bin\${PATH:+:\${PATH}}
	  LD_LIBRARY_PATH=${PREFIX}/lib64\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}
	  LD_LIBRARY_PATH+=:${PREFIX}/lib
	  LD_LIBRARY_PATH+=:/usr/lib64
	  export LD_LIBRARY_PATH

	  Run the following commands to use ScyllaDB:
	  ${PREFIX}/bin/php -v

	  More information can be found here:
	  https://www.php.net/
eof
}



#==============================================================================
buildCmake()
{
  local ver=3.12.4
  local url
  msg "Building cmake $ver"

  cd "$SOURCE_ROOT"
  url=https://github.com/Kitware/CMake/releases/download/v${ver}/cmake-${ver}.tar.gz
  curl -sSL $url | tar xzf - || error "cmake $ver"
  cd cmake-${ver}
  ./bootstrap
  make
  sudo make install
}


#==============================================================================
buildBison()
{
  local ver=3.6
  local url
  msg "Building bison $ver"

  cd "$SOURCE_ROOT"
  url=https://ftp.gnu.org/gnu/bison/bison-${ver}.tar.gz
  curl -sSL $url | tar xzf - || error "bison $ver"
  cd bison-${ver}
  ./configure --prefix=${PREFIX}
  make
  sudo make install
}


#==============================================================================
buildZip()
{
  local ver=rel-1-4-0
  msg "Building libzip $ver"

  cd "$SOURCE_ROOT"
  git clone https://github.com/nih-at/libzip
  cd libzip
  git checkout ${ver}
  mkdir build && cd build
  $CMAKE .. -DCMAKE_INSTALL_PREFIX=${PREFIX}
  make
  sudo make install
}


#==============================================================================
buildTidy()
{
  local ver=5.6.0
  msg "Building tidy-html $ver"

  cd "$SOURCE_ROOT"
  git clone https://github.com/htacg/tidy-html5.git
  cd tidy-html5/
  git checkout ${ver}
  cd build/cmake
  $CMAKE ../.. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=${PREFIX}
  make
  sudo make install
}


#==============================================================================
buildOniguruma()
{
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
buildEnchant()
{
  local ver=1-5-0
  local url
  msg "Building enchant $ver"

  cd "$SOURCE_ROOT"
  url=https://github.com/AbiWord/enchant/archive/enchant-${ver}.tar.gz
  curl -sSL $url | tar xzf - || error "enchant $ver"

  cd enchant-enchant-${ver}
  ./autogen.sh
  make
  sudo make install
}


#==============================================================================
buildOpenssl()
{
  local ver=${1}
  msg "Building openssl $ver"

  cd "$SOURCE_ROOT"
  git clone git://github.com/openssl/openssl.git
  cd openssl
  git checkout OpenSSL_${ver}
  ./config --prefix=$PREFIX shared
  make
  sudo make install
}


#==============================================================================
buildIcu()
{
  local ver=55-1
  local url
  msg "Building icu $ver"

  cd "$SOURCE_ROOT"
  url=https://github.com/unicode-org/icu/archive/release-${ver}.tar.gz
  curl -sSL $url | tar xzf - || error "icu $ver"
  cd icu-release-${ver}/icu4c/source

  ./configure --prefix=${PREFIX}
  CFLAGS=-D__USE_XOPEN2K8 CXXFLAGS=-D__USE_XOPEN2K8 make
  sudo make install
}




#==============================================================================
buildAspell()
{
  local ver=0.60.7
  local url
  msg "Building aspell $ver"

  cd "$SOURCE_ROOT"
  url=https://ftp.gnu.org/gnu/aspell/aspell-${ver}.tar.gz
  curl -sSL $url | tar xzf - || error "aspell $ver"
  cd aspell-${ver}
  ./configure --prefix=${PREFIX}
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

  sudo apt-get update |& tee -a "$LOG_FILE"

  sudo apt-get install -y locales language-pack-de \
    libaspell-dev libbz2-dev libcurl4-gnutls-dev libenchant-dev \
    libfreetype6-dev libgmp-dev libicu-dev libjpeg-dev \
    libkrb5-dev libonig-dev libpng-dev libpq-dev \
    libpspell-dev libsasl2-dev libsqlite3-dev \
    libsodium-dev libtidy-dev libxml2-dev \
    libxpm-dev libxslt1-dev libzip-dev \
    librecode-dev libreadline-dev libssl-dev \
    libpq-dev libmysqlclient-dev libgdbm-dev \
    autoconf automake make patch curl git pkg-config libtool gcc g++ \
    openssl re2c |& tee -a "$LOG_FILE"

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  buildBison |& tee -a "$LOG_FILE"

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  export PATH=${PREFIX}/bin${PATH:+:${PATH}}
  configureAndInstall |& tee -a "$LOG_FILE"
;;


#----------------------------------------------------------
"ubuntu-20.04" | "ubuntu-20.10")

  sudo apt-get update |& tee -a "$LOG_FILE"

  sudo apt-get install -y locales language-pack-de \
    libaspell-dev libbz2-dev libcurl4-gnutls-dev libenchant-dev \
    libfreetype6-dev libgmp-dev libicu-dev libjpeg-dev \
    libkrb5-dev libonig-dev libpng-dev libpq-dev \
    libpspell-dev libsasl2-dev libsqlite3-dev \
    libsodium-dev libtidy-dev libxml2-dev \
    libxpm-dev libxslt1-dev libzip-dev \
    librecode-dev libreadline-dev \
    libpq-dev libmysqlclient-dev libgdbm-dev \
    autoconf automake make patch curl git pkg-config libtool gcc g++ \
    re2c |& tee -a "$LOG_FILE"

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  buildOpenssl 1_1_1c |& tee -a "$LOG_FILE"
  buildBison |& tee -a "$LOG_FILE"


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  export PATH=${PREFIX}/bin${PATH:+:${PATH}}

  PKG_CONFIG_PATH=${PREFIX}/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}
  PKG_CONFIG_PATH+=:${PREFIX}/lib64/pkgconfig
  export PKG_CONFIG_PATH

  LD_LIBRARY_PATH=${PREFIX}/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
  LD_LIBRARY_PATH+=:${PREFIX}/lib
  LD_LIBRARY_PATH+=:/usr/lib64
  export LD_LIBRARY_PATH


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  configureAndInstall |& tee -a "$LOG_FILE"
;;


#----------------------------------------------------------
"rhel-7.7" | "rhel-7.8" | "rhel-7.9")

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
if [[ "$DISTRO" == "rhel-7.8" ]]; then
  set +e
  sudo yum list installed glibc-2.17-307.el7.1.s390 |& tee -a "$LOG_FILE"
  if [[ $? ]]; then
    sudo yum downgrade -y glibc glibc-common |& tee -a "$LOG_FILE"
    sudo yum downgrade -y krb5-libs |& tee -a "$LOG_FILE"
    sudo yum downgrade -y libss e2fsprogs-libs e2fsprogs libcom_err |& tee -a "$LOG_FILE"
    sudo yum downgrade -y libselinux-utils libselinux-python libselinux |& tee -a "$LOG_FILE"
    fi
  set -e
fi

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  sudo yum install -y \
    bzip2-devel curl-devel enchant-devel \
    freetype-devel gmp-devel libjpeg-devel \
    krb5-devel libpng-devel postgresql-devel mysql-devel \
    aspell-devel cyrus-sasl-devel sqlite-devel \
    libxml2-devel libXpm-devel libxslt-devel \
    recode-devel readline-devel openssl-devel \
    gdbm-devel libdb-devel \
    openldap-devel pcre-devel net-snmp-devel \
    autoconf automake make patch curl git pkgconfig libtool gcc gcc-c++ \
    bison openssl aspell |& tee -a "$LOG_FILE"

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  buildCmake |& tee -a "$LOG_FILE"

  PATH=${PREFIX}/bin${PATH:+:${PATH}}
  PATH+=:${PREFIX}/sbin${PATH:+:${PATH}}
  export PATH
  
  PKG_CONFIG_PATH=${PREFIX}/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}
  PKG_CONFIG_PATH+=:${PREFIX}/lib64/pkgconfig
  export PKG_CONFIG_PATH

  LD_LIBRARY_PATH=${PREFIX}/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
  LD_LIBRARY_PATH+=:${PREFIX}/lib
  LD_LIBRARY_PATH+=:/usr/lib64
  export LD_LIBRARY_PATH

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  buildZip |& tee -a "$LOG_FILE"
  ZLIB_DIR=${PREFIX}

  buildTidy |& tee -a "$LOG_FILE"
  TIDY_DIR=${PREFIX}

  buildOniguruma |& tee -a "$LOG_FILE"
  buildIcu |& tee -a "$LOG_FILE"

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  echo 128128 | sudo tee /proc/sys/user/max_user_namespaces

  configureAndInstall |& tee -a "$LOG_FILE"
;;


#----------------------------------------------------------
"rhel-8.1" | "rhel-8.2")

  sudo yum install -y \
    bzip2-devel curl-devel \
    freetype-devel gmp-devel libicu-devel libjpeg-devel \
    krb5-devel libpng-devel postgresql-devel mysql-devel \
    aspell-devel cyrus-sasl-devel sqlite-devel \
    libxml2-devel libXpm-devel libxslt-devel \
    recode-devel readline-devel \
    gdbm-devel libdb-devel glib2-devel glib2 \
    openldap-devel pcre-devel net-snmp-devel \
    autoconf automake make cmake patch curl git pkgconfig libtool gcc gcc-c++ \
    bison icu aspell |& tee -a "$LOG_FILE"

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  CMAKE=cmake

  export PATH=${PREFIX}/bin${PATH:+:${PATH}}

  PKG_CONFIG_PATH=${PREFIX}/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}
  PKG_CONFIG_PATH+=:${PREFIX}/lib64/pkgconfig
  export PKG_CONFIG_PATH

  LD_LIBRARY_PATH=${PREFIX}/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
  LD_LIBRARY_PATH+=:${PREFIX}/lib
  LD_LIBRARY_PATH+=:/usr/lib64
  export LD_LIBRARY_PATH

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  buildOpenssl 1_0_2l |& tee -a "$LOG_FILE"

  buildZip |& tee -a "$LOG_FILE"
  ZLIB_DIR=${PREFIX}

  buildTidy |& tee -a "$LOG_FILE"
  TIDY_DIR=${PREFIX}

  buildOniguruma |& tee -a "$LOG_FILE"

  buildEnchant |& tee -a "$LOG_FILE"
  ENCHANT_DIR=${PREFIX}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  configureAndInstall |& tee -a "$LOG_FILE"
;;


#----------------------------------------------------------
"sles-12.5")

  sudo zypper install -y \
    libcurl-devel enchant-devel \
    freetype2-devel gmp-devel libjpeg62-devel \
    libpng16-compat-devel libpng16-devel \
    libpq5 postgresql10-devel libmysqlclient-devel sqlite3-devel \
    cyrus-sasl-devel \
    libxml2-devel libXpm-devel libxslt-devel \
    readline-devel libopenssl-devel \
    gdbm-devel libdb-4_8-devel \
    openldap2-devel pcre-devel net-snmp-devel \
    autoconf automake make patch curl git pkg-config libtool gcc gcc-c++ \
    tar gzip gawk glibc-locale bzip2 bison \
    krb5-devel aspell-devel aspell |& tee -a "$LOG_FILE"

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  buildCmake |& tee -a "$LOG_FILE"

  PATH=${PREFIX}/bin${PATH:+:${PATH}}
  PATH+=:${PREFIX}/sbin
  export PATH

  PKG_CONFIG_PATH=${PREFIX}/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}
  PKG_CONFIG_PATH+=:${PREFIX}/lib64/pkgconfig
  export PKG_CONFIG_PATH

  LD_LIBRARY_PATH=${PREFIX}/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
  LD_LIBRARY_PATH+=:${PREFIX}/lib
  LD_LIBRARY_PATH+=:/usr/lib64
  export LD_LIBRARY_PATH

  LD_RUN_PATH=${PREFIX}/lib64${LD_RUN_PATH:+:${LD_RUN_PATH}}
  LD_RUN_PATH+=:${PREFIX}/lib
  export LD_RUN_PATH

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  buildZip |& tee -a "$LOG_FILE"
  ZLIB_DIR=${PREFIX}

  buildTidy |& tee -a "$LOG_FILE"
  TIDY_DIR=${PREFIX}

  buildOniguruma |& tee -a "$LOG_FILE"

  buildIcu |& tee -a "$LOG_FILE"

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  echo 128128 | sudo tee /proc/sys/user/max_user_namespaces

  configureAndInstall |& tee -a "$LOG_FILE"
;;


#----------------------------------------------------------
"sles-15.1")

  sudo zypper install -y \
    libcurl-devel enchant-devel \
    freetype2-devel gmp-devel libjpeg62-devel \
    libpng16-compat-devel libpng16-devel \
    libpq5 postgresql10-devel libmysqlclient-devel sqlite3-devel \
    cyrus-sasl-devel \
    libxml2-devel libXpm-devel libxslt-devel \
    readline-devel libopenssl-devel \
    gdbm-devel libdb-4_8-devel \
    openldap2-devel pcre-devel net-snmp-devel \
    autoconf automake make patch curl git pkg-config libtool gcc gcc-c++ \
    tar gzip gawk glibc-locale bzip2 bison \
    libicu-devel krb5-devel |& tee -a "$LOG_FILE"

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  buildCmake |& tee -a "$LOG_FILE"

  PATH=${PREFIX}/bin${PATH:+:${PATH}}
  PATH+=:${PREFIX}/sbin
  export PATH

  PKG_CONFIG_PATH=${PREFIX}/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}
  PKG_CONFIG_PATH+=:${PREFIX}/lib64/pkgconfig
  export PKG_CONFIG_PATH

  LD_RUN_PATH=${PREFIX}/lib64${LD_RUN_PATH:+:${LD_RUN_PATH}}
  LD_RUN_PATH+=:${PREFIX}/lib
  export LD_RUN_PATH

  LD_LIBRARY_PATH=${PREFIX}/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
  LD_LIBRARY_PATH+=:${PREFIX}/lib
  LD_LIBRARY_PATH+=:/usr/lib64
  export LD_LIBRARY_PATH

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  buildZip |& tee -a "$LOG_FILE"
  ZLIB_DIR=${PREFIX}

  buildTidy |& tee -a "$LOG_FILE"
  TIDY_DIR=${PREFIX}

  buildOniguruma |& tee -a "$LOG_FILE"

  buildAspell |& tee -a "$LOG_FILE"
  PSPELL_DIR=${PREFIX}

  buildIcu |& tee -a "$LOG_FILE"

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  echo 128128 | sudo tee /proc/sys/user/max_user_namespaces

  configureAndInstall |& tee -a "$LOG_FILE"
;;

#----------------------------------------------------------
"sles-15.2")

  sudo zypper install -y \
    libcurl-devel enchant-devel \
    freetype2-devel gmp-devel libjpeg62-devel \
    libpng16-compat-devel libpng16-devel \
    libpq5 postgresql10-devel libmysqlclient-devel sqlite3-devel \
    cyrus-sasl-devel \
    libxml2-devel libXpm-devel libxslt-devel \
    readline-devel libopenssl-devel \
    gdbm-devel libdb-4_8-devel \
    openldap2-devel pcre-devel net-snmp-devel \
    autoconf automake make patch curl git pkg-config libtool gcc gcc-c++ \
    tar gzip gawk glibc-locale bzip2 bison \
    libicu-devel krb5-devel |& tee -a "$LOG_FILE"

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  buildCmake |& tee -a "$LOG_FILE"

  PATH=${PREFIX}/bin${PATH:+:${PATH}}
  PATH+=:${PREFIX}/sbin
  export PATH

  PKG_CONFIG_PATH=${PREFIX}/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}
  PKG_CONFIG_PATH+=:${PREFIX}/lib64/pkgconfig
  export PKG_CONFIG_PATH

  LD_RUN_PATH=${PREFIX}/lib64${LD_RUN_PATH:+:${LD_RUN_PATH}}
  LD_RUN_PATH+=:${PREFIX}/lib
  export LD_RUN_PATH

  LD_LIBRARY_PATH=${PREFIX}/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
  LD_LIBRARY_PATH+=:${PREFIX}/lib
  LD_LIBRARY_PATH+=:/usr/lib64
  export LD_LIBRARY_PATH

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  buildZip |& tee -a "$LOG_FILE"
  ZLIB_DIR=${PREFIX}

  buildTidy |& tee -a "$LOG_FILE"
  TIDY_DIR=${PREFIX}

  buildOniguruma |& tee -a "$LOG_FILE"

  buildAspell |& tee -a "$LOG_FILE"
  PSPELL_DIR=${PREFIX}

  buildIcu |& tee -a "$LOG_FILE"

  buildEnchant |& tee -a "$LOG_FILE"
  ENCHANT_DIR=${PREFIX}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  echo 128128 | sudo tee /proc/sys/user/max_user_namespaces
  
  PG_CONFIG=/usr/lib/postgresql10/bin/pg_config

  configureAndInstall |& tee -a "$LOG_FILE"
;;

#----------------------------------------------------------
*)
  errlog "$DISTRO not supported"
;;

esac

gettingStarted |& tee -a "$LOG_FILE"
