#!/bin/bash
# © Copyright IBM Corporation 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Keystone/18.0.0/build_keystone.sh
# Execute build script: bash build_keystone.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="keystone"
PACKAGE_VERSION="18.0.0"
KEYSTONE_DBPASS="keystone"
KEYSTONE_HOST_IP="localhost"

CONF_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Keystone/${PACKAGE_VERSION}/conf"

export SOURCE_ROOT="$(pwd)"

TEST_USER="$(whoami)"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
    mkdir -p "$SOURCE_ROOT/logs/"
fi

if [ -f "/etc/os-release" ]; then
    source "/etc/os-release"
fi

DISTRO="$ID-$VERSION_ID"

function prepare()
{

    if [[ "$FORCE" == "true" ]]; then
        printf -- 'Force attribute provided hence continuing with install without confirmation message\n' | tee -a "$LOG_FILE"
    else
        printf -- 'As part of the installation, dependencies would be installed/upgraded.\n'
        while true; do
            read -r -p "Do you want to continue (y/n) ? :  " yn
            case $yn in
            [Yy]*)

                break
                ;;
            [Nn]*) exit ;;
            *) echo "Please provide correct input to proceed." ;;
            esac
        done
    fi
}

function cleanup() {
    printf -- '\nCleaned up the artifacts\n'
}

function setUpApache2HttpdConf() {
  case "$DISTRO" in
"ubuntu-18.04" | "ubuntu-20.04" | "ubuntu-20.10")
    echo "ServerName ${KEYSTONE_HOST_IP}" | sudo tee -a /etc/apache2/apache2.conf
    echo 'LoadModule wsgi_module /usr/local/lib/python3.6/dist-packages/mod_wsgi/server/mod_wsgi-py36.cpython-36m-s390x-linux-gnu.so' | sudo tee -a /etc/apache2/apache2.conf
    ;;

"rhel-7.8" | "rhel-7.9" | "rhel-8.1" | "rhel-8.2" | "rhel-8.3")
    echo "ServerName ${KEYSTONE_HOST_IP}" | sudo tee -a /etc/httpd/conf/httpd.conf
    echo 'Include /etc/httpd/sites-enabled/' | sudo tee -a /etc/httpd/conf/httpd.conf
    echo 'LoadModule wsgi_module /usr/local/lib64/python3.6/site-packages/mod_wsgi/server/mod_wsgi-py36.cpython-36m-s390x-linux-gnu.so' | sudo tee -a /etc/httpd/conf/httpd.conf
    ;;

"sles-12.5")
    echo "ServerName ${KEYSTONE_HOST_IP}" | sudo tee -a /etc/apache2/httpd.conf
    echo 'Include /etc/apache2/sites-enabled/' | sudo tee -a /etc/apache2/httpd.conf
    echo 'LoadModule wsgi_module /usr/lib64/apache2/mod_wsgi.so' | sudo tee -a /etc/apache2/httpd.conf

    sudo sed -i 's|Include /etc/apache2/sysconfig.d/include.conf|#Include /etc/apache2/sysconfig.d/include.conf|g' /etc/apache2/httpd.conf
    ;;

"sles-15.1" | "sles-15.2")
    echo "ServerName ${KEYSTONE_HOST_IP}" | sudo tee -a /etc/apache2/httpd.conf
    echo 'Include /etc/apache2/sites-enabled/' | sudo tee -a /etc/apache2/httpd.conf
    echo 'LoadModule wsgi_module /usr/lib64/python3.6/site-packages/mod_wsgi/server/mod_wsgi-py36.cpython-36m-s390x-linux-gnu.so' | sudo tee -a /etc/apache2/httpd.conf

    sudo sed -i 's|Include /etc/apache2/sysconfig.d/include.conf|#Include /etc/apache2/sysconfig.d/include.conf|g' /etc/apache2/httpd.conf
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" | tee -a "$LOG_FILE"
    exit 1
    ;;
esac
}

function setUpKeystoneConf() {
  cd "${SOURCE_ROOT}"
  case "$DISTRO" in
"ubuntu-18.04" | "ubuntu-20.04" | "ubuntu-20.10")
    curl -SL -k -o wsgi-keystone.conf $CONF_URL/ubuntu-wsgi-keystone.conf
    sudo mv wsgi-keystone.conf /etc/apache2/sites-available/
    sudo ln -s /etc/apache2/sites-available/wsgi-keystone.conf /etc/apache2/sites-enabled
    ;;

"rhel-7.8" | "rhel-7.9" | "rhel-8.1" | "rhel-8.2" | "rhel-8.3")
    sudo mkdir -p /etc/httpd/sites-available
    sudo mkdir -p /etc/httpd/sites-enabled
    curl -SL -k -o wsgi-keystone.conf $CONF_URL/rhel-wsgi-keystone.conf
    sudo mv wsgi-keystone.conf /etc/httpd/sites-available/
    sudo ln -s /etc/httpd/sites-available/wsgi-keystone.conf /etc/httpd/sites-enabled
    ;;

"sles-12.5" | "sles-15.1" | "sles-15.2")
    sudo mkdir -p /etc/apache2/sites-available
    sudo mkdir -p /etc/apache2/sites-enabled
    curl -SL -k -o wsgi-keystone.conf $CONF_URL/sles-wsgi-keystone.conf
    sudo mv wsgi-keystone.conf /etc/apache2/sites-available/
    sudo ln -s /etc/apache2/sites-available/wsgi-keystone.conf /etc/apache2/sites-enabled
    ;;

*)
    printf -- "%s not supported \n" "$DISTRO" | tee -a "$LOG_FILE"
    exit 1
    ;;
esac
}

function runCheck() {
    set +e

    if [[ "$TESTS" == "true" ]]; then
        export OS_USERNAME=admin
        export OS_PASSWORD=ADMIN_PASS
        export OS_PROJECT_NAME=admin
        export OS_USER_DOMAIN_NAME=Default
        export OS_PROJECT_DOMAIN_NAME=Default
        export OS_AUTH_URL=http://localhost:35357/v3
        export OS_IDENTITY_API_VERSION=3

        openstack service list 
        openstack token issue 
        printf -- '\n Verification Completed !! \n'
    fi

    set -e
}

function configureAndInstall() {
    printf -- 'User responded with Yes. \n'

    printf -- '\nConfiguration and Installation started \n'


    #Installing dependencies

    printf -- 'Building dependencies\n'

    if [[ "${ID}" == "rhel" ]] || [[ "${ID}" == "sles" ]]; then
       sudo /usr/bin/mysql_install_db --user=mysql
    fi

    if [[ "${ID}" == "ubuntu" ]]; then
      sudo mkdir -p /var/lib/mysql/data
      sudo chown -R mysql:mysql /var/lib/mysql/data
      sudo /usr/sbin/mysqld --initialize --user=mysql --datadir=/var/lib/mysql/data

      sudo mkdir -p /var/log/mysql
      sudo mkdir -p /var/run/mysqld
      sudo chown -R mysql:mysql /var/run/mysqld
    fi

    nohup sudo /usr/bin/mysqld_safe --user=mysql &>/dev/null &

    sleep 5

    sudo mysql -e "CREATE DATABASE keystone"
    sudo mysql -e "CREATE USER 'keystone'@'localhost' IDENTIFIED BY '${KEYSTONE_DBPASS}'"
    sudo mysql -e "CREATE USER 'keystone'@'%' IDENTIFIED BY '${KEYSTONE_DBPASS}'"
    sudo mysql -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%'"
    sudo mysql -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost'"

    cd "${SOURCE_ROOT}"
    printf -- '\nDownloading Keystone source. \n'
    git clone https://github.com/openstack/keystone.git
    cd keystone/
    git checkout ${PACKAGE_VERSION}
    printf -- '\nKeystone download completed successfully. \n'

    printf -- '\nStarting Keystone install. \n'
    sudo pip3 install --ignore-installed -r requirements.txt
    sudo pip3 install --ignore-installed -r test-requirements.txt
    sudo python3 setup.py install

    if [[ "${ID}" == "rhel" ]]; then
      sudo env PATH=$PATH tox -egenconfig
    else
      sudo tox -egenconfig
    fi

    printf -- '\nKeystone install completed successfully. \n'

    printf -- '\nStarting Keystone configure. \n'
    sudo cp -r etc/ /etc/keystone
    cd /etc/keystone/
    sudo mv keystone.conf.sample keystone.conf
    sudo mv logging.conf.sample logging.conf
    export OS_KEYSTONE_CONFIG_DIR=/etc/keystone
    printf -- '\nKeystone configuration completed successfully. \n'


    sudo sed -i "s|#connection = <None>|connection = mysql://keystone:${KEYSTONE_DBPASS}@localhost/keystone|g" /etc/keystone/keystone.conf
    sudo sed -i "s|#provider = fernet|provider = fernet|g" /etc/keystone/keystone.conf

    printf -- '\nPopulating Keystone DB. \n'
    keystone-manage db_sync

    printf -- '\nInitializing fernet key repo. \n'
    sudo groupadd keystone
    sudo useradd -m -g keystone keystone
    sudo mkdir -p /etc/keystone/fernet-keys
    sudo chown -R keystone:keystone fernet-keys

    if [[ "${ID}" == "rhel" ]]; then
      sudo env PATH=$PATH keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
      sudo env PATH=$PATH keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
    else
      sudo keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
      sudo keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
    fi

    printf -- '\nBootstrapping identity service. \n'
    keystone-manage bootstrap --bootstrap-password ADMIN_PASS \
      --bootstrap-admin-url http://${KEYSTONE_HOST_IP}:35357/v3/ \
      --bootstrap-internal-url http://${KEYSTONE_HOST_IP}:5000/v3/ \
      --bootstrap-public-url http://${KEYSTONE_HOST_IP}:5000/v3/ \
      --bootstrap-region-id RegionOne


    setUpApache2HttpdConf
    setUpKeystoneConf

    if [[ "${ID}" == "ubuntu" ]]; then
      sudo service apache2 restart
    else
      nohup sudo /usr/sbin/httpd &>/dev/null &
    fi

    export OS_USERNAME=admin
    export OS_PASSWORD=ADMIN_PASS
    export OS_PROJECT_NAME=admin
    export OS_USER_DOMAIN_NAME=Default
    export OS_PROJECT_DOMAIN_NAME=Default
    export OS_AUTH_URL=http://${KEYSTONE_HOST_IP}:35357/v3
    export OS_IDENTITY_API_VERSION=3

    if [[ "${ID}" == "rhel" ]]; then
      sudo ln -s /usr/local/bin/keystone-wsgi-admin /bin/
      sudo ln -s /usr/local/bin/keystone-wsgi-public /bin/
    fi

    # Run Check
    runCheck
}

function logDetails() {
    printf -- 'SYSTEM DETAILS\n' >"$LOG_FILE"
    if [ -f "/etc/os-release" ]; then
        cat "/etc/os-release" >>"$LOG_FILE"
    fi

    cat /proc/version >>"$LOG_FILE"
    printf -- "\nDetected %s \n" "$PRETTY_NAME"
    printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" | tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
    echo
    echo "Usage: "
    echo "  build_keystone.sh  [-d debug] [-y install-without-confirmation] [-t run-check-after]"
    echo
}

function printSummary() {

    printf -- '\n********************************************************************************************************\n'
    printf -- "\n* Getting Started * \n"
    printf -- "\nTo run commands locally set the following:\n"
    printf -- "\nexport OS_USERNAME=admin"
    printf -- "\nexport OS_PASSWORD=ADMIN_PASS"
    printf -- "\nexport OS_PROJECT_NAME=admin"
    printf -- "\nexport OS_USER_DOMAIN_NAME=Default"
    printf -- "\nexport OS_PROJECT_DOMAIN_NAME=Default"
    printf -- "\nexport OS_AUTH_URL=http://localhost:35357/v3"
    printf -- "\nexport OS_IDENTITY_API_VERSION=3\n"
    printf -- "\nRun openstack --help for a full list of available commands\n"
    printf -- '\nFor more information on Keystone please visit http://docs.openstack.org/developer/keystone/installing.html \n\n'
    printf -- '**********************************************************************************************************\n'
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
        if [ -d "/etc/keystone" ]; then
            printf -- "%s is detected in the system. Skipping build and running check .\n" "$PACKAGE_NAME" | tee -a "$LOG_FILE"
            TESTS="true"
            runCheck
            printSummary
            exit 0
        else
            TESTS="true"
        fi

        ;;
    esac
done

logDetails
prepare

case "$DISTRO" in
"ubuntu-18.04" | "ubuntu-20.04" | "ubuntu-20.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
    sudo apt-get update
    sudo apt-get install -y libpq-dev build-essential libncurses-dev libapache2-mod-wsgi-py3 git wget cmake \
      gcc make tar libpcre3-dev bison scons libboost-dev libboost-program-options-dev openssl dh-autoreconf \
      libssl-dev python3-setuptools python3-lxml curl python3-ldap python3-dev libxslt-dev net-tools libffi-dev \
      apache2-dev python3-mysqldb apache2 mysql-server python3-pkgconfig libsasl2-dev zlib1g-dev ed patch python3-pip

    sudo pip3 install --upgrade setuptools
    sudo pip3 install six tox cryptography mod_wsgi python-memcached python-openstackclient requests pika

    configureAndInstall | tee -a "$LOG_FILE"

    ;;

"rhel-7.8" | "rhel-7.9")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

    sudo yum install -y gcc git python3-setuptools curl sqlite-devel openldap-devel python3-devel libxslt-devel \
      net-tools libffi-devel which httpd httpd-devel mariadb-server postgresql-devel mariadb-devel bzip2-devel \
      patch python3-pip make redhat-rpm-config wget

    cd $SOURCE_ROOT
    wget --no-check-certificate https://www.openssl.org/source/old/1.1.1/openssl-1.1.1g.tar.gz
    tar -xzvf openssl-1.1.1g.tar.gz
    cd openssl-1.1.1g
    ./config --prefix=/usr --openssldir=/usr
    make
    sudo make install

    sudo pip3 install --upgrade setuptools
    sudo pip3 install --ignore-installed ipaddress wheel
    sudo pip3 install six==1.11 tox cryptography mod_wsgi python-memcached python-openstackclient requests pika==0.10.0 mysqlclient==2.0.1

    configureAndInstall | tee -a "$LOG_FILE"

    ;;

"rhel-8.1" | "rhel-8.2" | "rhel-8.3")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

    sudo yum install -y gcc git python3-setuptools python3-lxml curl python3-ldap sqlite-devel openldap-devel \
      python3-devel libxslt-devel openssl-devel net-tools libffi-devel which openssl httpd httpd-devel mariadb-server \
      postgresql-devel mariadb-devel bzip2-devel patch python3-pip make redhat-rpm-config

    sudo pip3 install --upgrade setuptools
    sudo pip3 install --ignore-installed ipaddress wheel
    sudo pip3 install six==1.11 tox cryptography mod_wsgi python-memcached python-openstackclient requests pika==0.10.0 mysqlclient

    configureAndInstall | tee -a "$LOG_FILE"

    ;;

"sles-12.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

    sudo zypper install -y gcc gcc-c++ gdbm-devel git-core curl openldap2-devel libbz2-devel libdb-4_8-devel \
      libffi-devel libffi48-devel libxslt-devel which apache2 apache2-devel libuuid-devel ncurses-devel readline-devel \
      sqlite3-devel tk-devel xz-devel zlib-devel apache2-mod_wsgi mariadb postgresql-devel make cyrus-sasl-devel \
      net-tools libpcre1 libmysqlclient-devel gawk patch wget tar

    cd $SOURCE_ROOT
    wget --no-check-certificate https://www.openssl.org/source/old/1.1.1/openssl-1.1.1g.tar.gz
    tar -xzvf openssl-1.1.1g.tar.gz
    cd openssl-1.1.1g
    ./config --prefix=/usr --openssldir=/usr
    make
    sudo make install

    cd $SOURCE_ROOT
    wget --no-check-certificate "https://www.python.org/ftp/python/3.8.5/Python-3.8.5.tgz"
    tar -xzvf "Python-3.8.5.tgz"
    cd Python-3.8.5/
    ./configure --prefix=/usr
    make
    sudo make install

    cd $SOURCE_ROOT
    wget --no-check-certificate https://github.com/GrahamDumpleton/mod_wsgi/archive/4.7.1.tar.gz
    tar -xzvf 4.7.1.tar.gz
    cd mod_wsgi-4.7.1/
    ./configure --with-apxs=/usr/bin/apxs2 --with-python=/usr/bin/python3
    make
    sudo make install

    sudo ln -fs /usr/lib/libpq.so.5 /usr/lib/libpq.so
    sudo ln -fs /usr/lib64/libpq.so.5 /usr/lib64/libpq.so
    sudo pip3 install --upgrade setuptools
    sudo pip3 install six tox cryptography mod_wsgi python-memcached python-openstackclient requests pika mysqlclient==2.0.1

    configureAndInstall | tee -a "$LOG_FILE"

    ;;

"sles-15.1" | "sles-15.2")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

    sudo zypper install -y wget tar gzip gcc git-core curl openldap2-devel libffi-devel python3-devel libxslt-devel which apache2 \
      apache2-devel mariadb postgresql-devel make cyrus-sasl-devel python3-setuptools python3-lxml openssl \
      openssl-devel net-tools libpcre1 libmariadb-devel gawk patch python3-pip postgresql12-server-devel

    if [[ "${DISTRO}" == "sles-15.1" ]]; then
        git config --global http.sslVerify false
        cd $SOURCE_ROOT
        wget --no-check-certificate https://www.openssl.org/source/old/1.1.1/openssl-1.1.1g.tar.gz
        tar -xzvf openssl-1.1.1g.tar.gz
        cd openssl-1.1.1g
        ./config --prefix=/usr --openssldir=/usr
        make
        sudo make install
    fi

    sudo ln -fs /usr/lib/libpq.so.5 /usr/lib/libpq.so
    sudo ln -fs /usr/lib64/libpq.so.5 /usr/lib64/libpq.so
    sudo pip3 install --upgrade pip
    sudo pip3 install --upgrade setuptools
    sudo pip3 install six==1.11 tox cryptography mod_wsgi python-memcached python-openstackclient requests pika==0.10.0 mysqlclient python-ldap

    configureAndInstall | tee -a "$LOG_FILE"

    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" | tee -a "$LOG_FILE"
    exit 1
    ;;
esac

printSummary | tee -a "$LOG_FILE"
