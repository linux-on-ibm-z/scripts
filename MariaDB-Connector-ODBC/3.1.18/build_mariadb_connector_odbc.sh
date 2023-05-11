#!/bin/bash
# © Copyright IBM Corporation 2023
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/MariaDB-Connector-ODBC/3.1.18/build_mariadb_connector_odbc.sh
# Execute build script: bash build_mariadb_connector_odbc.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="MariaDB-Connector-ODBC"
PACKAGE_VERSION="3.1.18"
SOURCE_ROOT="$(pwd)"

FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/"
PATCH_URL+="${PACKAGE_NAME}/${PACKAGE_VERSION}/patch"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
    mkdir -p "$SOURCE_ROOT/logs/"
fi

# Set the Distro ID
    source "/etc/os-release"

function prepare() {
    if command -v "sudo" >/dev/null; then
        printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
    else
        printf -- 'Sudo : No \n' >>"$LOG_FILE"
        printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n'
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
    # Remove artifacts
    cd $SOURCE_ROOT/mariadb-connector-odbc
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function installUnixODBC() {
    printf -- "Installing unixODBC"

    cd $SOURCE_ROOT
    git clone https://github.com/lurcher/unixODBC.git
    cd unixODBC
    git checkout v2.3.11
    curl -o iconv.diff ${PATCH_URL}/iconv.diff
    git apply --ignore-whitespace iconv.diff
    autoreconf -fi
    ./configure
    make
    sudo make install

    printf -- "\n UnixODBC installed successfully"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

    #Download MariaDB Connector/ODBC source code
    cd $SOURCE_ROOT
    git clone https://github.com/MariaDB/mariadb-connector-odbc.git
    cd mariadb-connector-odbc
    git checkout ${PACKAGE_VERSION}

    git submodule init
    git submodule update
    
    #Build and install
    case "$DISTRO" in
        "ubuntu"*)
            echo $DISTRO
            cmake -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCONC_WITH_UNIT_TESTS=Off  -DWITH_SSL=OPENSSL -DCMAKE_INSTALL_PREFIX=/usr/local  -DODBC_LIB_DIR=/usr/lib/s390x-linux-gnu/
            make
            sudo make install
            sudo cp /usr/local/lib/mariadb/libmaodbc.so /usr/local/lib
            ;;
        "sles-12"* | "rhel"*)
            echo $DISTRO
            cmake -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCONC_WITH_UNIT_TESTS=Off  -DWITH_SSL=OPENSSL -DCMAKE_INSTALL_PREFIX=/usr/local
            make
            sudo make install
            sudo cp /usr/local/lib/mariadb/libmaodbc.so /usr/local/lib
            ;;
        "sles-15"*)
            echo $DISTRO
            cmake -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCONC_WITH_UNIT_TESTS=Off  -DWITH_SSL=OPENSSL -DCMAKE_INSTALL_PREFIX=/usr/local -DODBC_LIB_DIR=/usr/local/lib
            make
            sudo make install
            sudo cp /usr/local/lib/mariadb/libmaodbc.so /usr/local/lib
            ;;
    esac

    printf -- "\n* MariaDB Connector ODBC installed successfully *\n"

    #Run Tests
    runTest
}

function runTest() {
    set +e
    if [[ "$TESTS" == "true" ]]; then

        printf -- "TEST Flag is set, continue with running test \n"  >> "$LOG_FILE"

        # Start MariaDB server and configure for testing
        if [[ "$DISTRO" == "ubuntu-2"* || "$DISTRO" == "sles"* || "$DISTRO" == "rhel-8"* || "$DISTRO" == "rhel-9"* ]]; then
            sudo mysql_install_db --user=mysql
            sleep 20s
        fi

        if [[ "$DISTRO" == "rhel-7"* ]]; then
            sudo mkdir /var/log/mariadb
            sudo chown mysql:root /var/log/mariadb

            sudo mkdir /var/run/mariadb
            sudo chown mysql:root /var/run/mariadb
        fi

        
        sudo env PATH=$PATH mysqld_safe --user=mysql &
        sleep 30s
        case $DISTRO in
            "ubuntu"*)
                sudo ln -s /var/run/mysqld/mysqld.sock /tmp/mysql.sock
                sleep 20s
                if [[ "$DISTRO" == "ubuntu-20.04" ]]; then
                    sudo mysql -u root -e "USE mysql; UPDATE user SET plugin='mysql_native_password' WHERE User='root'; FLUSH PRIVILEGES;"
                else # Ubuntu 18.04, 22.04
                    sudo env PATH=$PATH mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('');"
                fi    
                sudo env PATH=$PATH mysql -u root -e "CREATE DATABASE IF NOT EXISTS test;"
                ;;
            "rhel"*)
                sudo ln -s /var/lib/mysql/mysql.sock /tmp/mysql.sock
                ;;
            "sles"*)
                sudo ln -s /run/mysql/mysql.sock /tmp/mysql.sock
                ;;
        esac

        if [[ "$DISTRO" == "ubuntu"* || "$DISTRO" == "rhel-7"* || "$DISTRO" == "sles-15"* ]]; then
            sudo env PATH=$PATH mysql -u root -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('');"
        else
            sudo env PATH=$PATH mysql -u root -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('rootpass');"
        fi

        #Set Environment Variables
        export TEST_DRIVER=maodbc_test
        export TEST_SCHEMA=test
        export TEST_DSN=maodbc_test
        export TEST_UID=root

        if [[ "$DISTRO" == "ubuntu"* || "$DISTRO" == "rhel-7"* || "$DISTRO" == "sles-15"* ]]; then
            export TEST_PASSWORD=
        else
            export TEST_PASSWORD=rootpass
        fi

        #Edit odbc.ini and odbcinst.ini
        if [[ "$DISTRO" == "rhel-8"* || "$DISTRO" == "rhel-9"* ]]; then
cat <<EOF |& sudo tee -a /etc/odbc.ini
[maodbc_test]
Driver      = maodbc_test
DESCRIPTION = MariaDB ODBC Connector Test
SERVER      = localhost
PORT        = 3306
DATABASE    = test
UID         = root
PASSWORD    = rootpass
EOF
cat <<EOF |& sudo tee -a /etc/odbcinst.ini
[ODBC]
# Change to "yes" to turn on tracing
Trace     = no
TraceFile = /tmp/maodbc_trace.log
[maodbc_test]
Driver      = /usr/local/lib/libmaodbc.so
DESCRIPTION = MariaDB ODBC Connector
Threading   = 0
IconvEncoding=UTF16
EOF
        fi

        if [[ "$DISTRO" == "sles-12"* ]]; then
cat <<EOF |& sudo tee -a /etc/unixODBC/odbc.ini
[maodbc_test]
Driver      = maodbc_test
DESCRIPTION = MariaDB ODBC Connector Test
SERVER      = localhost
PORT        = 3306
DATABASE    = test
UID         = root
PASSWORD    = rootpass
EOF
cat <<EOF |& sudo tee -a /etc/unixODBC/odbcinst.ini
[ODBC]
# Change to "yes" to turn on tracing
Trace     = no
TraceFile = /tmp/maodbc_trace.log
[maodbc_test]
Driver      = /usr/local/lib/libmaodbc.so
DESCRIPTION = MariaDB ODBC Connector
Threading   = 0
IconvEncoding=UTF16 
EOF
        fi


        #Run tests
        cd $SOURCE_ROOT/mariadb-connector-odbc/test
        case $DISTRO in
                "rhel-7.8" | "rhel-7.9" | "ubuntu"* | "sles-15"* )
            export ODBCINI="$PWD/odbc.ini"
            export ODBCSYSINI=$PWD
            ;;
        esac
        ctest 2>&1 |& tee -a "$LOG_FILE"
        if [[ "$DISTRO" == "ubuntu"* || "$DISTRO" == "rhel-7"* || "$DISTRO" == "sles-15"* ]]; then
            mysqladmin -u root --password="" shutdown
        else
            mysqladmin -u root --password="rootpass" shutdown
        fi
        case $DISTRO in
            "rhel"*)
                if cat "$LOG_FILE" | grep -q "odbc_connstring (Failed)"; then
                    echo "Expected failures found!"
                    exit 0
                else
                    echo "Unexpected failures found! Please check the logs for details!"
                    exit 1
                fi
                ;;
            "sles"*)
                if cat "$LOG_FILE" | grep -q "odbc_prepare (Failed)"; then
                    echo "Expected failures found!"
                    exit 0
                else
                    echo "Unexpected failures found! Please check the logs for details!"
                    exit 1
                fi
                ;;
        esac
    fi
    set -e
}
function logDetails() {
    printf -- '**************************** SYSTEM DETAILS *************************************************************\n' >>"$LOG_FILE"
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
    echo " bash build_mariadb-connector-odbc.sh  [-d debug] [-y install-without-confirmation] [-t install-with-test]"
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
    printf -- '\n********************************************************************************************************\n'
    printf -- "*                     Getting Started                 * \n"
    printf -- "         You have successfully installed MariaDB Connector/ODBC. \n"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"ubuntu-20.04" | "ubuntu-22.04" | "ubuntu-22.10" | "ubuntu-23.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y mariadb-server unixodbc-dev odbcinst git cmake gcc libssl-dev tar curl libcurl4-openssl-dev libkrb5-dev |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-9.0" | "rhel-9.1")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo subscription-manager repos --enable=codeready-builder-for-rhel-9-s390x-rpms
    sudo yum install -y mariadb mariadb-server unixODBC unixODBC-devel git cmake gcc libarchive openssl-devel openssl tar curl libcurl-devel krb5-devel make glibc-langpack-en |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-8.6" | "rhel-8.7")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y mariadb mariadb-server unixODBC unixODBC-devel git cmake gcc libarchive openssl-devel openssl tar curl libcurl-devel krb5-devel make glibc-langpack-en |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-7.8" | "rhel-7.9")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo subscription-manager repos --enable=rhel-7-server-for-system-z-rhscl-rpms
    sudo yum install -y wget
    wget -q https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/MariaDB/10.10.2/build_mariadb.sh
    sudo bash build_mariadb.sh -y
    export PATH=/usr/local/mysql/bin/:$PATH
    sudo yum install -y wget gcc-c++ unixODBC unixODBC-devel git cmake gcc libarchive openssl-devel openssl tar curl libcurl-devel krb5-devel make |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
 "sles-15.4")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y git cmake gcc mariadb libopenssl-devel openssl glibc-locale tar curl libcurl-devel krb5-devel autoconf automake libtool |& tee -a "$LOG_FILE"
    installUnixODBC |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
 "sles-12.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y mariadb unixODBC unixODBC-devel git cmake gcc libopenssl-devel openssl glibc-locale tar curl libcurl-devel krb5-devel |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
