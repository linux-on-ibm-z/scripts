#!/bin/bash
# © Copyright IBM Corporation 2022.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Keystone/22.0.0/build_keystone.sh
# Execute build script: bash build_keystone.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="keystone"
PACKAGE_VERSION="22.0.0"
KEYSTONE_DBPASS="keystone"
KEYSTONE_HOST_IP="localhost"

CONF_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Keystone/22.0.0/conf"

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
    if [[ "${DISTRO}" == "rhel-8."* || "${DISTRO}" == "rhel-9."* ]]; then
      echo "ServerName ${KEYSTONE_HOST_IP}" | sudo tee -a /etc/httpd/conf/httpd.conf
      echo 'Include /etc/httpd/sites-enabled/' | sudo tee -a /etc/httpd/conf/httpd.conf
      echo 'LoadModule wsgi_module /usr/local/lib64/python3.9/site-packages/mod_wsgi/server/mod_wsgi-py39.cpython-39-s390x-linux-gnu.so' | sudo tee -a /etc/httpd/conf/httpd.conf
    elif [[ "${DISTRO}" == "sles-15.4" ]]; then
      echo "ServerName ${KEYSTONE_HOST_IP}" | sudo tee -a /etc/apache2/httpd.conf
      echo 'Include /etc/apache2/sites-enabled/' | sudo tee -a /etc/apache2/httpd.conf
      echo 'LoadModule wsgi_module /usr/local/lib64/python3.10/site-packages/mod_wsgi/server/mod_wsgi-py310.cpython-310-s390x-linux-gnu.so' | sudo tee -a /etc/apache2/httpd.conf
    fi
}

function setUpKeystoneConf() {
  cd "${SOURCE_ROOT}"
  if [[ "${DISTRO}" == "rhel-8."* || "${DISTRO}" == "rhel-9."* ]]; then
      sudo mkdir -p /etc/httpd/sites-available
      sudo mkdir -p /etc/httpd/sites-enabled
      curl -SL -k -o wsgi-keystone.conf $CONF_URL/rhel-wsgi-keystone.conf
      sudo mv wsgi-keystone.conf /etc/httpd/sites-available/
      sudo ln -s /etc/httpd/sites-available/wsgi-keystone.conf /etc/httpd/sites-enabled
  elif [[ "${DISTRO}" == "sles-15.4" ]]; then
      sudo mkdir -p /etc/apache2/sites-available
      sudo mkdir -p /etc/apache2/sites-enabled
      sudo curl -SL -k -o wsgi-keystone.conf $CONF_URL/sles-wsgi-keystone.conf
      sudo mv wsgi-keystone.conf /etc/apache2/sites-available/
      sudo ln -s /etc/apache2/sites-available/wsgi-keystone.conf /etc/apache2/sites-enabled
  fi
}

function runCheck() {
    set +e

    if [[ "$TESTS" == "true" ]]; then

        export OS_USERNAME=admin
        export OS_PASSWORD=ADMIN_PASS
        export OS_PROJECT_NAME=admin
        export OS_USER_DOMAIN_NAME=Default
        export OS_PROJECT_DOMAIN_NAME=Default
        export OS_AUTH_URL=http://${KEYSTONE_HOST_IP}:5000/v3
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


    #Starting MySQL
    printf -- 'Starting MySQL Server\n'

    if [[ "${DISTRO}" == "rhel-8."* ]] || [[ "${DISTRO}" == "sles-15.4" ]]; then
       sudo /usr/bin/mysql_install_db --user=mysql
    fi

    if [[ "${DISTRO}" == "rhel-8."* ]] || [[ "${DISTRO}" == "sles-15.4" ]]; then
       nohup sudo /usr/bin/mysqld_safe --user=mysql &>/dev/null &
    else
       nohup sudo mysqld_safe &>/dev/null &
    fi 

    sleep 5

    sudo mysql -e "CREATE DATABASE keystone"
    sudo mysql -e "CREATE USER 'keystone'@'localhost' IDENTIFIED BY '${KEYSTONE_DBPASS}'"
    sudo mysql -e "CREATE USER 'keystone'@'%' IDENTIFIED BY '${KEYSTONE_DBPASS}'"
    sudo mysql -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%'"
    sudo mysql -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost'"

    printf -- '\nKeystone install completed successfully. \n'

    printf -- '\nStarting Keystone configure. \n'
    sudo mkdir -p /etc/keystone/
    cd /etc/keystone/
    sudo wget -O keystone.conf https://docs.openstack.org/keystone/yoga/_static/keystone.conf.sample
    export OS_KEYSTONE_CONFIG_DIR=/etc/keystone
    printf -- '\nKeystone configuration completed successfully. \n'

    sudo sed -i "s|#connection = <None>|connection = mysql://keystone:${KEYSTONE_DBPASS}@localhost/keystone|g" /etc/keystone/keystone.conf
    sudo sed -i "s|#provider = fernet|provider = fernet|g" /etc/keystone/keystone.conf

    printf -- '\nPopulating Keystone DB. \n'
    if [[ "${DISTRO}" == "rhel-8."* || "${DISTRO}" == "rhel-9."* ]]; then
     sudo env PATH=$PATH keystone-manage db_sync
    else
     sudo keystone-manage db_sync
    fi

    printf -- '\nInitializing fernet key repo & Bootstrapping identity service. \n'
    sudo groupadd keystone
    sudo useradd -m -g keystone keystone
    sudo mkdir -p /etc/keystone/fernet-keys
   
    sudo chown -R keystone:keystone /etc/keystone/fernet-keys

    if [[ "${DISTRO}" == "rhel-8."* || "${DISTRO}" == "rhel-9."* ]]; then
      sudo env PATH=$PATH keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
      sudo env PATH=$PATH keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
      
      # Bootstrapping identity service
      sudo env PATH=$PATH keystone-manage bootstrap \
      --bootstrap-password ADMIN_PASS \
      --bootstrap-admin-url http://${KEYSTONE_HOST_IP}:35357/v3/ \
      --bootstrap-internal-url http://${KEYSTONE_HOST_IP}:5000/v3/ \
      --bootstrap-public-url http://${KEYSTONE_HOST_IP}:5000/v3/ \
      --bootstrap-region-id RegionOne
    else
      sudo keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
      sudo keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
      
      # Bootstrapping identity service
      sudo keystone-manage bootstrap \
      --bootstrap-password ADMIN_PASS \
      --bootstrap-admin-url http://${KEYSTONE_HOST_IP}:35357/v3/ \
      --bootstrap-internal-url http://${KEYSTONE_HOST_IP}:5000/v3/ \
      --bootstrap-public-url http://${KEYSTONE_HOST_IP}:5000/v3/ \
      --bootstrap-region-id RegionOne
    fi

    setUpApache2HttpdConf
    setUpKeystoneConf

    if [[ "${ID}" != "ubuntu" ]]; then
      nohup sudo /usr/sbin/httpd &>/dev/null &
    else
      nohup sudo uwsgi --http-socket 127.0.0.1:5000 --plugin /usr/lib/uwsgi/plugins/python3_plugin.so --wsgi-file $(which keystone-wsgi-public) &>/dev/null &
      sleep 60s
    fi

    export OS_USERNAME=admin
    export OS_PASSWORD=ADMIN_PASS
    export OS_PROJECT_NAME=admin
    export OS_USER_DOMAIN_NAME=Default
    export OS_PROJECT_DOMAIN_NAME=Default
    export OS_AUTH_URL=http://${KEYSTONE_HOST_IP}:5000/v3
    export OS_IDENTITY_API_VERSION=3

    if [[ "${ID}" == "rhel" ]]; then
      sudo ln -s /usr/local/bin/keystone-wsgi-admin /bin/
      sudo ln -s /usr/local/bin/keystone-wsgi-public /bin/
    fi

    # Run Check
    runCheck
}

function installRustc() {

	cd $SOURCE_ROOT
	wget https://static.rust-lang.org/dist/rust-1.63.0-s390x-unknown-linux-gnu.tar.gz
	tar -xzf rust-1.63.0-s390x-unknown-linux-gnu.tar.gz
	cd rust-1.63.0-s390x-unknown-linux-gnu
	sudo ./install.sh
	export PATH=$HOME/.cargo/bin:$PATH
	rustc -V
	cargo  -V

}

function installOpenSSL() {

	cd $SOURCE_ROOT
	wget https://www.openssl.org/source/old/1.1.1/openssl-1.1.1l.tar.gz
	tar -xf openssl-1.1.1l.tar.gz
	cd openssl-1.1.1l/
	./config shared enable-ec_nistp_64_gcc_128 -Wl,-rpath=/usr/local/ssl/lib --prefix=/usr/local/ssl
	make -j $(nproc)
	sudo make install
	hash -r
	sudo ln -sf /usr/local/ssl/bin/openssl /usr/local/bin/openssl
	sudo mv /usr/bin/openssl /usr/bin/openssl_ORIG
	sudo ln -sf /usr/local/ssl/bin/openssl /usr/bin/openssl
	openssl version

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
    echo " bash build_keystone.sh  [-d debug] [-y install-without-confirmation] [-t run-check-after]"
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
    printf -- "\nexport OS_AUTH_URL=http://localhost:5000/v3"
    printf -- "\nexport OS_IDENTITY_API_VERSION=3\n"
    printf -- "\nRun openstack --help for a full list of available commands\n"
    printf -- "\nFor more information on Keystone please visit http://docs.openstack.org/developer/keystone/installing.html \n\n"
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
"ubuntu-20.04" | "ubuntu-22.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

    sudo apt-get update
    sudo apt-get install -y python3-pip libffi-dev  mysql-server libmysqlclient-dev libapache2-mod-wsgi-py3 apache2  apache2-dev wget curl uwsgi-plugin-python3
    installRustc

    sudo -H pip3 install --upgrade pip
    sudo pip3 install alembic==1.8.1 amqp==5.1.1 aniso8601==9.0.1 appdirs==1.4.4 attrs==22.1.0 autopage==0.5.1 bcrypt==4.0.1 cachetools==5.2.0 certifi==2022.9.24 cffi==1.15.1 charset-normalizer==2.1.1 click==8.1.3 cliff==4.0.0 cmd2==2.4.2 cryptography debtcollector==2.5.0 decorator==5.1.1 defusedxml==0.7.1 dnspython==2.2.1 dogpile.cache==1.1.8 elementpath==3.0.2 eventlet==0.33.1 extras==1.0.0 fasteners==0.18 fixtures==4.0.1 Flask==2.1.0 Flask-RESTful==0.3.9 futurist==2.4.1 greenlet==2.0.1 idna==3.4 importlib-metadata==5.0.0 iso8601==1.1.0 itsdangerous==2.1.2 Jinja2==3.0.0 jmespath==1.0.1 jsonpatch==1.32 jsonpointer==2.3 jsonschema==4.17.0 keystone==22.0.0 keystoneauth1==5.0.0 keystonemiddleware==10.1.0 kombu==5.2.4 Mako==1.2.4 MarkupSafe==2.1.1 mod-wsgi==4.9.4 msgpack==1.0.4 munch==2.5.0 mysqlclient==2.1.1 netaddr==0.8.0 netifaces==0.11.0 oauthlib==3.2.2 openstacksdk==0.102.0 os-service-types==1.7.0 osc-lib==2.6.2 oslo.cache==3.3.0 oslo.concurrency==5.0.1 oslo.config==9.0.0 oslo.context==5.0.0 oslo.db==12.2.0 oslo.i18n==5.1.0 oslo.log==5.0.2 oslo.messaging==14.0.0 oslo.metrics==0.5.0 oslo.middleware==5.0.0 oslo.policy==4.0.0 oslo.serialization==5.0.0 oslo.service==3.0.0 oslo.upgradecheck==2.0.0 oslo.utils==6.0.1 osprofiler==3.4.3 packaging==21.3 passlib==1.7.4 Paste==3.5.2 PasteDeploy==3.0.1 pbr==5.11.0 prettytable==3.5.0 prometheus-client==0.15.0 pycadf==3.1.1 pycparser==2.21 pyinotify==0.9.6 PyJWT==2.6.0 pyOpenSSL==23.0.0 pyparsing==3.0.9 pyperclip==1.8.2 pyrsistent==0.19.2 pysaml2==7.2.1 python-cinderclient==9.1.0 python-dateutil==2.8.2 python-keystoneclient==5.0.1 python-novaclient==18.1.0 python-openstackclient==6.0.0 pytz==2022.6 PyYAML==6.0 repoze.lru==0.7 requests==2.28.1 requestsexceptions==1.4.0 rfc3986==2.0.0 Routes==2.5.1 scrypt==0.8.20 simplejson==3.18.0 six==1.16.0 SQLAlchemy==1.4.44 sqlalchemy-migrate==0.13.0 sqlparse==0.4.3 statsd==4.0.1 stevedore==4.1.1 Tempita==0.5.2 testresources==2.0.1 testscenarios==0.5.0 testtools==2.5.0 urllib3==1.26.12 vine==5.0.0 wcwidth==0.2.5 WebOb==1.8.7 Werkzeug==2.2.2 wrapt==1.14.1 xmlschema==2.1.1 yappi==1.4.0 zipp==3.10.0 uwsgi --ignore-installed
    configureAndInstall | tee -a "$LOG_FILE"
    ;;

"rhel-8.4" | "rhel-8.6" | "rhel-8.7")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

    sudo yum install -y python39-devel libffi-devel curl wget openssl-devel gcc make gcc-c++ python39-mod_wsgi httpd httpd-devel mariadb-server procps sqlite-devel python39-pip perl mariadb-devel mariadb-server
    installRustc

    sudo -H env PATH=$PATH pip3 install --upgrade pip
    sudo -E env PATH=$PATH pip3 install alembic==1.8.1 amqp==5.1.1 aniso8601==9.0.1 appdirs==1.4.4 attrs==22.1.0 autopage==0.5.1 bcrypt==4.0.1 cachetools==5.2.0 certifi==2022.9.24 cffi==1.15.1 charset-normalizer==2.1.1 click==8.1.3 cliff==4.0.0 cmd2==2.4.2 cryptography debtcollector==2.5.0 decorator==5.1.1 defusedxml==0.7.1 dnspython==2.2.1 dogpile.cache==1.1.8 elementpath==3.0.2 eventlet==0.33.1 extras==1.0.0 fasteners==0.18 fixtures==4.0.1 Flask==2.1.0 Flask-RESTful==0.3.9 futurist==2.4.1 greenlet==2.0.1 idna==3.4 importlib-metadata==5.0.0 iso8601==1.1.0 itsdangerous==2.1.2 Jinja2==3.0.0 jmespath==1.0.1 jsonpatch==1.32 jsonpointer==2.3 jsonschema==4.17.0 keystone==22.0.0 keystoneauth1==5.0.0 keystonemiddleware==10.1.0 kombu==5.2.4 Mako==1.2.4 MarkupSafe==2.1.1 mod-wsgi==4.9.4 msgpack==1.0.4 munch==2.5.0 mysqlclient==2.1.1 netaddr==0.8.0 netifaces==0.11.0 oauthlib==3.2.2 openstacksdk==0.102.0 os-service-types==1.7.0 osc-lib==2.6.2 oslo.cache==3.3.0 oslo.concurrency==5.0.1 oslo.config==9.0.0 oslo.context==5.0.0 oslo.db==12.2.0 oslo.i18n==5.1.0 oslo.log==5.0.2 oslo.messaging==14.0.0 oslo.metrics==0.5.0 oslo.middleware==5.0.0 oslo.policy==4.0.0 oslo.serialization==5.0.0 oslo.service==3.0.0 oslo.upgradecheck==2.0.0 oslo.utils==6.0.1 osprofiler==3.4.3 packaging==21.3 passlib==1.7.4 Paste==3.5.2 PasteDeploy==3.0.1 pbr==5.11.0 prettytable==3.5.0 prometheus-client==0.15.0 pycadf==3.1.1 pycparser==2.21 pyinotify==0.9.6 PyJWT==2.6.0 pyOpenSSL==23.0.0 pyparsing==3.0.9 pyperclip==1.8.2 pyrsistent==0.19.2 pysaml2==7.2.1 python-cinderclient==9.1.0 python-dateutil==2.8.2 python-keystoneclient==5.0.1 python-novaclient==18.1.0 python-openstackclient==6.0.0 pytz==2022.6 PyYAML==6.0 repoze.lru==0.7 requests==2.28.1 requestsexceptions==1.4.0 rfc3986==2.0.0 Routes==2.5.1 scrypt==0.8.20 simplejson==3.18.0 six==1.16.0 SQLAlchemy==1.4.44 sqlalchemy-migrate==0.13.0 sqlparse==0.4.3 statsd==4.0.1 stevedore==4.1.1 Tempita==0.5.2 testresources==2.0.1 testscenarios==0.5.0 testtools==2.5.0 urllib3==1.26.12 vine==5.0.0 wcwidth==0.2.5 WebOb==1.8.7 Werkzeug==2.2.2 wrapt==1.14.1 xmlschema==2.1.1 yappi==1.4.0 zipp==3.10.0 uwsgi --ignore-installed
    configureAndInstall | tee -a "$LOG_FILE"
    ;;

"rhel-9.0" | "rhel-9.1")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

    sudo yum install -y python3-devel libffi-devel cargo curl wget openssl-devel gcc make gcc-c++ python3-mod_wsgi httpd httpd-devel procps sqlite-devel python3-pip perl
    
    echo "[mariadb]" | sudo tee -a /etc/yum.repos.d/MariaDB.repo
    echo "name = MariaDB-10.11.2" | sudo tee -a /etc/yum.repos.d/MariaDB.repo
    echo "baseurl=http://mirror.mariadb.org/mariadb-10.11.2/yum/rhel9-s390x" | sudo tee -a /etc/yum.repos.d/MariaDB.repo
    echo "gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB" | sudo tee -a /etc/yum.repos.d/MariaDB.repo
    echo "gpgcheck=1" | sudo tee -a /etc/yum.repos.d/MariaDB.repo

    #Install MariaDB
    sudo yum install -y MariaDB-devel mariadb-server
    installOpenSSL

    sudo -H env PATH=$PATH pip3 install --upgrade pip
    sudo -E env PATH=$PATH pip3 install alembic==1.8.1 amqp==5.1.1 aniso8601==9.0.1 appdirs==1.4.4 attrs==22.1.0 autopage==0.5.1 bcrypt==4.0.1 cachetools==5.2.0 certifi==2022.9.24 cffi==1.15.1 charset-normalizer==2.1.1 click==8.1.3 cliff==4.0.0 cmd2==2.4.2 cryptography debtcollector==2.5.0 decorator==5.1.1 defusedxml==0.7.1 dnspython==2.2.1 dogpile.cache==1.1.8 elementpath==3.0.2 eventlet==0.33.1 extras==1.0.0 fasteners==0.18 fixtures==4.0.1 Flask==2.1.0 Flask-RESTful==0.3.9 futurist==2.4.1 greenlet==2.0.1 idna==3.4 importlib-metadata==5.0.0 iso8601==1.1.0 itsdangerous==2.1.2 Jinja2==3.0.0 jmespath==1.0.1 jsonpatch==1.32 jsonpointer==2.3 jsonschema==4.17.0 keystone==22.0.0 keystoneauth1==5.0.0 keystonemiddleware==10.1.0 kombu==5.2.4 Mako==1.2.4 MarkupSafe==2.1.1 mod-wsgi==4.9.4 msgpack==1.0.4 munch==2.5.0 mysqlclient==2.1.1 netaddr==0.8.0 netifaces==0.11.0 oauthlib==3.2.2 openstacksdk==0.102.0 os-service-types==1.7.0 osc-lib==2.6.2 oslo.cache==3.3.0 oslo.concurrency==5.0.1 oslo.config==9.0.0 oslo.context==5.0.0 oslo.db==12.2.0 oslo.i18n==5.1.0 oslo.log==5.0.2 oslo.messaging==14.0.0 oslo.metrics==0.5.0 oslo.middleware==5.0.0 oslo.policy==4.0.0 oslo.serialization==5.0.0 oslo.service==3.0.0 oslo.upgradecheck==2.0.0 oslo.utils==6.0.1 osprofiler==3.4.3 packaging==21.3 passlib==1.7.4 Paste==3.5.2 PasteDeploy==3.0.1 pbr==5.11.0 prettytable==3.5.0 prometheus-client==0.15.0 pycadf==3.1.1 pycparser==2.21 pyinotify==0.9.6 PyJWT==2.6.0 pyOpenSSL==23.0.0 pyparsing==3.0.9 pyperclip==1.8.2 pyrsistent==0.19.2 pysaml2==7.2.1 python-cinderclient==9.1.0 python-dateutil==2.8.2 python-keystoneclient==5.0.1 python-novaclient==18.1.0 python-openstackclient==6.0.0 pytz==2022.6 PyYAML==6.0 repoze.lru==0.7 requests==2.28.1 requestsexceptions==1.4.0 rfc3986==2.0.0 Routes==2.5.1 scrypt==0.8.20 simplejson==3.18.0 six==1.16.0 SQLAlchemy==1.4.44 sqlalchemy-migrate==0.13.0 sqlparse==0.4.3 statsd==4.0.1 stevedore==4.1.1 Tempita==0.5.2 testresources==2.0.1 testscenarios==0.5.0 testtools==2.5.0 urllib3==1.26.12 vine==5.0.0 wcwidth==0.2.5 WebOb==1.8.7 Werkzeug==2.2.2 wrapt==1.14.1 xmlschema==2.1.1 yappi==1.4.0 zipp==3.10.0 uwsgi --ignore-installed
    configureAndInstall | tee -a "$LOG_FILE"
    ;;

"sles-15.4")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

    sudo zypper install -y libopenssl-devel libffi-devel gcc make python310-devel python310-pip gawk apache2 apache2-devel mariadb libmariadb-devel gcc-c++ cargo curl wget
	
    sudo -H pip3 install --upgrade pip
    sudo pip3 install alembic==1.8.1 amqp==5.1.1 aniso8601==9.0.1 appdirs==1.4.4 attrs==22.1.0 autopage==0.5.1 bcrypt==4.0.1 cachetools==5.2.0 certifi==2022.9.24 cffi==1.15.1 charset-normalizer==2.1.1 click==8.1.3 cliff==4.0.0 cmd2==2.4.2 cryptography debtcollector==2.5.0 decorator==5.1.1 defusedxml==0.7.1 dnspython==2.2.1 dogpile.cache==1.1.8 elementpath==3.0.2 eventlet==0.33.1 extras==1.0.0 fasteners==0.18 fixtures==4.0.1 Flask==2.1.0 Flask-RESTful==0.3.9 futurist==2.4.1 greenlet==2.0.1 idna==3.4 importlib-metadata==5.0.0 iso8601==1.1.0 itsdangerous==2.1.2 Jinja2==3.0.0 jmespath==1.0.1 jsonpatch==1.32 jsonpointer==2.3 jsonschema==4.17.0 keystone==22.0.0 keystoneauth1==5.0.0 keystonemiddleware==10.1.0 kombu==5.2.4 Mako==1.2.4 MarkupSafe==2.1.1 mod-wsgi==4.9.4 msgpack==1.0.4 munch==2.5.0 mysqlclient==2.1.1 netaddr==0.8.0 netifaces==0.11.0 oauthlib==3.2.2 openstacksdk==0.102.0 os-service-types==1.7.0 osc-lib==2.6.2 oslo.cache==3.3.0 oslo.concurrency==5.0.1 oslo.config==9.0.0 oslo.context==5.0.0 oslo.db==12.2.0 oslo.i18n==5.1.0 oslo.log==5.0.2 oslo.messaging==14.0.0 oslo.metrics==0.5.0 oslo.middleware==5.0.0 oslo.policy==4.0.0 oslo.serialization==5.0.0 oslo.service==3.0.0 oslo.upgradecheck==2.0.0 oslo.utils==6.0.1 osprofiler==3.4.3 packaging==21.3 passlib==1.7.4 Paste==3.5.2 PasteDeploy==3.0.1 pbr==5.11.0 prettytable==3.5.0 prometheus-client==0.15.0 pycadf==3.1.1 pycparser==2.21 pyinotify==0.9.6 PyJWT==2.6.0 pyOpenSSL==23.0.0 pyparsing==3.0.9 pyperclip==1.8.2 pyrsistent==0.19.2 pysaml2==7.2.1 python-cinderclient==9.1.0 python-dateutil==2.8.2 python-keystoneclient==5.0.1 python-novaclient==18.1.0 python-openstackclient==6.0.0 pytz==2022.6 PyYAML==6.0 repoze.lru==0.7 requests==2.28.1 requestsexceptions==1.4.0 rfc3986==2.0.0 Routes==2.5.1 scrypt==0.8.20 simplejson==3.18.0 six==1.16.0 SQLAlchemy==1.4.44 sqlalchemy-migrate==0.13.0 sqlparse==0.4.3 statsd==4.0.1 stevedore==4.1.1 Tempita==0.5.2 testresources==2.0.1 testscenarios==0.5.0 testtools==2.5.0 urllib3==1.26.12 vine==5.0.0 wcwidth==0.2.5 WebOb==1.8.7 Werkzeug==2.2.2 wrapt==1.14.1 xmlschema==2.1.1 yappi==1.4.0 zipp==3.10.0 uwsgi --ignore-installed
    configureAndInstall | tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" | tee -a "$LOG_FILE"
    exit 1
    ;;
esac

printSummary |& tee -a "$LOG_FILE"
