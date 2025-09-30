#!/usr/bin/env bash
# © Copyright IBM Corporation 2025.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Zabbix/7.0.18/build_zabbixserver.sh
# Execute build script: bash build_zabbixserver.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="zabbixserver"
URL_NAME="zabbix"
PACKAGE_VERSION="7.0.18"
PHP_VERSION="8.4.6"
CURDIR="$(pwd)"
BUILD_DIR="$(pwd)"
PREFIX="/usr/local"
CMAKE=$PREFIX/bin/cmake
PHP_URL="https://www.php.net/distributions/php-${PHP_VERSION}.tar.gz"

FORCE="false"
TESTS="false"
SKIP="false"
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

  if [ -f php-$PHP_VERSION.tar.gz ]; then
    sudo rm -f php-$PHP_VERSION.tar.gz
  fi

  if [ -d php-$PHP_VERSION ]; then
    sudo rm -rf php-$PHP_VERSION
  fi

  if [ -d cmocka ]; then
    sudo rm -rf cmocka
  fi

  printf -- 'Cleaned up the artifacts\n' >>"$LOG_FILE"
}

function runTest() {
  set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- "TEST Flag is set , Continue with running test \n"
		cd $BUILD_DIR/$URL_NAME
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
    cat <<EOF >> httpd.conf
ServerName localhost
AddType application/x-httpd-php .php
<Directory />
    DirectoryIndex index.php
</Directory>
EOF
    sudo chmod 644 httpd.conf

    sudo groupadd --system zabbix || echo "group already exists"
    sudo useradd --system -g zabbix -d /usr/lib/zabbix -s /sbin/nologin -c "Zabbix Monitoring System" zabbix || echo "user already exists"
    if [[ "$VERSION_ID" == "9."* ]]; then
      sudo sed -i 's/max_execution_time = 30/max_execution_time = 300/g' /etc/php.ini
      sudo sed -i 's/max_input_time = 60/max_input_time = 300/g' /etc/php.ini
      sudo sed -i 's/post_max_size = 8M/post_max_size = 16M/g' /etc/php.ini
      sudo service php-fpm restart
    fi

  fi

  if [[ "$ID" == "sles" ]]; then
    cd /etc/apache2/
    sudo chmod 766 httpd.conf
    cat <<EOF >> httpd.conf
ServerName localhost
AddType application/x-httpd-php .php
<Directory />
    DirectoryIndex index.php
</Directory>
LoadModule php_module /usr/lib64/apache2/mod_php8.so
EOF
    sudo sed -i 's/max_execution_time = 30/max_execution_time = 300/g' /etc/php8/apache2/php.ini
    sudo sed -i 's/max_input_time = 60/max_input_time = 300/g' /etc/php8/apache2/php.ini
    sudo sed -i 's/post_max_size = 8M/post_max_size = 16M/g' /etc/php8/apache2/php.ini

    sudo chmod 644 httpd.conf

    sudo groupadd --system zabbix || echo "group already exists"
    sudo useradd --system -g zabbix -d /usr/lib/zabbix -s /sbin/nologin -c "Zabbix Monitoring System" zabbix || echo "user already exists"
  fi

  if [[ "$ID" == "ubuntu" ]]; then
    cd /etc/apache2/
    sudo chmod 766 apache2.conf
    cat <<EOF >> apache2.conf
ServerName localhost
AddType application/x-httpd-php .php
<Directory />
    DirectoryIndex index.php
</Directory>
EOF
    sudo chmod 644 apache2.conf

    sudo addgroup --system --quiet zabbix || echo "group already exists"
    sudo adduser --quiet --system --disabled-login --ingroup zabbix --home /var/lib/zabbix --no-create-home zabbix || echo "user already exists"
    
    sudo locale-gen en_US en_US.UTF-8
    sudo dpkg-reconfigure -f noninteractive locales  
    LANG='en_US.UTF-8'
    LANGUAGE='en_US.UTF-8'
    if [[ "$VERSION_ID" == "22.04" ]]; then
      sudo sed -i 's/max_execution_time = 30/max_execution_time = 300/g' /etc/php/8.1/apache2/php.ini
      sudo sed -i 's/max_input_time = 60/max_input_time = 300/g' /etc/php/8.1/apache2/php.ini
      sudo sed -i 's/post_max_size = 8M/post_max_size = 16M/g' /etc/php/8.1/apache2/php.ini
      sudo sed -i 's/;date.timezone =/date.timezone = Asia\/Kolkata/g' /etc/php/8.1/apache2/php.ini
    fi
    if [[ "$VERSION_ID" == "24.04" ]]; then
      sudo sed -i 's/max_execution_time = 30/max_execution_time = 300/g' /etc/php/8.3/apache2/php.ini
      sudo sed -i 's/max_input_time = 60/max_input_time = 300/g' /etc/php/8.3/apache2/php.ini
      sudo sed -i 's/post_max_size = 8M/post_max_size = 16M/g' /etc/php/8.3/apache2/php.ini
      sudo sed -i 's/;date.timezone =/date.timezone = Asia\/Kolkata/g' /etc/php/8.3/apache2/php.ini
    fi
  fi

  #Download and install zabbix server
  printf -- 'Build and install Zabbix server... \n'
  cd $BUILD_DIR
  if ! [ -d ${URL_NAME} ]; then
      git clone -b ${PACKAGE_VERSION} --depth 1 https://github.com/zabbix/zabbix.git
  fi
  cd ${URL_NAME}
  export CFLAGS="-std=gnu99"
  ./bootstrap.sh tests
  ./configure --enable-server --enable-agent --enable-proxy --with-mysql --with-unixodbc --enable-ipv6 --with-net-snmp --with-libcurl --with-libxml2 --with-libpcre2

  # Installation
  make -j$(nproc)
  make dbschema -j$(nproc)
  sudo make install

  # Installing Zabbix web interface
  printf -- 'Installing Zabbix web interface... \n'
  if [[ "$ID" == "ubuntu" ]]; then
    cd "$BUILD_DIR"/${URL_NAME}/ui/
    sudo mkdir -p /var/www/html/${URL_NAME}
    sudo cp -rf * /var/www/html/${URL_NAME}/
    sudo chown -R www-data:www-data /var/www/html/zabbix/conf
    sudo service apache2 start
    sudo service mysql stop
    sudo usermod -d /var/lib/mysql/ mysql
    sudo service mysql start
  fi

  if [[ "$ID" == "rhel" ]]; then
    cd /"$BUILD_DIR"/${URL_NAME}/ui/
    sudo mkdir -p /var/www/html/${URL_NAME}
    sudo cp -rf * /var/www/html/${URL_NAME}/
    sudo chown -R apache:apache /var/www/html/zabbix/conf
    sudo service mariadb start
    sudo /usr/sbin/service httpd start
  fi

  if [[ "$ID" == "sles" ]]; then
    cd /"$BUILD_DIR"/${URL_NAME}/ui/
    sudo mkdir -p /srv/www/htdocs/${URL_NAME}
    sudo cp -rf * /srv/www/htdocs/${URL_NAME}
    sudo chown -R wwwrun:www /srv/www/htdocs/zabbix/conf
    sudo service mariadb restart
    sudo service apache2 restart
  fi

  printf -- 'Create database and grant privileges to zabbix user... \n'
  sudo mysql -e "create user 'zabbix'@'localhost'"
  sudo mysql -e "create database zabbix character set utf8 collate utf8_bin"
  sudo mysql -e "grant all privileges on zabbix.* to 'zabbix'@'localhost'"

  printf -- 'Populate database with initial load... \n'
  if [[ "$ID" == "ubuntu" ]]; then
    printf -- 'Set MySQL setting... \n'
    sudo mysql -e "SET GLOBAL log_bin_trust_function_creators = 1"
  fi
  cd ${BUILD_DIR}/${URL_NAME}/database/mysql
  sudo mysql -uzabbix zabbix < schema.sql
  sudo mysql -uzabbix zabbix < images.sql
  sudo mysql -uzabbix zabbix < data.sql

  #run tests
  runTest

  #display getting started info
  gettingStarted

  #cleanup
  if [[ "$SKIP" != "true" ]]; then
	cleanup
	# To remove color prefixes from log
  sed -i 's/\x1b\[[0-9;]*m//g' $LOG_FILE
  fi
}

#==============================================================================
buildCmocka()
{
  printf -- 'Building cmocka... \n'
  cd "$CURDIR"
  if [ ! -d cmocka ]; then
    git clone -b cmocka-1.1.7 https://gitlab.com/cmocka/cmocka.git
  fi
  cd cmocka
  mkdir -p build
  cd build
  cmake -DCMAKE_INSTALL_PREFIX=/usr ..
  sudo make install
}

#==============================================================================
buildPHP()
{
  local ver=${PHP_VERSION}
  echo "Building PHP $ver"
  
  cd "$CURDIR"
  wget -qO- $PHP_URL | tar xzf -
  cd "$CURDIR/php-${PHP_VERSION}" 

  ./configure --prefix=${PREFIX} --enable-zts \
    --without-pcre-jit --without-pear \
    --with-pdo-mysql=mysqlnd --with-mysqli=mysqlnd \
    --with-readline --with-gettext \
    --with-apxs2=/usr/bin/apxs \
    --enable-gd --with-jpeg \
    --with-freetype --with-xpm --with-openssl \
    --with-xsl --with-gmp --with-zip \
    --with-mhash --enable-intl \
    --enable-fpm --enable-exif --enable-xmlreader \
    --enable-sockets --enable-ctype --enable-sysvsem \
    --enable-sysvshm --enable-sysvmsg \
    --enable-shmop --enable-pcntl --enable-mbstring \
    --enable-soap --enable-bcmath --enable-calendar \
    --enable-ftp --enable-zend-test=shared \
    --with-curl=/usr --with-zlib --with-zlib-dir=/usr/local |& tee -a "$LOG_FILE"

  make -j$(nproc) |& tee -a "$LOG_FILE"
  sudo make install |& tee -a "$LOG_FILE"

  sudo install -m644 php.ini-production ${PREFIX}/lib/php.ini
  sudo sed -i "s@php/includes\"@&\ninclude_path = \".:/usr/local/lib/php\"@" /usr/local/lib/php.ini
  sudo sed -i "s/;mysqli.allow_local_infile = On/mysqli.allow_local_infile = On/" /usr/local/lib/php.ini
  sudo sed -i "s/;opcache.enable=1/opcache.enable=1/" /usr/local/lib/php.ini
  sudo sed -i "s/;opcache.enable_cli=0/opcache.enable_cli=1/" /usr/local/lib/php.ini
  sudo sed -i 's/max_execution_time = 30/max_execution_time = 300/g' /usr/local/lib/php.ini
  sudo sed -i 's/max_input_time = 60/max_input_time = 300/g' /usr/local/lib/php.ini
  sudo sed -i 's/post_max_size = 8M/post_max_size = 16M/g' /usr/local/lib/php.ini
  sudo sed -i 's/;date.timezone =/date.timezone = Asia\/Kolkata/g' /usr/local/lib/php.ini
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

while getopts "h?dyts" opt; do
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
  s)
	SKIP="true"
	;;
  esac
done

function gettingStarted() {
  printf -- "\n* Getting Started * \n"
  printf -- " Please follow the following steps from the build instructions to complete the installation :\n"
  printf -- " Step 7: Start Zabbix server.  \n"
  printf -- " Step 8: Configure through online console. \n"
  printf -- "\n\nReference: \n"
  printf -- " More information can be found here : https://www.zabbix.com/documentation/7.0/manual/installation\n"
  printf -- '\n'
  printf -- ""
}

###############################################################################################################

logDetails
checkPrequisites #Check Prequisites

case "$DISTRO" in

"rhel-8.10")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  printf -- 'Installing the dependencies for Zabbix server from repository \n' |& tee -a "$LOG_FILE"
  sudo subscription-manager repos --enable=codeready-builder-for-rhel-8-s390x-rpms |& tee -a "$LOG_FILE"
  export LC_CTYPE="en_US.UTF-8"
  cat > MariaDB.repo <<'EOF'
# MariaDB 10.11 RedHatEnterpriseLinux repository list - created 2023-07-14 14:59 UTC
# https://mariadb.org/download/
[mariadb]
name = MariaDB
# rpm.mariadb.org is a dynamic mirror if your preferred mirror goes offline. See https://mariadb.org/mirrorbits/ for details.
# baseurl = https://rpm.mariadb.org/10.11/rhel/$releasever/$basearch
baseurl = https://mirror.its.dal.ca/mariadb/yum/10.11/rhel/$releasever/$basearch
module_hotfixes = 1
# gpgkey = https://rpm.mariadb.org/RPM-GPG-KEY-MariaDB
gpgkey = https://mirror.its.dal.ca/mariadb/yum/RPM-GPG-KEY-MariaDB
gpgcheck = 1
EOF
  sudo mv MariaDB.repo /etc/yum.repos.d/
  sudo yum install -y autoconf libtool cmake openssl-devel libcurl libcurl-devel libxml2 libxml2-devel readline readline-devel \
  libzip-devel libzip nginx openssl pkgconf zlib-devel bzip2 sqlite-libs sqlite-devel oniguruma oniguruma-devel libpq-devel \
  git curl tar  gcc-toolset-10-gcc gcc-toolset-10-gcc-c++ binutils wget  \
  initscripts httpd vim pcre pcre-devel pcre2-devel make net-snmp net-snmp-devel httpd-devel \
  git libxml2-devel libjpeg-devel libpng-devel freetype freetype-devel openldap openldap-devel \
  libevent-devel libyaml-devel perl-IPC-Run3 bzip2-devel curl-devel \
  enchant-devel gmp-devel krb5-devel postgresql-devel aspell-devel cyrus-sasl-devel libXpm-devel libxslt-devel \
  recode-devel  gdbm-devel libdb-devel automake patch pkgconfig perl-YAML-LibYAML perl-Path-Tiny \
  ncurses-devel boost-devel check-devel php-fpm perl-Test-Simple perl-Time-HiRes  pam-devel hostname unixODBC-devel \
  bison aspell MariaDB-server MariaDB-client mysql-devel |& tee -a "$LOG_FILE"
  sudo yum groupinstall -y 'Development Tools' |& tee -a "$LOG_FILE"
  buildCmocka |& tee -a "$LOG_FILE"
  buildPHP |& tee -a "$LOG_FILE"
  configureAndInstall |& tee -a "$LOG_FILE"
  ;;

"rhel-9.4" | "rhel-9.6")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  printf -- 'Installing the dependencies for Zabbix server from repository \n' |& tee -a "$LOG_FILE"
  sudo dnf install -y initscripts httpd tar wget curl vim gcc make net-snmp net-snmp-devel php-mysqlnd mysql-libs git \
        php libcurl-devel libxml2-devel php-xml php-gd php-bcmath php-mbstring php-ldap php-json libevent-devel unixODBC-devel \
        pcre-devel pcre2-devel policycoreutils-python-utils automake pkgconfig libcmocka-devel libyaml-devel perl-YAML-LibYAML \
        libpath_utils-devel perl-IPC-Run3 perl-Path-Tiny mariadb mariadb-server mysql-devel perl-Time-HiRes |& tee -a "$LOG_FILE"
  sudo yum groupinstall -y 'Development Tools' |& tee -a "$LOG_FILE"
  configureAndInstall |& tee -a "$LOG_FILE"
  ;;

"sles-15.6")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  printf -- 'Installing the dependencies for Zabbix server from repository \n' |& tee -a "$LOG_FILE"
  sudo zypper install -y wget tar curl vim gcc make net-snmp net-snmp-devel net-tools git apache2 apache2-devel mariadb \
        libmariadbd-devel apache2-mod_php8 php8 php8-mysql php8-xmlreader php8-xmlwriter php8-gd php8-bcmath php8-mbstring \
        php8-ctype php8-sockets php8-gettext libcurl-devel libxml2-2 libxml2-devel openldap2-devel php8-ldap unixODBC-devel \
        libevent-devel pcre-devel pcre2-devel awk gzip automake cmake libyaml-devel perl-YAML-LibYAML perl-Path-Tiny perl-IPC-Run3 \
        glibc-locale |& tee -a "$LOG_FILE"
  export LC_CTYPE="en_US.UTF-8"

  buildCmocka |& tee -a "$LOG_FILE"
  configureAndInstall |& tee -a "$LOG_FILE"
  ;;

"ubuntu-22.04") 
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  printf -- 'Installing the dependencies for Zabbix server from repository \n' |& tee -a "$LOG_FILE"
  sudo apt-get update >/dev/null
  sudo DEBIAN_FRONTEND=noninteractive apt-get -y install wget curl vim gcc make pkg-config snmp snmptrapd ceph locales libmariadbd-dev libxml2-dev \
        libsnmp-dev libcurl4 libcurl4-openssl-dev git apache2 php php-mysql libapache2-mod-php mysql-server php8.1-xml \
        php8.1-gd php-bcmath php-mbstring php8.1-ldap libevent-dev libpcre3-dev libpcre2-dev automake pkg-config libcmocka-dev unixodbc-dev \
        libyaml-dev libyaml-libyaml-perl libpath-tiny-perl libipc-run3-perl build-essential |& tee -a "$LOG_FILE"
  configureAndInstall |& tee -a "$LOG_FILE"
  ;;

"ubuntu-24.04")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  printf -- 'Installing the dependencies for Zabbix server from repository \n' |& tee -a "$LOG_FILE"
  sudo apt-get update >/dev/null
  sudo DEBIAN_FRONTEND=noninteractive apt-get -y install wget curl vim gcc make pkg-config snmp snmptrapd ceph locales libmariadbd-dev libxml2-dev \
      libsnmp-dev libcurl4 libcurl4-openssl-dev git apache2 php php-mysql libapache2-mod-php mysql-server php8.3-xml \
      php8.3-gd php-bcmath php-mbstring php8.3-ldap libevent-dev libpcre3-dev libpcre2-dev automake pkg-config libcmocka-dev unixodbc-dev \
      libyaml-dev libyaml-libyaml-perl libpath-tiny-perl libipc-run3-perl build-essential |& tee -a "$LOG_FILE"
  configureAndInstall |& tee -a "$LOG_FILE"
  ;;

"ubuntu-25.04")
  printf -- "Installing %s %s for %s (MySQL backend) \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  printf -- 'Installing the dependencies for Zabbix server with MySQL backend from repository \n' |& tee -a "$LOG_FILE"
  sudo apt-get update >/dev/null
  sudo DEBIAN_FRONTEND=noninteractive apt-get -y install wget curl vim gcc make pkg-config snmp snmptrapd ceph locales \
      default-libmysqlclient-dev libxml2-dev libsnmp-dev libcurl4 libcurl4-openssl-dev git apache2 php php-mysql \
      libapache2-mod-php mysql-server php8.4-xml php8.4-gd php-bcmath php-mbstring php8.4-ldap libevent-dev libpcre3-dev \
      libpcre2-dev automake pkg-config libcmocka-dev unixodbc-dev libyaml-dev libyaml-libyaml-perl libpath-tiny-perl \
      libipc-run3-perl build-essential |& tee -a "$LOG_FILE"

  configureAndInstall |& tee -a "$LOG_FILE"
  ;;

*)
  printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
  exit 1
  ;;
esac