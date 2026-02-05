#!/bin/bash
# © Copyright IBM Corporation 2026.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Keystone/28.0.0/build_keystone.sh
# Execute build script: bash build_keystone.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="keystone"
PACKAGE_VERSION="28.0.0"
ADMIN_PASS="${ADMIN_PASS:-changeme}"
REGION="RegionOne"
DB_URL="sqlite:////var/lib/keystone/keystone.db"
PUBLIC_PORT=5000
UWSGI_SOCK="/run/keystone/keystone-wsgi.sock"

export SOURCE_ROOT="$(pwd)"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

function log() {
	printf -- "[$(date +'%Y-%m-%d %H:%M:%S')] %s\n" "$1" | tee -a "$LOG_FILE"
}

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

function prepare() {

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

function runCheck() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
		export OS_AUTH_URL=http://localhost:5000/v3
		export OS_IDENTITY_API_VERSION=3
		export OS_USERNAME=admin
		export OS_PASSWORD="${ADMIN_PASS}"
		export OS_PROJECT_NAME=admin
		export OS_USER_DOMAIN_NAME=Default
		export OS_PROJECT_DOMAIN_NAME=Default

		openstack service list
		openstack token issue
		printf -- '\n Verification Completed !! \n'
	fi
	set -e
}

function prepare_env() {
	log "Preparing system environment..."
	mkdir -p "$SOURCE_ROOT/logs/"

	# 1. Ensure Group Exists
	if ! getent group keystone >/dev/null; then
		groupadd --system keystone
	fi

	# 2. Ensure User Exists
	if ! id keystone &>/dev/null; then
		useradd --system --gid keystone --home /var/lib/keystone --shell /sbin/nologin keystone
	fi

	# 3. Create Directories
	mkdir -p /etc/keystone /var/lib/keystone /var/log/keystone /run/keystone

	# 4. Apply Permissions (Verify user exists before chown)
	if id keystone &>/dev/null; then
		chown -R keystone:keystone /etc/keystone /var/lib/keystone /var/log/keystone /run/keystone
	else
		log "ERROR: Keystone user creation failed!"
		exit 1
	fi
}

function configureLibexpat() {
	mkdir -p /usr/local/src
	cd /usr/local/src

	if [ ! -d libexpat ]; then
		git clone https://github.com/libexpat/libexpat.git
	fi

	cd libexpat/expat

	rm -rf build
	mkdir build
	cd build

	cmake .. \
		-DCMAKE_INSTALL_PREFIX=/usr/local \
		-DEXPAT_BUILD_TESTS=OFF \
		-DEXPAT_BUILD_EXAMPLES=OFF

	make -j"$(nproc)"
	make install

	echo "/usr/local/lib64" >/etc/ld.so.conf.d/00-local-expat.conf
	ldconfig

	echo "/usr/local/lib64/libexpat.so.1" >/etc/ld.so.preload

}

function configure_keystone_stack() {

	# Generate Keystone Config
	cat >/etc/keystone/keystone.conf <<EOF
[DEFAULT]
log_dir = /var/log/keystone
[database]
connection = ${DB_URL}
[token]
provider = fernet
EOF
	chown keystone:keystone /etc/keystone/keystone.conf
	chmod 640 /etc/keystone/keystone.conf

	if [[ "${DB_URL}" == sqlite:* ]]; then
		touch /var/lib/keystone/keystone.db
		chown keystone:keystone /var/lib/keystone/keystone.db
		chmod 600 /var/lib/keystone/keystone.db
	fi

	keystone-manage db_sync
	keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
	keystone-manage credential_setup --keystone-user keystone --keystone-group keystone

	# Generate uWSGI Config
	cat >/etc/keystone/keystone-uwsgi.ini <<EOF
[uwsgi]
module = keystone.wsgi.api:application
uid = keystone
gid = keystone
chdir = /var/lib/keystone
env = OSLO_CONFIG_DIR=/etc/keystone
env = OSLO_CONFIG_FILE=/etc/keystone/keystone.conf
socket = ${UWSGI_SOCK}
chmod-socket = 666
vacuum = true
master = true
processes = 4
threads = 2
enable-threads = true
logto = /var/log/keystone/uwsgi.log
EOF
}

function bootstrap_keystone() {
	log "Bootstrapping Keystone..."
	keystone-manage bootstrap \
		--bootstrap-password "${ADMIN_PASS}" \
		--bootstrap-admin-url "http://localhost:${PUBLIC_PORT}/v3/" \
		--bootstrap-internal-url "http://localhost:${PUBLIC_PORT}/v3/" \
		--bootstrap-public-url "http://localhost:${PUBLIC_PORT}/v3/" \
		--bootstrap-region-id "${REGION}"
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
    disown -a
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
		if [ -d "/etc/keystone-x" ]; then
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
prepare_env

case "$DISTRO" in
"rhel-8.10" | "rhel-9.4" | "rhel-9.6" | "rhel-9.7" | "rhel-10.0" | "rhel-10.1")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

	sudo dnf install -y python3.12 python3.12-pip python3.12-devel gcc gcc-c++ make httpd rust cargo openssl-devel libffi-devel sqlite
	python3.12 -m pip install -U pip setuptools wheel
	python3.12 -m pip install keystone==${PACKAGE_VERSION} uwsgi python-openstackclient

	configure_keystone_stack
	cat >/etc/httpd/conf.d/uwsgi-keystone.conf <<EOF
Listen ${PUBLIC_PORT}
<VirtualHost *:${PUBLIC_PORT}>
  ProxyPass / unix:${UWSGI_SOCK}|uwsgi://localhost/
</VirtualHost>
EOF
	killall -9 uwsgi httpd 2>/dev/null || true
    nohup uwsgi --ini /etc/keystone/keystone-uwsgi.ini >/var/log/keystone/uwsgi.nohup.log 2>&1 &
    
    for i in {1..10}; do
        [ -S "${UWSGI_SOCK}" ] && break
        log "Waiting for uWSGI socket..."
        sleep 1
    done

    nohup /usr/sbin/httpd -DFOREGROUND >/var/log/httpd/httpd.nohup.log 2>&1 &
	;;

"sles-15.7" | "sles-16.0")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

	sudo zypper -n in python313 python313-devel python313-pip gcc gcc-c++ make cmake git wget gawk apache2 libopenssl-devel libffi-devel rust cargo
	configureLibexpat
	python3.13 -m pip install -U pip setuptools wheel
	python3.13 -m pip install keystone==${PACKAGE_VERSION} uwsgi python-openstackclient

	configure_keystone_stack
	mkdir -p /etc/apache2/vhosts.d
	APACHE_CONF=/etc/apache2/httpd.conf
	grep -q '^ServerName' "$APACHE_CONF" || echo "ServerName localhost" >>"$APACHE_CONF"
	for m in proxy proxy_http proxy_uwsgi; do
		grep -q "${m}_module" "$APACHE_CONF" ||
			echo "LoadModule ${m}_module /usr/lib64/apache2/mod_${m}.so" >>"$APACHE_CONF"
	done
	cat >/etc/apache2/vhosts.d/keystone.conf <<EOF
Listen ${PUBLIC_PORT}
<VirtualHost *:${PUBLIC_PORT}>
  ServerName localhost
  ProxyPreserveHost On
  ProxyRequests Off
  ProxyPass / unix:${UWSGI_SOCK}|uwsgi://localhost/
  ErrorLog /var/log/keystone/apache_error.log
  CustomLog /var/log/keystone/apache_access.log combined
</VirtualHost>
EOF
	pkill -9 uwsgi httpd 2>/dev/null || true
	uwsgi --ini /etc/keystone/keystone-uwsgi.ini &
	httpd -DFOREGROUND &
	;;

"ubuntu-22.04" | "ubuntu-24.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

	sudo apt update && sudo apt-get install -y python3-pip python3-dev apache2 apache2-dev wget curl rustc cargo librust-openssl-dev
    	sudo apt-get remove -y --ignore-missing python3-bcrypt
	sudo -H python3 -m pip install --upgrade pip

    PIP_FLAGS=""
    if python3 -m pip install --help | grep -q "break-system-packages"; then
        PIP_FLAGS="--break-system-packages"
    fi

    sudo python3 -m pip install $PIP_FLAGS bcrypt==4.0.1 keystone==${PACKAGE_VERSION} python-openstackclient uwsgi
	configure_keystone_stack
	a2enmod proxy proxy_http proxy_uwsgi headers >/dev/null
	cat >/etc/apache2/sites-available/keystone.conf <<EOF
Listen ${PUBLIC_PORT}
<VirtualHost *:${PUBLIC_PORT}>
  ProxyPass / unix:${UWSGI_SOCK}|uwsgi://localhost/
</VirtualHost>
EOF
	a2ensite keystone >/dev/null
	pkill -9 uwsgi apache2 2>/dev/null || true
	uwsgi --ini /etc/keystone/keystone-uwsgi.ini &
	apache2ctl -DFOREGROUND &
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" | tee -a "$LOG_FILE"
	exit 1
	;;
esac

bootstrap_keystone
runCheck
printSummary |& tee -a "$LOG_FILE"

