#!/bin/bash
# © Copyright IBM Corporation 2021, 2022.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Keystone/20.0.0/build_keystone.sh
# Execute build script: bash build_keystone.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="keystone"
PACKAGE_VERSION="20.0.0"
KEYSTONE_DBPASS="keystone"
KEYSTONE_HOST_IP="localhost"

CONF_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Keystone/20.0.0/conf"

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
"ubuntu-18.04" | "ubuntu-21.04")
    echo "ServerName ${KEYSTONE_HOST_IP}" | sudo tee -a /etc/apache2/apache2.conf
    echo 'LoadModule wsgi_module /usr/local/lib/python3.6/dist-packages/mod_wsgi/server/mod_wsgi-py36.cpython-36m-s390x-linux-gnu.so' | sudo tee -a /etc/apache2/apache2.conf
    ;;

"rhel-7.8" | "rhel-7.9")
    echo "ServerName ${KEYSTONE_HOST_IP}" | sudo tee -a /etc/httpd/conf/httpd.conf
    echo 'Include /etc/httpd/sites-enabled/' | sudo tee -a /etc/httpd/conf/httpd.conf
    echo 'LoadModule wsgi_module /usr/lib64/httpd/modules/mod_wsgi.so' | sudo tee -a /etc/httpd/conf/httpd.conf
    ;;
	
"rhel-8.2" |  "rhel-8.4")
    echo "ServerName ${KEYSTONE_HOST_IP}" | sudo tee -a /etc/httpd/conf/httpd.conf
    echo 'Include /etc/httpd/sites-enabled/' | sudo tee -a /etc/httpd/conf/httpd.conf
    echo 'LoadModule wsgi_module /usr/lib64/python3.6/site-packages/mod_wsgi/server/mod_wsgi-py36.cpython-36m-s390x-linux-gnu.so' | sudo tee -a /etc/httpd/conf/httpd.conf
    ;;

"sles-12.5")
    echo "ServerName ${KEYSTONE_HOST_IP}" | sudo tee -a /etc/apache2/httpd.conf
    echo 'Include /etc/apache2/sites-enabled/' | sudo tee -a /etc/apache2/httpd.conf
    echo 'LoadModule wsgi_module /usr/lib64/apache2/mod_wsgi.so' | sudo tee -a /etc/apache2/httpd.conf

    sudo sed -i 's|Include /etc/apache2/sysconfig.d/include.conf|#Include /etc/apache2/sysconfig.d/include.conf|g' /etc/apache2/httpd.conf
    ;;

"sles-15.2" | "sles-15.3")
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
"ubuntu-18.04" | "ubuntu-21.04")
    curl -SL -k -o wsgi-keystone.conf $CONF_URL/ubuntu-wsgi-keystone.conf
    sudo mv wsgi-keystone.conf /etc/apache2/sites-available/
    sudo ln -s /etc/apache2/sites-available/wsgi-keystone.conf /etc/apache2/sites-enabled
    ;;

"rhel-7.8" | "rhel-7.9" | "rhel-8.2" | "rhel-8.4")
    sudo mkdir -p /etc/httpd/sites-available
    sudo mkdir -p /etc/httpd/sites-enabled
    curl -SL -k -o wsgi-keystone.conf $CONF_URL/rhel-wsgi-keystone.conf
    sudo mv wsgi-keystone.conf /etc/httpd/sites-available/
    sudo ln -s /etc/httpd/sites-available/wsgi-keystone.conf /etc/httpd/sites-enabled
    ;;

"sles-12.5" | "sles-15.2" | "sles-15.3")
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

    if [[ "${DISTRO}" == "ubuntu-18.04" ]]; then
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

    if  [[ "${DISTRO}" == "sles-12."* || "${DISTRO}" == "rhel-7."* ]]; then
	 printf -- '\nInstalling mod_wsgi. \n'
	cd $SOURCE_ROOT
	wget https://github.com/GrahamDumpleton/mod_wsgi/archive/4.9.0.tar.gz
	tar -xvf 4.9.0.tar.gz
	cd mod_wsgi-4.9.0/
		if  [[ "${DISTRO}" == "sles-12."* ]]; then
		echo "Inside SLES 12.x"
		./configure --with-apxs=/usr/bin/apxs2 --with-python=/usr/local/bin/python3
		else
		echo "Inside RHEL 7.x"
		./configure --with-apxs=/usr/bin/apxs --with-python=/usr/local/bin/python3
		fi
	make
	sudo make install
	
		if  [[ "${DISTRO}" == "sles-12."* ]]; then
		echo "Inside SLES 12.x"
		sudo chmod 755 /usr/lib64/apache2/mod_wsgi.so
		else
		echo "Inside RHEL 7.x"
		sudo chmod 755 /usr/lib64/httpd/modules/mod_wsgi.so
		fi
	fi


    printf -- '\nKeystone install completed successfully. \n'

    printf -- '\nStarting Keystone configure. \n'
    sudo mkdir -p /etc/keystone/
    cd /etc/keystone/
    sudo wget -O keystone.conf https://docs.openstack.org/keystone/xena/_static/keystone.conf.sample
    export OS_KEYSTONE_CONFIG_DIR=/etc/keystone
    printf -- '\nKeystone configuration completed successfully. \n'

    sudo sed -i "s|#connection = <None>|connection = mysql://keystone:${KEYSTONE_DBPASS}@localhost/keystone|g" /etc/keystone/keystone.conf
    sudo sed -i "s|#provider = fernet|provider = fernet|g" /etc/keystone/keystone.conf

    printf -- '\nPopulating Keystone DB. \n'
    if  [[ "${DISTRO}" == "sles-12."* || "${DISTRO}" == "rhel-7."* ]]; then
     sudo env PATH=$PATH keystone-manage db_sync
    else
    keystone-manage db_sync
    fi


    printf -- '\nInitializing fernet key repo. \n'
    sudo groupadd keystone
    sudo useradd -m -g keystone keystone
    sudo mkdir -p /etc/keystone/fernet-keys
   
    sudo chown -R keystone:keystone /etc/keystone/fernet-keys

    if [[ "${ID}" == "rhel" || "${DISTRO}" == "sles-12."* ]]; then
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
	elif [[ "${DISTRO}" == "sles-12."* ]]; then
	sudo sed -i 's/\/usr\/bin/\/usr\/local\/bin/g' /etc/apache2/sites-available/wsgi-keystone.conf
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
"ubuntu-18.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

    sudo apt-get update
    sudo apt-get install -y python3-pip libffi-dev libssl-dev  mysql-server libmysqlclient-dev libapache2-mod-wsgi-py3 apache2  apache2-dev
    sudo -H pip3 install --upgrade pip
    sudo pip3 install cryptography==3.3.1 python-openstackclient mysqlclient mod_wsgi keystone
    configureAndInstall | tee -a "$LOG_FILE"

    ;;

"ubuntu-21.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
    
    sudo apt-get update
    sudo apt-get install -y python3-pip libffi-dev libssl-dev  mysql-server libmysqlclient-dev libapache2-mod-wsgi-py3 apache2  apache2-dev
    sudo apt-get install -y mariadb-server
    sudo -H pip3 install --upgrade pip
    sudo pip3 install cryptography==3.3.1 python-openstackclient mysqlclient mod_wsgi keystone
    configureAndInstall | tee -a "$LOG_FILE"
    
    ;;

"rhel-7.8" | "rhel-7.9")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

    sudo yum install -y gcc gcc-c++ openssl.s390x httpd httpd-devel mariadb-server mariadb-devel sqlite-devel wget
    wget -q https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Python3/3.9.1/build_python3.sh
    bash build_python3.sh -y
    export PATH=/usr/local/bin:$PATH
    sudo -H env PATH=$PATH pip3 install --upgrade pip
    sudo env PATH=$PATH  pip3 install cryptography==3.3.1 flask==1.1.2 itsdangerous==2.0.1 mod_wsgi python-openstackclient mysqlclient keystone
    configureAndInstall | tee -a "$LOG_FILE"
    ;;

"rhel-8.2" | "rhel-8.4")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

    sudo yum install -y python3-devel libffi-devel openssl-devel gcc make gcc-c++ python3-mod_wsgi.s390x httpd httpd-devel mariadb-devel  mariadb-server procps sqlite-devel.s390x
    export PATH=/usr/local/bin:$PATH
    sudo -H pip3 install --upgrade pip
    sudo pip3 install cryptography==3.3.1 flask==1.1.2 python-openstackclient keystone mysqlclient
    configureAndInstall | tee -a "$LOG_FILE"
    ;;

"sles-12.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

    sudo zypper install -y apache2-mod_wsgi libopenssl-devel gcc make gawk apache2  apache2-devel mariadb libmariadb3 gcc-c++ libmysqld-devel wget
    wget -q https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Python3/3.9.1/build_python3.sh
    bash build_python3.sh -y

    export PATH=/usr/local/bin:$PATH
    sudo -H env PATH=$PATH pip3 install --upgrade pip
    sudo env PATH=$PATH  pip3 install cryptography==3.3.1 flask==1.1.2 itsdangerous==2.0.1 python-openstackclient mysqlclient keystone
    configureAndInstall | tee -a "$LOG_FILE"
    ;;

"sles-15.2" | "sles-15.3")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

    sudo zypper install -y libopenssl-devel libffi-devel gcc make python3-devel python3-pip gawk apache2  apache2-devel mariadb libmariadb-devel gcc-c++
    sudo -H pip3 install --upgrade pip
    sudo pip3 install cryptography==3.3.1 flask==1.1.2 python-openstackclient mysqlclient keystone mod_wsgi
    configureAndInstall | tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" | tee -a "$LOG_FILE"
    exit 1
    ;;
esac

printSummary | tee -a "$LOG_FILE"
