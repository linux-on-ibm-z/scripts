#!/usr/bin/env bash
# © Copyright IBM Corporation 2021.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/RabbitMQ/3.9.8/build_rabbitmq.sh
# Execute build script: bash build_rabbitmq.sh    

set -e -o pipefail
PACKAGE_NAME="rabbitmq"
PACKAGE_VERSION="3.9.8"
HEX_VERSION="0.21.3"
ELIXIR_VERSION="1.12.3"
ERLANG_VERSION="24.1"
LOG_FILE="logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
OVERRIDE=false
FORCE="false"
CURDIR="$PWD"
trap cleanup 1 2 ERR

#Check if directory exists
if [ ! -d "logs" ]; then
	mkdir -p "logs"
fi

if [ -f "/etc/os-release" ]; then
	source "/etc/os-release"
fi

function prepare() {
	if command -v "sudo" >/dev/null; then
		printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
	else
		printf -- 'Sudo : No \n' >>"$LOG_FILE"
		printf -- 'You can install sudo from repository using apt, yum or zypper based on your distro.. \n'
		exit 1
	fi
	if [[ "$FORCE" == "true" ]]; then
		printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
	else
		# Ask user for prerequisite installation
		printf -- "\nAs part of the installation , some dependencies will be installed, \n"
		while true; do
			read -r -p "Do you want to continue (y/n) ? :  " yn
			case $yn in
			[Yy]*)
				printf -- 'User responded with Yes. \n' >> "$LOG_FILE"
				break
				;;
			[Nn]*) exit ;;
			*) echo "Please provide confirmation to proceed." ;;
			esac
		done
	fi
}

function cleanup() {
	printf -- 'Started cleanup\n'
	rm -rf "${CURDIR}/rabbitmq-server-$PACKAGE_VERSION.tar.xz"
	printf -- 'Cleaned up successfully.\n'
}

# Only on RHEL7.x
function installPython() {
  cd "${CURDIR}"
  wget -q https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Python3/3.9.1/build_python3.sh
  bash build_python3.sh  -y
}

function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'
	if [[ "${OVERRIDE}" == "true" ]]; then
		printf -- 'Rabbitmq exists on the system. Override flag is set to true hence updating the same\n '
	fi
	
	if [[ "${DISTRO}" == "rhel-7."* ]]; then
		     printf -- "\nBuilding make 4.x \n"
	             cd "${CURDIR}"
		     wget https://ftp.gnu.org/gnu/make/make-4.2.tar.gz
		     tar -xvf make-4.2.tar.gz
		     cd make-4.2
		     ./configure 
		     make && sudo make install
		     export PATH=/usr/local/bin/:$PATH
		     printf -- 'Installed make successfully \n'
	fi
	
	cd "${CURDIR}"
	# Install Erlang
	printf -- "\nBuilding Erlang \n"
	wget -q https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Erlang/24.1/build_erlang.sh
	chmod +x build_erlang.sh
	bash build_erlang.sh -y
	export ERL_TOP=/usr/local/erlang
	export PATH=$PATH:$ERL_TOP/bin 
	printf -- 'Installed erlang successfully \n'
	sudo localedef -c -f UTF-8 -i en_US en_US.UTF-8
	export LC_ALL=en_US.UTF-8
	
	cd "${CURDIR}"
	# Install elixir
	printf -- 'Downloading and installing elixir \n'
	git clone git://github.com/elixir-lang/elixir
	cd elixir && git checkout v${ELIXIR_VERSION}
	make
	sudo env PATH=$PATH make install
	export PATH=/usr/local/bin:$PATH
	elixir --version
	printf -- 'Installed elixir successfully \n'

	cd "${CURDIR}"
	# Install hex
	printf -- 'Downloading and installing hex \n'
	git clone git://github.com/hexpm/hex.git
	cd hex && git checkout v${HEX_VERSION}
	mix install
	mix hex.info
	printf -- 'Installed hex successfully \n'

	cd "${CURDIR}"
	# Install rabbitmq
	printf -- 'Downloading and installing rabbitmq \n'
	wget https://github.com/rabbitmq/rabbitmq-server/releases/download/v$PACKAGE_VERSION/rabbitmq-server-$PACKAGE_VERSION.tar.xz
	tar -xf rabbitmq-server-$PACKAGE_VERSION.tar.xz
	cd rabbitmq-server-$PACKAGE_VERSION
	sudo cp ${CURDIR}/hex/_build/dev/lib/hex/ebin/* deps/.mix/archives/hex-$HEX_VERSION/hex-$HEX_VERSION/ebin/
	make
	if [[ "$ID" != "ubuntu" ]]; then
           sudo env PATH=$PATH make install
	else
	   sudo make install
	fi
	printf -- 'Installed rabbitmq successfully \n'

	#Clean up the downloaded zip
	cleanup
	cd "${CURDIR}"
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
	echo "bash build_rabbitmq.sh [-d debug] [-y install-without-confirmation] [-v package version] [-o override]"
	echo "       default: If no -v specified, latest version will be installed"
	echo
}

while getopts "h?doyv:" opt; do
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
	v)
		PACKAGE_VERSION="$OPTARG"
		;;
	o)
		OVERRIDE=true
		;;
	esac
done

function gettingStarted() {
	printf -- "\n\nUsage: \n"
	printf -- "  Note: RabbitMQ comes with default built-in settings \n"
	printf -- "  which will be sufficient for running your RabbitMQ server effectively. In case you need to customize the settings for the RabbitMQ server. \n"
	printf -- "  copy the rabbitmq.config file in /etc/rabbitmq directory. \n"
	printf -- "  To Start the server Follow Step 2 from the receipe : https://github.com/linux-on-ibm-z/docs/wiki/Building-RabbitMQ \n"
	printf -- "  More information can be found here : http://www.rabbitmq.com/ "
	printf -- '\n'
}
###############################################################################################################
logDetails
prepare
DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-18.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
	sudo apt-get update
	sudo apt-get install -y locales ant  openssl wget tar xz-utils make python3 xsltproc rsync git zip sed wget tar make perl openssl gcc g++ libncurses-dev libncurses5-dev unixodbc unixodbc-dev libssl-dev openjdk-8-jdk libwxgtk3.0-dev xsltproc fop libxml2-utils |& tee -a "${LOG_FILE}"
	sudo ln -sf /usr/bin/python3 /usr/bin/python
	configureAndInstall |& tee -a "$LOG_FILE"
	;;
"ubuntu-20.04" | "ubuntu-21.04" | "ubuntu-21.10")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
	sudo apt-get update
	sudo apt-get install -y locales ant  openssl wget tar xz-utils make python3 xsltproc rsync git zip sed wget tar make perl openssl gcc g++ libncurses-dev libncurses5-dev unixodbc unixodbc-dev libssl-dev openjdk-8-jdk xsltproc fop libxml2-utils |& tee -a "${LOG_FILE}"
	sudo ln -sf /usr/bin/python3 /usr/bin/python
	configureAndInstall |& tee -a "$LOG_FILE"
	;;
"rhel-7.8" | "rhel-7.9")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for rabbitmq from repository \n' |& tee -a "$LOG_FILE"
	sudo yum install -y sed glibc-common gcc gcc-c++ gzip findutils zip unzip libxslt xmlto patch subversion ca-certificates ant ant-junit xz xz-devel git wget tar make curl java-1.8.0-ibm java-1.8.0-ibm-devel wget tar make perl gcc gcc-c++ openssl openssl-devel ncurses-devel ncurses unixODBC unixODBC-devel fop hostname |& tee -a "${LOG_FILE}"
	installPython
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;
"rhel-8.2" |"rhel-8.4")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for rabbitmq from repository \n' |& tee -a "$LOG_FILE"
	sudo yum install -y sed  make glibc-common gcc gcc-c++ gzip findutils zip unzip libxslt xmlto patch subversion ca-certificates ant xz xz-devel git wget tar make curl java-1.8.0-openjdk java-1.8.0-openjdk-devel perl gcc openssl-devel ncurses-devel ncurses unixODBC unixODBC-devel glibc-locale-source glibc-langpack-en python3 rsync hostname diffutils |& tee -a "${LOG_FILE}"
	sudo alternatives --set python /usr/bin/python3
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;
"sles-12.5" | "sles-15.2" | "sles-15.3")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
	printf -- 'Installing the dependencies for rabbitmq from repository \n' |& tee -a "$LOG_FILE"
	sudo zypper install -y make tar wget gcc gcc-c++ glibc-locale glibc-i18ndata sed curl zip unzip libxslt xmlto patch subversion procps ant ant-junit git-core python3-devel python3-xml java-1_8_0-openjdk  java-1_8_0-openjdk-devel wget tar make perl gcc gcc-c++ libopenssl-devel libssh-devel ncurses-devel unixODBC unixODBC-devel xz gzip gawk net-tools |& tee -a "${LOG_FILE}"
	sudo ln -sf /usr/bin/python3 /usr/bin/python
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;
*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac
gettingStarted |& tee -a "${LOG_FILE}"
