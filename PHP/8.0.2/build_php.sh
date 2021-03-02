#!/bin/bash
# ©  Copyright IBM Corporation 2021.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/PHP/8.0.2/build_php.sh
# Execute build script: bash build_php.sh    (provide -h for help)
#


#==============================================================================
set -e -o pipefail

PACKAGE_NAME="PHP"
PACKAGE_VERSION="8.0.2"
SOURCE_ROOT="$(pwd)"

FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

PHP_URL="https://www.php.net/distributions"
PHP_URL+="/php-${PACKAGE_VERSION}.tar.gz"

PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/"
PATCH_URL+="${PACKAGE_NAME}/${PACKAGE_VERSION}/patch"


PREFIX=/usr/local

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
  sudo mv /usr/bin/gcc /usr/bin/gcc-orig
  sudo mv /usr/bin/g++ /usr/bin/g++-orig
  sudo mv /usr/bin/cc /usr/bin/cc-orig
}

#==============================================================================
cleanCompiler()
{
  #Make sure no previous versions of gcc are installed
  if [ -x "/usr/bin/cc" ]; then
    sudo mv /usr/bin/cc /usr/bin/cc-orig
    msglog "Moving cc to cc-orig"
  fi
  if [ -x "/usr/bin/gcc" ]; then
    sudo mv /usr/bin/gcc /usr/bin/gcc-orig
    msglog "Moving gcc to gcc-orig"
  fi
  if [ -x "/usr/bin/g++" ]; then
    sudo mv /usr/bin/g++ /usr/bin/g++-orig
  fi
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

  ./configure --prefix=${PREFIX} \
    --without-pcre-jit --without-pear \
    --enable-mysqlnd --with-pdo-mysql  --with-pdo-mysql=mysqlnd --with-pdo-pgsql=/usr/bin/pg_config \
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
    "rhel-7.8" | "rhel-7.9") url=${PATCH_URL}/rhel7-test.diff ;;
    "rhel-8.2" | "rhel-8.3") url=${PATCH_URL}/rhel8-test.diff ;;
    "sles-12.5" | "sles-15.2") url=${PATCH_URL}/sles-test.diff ;;
  esac

  if [[ -n "${url}" ]]; then
    curl -sSL ${url} | patch -p1 || error "${url}"
  fi
    curl -sSL ${PATCH_URL}/range-test.diff | patch -p1 || error "${url}"
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
    sed -i 's/run-tests.php -n -c/run-tests.php -q -n -c/' Makefile
    make test 

    msg "Test execution completed. "
    sed -i 's/run-tests.php -q -n -c/run-tests.php -n -c/' Makefile
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

	  export PATH=${PREFIX}/bin:\${PATH}
	  export PKG_CONFIG_PATH=${PREFIX}/lib/pkgconfig:${PREFIX}/lib64/pkgconfig:\${PKG_CONFIG_PATH}
	  export LD_LIBRARY_PATH=${PREFIX}/lib:${PREFIX}/lib64:\${LD_LIBRARY_PATH}
	  export LD_RUN_PATH=${PREFIX}/lib:\${LD_RUN_PATH}

	  Run the following commands to check PHP version:
	  ${PREFIX}/bin/php -v

	  More information can be found here:
	  https://www.php.net/
eof
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
buildGCC()
{
  local ver=10.2.0
  local url
  msg "Building gcc $ver"

  cd "$SOURCE_ROOT"
  url=http://ftp.mirrorservice.org/sites/sourceware.org/pub/gcc/releases/gcc-${ver}/gcc-${ver}.tar.gz
  curl -sSL $url | tar xzf - || error "gcc $ver"

  cd gcc-${ver}
  mkdir build-gcc; cd build-gcc
  ../configure --enable-languages=c,c++ --disable-multilib
  make -j$(nproc)
  sudo make install

  if [ -x "/usr/bin/cc" ]; then
    sudo mv /usr/bin/cc /usr/bin/cc-orig
  fi
 
  sudo ln -s /usr/local/bin/gcc /usr/bin/cc
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
       autoconf build-essential curl libtool \
       libssl-dev libcurl4-openssl-dev libxml2-dev \
       libreadline7 libreadline-dev libzip-dev libzip4 \
       nginx openssl pkg-config zlib1g-dev libsqlite3-dev \
       libonig-dev libpq-dev gcc-10 g++-10 git curl tar \
       make patch |& tee -a "$LOG_FILE"

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  cleanCompiler |& tee -a "$LOG_FILE"
  PATH=${PREFIX}/bin${PATH:+:${PATH}}
  export PATH

  sudo ln -s /usr/bin/gcc-10 /usr/bin/gcc
  sudo ln -s /usr/bin/g++-10 /usr/bin/g++
  sudo ln -s /usr/bin/gcc /usr/bin/cc

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  configureAndInstall |& tee -a "$LOG_FILE"
;;


#----------------------------------------------------------
"ubuntu-20.04" | "ubuntu-20.10")

  sudo apt-get update |& tee -a "$LOG_FILE"

  sudo apt-get install -y locales language-pack-de \
       autoconf build-essential curl libtool \
       libssl-dev libcurl4-openssl-dev libxml2-dev \
       libreadline8 libreadline-dev libzip-dev libzip5 \
       nginx openssl pkg-config zlib1g-dev \
       libsqlite3-dev libonig-dev libpq-dev \
       gcc-10 g++-10 git curl tar gcc make \
       patch |& tee -a "$LOG_FILE"

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  cleanCompiler |& tee -a "$LOG_FILE"
  PATH=${PREFIX}/bin${PATH:+:${PATH}}
  export PATH

  sudo ln -s /usr/bin/gcc-10 /usr/bin/gcc
  sudo ln -s /usr/bin/g++-10 /usr/bin/g++
  sudo ln -s /usr/bin/gcc /usr/bin/cc

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  configureAndInstall |& tee -a "$LOG_FILE"
;;


#----------------------------------------------------------
"rhel-7.8" | "rhel-7.9")

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  sudo yum install -y \
    autoconf curl libtool openssl-devel libcurl \
    libcurl-devel libxml2 libxml2-devel readline \
    readline-devel libzip-devel libzip openssl \
    zlib-devel sqlite-devel git curl tar postgresql \
    postgresql-devel pkgconfig patch gcc \
    make |& tee -a "$LOG_FILE"

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  buildOniguruma |& tee -a "$LOG_FILE"

  PATH=${PREFIX}/bin${PATH:+:${PATH}}
  export PATH
  
  PKG_CONFIG_PATH=${PREFIX}/lib/pkgconfig:${PREFIX}/lib64/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}
  export PKG_CONFIG_PATH

  LD_LIBRARY_PATH=${PREFIX}/lib:${PREFIX}/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
  export LD_LIBRARY_PATH

  LD_RUN_PATH=${PREFIX}/lib${LD_RUN_PATH:+:${LD_RUN_PATH}}
  export LD_RUN_PATH

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  sudo yum install -y \
    bzip2 wget gcc gcc-c++ gmp-devel mpfr-devel \
    libmpc-devel make |& tee -a "$LOG_FILE"


  buildGCC |& tee -a "$LOG_FILE"

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  echo 128128 | sudo tee /proc/sys/user/max_user_namespaces

  configureAndInstall |& tee -a "$LOG_FILE"
;;


#----------------------------------------------------------
"rhel-8.1" | "rhel-8.2" | "rhel-8.3")

  sudo yum install -y \
    autoconf curl libtool openssl-devel \
    libcurl libcurl-devel libxml2 libxml2-devel readline \
    readline-devel libzip-devel libzip nginx openssl \
    pkgconf zlib-devel sqlite-libs sqlite-devel \
    oniguruma oniguruma-devel libpq-devel git curl \
    tar make binutils gcc-toolset-10-gcc \
    gcc-toolset-10-gcc-c++ patch \
    binutils |& tee -a "$LOG_FILE"

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  cleanCompiler |& tee -a "$LOG_FILE"
  PATH=${PREFIX}/bin${PATH:+:${PATH}}
  export PATH

  sudo ln -s /opt/rh/gcc-toolset-10/root/bin/gcc /usr/bin/gcc
  sudo ln -s /opt/rh/gcc-toolset-10/root/bin/g++ /usr/bin/g++
  sudo ln -s /opt/rh/gcc-toolset-10/root/bin/cc /usr/bin/cc

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  configureAndInstall |& tee -a "$LOG_FILE"
;;


#----------------------------------------------------------
"sles-12.5")

  sudo zypper install -y \
    autoconf curl libtool openssl-devel libxml2 \
    libxml2-devel readline readline-devel libcurl4 \
    libcurl-devel libreadline6 nginx openssl \
    libzip-devel libzip2 pkg-config oniguruma-devel git \
    curl tar postgresql10-devel postgresql10 \
    sqlite3-devel zlib-devel gcc10 gcc10-c++ \
    make patch |& tee -a "$LOG_FILE"

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  cleanCompiler |& tee -a "$LOG_FILE"
  PATH=${PREFIX}/bin${PATH:+:${PATH}}
  export PATH

  sudo ln -s /usr/bin/g++-10 /usr/bin/g++
  sudo ln -s /usr/bin/gcc-10 /usr/bin/gcc
  sudo ln -s /usr/bin/gcc /usr/bin/cc
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  echo 128128 | sudo tee /proc/sys/user/max_user_namespaces

  configureAndInstall |& tee -a "$LOG_FILE"
;;


#----------------------------------------------------------
"sles-15.2")

  sudo zypper install -y \
    autoconf curl libtool openssl-devel libxml2 \
    libxml2-devel readline readline-devel \
    libcurl4 libcurl-devel libreadline7 openssl \
    libzip-devel pkg-config oniguruma-devel git curl \
    tar sqlite3-devel zlib-devel gcc10 gcc10-c++ \
    libzip5 postgresql12 nginx postgresql12-server-devel \
    patch make |& tee -a "$LOG_FILE"

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  cleanCompiler |& tee -a "$LOG_FILE"
  PATH=${PREFIX}/bin${PATH:+:${PATH}}
  export PATH

  sudo ln -s /usr/bin/gcc-10 /usr/bin/gcc
  sudo ln -s /usr/bin/g++-10 /usr/bin/g++
  sudo ln -s /usr/bin/gcc /usr/bin/cc 

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  echo 128128 | sudo tee /proc/sys/user/max_user_namespaces

  configureAndInstall |& tee -a "$LOG_FILE"
;;

#----------------------------------------------------------
*)
  errlog "$DISTRO not supported"
;;

esac

gettingStarted |& tee -a "$LOG_FILE"
