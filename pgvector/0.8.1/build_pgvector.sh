#!/bin/bash
# © Copyright IBM Corporation 2025
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/pgvector/0.8.1/build_pgvector.sh
# Execute build script: bash build_pgvector.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="pgvector"
PACKAGE_VERSION="0.8.1"
SOURCE_ROOT="$(pwd)"

TESTS="false"
FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
    mkdir -p "$SOURCE_ROOT/logs/"
fi

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
    printf -- "Stopping PostgreSQL...\n" >>"$LOG_FILE"
    case "$DISTRO" in
            ubuntu-*)
                sudo service postgresql stop >/dev/null 2>&1 || true
                ;;
            rhel-*|sles-*)
                if command -v pg_ctl >/dev/null && [ -d ~/pgdata ]; then
                    pg_ctl -D ~/pgdata stop >/dev/null 2>&1 || true  
					rm -rf ~/pgdata
                fi
                ;;
    esac

    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

    #Install postgresql
	if [[ "$DISTRO" == rhel-8.10 ]]; then
	    cd $SOURCE_ROOT
	    wget -q https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/PostgreSQL/16.9/build_postgresql.sh
            bash build_postgresql.sh -y
	    export PATH=$PATH:/usr/local/pgsql/bin
        fi
	
    #Setup pgvector build
    cd $SOURCE_ROOT
    if [ ! -d "$SOURCE_ROOT/pgvector/" ]; then
        git clone -b v$PACKAGE_VERSION https://github.com/pgvector/pgvector.git
    fi
    cd pgvector
    make
	if [[ "$DISTRO" == rhel-8.10 ]]; then
	    sudo env "PATH=$PATH" make install
	else
	    sudo make install
	fi
    
    printf -- "pgvector build completed successfully. \n"

  # Run Tests
    runTest

  # Cleanup
    cleanup
}

function runTest() {
    set +e

    if [[ "$TESTS" == "true" ]]; then
        printf -- "TEST Flag is set, continue with running test \n"
        cd $SOURCE_ROOT/pgvector
        if [[ "$DISTRO" == ubuntu-* ]]; then
		    sudo service postgresql start
                    sudo -u postgres psql -c "CREATE USER test WITH PASSWORD 'test';"
                    sudo -u postgres psql -c "ALTER USER test WITH SUPERUSER;"
                    sudo -u postgres psql -c " CREATE DATABASE test OWNER test;"
                    sudo service postgresql restart
                    sudo service postgresql status
		    make installcheck
                    make prove_installcheck
		else
		    mkdir -p ~/pgdata
                    initdb -D ~/pgdata
                    pg_ctl -D ~/pgdata -l logfile -o "-k /tmp" start
                    psql -h /tmp -d postgres -c "CREATE USER test WITH PASSWORD 'test';"
                    psql -h /tmp -U postgres -d postgres -c "ALTER USER test WITH SUPERUSER;"
                    psql -h /tmp -U postgres -d postgres -c "CREATE DATABASE test OWNER test;"
                    pg_ctl -D ~/pgdata restart
                    pg_ctl -D ~/pgdata status 
		    export PGHOST=/tmp  
                    make installcheck
			if [[ "$DISTRO" == rhel-9.4 || "$DISTRO" == rhel-9.6 ]]; then
			    cd $SOURCE_ROOT
                	    wget https://ftp.postgresql.org/pub/source/v13.20/postgresql-13.20.tar.bz2
                	    tar -xf postgresql-13.20.tar.bz2
                	    export PERL5LIB=$SOURCE_ROOT/postgresql-13.20/src/test/perl
                	    cd $SOURCE_ROOT/pgvector
                	    make prove_installcheck
			else
			    cd $SOURCE_ROOT
                            if [[ "$DISTRO" == sles-* || "$DISTRO" == rhel-10.0 ]]; then
				    wget https://ftp.postgresql.org/pub/source/v16.9/postgresql-16.9.tar.bz2
                                    tar -xf postgresql-16.9.tar.bz2
                            fi 				
			    export PERL5LIB=$SOURCE_ROOT/postgresql-16.9/src/test/perl
                            cd $SOURCE_ROOT/pgvector
                            make prove_installcheck PROVE_FLAGS="-I $SOURCE_ROOT/postgresql-16.9/src/test/perl -I ./test/perl"
			fi
		fi
        printf -- "Tests completed. \n"
    fi
    set -e
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
    echo "bash build_pgvector.sh  [-d debug] [-y install-without-confirmation] [-t run tests]"
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
    printf -- "                       Getting Started                \n"
    printf -- " pgvector $PACKAGE_VERSION built successfully.        \n"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"rhel-8.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y make gcc gcc-c++ git git perl-IPC-Run diffutils perl-Test-Harness perl-core redhat-rpm-config |& tee -a "$LOG_FILE"

    configureAndInstall |& tee -a "$LOG_FILE"
        ;;
"rhel-9.4" | "rhel-9.6" | "rhel-10.0")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y postgresql postgresql-server postgresql-server-devel postgresql-contrib make gcc gcc-c++ git git perl-IPC-Run diffutils perl-Test-Harness perl-core redhat-rpm-config bzip2 readline-devel zlib-devel wget |& tee -a "$LOG_FILE"

    configureAndInstall |& tee -a "$LOG_FILE"
        ;;
"sles-15.6" | "sles-15.7")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y postgresql postgresql-server postgresql-server-devel postgresql-contrib make gcc gcc-c++ git perl-IPC-Run perl diffutils bzip2 readline-devel zlib-devel wget |& tee -a "$LOG_FILE"

    configureAndInstall |& tee -a "$LOG_FILE"
        ;;
"ubuntu-22.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    sudo apt update
    sudo DEBIAN_FRONTEND=noninteractive apt install -y postgresql-14 postgresql-server-dev-14 make gcc g++ git build-essential libipc-run-perl |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"ubuntu-24.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt install -y postgresql-16 postgresql-server-dev-16 make gcc g++ git build-essential libipc-run-perl |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"ubuntu-25.04" | "ubuntu-25.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt install -y postgresql-17 postgresql-server-dev-17 make gcc g++ git build-essential libipc-run-perl |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
