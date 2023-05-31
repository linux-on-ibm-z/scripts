#!/usr/bin/env bash
# © Copyright IBM Corporation 2023.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Zabbix/6.0.17/build_zabbixserver.sh
# Execute build script: bash build_zabbixserver.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="zabbixserver"
URL_NAME="zabbix"
PACKAGE_VERSION="6.0.17"
PHP_VERSION="7.4.11"
CURDIR="$(pwd)"
BUILD_DIR="$(pwd)"
PREFIX="/usr/local"
CMAKE=$PREFIX/bin/cmake
PHP_PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/"
PHP_PATCH_URL+="PHP/${PHP_VERSION}/patch"
PHP_URL="https://www.php.net/distributions"
PHP_URL+="/php-${PHP_VERSION}.tar.gz"

FORCE="false"
TESTS="false"
SUCCESS="false"

source "/etc/os-release"
DISTRO="$ID-$VERSION_ID"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-${DISTRO}-$(date +"%F-%T").log"

#Check if directory exists
if [ ! -d "$CURDIR/logs" ]; then
  mkdir -p "$CURDIR/logs"
fi

#==============================================================================

error() { echo "Error: ${*}"; exit 1; }
errlog() { echo "Error: ${*}" |& tee -a "$LOG_FILE"; exit 1; }

msg() { echo "${*}"; }
log() { echo "${*}" >> "$LOG_FILE"; }
msglog() { echo "${*}" |& tee -a "$LOG_FILE"; }


trap cleanup 0 1 2 ERR

#==============================================================================


function checkPrequisites() {
  if command -v "sudo" >/dev/null; then
    printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
  else
    printf -- 'Sudo : No \n' >>"$LOG_FILE"
    printf -- 'Sudo is required. Please install it using apt, yum or zypper based on your distro. \n'
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

  cd $BUILD_DIR

  if [[ $SUCCESS == "true" ]]; then
    if [ -d ${URL_NAME} ]; then
      sudo rm -rf ${URL_NAME}
    fi

    if [ -f php-$PHP_VERSION.tar.gz ]; then
      sudo rm php-$PHP_VERSION.tar.gz
    fi

    if [ -d php-$PHP_VERSION ]; then
      sudo rm -rf php-$PHP_VERSION
    fi

    if [ -d oniguruma ]; then
      sudo rm -rf oniguruma
    fi

    if [ -d libzip ]; then
      sudo rm -rf libzip
    fi

    if [ -d icu-release-55-1 ]; then
      sudo rm -rf icu-release-55-1
    fi

    if [ -d tidy-html5 ]; then
      sudo rm -rf tidy-html5
    fi

    if [ -d cmake-3.12.4 ]; then
      sudo rm -rf cmake-3.12.4
    fi
  fi

  printf -- 'Cleaned up the artifacts\n' >>"$LOG_FILE"
}

function runTest() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- "TEST Flag is set , Continue with running test \n"
		cd ${BUILD_DIR}/${URL_NAME}
		make tests
		printf -- "Tests completed. \n"

	fi
	set -e
}

function configureAndInstall() {
  printf -- 'Configuration and Installation started \n'
  printf -- 'Configuing httpd to enable PHP... \n'
  # Configure httpd to enable PHP
  if [[ "$ID" == "rhel" ]]; then
    cd /etc/httpd/conf/
    sudo chmod 766 httpd.conf
    echo "ServerName localhost" >> httpd.conf
    echo "AddType application/x-httpd-php .php" >> httpd.conf
    echo "<Directory />" >> httpd.conf
    echo "DirectoryIndex index.php" >> httpd.conf
    echo "</Directory>" >> httpd.conf
    sudo chmod 644 httpd.conf

    sudo groupadd --system zabbix || echo "group already exists"
    sudo useradd --system -g zabbix -d /usr/lib/zabbix -s /sbin/nologin -c "Zabbix Monitoring System" zabbix || echo "user already exists"

    if [[ "$VERSION_ID" == "7.8" || "$VERSION_ID" == "7.9" ]]; then
      sudo sed -i 's/max_execution_time = 30/max_execution_time = 300/g' /usr/local/lib/php.ini
      sudo sed -i 's/max_input_time = 60/max_input_time = 300/g' /usr/local/lib/php.ini
      sudo sed -i 's/post_max_size = 8M/post_max_size = 16M/g' /usr/local/lib/php.ini
    else
      sudo sed -i 's/max_execution_time = 30/max_execution_time = 300/g' /etc/php.ini
      sudo sed -i 's/max_input_time = 60/max_input_time = 300/g' /etc/php.ini
      sudo sed -i 's/post_max_size = 8M/post_max_size = 16M/g' /etc/php.ini
      sudo service php-fpm restart
    fi
  fi

  if [[ "$ID" == "sles" ]]; then
    cd /etc/apache2/
    sudo chmod 766 httpd.conf
    echo "ServerName localhost" >> httpd.conf
    echo "AddType application/x-httpd-php .php" >> httpd.conf
    echo "<Directory />" >> httpd.conf
    echo "DirectoryIndex index.php" >> httpd.conf
    echo "</Directory>" >> httpd.conf
    if [[ "$VERSION_ID" == "12.5" ]]; then
      echo "LoadModule php7_module /usr/lib64/apache2/mod_php7.so" >> httpd.conf
      sudo sed -i 's/max_execution_time = 30/max_execution_time = 300/g' /etc/php7/apache2/php.ini
      sudo sed -i 's/max_input_time = 60/max_input_time = 300/g' /etc/php7/apache2/php.ini
      sudo sed -i 's/post_max_size = 8M/post_max_size = 16M/g' /etc/php7/apache2/php.ini
    else
      echo "LoadModule php_module /usr/lib64/apache2/mod_php8.so" >> httpd.conf
      sudo sed -i 's/max_execution_time = 30/max_execution_time = 300/g' /etc/php8/apache2/php.ini
      sudo sed -i 's/max_input_time = 60/max_input_time = 300/g' /etc/php8/apache2/php.ini
      sudo sed -i 's/post_max_size = 8M/post_max_size = 16M/g' /etc/php8/apache2/php.ini
    fi
    sudo chmod 644 httpd.conf

    sudo groupadd --system zabbix || echo "group already exists"
    sudo useradd --system -g zabbix -d /usr/lib/zabbix -s /sbin/nologin -c "Zabbix Monitoring System" zabbix || echo "user already exists"
  fi

  if [[ "$ID" == "ubuntu" ]]; then
    cd /etc/apache2/
    sudo chmod 766 apache2.conf
    echo "ServerName localhost" >> apache2.conf
    echo "AddType application/x-httpd-php .php" >> apache2.conf
    echo "<Directory />" >> apache2.conf
    echo "DirectoryIndex index.php" >> apache2.conf
    echo "</Directory>" >> apache2.conf
    sudo chmod 644 apache2.conf

    sudo addgroup --system --quiet zabbix || echo "group already exists"
    sudo adduser --quiet --system --disabled-login --ingroup zabbix --home /var/lib/zabbix --no-create-home zabbix || echo "user already exists"

    if [[ "$VERSION_ID" == "20.04" ]]; then
      sudo sed -i 's/max_execution_time = 30/max_execution_time = 300/g' /etc/php/7.4/apache2/php.ini
      sudo sed -i 's/max_input_time = 60/max_input_time = 300/g' /etc/php/7.4/apache2/php.ini
      sudo sed -i 's/post_max_size = 8M/post_max_size = 16M/g' /etc/php/7.4/apache2/php.ini
    fi
    if [[ "$VERSION_ID" == "22.04" || "$VERSION_ID" == "22.10" || "$VERSION_ID" == "23.04" ]]; then
      sudo sed -i 's/max_execution_time = 30/max_execution_time = 300/g' /etc/php/8.1/apache2/php.ini
      sudo sed -i 's/max_input_time = 60/max_input_time = 300/g' /etc/php/8.1/apache2/php.ini
      sudo sed -i 's/post_max_size = 8M/post_max_size = 16M/g' /etc/php/8.1/apache2/php.ini
      sudo sed -i 's/;date.timezone =/date.timezone = Asia\/Kolkata/g' /etc/php/8.1/apache2/php.ini
    fi
  fi

  #Download and install zabbix server
  printf -- 'Build and install Zabbix server... \n'
  cd $BUILD_DIR
  if ! [ -d ${URL_NAME} ]; then
      git clone https://github.com/zabbix/zabbix.git
  fi
  cd ${URL_NAME}
  git checkout ${PACKAGE_VERSION}
  ./bootstrap.sh tests
  ./configure --enable-server --enable-agent --with-mysql --enable-ipv6 --with-net-snmp --with-libcurl --with-libxml2

  # Installation
  make
  make dbschema
  sudo make install

  # Installing Zabbix web interface
  printf -- 'Installing Zabbix web interface... \n'
  if [[ "$ID" == "ubuntu" ]]; then
    cd "$BUILD_DIR"/${URL_NAME}/ui/
    sudo mkdir -p /var/www/html/${URL_NAME}
    sudo cp -rf * /var/www/html/${URL_NAME}/
    sudo chown -R www-data:www-data /var/www/html/zabbix/conf
    sudo service apache2 start
  fi

  if [[ "$ID" == "rhel" ]]; then
    cd /"$BUILD_DIR"/${URL_NAME}/ui/
    sudo mkdir -p /var/www/html/${URL_NAME}
    sudo cp -rf * /var/www/html/${URL_NAME}/
    sudo chown -R apache:apache /var/www/html/zabbix/conf
    if [[ "$VERSION_ID" == "9."* ]]; then
      sudo service mariadb start
    fi
    sudo service httpd start
  fi

  if [[ "$ID" == "sles" ]]; then
    cd /"$BUILD_DIR"/${URL_NAME}/ui/
    sudo mkdir -p /srv/www/htdocs/${URL_NAME}
    sudo cp -rf * /srv/www/htdocs/${URL_NAME}
    sudo chown -R wwwrun:www /srv/www/htdocs/zabbix/conf
    if [[ "$VERSION_ID" == "15.4" ]]; then
      sudo service mariadb restart
    fi
    sudo service apache2 restart
  fi

  printf -- 'Create database and grant privileges to zabbix user... \n'
  if [[ "$ID" == "ubuntu" && "$VERSION_ID" == "20.04" ]]; then
    sudo mysql -e "create user 'zabbix'@'localhost' identified with mysql_native_password"
    sudo mysql -e "create database zabbix character set utf8 collate utf8_bin"
    sudo mysql -e "grant all privileges on zabbix.* to 'zabbix'@'localhost'"
  elif [[ "$DISTRO" == "rhel-7."* ]]; then
    sudo mysql -e "create user zabbix@localhost"
    sudo mysql -e "create database zabbix character set utf8 collate utf8_bin"
    sudo mysql -e "grant all privileges on zabbix.* to zabbix@localhost"
  else
    sudo mysql -e "create user 'zabbix'@'localhost'"
    sudo mysql -e "create database zabbix character set utf8 collate utf8_bin"
    sudo mysql -e "grant all privileges on zabbix.* to 'zabbix'@'localhost'"
  fi

  printf -- 'Populate database with initial load... \n'
  cd ${BUILD_DIR}/${URL_NAME}/database/mysql
  mysql -uzabbix zabbix < schema.sql
  mysql -uzabbix zabbix < images.sql
  mysql -uzabbix zabbix < data.sql

  #run tests
  runTest

  #cleanup
  cleanup
}

#==============================================================================
buildCmocka()
{
  printf -- 'Building cmocka... \n'
  cd "$SOURCE_ROOT"
  if [ ! -d cmocka ]; then
    git clone https://gitlab.com/cmocka/cmocka.git
  fi
  cd cmocka
  git checkout cmocka-1.1.5
  mkdir -p build
  cd build
  cmake -DCMAKE_INSTALL_PREFIX=/usr ..
  sudo make install
}

#==============================================================================
buildCmake()
{
  local ver=3.12.4
  local url
  echo "Building cmake $ver"

  cd "$SOURCE_ROOT"
  if [ ! -d cmake-${ver} ]; then
    url=https://github.com/Kitware/CMake/releases/download/v${ver}/cmake-${ver}.tar.gz
    curl -sSL $url | tar xzf - || error "cmake $ver"
  fi
  cd cmake-${ver}
  ./bootstrap
  make
  sudo make install
}

#==============================================================================
buildZip()
{
  local ver=rel-1-4-0
  echo "Building libzip $ver"

  cd "$SOURCE_ROOT"
  if [ ! -d libzip ]; then
    git clone https://github.com/nih-at/libzip
  fi
  cd libzip
  git checkout ${ver}
  mkdir -p build && cd build
  $CMAKE .. -DCMAKE_INSTALL_PREFIX=${PREFIX}
  make
  sudo make install
}

#==============================================================================
buildTidy()
{
  local ver=5.6.0
  echo "Building tidy-html $ver"

  cd "$SOURCE_ROOT"
  if [ ! -d tidy-html5 ]; then
    git clone https://github.com/htacg/tidy-html5.git
  fi
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
  echo "Building oniguruma $ver"

  cd "$SOURCE_ROOT"
  if [ ! -d oniguruma ]; then
    git clone https://github.com/kkos/oniguruma
  fi
  cd oniguruma
  git checkout ${ver}
  autoreconf -vfi
  ./configure --prefix=${PREFIX}
  make
  sudo make install
}

#==============================================================================
buildIcu()
{
  local ver=55-1
  local url
  echo "Building icu $ver"

  cd "$SOURCE_ROOT"
  if [ ! -d icu-release-${ver} ]; then
    url=https://github.com/unicode-org/icu/archive/release-${ver}.tar.gz
    curl -sSL $url | tar xzf - || error "icu $ver"
  fi
  cd icu-release-${ver}/icu4c/source

  ./configure --prefix=${PREFIX}
  CFLAGS=-D__USE_XOPEN2K8 CXXFLAGS=-D__USE_XOPEN2K8 make
  sudo make install
}

#==============================================================================
buildPHP()
{
  local ver=${PHP_VERSION}
  local url=${PHP_PATCH_URL}
  echo "Building PHP $ver"

  cd "$SOURCE_ROOT"

  if [ ! -f php-${ver}.tar.gz ]; then
    wget $PHP_URL
  fi
  if [ ! -d php-${ver} ]; then
    tar xzf php-${ver}.tar.gz
  fi
  cd php-${ver}

  # backport NAN and infinity handling
  curl -sSL ${PHP_PATCH_URL}/nan.diff | patch -p1 || error "${PHP_PATCH_URL}/nan.diff"
  curl -sSL ${PHP_PATCH_URL}/infinity.diff | patch -p1 || error "${PHP_PATCH_URL}/infinity.diff"

  # fix reflection
  curl -sSL ${PHP_PATCH_URL}/reflection.diff | patch -p1 || error "${PHP_PATCH_URL}/reflection.diff"

  icupkg -tb ext/intl/tests/_files/resourcebundle/root.res
  icupkg -tb ext/intl/tests/_files/resourcebundle/es.res
  icupkg -tb ext/intl/tests/_files/resourcebundle/res_index.res

  ./configure --prefix=${PREFIX} \
    --without-pcre-jit --without-pear \
    --with-pdo-mysql=mysqlnd --with-mysqli=mysqlnd \
    --with-pgsql --with-pdo-pgsql --with-pdo-sqlite \
    --with-readline --with-gettext --with-apxs2=/usr/bin/apxs \
    --enable-gd --with-jpeg --with-freetype --with-xpm \
    --with-kerberos --with-openssl --with-ldap \
    --with-xsl --with-xmlrpc --with-bz2 --with-gmp --with-zip \
    --with-mhash --disable-inline-optimization \
    --enable-intl --enable-fpm --enable-exif \
    --enable-xmlreader --enable-sockets --enable-ctype \
    --enable-sysvsem --enable-sysvshm --enable-sysvmsg --enable-shmop \
    --enable-pcntl --enable-mbstring --enable-soap \
    --enable-bcmath --enable-calendar --enable-ftp \
    --enable-zend-test=shared \
    --with-curl=/usr \
    --with-zlib --with-zlib-dir=${ZLIB_DIR} \
    --with-tidy=${TIDY_DIR} \
    --with-pspell=/usr \
    --with-enchant=/usr

  make
  sudo make install

  sudo install -m644 php.ini-production ${PREFIX}/lib/php.ini
  sudo sed -i "s@php/includes\"@&\ninclude_path = \".:$PREFIX/lib/php\"@" ${PREFIX}/lib/php.ini

  sudo sed -i "s/;mysqli.allow_local_infile = On/mysqli.allow_local_infile = On/" ${PREFIX}/lib/php.ini

  sudo sed -i "s/;opcache.enable=1/opcache.enable=1/" ${PREFIX}/lib/php.ini
  sudo sed -i "s/;opcache.enable_cli=0/opcache.enable_cli=1/" ${PREFIX}/lib/php.ini
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
  echo "  bash build_zabbixserver.sh [-d debug] [-y install-without-confirmation] [-t run-tests] [-s skip-cleanup]"
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
  printf -- "\n* Getting Started * \n"
  printf -- " Please follow the following steps from the build instructions to complete the installation :\n"
  printf -- " Step 8: Start Zabbix server.  \n"
  printf -- " Step 9: Configure through online console. \n"
  printf -- "\n\nReference: \n"
  printf -- " More information can be found here : https://www.zabbix.com/documentation/6.0/manual/installation\n"
  printf -- '\n'
  printf -- ""
}

###############################################################################################################

logDetails
checkPrequisites #Check Prequisites

case "$DISTRO" in

"ubuntu-20.04")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  printf -- 'Installing the dependencies for Zabbix server from repository \n' |& tee -a "$LOG_FILE"
  sudo apt-get update >/dev/null
  sudo apt-get -y install wget curl vim gcc make pkg-config snmp snmptrapd ceph libmariadbd-dev libxml2-dev \
        libsnmp-dev libcurl4 libcurl4-openssl-dev git apache2 php php-mysql libapache2-mod-php mysql-server php7.4-xml \
        php7.4-gd php-bcmath php-mbstring php7.4-ldap libevent-dev libpcre3-dev automake pkg-config libcmocka-dev \
        libyaml-dev libyaml-libyaml-perl libpath-tiny-perl libipc-run3-perl build-essential |& tee -a "$LOG_FILE"
  configureAndInstall |& tee -a "$LOG_FILE"
  ;;

"ubuntu-22.04" | "ubuntu-22.10" | "ubuntu-23.04")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  printf -- 'Installing the dependencies for Zabbix server from repository \n' |& tee -a "$LOG_FILE"
  sudo apt-get update >/dev/null
  sudo apt-get -y install wget curl vim gcc make pkg-config snmp snmptrapd ceph libmariadbd-dev libxml2-dev \
        libsnmp-dev libcurl4 libcurl4-openssl-dev git apache2 php php-mysql libapache2-mod-php mysql-server php8.1-xml \
        php8.1-gd php-bcmath php-mbstring php8.1-ldap libevent-dev libpcre3-dev automake pkg-config libcmocka-dev \
        libyaml-dev libyaml-libyaml-perl libpath-tiny-perl libipc-run3-perl build-essential |& tee -a "$LOG_FILE"
  configureAndInstall |& tee -a "$LOG_FILE"
  ;;

"rhel-7.8" | "rhel-7.9")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  printf -- 'Installing the dependencies for Zabbix server from repository \n' |& tee -a "$LOG_FILE"
  sudo yum install -y devtoolset-7-gcc-c++ devtoolset-7-gcc \
        initscripts httpd tar wget curl vim pcre pcre-devel make net-snmp net-snmp-devel httpd-devel \
        git libcurl-devel libxml2-devel libjpeg-devel libpng-devel freetype freetype-devel openldap openldap-devel \
        libevent-devel sqlite-devel policycoreutils-python libyaml-devel perl-IPC-Run3 bzip2-devel curl-devel \
        enchant-devel gmp-devel krb5-devel postgresql-devel aspell-devel cyrus-sasl-devel libXpm-devel libxslt-devel \
        recode-devel readline-devel openssl-devel gdbm-devel libdb-devel autoconf automake patch pkgconfig libtool \
        bison openssl aspell mariadb-devel mariadb-libs |& tee -a "$LOG_FILE"

  source /opt/rh/devtoolset-7/enable

  curl -L http://cpanmin.us | sudo perl - --self-upgrade |& tee -a "$LOG_FILE"
  sudo /usr/local/bin/cpanm YAML::XS |& tee -a "$LOG_FILE"
  sudo /usr/local/bin/cpanm Path::Tiny |& tee -a "$LOG_FILE"

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

  sudo ln -sf /usr/lib64/libldap* /usr/lib/
  sudo ln -sf /usr/lib64/liblber.so /usr/lib/

  buildPHP |& tee -a "$LOG_FILE"

  buildCmocka |& tee -a "$LOG_FILE"

  configureAndInstall |& tee -a "$LOG_FILE"

  ;;

"rhel-8.6" | "rhel-8.7")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  printf -- 'Installing the dependencies for Zabbix server from repository \n' |& tee -a "$LOG_FILE"
  sudo subscription-manager repos --enable=codeready-builder-for-rhel-8-s390x-rpms |& tee -a "$LOG_FILE"
  sudo yum install -y initscripts httpd tar wget curl vim gcc make net-snmp net-snmp-devel php-mysqlnd git \
        httpd php libcurl-devel libxml2-devel php-xml php-gd php-bcmath php-mbstring php-ldap php-json libevent-devel \
        pcre-devel policycoreutils-python-utils automake pkgconfig libcmocka-devel libyaml-devel perl-YAML-LibYAML \
        libpath_utils-devel perl-IPC-Run3 perl-Path-Tiny php-fpm |& tee -a "$LOG_FILE"
  sudo yum groupinstall -y 'Development Tools' |& tee -a "$LOG_FILE"
  configureAndInstall |& tee -a "$LOG_FILE"
  ;;

"rhel-9.0")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  printf -- 'Installing the dependencies for Zabbix server from repository \n' |& tee -a "$LOG_FILE"
  sudo subscription-manager repos --enable=codeready-builder-for-rhel-9-s390x-rpms |& tee -a "$LOG_FILE"
  sudo dnf install -y initscripts httpd tar wget curl vim gcc make net-snmp net-snmp-devel php-mysqlnd mysql-libs git \
        httpd php libcurl-devel libxml2-devel php-xml php-gd php-bcmath php-mbstring php-ldap php-json libevent-devel \
        pcre-devel policycoreutils-python-utils automake pkgconfig libcmocka-devel libyaml-devel perl-YAML-LibYAML \
        libpath_utils-devel perl-IPC-Run3 perl-Path-Tiny mariadb mariadb-server mysql-devel perl-Time-HiRes |& tee -a "$LOG_FILE"
  sudo yum groupinstall -y 'Development Tools' |& tee -a "$LOG_FILE"
  configureAndInstall |& tee -a "$LOG_FILE"
  ;;

"rhel-9.1")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  printf -- 'Installing the dependencies for Zabbix server from repository \n' |& tee -a "$LOG_FILE"
  sudo subscription-manager repos --enable=codeready-builder-for-rhel-9-s390x-rpms |& tee -a "$LOG_FILE"
  sudo dnf install -y php\*-8.0.\*
  sudo dnf install -y initscripts httpd tar wget curl vim gcc make net-snmp net-snmp-devel mysql-libs git \
        httpd libcurl-devel libxml2-devel libevent-devel \
        pcre-devel policycoreutils-python-utils automake pkgconfig libcmocka-devel libyaml-devel perl-YAML-LibYAML \
        libpath_utils-devel perl-IPC-Run3 perl-Path-Tiny mariadb mariadb-server mysql-devel perl-Time-HiRes |& tee -a "$LOG_FILE"
  sudo yum groupinstall -y 'Development Tools' |& tee -a "$LOG_FILE"
  configureAndInstall |& tee -a "$LOG_FILE"
  ;;

"sles-12.5")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  printf -- 'Installing the dependencies for Zabbix server from repository \n' |& tee -a "$LOG_FILE"
  sudo zypper install -y wget tar curl vim gcc7 make net-snmp net-snmp-devel net-tools git apache2 apache2-devel \
        apache2-mod_php72 php72 php72-mysql php72-xmlreader php72-xmlwriter php72-gd php72-bcmath php72-mbstring \
        php72-ctype php72-sockets php72-gettext php72-ldap libcurl-devel libxml2 libxml2-devel openldap2-devel openldap2 \
        libevent-devel pcre-devel automake libyaml-devel perl-YAML-LibYAML perl-IPC-Run3 cmake glibc-locale libmysqld-devel libnghttp2-devel |& tee -a "$LOG_FILE"
  curl -L http://cpanmin.us | sudo perl - --self-upgrade |& tee -a "$LOG_FILE"
  sudo cpanm Path::Tiny |& tee -a "$LOG_FILE"
  export LC_CTYPE="en_US.UTF-8"

  sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-7 40
  sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-7 40

  buildCmocka |& tee -a "$LOG_FILE"
  configureAndInstall |& tee -a "$LOG_FILE"
  ;;

"sles-15.4")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  printf -- 'Installing the dependencies for Zabbix server from repository \n' |& tee -a "$LOG_FILE"
  sudo zypper install -y wget tar curl vim gcc make net-snmp net-snmp-devel net-tools git apache2 apache2-devel mariadb \
        libmariadbd-devel apache2-mod_php8 php8 php8-mysql php8-xmlreader php8-xmlwriter php8-gd php8-bcmath php8-mbstring \
        php8-ctype php8-sockets php8-gettext libcurl-devel libxml2-2 libxml2-devel openldap2-devel php8-ldap \
        libevent-devel pcre-devel awk gzip automake cmake libyaml-devel perl-YAML-LibYAML perl-Path-Tiny perl-IPC-Run3 \
        glibc-locale |& tee -a "$LOG_FILE"
  export LC_CTYPE="en_US.UTF-8"

  buildCmocka |& tee -a "$LOG_FILE"
  configureAndInstall |& tee -a "$LOG_FILE"
  ;;


*)
  printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
  exit 1
  ;;
esac

SUCCESS="true"
gettingStarted |& tee -a "$LOG_FILE"
