#!/bin/bash
# © Copyright IBM Corporation 2025.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Keystone/26.0.0/build_keystone.sh
# Execute build script: bash build_keystone.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="keystone"
PACKAGE_VERSION="26.0.0"
KEYSTONE_DBPASS="keystone"
KEYSTONE_HOST_IP="localhost"

CONF_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Keystone/26.0.0/conf"

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
    elif [[ "${DISTRO}" == "sles-15."* ]]; then
      echo "ServerName ${KEYSTONE_HOST_IP}" | sudo tee -a /etc/apache2/httpd.conf
      echo 'Include /etc/apache2/sites-enabled/' | sudo tee -a /etc/apache2/httpd.conf
      echo 'LoadModule wsgi_module /usr/local/lib64/python3.12/site-packages/mod_wsgi/server/mod_wsgi-py312.cpython-312-s390x-linux-gnu.so' | sudo tee -a /etc/apache2/httpd.conf
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
  elif [[ "${DISTRO}" == "sles-15."* ]]; then
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

    if [[ "${DISTRO}" == "rhel"* ]] || [[ "${DISTRO}" == "sles-15."* ]]; then
       sudo /usr/bin/mysql_install_db --user=mysql
       sleep 30s
    fi

    if [[ "${DISTRO}" == "rhel-8."* ]] || [[ "${DISTRO}" == "sles-15."* ]]; then
       nohup sudo /usr/bin/mysqld_safe --user=mysql &>/dev/null &
    else
       nohup sudo mysqld_safe &>/dev/null &
    fi 

    sleep 60s

    sudo mysql -e "CREATE DATABASE keystone"
    sudo mysql -e "CREATE USER 'keystone'@'localhost' IDENTIFIED BY '${KEYSTONE_DBPASS}'"
    sudo mysql -e "CREATE USER 'keystone'@'%' IDENTIFIED BY '${KEYSTONE_DBPASS}'"
    sudo mysql -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%'"
    sudo mysql -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost'"

    printf -- '\nKeystone install completed successfully. \n'

    printf -- '\nStarting Keystone configure. \n'
    sudo mkdir -p /etc/keystone/
    cd /etc/keystone/
    sudo wget -O keystone.conf https://docs.openstack.org/keystone/2024.2/_static/keystone.conf.sample
    export OS_KEYSTONE_CONFIG_DIR=/etc/keystone
    printf -- '\nKeystone configuration completed successfully. \n'

    sudo sed -i "s|#connection = <None>|connection = mysql://keystone:${KEYSTONE_DBPASS}@localhost/keystone|g" /etc/keystone/keystone.conf
    sudo sed -i "s|#provider = fernet|provider = fernet|g" /etc/keystone/keystone.conf

    printf -- '\nPopulating Keystone DB. \n'
    if [[ "${DISTRO}" == "rhel-8."* || "${DISTRO}" == "rhel-9."* ]]; then
     sudo env PATH=$PATH keystone-manage db_sync
    else
     sudo env "PATH=$PATH" keystone-manage db_sync
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
      sudo env PATH=$PATH keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
      sudo env PATH=$PATH keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
      
      # Bootstrapping identity service
      sudo env PATH=$PATH keystone-manage bootstrap \
      --bootstrap-password ADMIN_PASS \
      --bootstrap-admin-url http://${KEYSTONE_HOST_IP}:35357/v3/ \
      --bootstrap-internal-url http://${KEYSTONE_HOST_IP}:5000/v3/ \
      --bootstrap-public-url http://${KEYSTONE_HOST_IP}:5000/v3/ \
      --bootstrap-region-id RegionOne
    fi

    setUpApache2HttpdConf
    setUpKeystoneConf
    sleep 30s
    if [[ "${ID}" == "rhel" ]]; then
      nohup sudo /usr/sbin/httpd &>/dev/null &
    else
      nohup sudo env PATH=$PATH uwsgi --http-socket 127.0.0.1:5000 --plugin /usr/lib/uwsgi/plugins/python3_plugin.so --wsgi-file $(which keystone-wsgi-public) &>/dev/null &
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
"rhel-8.8" | "rhel-8.10" | "rhel-9.2" | "rhel-9.4" | "rhel-9.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

    sudo yum install -y curl wget openssl-devel gcc make gcc-c++ httpd httpd-devel mariadb-server procps sqlite-devel perl mariadb-devel mariadb-server rust cargo 

    if [[ "${DISTRO}" == "rhel-8."* ]]; then
        sudo yum install -y python39-devel python39-mod_wsgi python39-pip
    else
        sudo yum install -y python3-devel python3-mod_wsgi python3-pip
        sudo yum remove -y python3-requests
    fi
    sudo -H pip3 install --upgrade pip
    sudo pip3 install bcrypt==4.0.1 keystone==26.0.0 python-openstackclient mysqlclient
    configureAndInstall | tee -a "$LOG_FILE"
    ;;

"sles-15.6")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

    sudo zypper install -y lsof libopenssl-devel gcc make python312-devel python312-pip gawk apache2 apache2-devel mariadb libmariadb-devel gcc-c++ cargo curl wget
	
    sudo pip3 install cryptography==41.0.7 bcrypt==4.0.1 keystone==26.0.0 python-openstackclient mysqlclient mod-wsgi uwsgi
    configureAndInstall | tee -a "$LOG_FILE"
    ;;

"ubuntu-22.04" | "ubuntu-24.04" | "ubuntu-24.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

    sudo apt-get update
    sudo apt-get install -y python3-pip mysql-server libmysqlclient-dev libapache2-mod-wsgi-py3 apache2 apache2-dev wget curl uwsgi-plugin-python3 rustc cargo librust-openssl-dev python3-mysqldb
    
    if [[ "${DISTRO}" != "ubuntu-22.04" ]]; then
        PIP_OPTIONS="--break-system-packages"
        if [[ "${DISTRO}" == "ubuntu-24.10" ]]; then
            sudo apt install -y python3-setuptools
            sudo apt remove -y python3-blinker
        fi
    fi

    sudo -H pip3 install $PIP_OPTIONS --upgrade --user pip
    sudo pip3 install $PIP_OPTIONS bcrypt==4.0.1 keystone==26.0.0 python-openstackclient
    configureAndInstall | tee -a "$LOG_FILE"
    ;;

*)
    printf -- "%s not supported \n" "$DISTRO" | tee -a "$LOG_FILE"
    exit 1
    ;;
esac

printSummary |& tee -a "$LOG_FILE"
