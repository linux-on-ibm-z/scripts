#!/usr/bin/env bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/RabbitMQ/build_rabbitmq.sh
# Execute build script: bash build_rabbitmq.sh    (provide -h for help)
#

set -e -o pipefail

PACKAGE_NAME="rabbitmq"
PACKAGE_VERSION="3.7.8"
LOG_FILE="logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
OVERRIDE=false
CURDIR="$PWD"

trap cleanup 1 2 ERR

#Check if directory exsists
if [ ! -d "logs" ]; then
	mkdir -p "logs"
fi

# Need handling for RHEL 6.10 as it doesn't have os-release file
if [ -f "/etc/os-release" ]; then
	source "/etc/os-release"
else
	cat /etc/redhat-release >>"${LOG_FILE}"
	export ID="rhel"
	export VERSION_ID="6.x"
	export PRETTY_NAME="Red Hat Enterprise Linux 6.x"
fi

function checkPrequisites() {
	if command -v "sudo" >/dev/null; then
		printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
	else
		printf -- 'Sudo : No \n' >>"$LOG_FILE"
		printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n'
		exit 1
	fi

}

function cleanup() {
	printf -- 'Started cleanup\n'
	rm -rf "${CURDIR}/rabbitmq-server-3.7.8.tar.xz"
	rm -rf "${CURDIR}/otp_src_21.0.tar.gz"
	printf -- 'Cleaned up successfull\n'
}

function startServer() {
	printf -- 'Starting RabbitMQ server \n'
	cd "${CURDIR}/rabbitmq-server-3.7.8"
	sudo make run-broker

	printf -- 'Running RabbitMQ from script \n'
	#Running RabbitMQ from script(Optional)
	sudo mkdir -p /etc/rabbitmq
	cd "${CURDIR}/rabbitmq-server-3.7.8"
	sudo ln -s $PWD/plugins deps/rabbit/plugins
	sudo deps/rabbit/scripts/rabbitmq-plugins enable rabbitmq_management
	sudo deps/rabbit/scripts/rabbitmq-server

}

function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'

	if [[ "${OVERRIDE}" == "true" ]]; then
		printf -- 'Rabbitmq exists on the system. Override flag is set to true hence updating the same\n '
	fi

	if [[ "${VERSION_ID}" != "18.04" ]]; then
		if [[ "${ID}" == "rhel" ]]; then
			export JAVA_HOME=/usr/lib/jvm/java ### only for RHEL distributions
		fi

		if [[ "${ID}" == "sles" ]]; then
			export JAVA_HOME=/usr/lib64/jvm/java ### only for SLES distributions
		fi

    cd "${CURDIR}"
    wget http://www.erlang.org/download/otp_src_21.0.tar.gz
    tar zxf otp_src_21.0.tar.gz
    cd otp_src_21.0
    export ERL_TOP="${CURDIR}/otp_src_21.0"
    ./configure --prefix=/usr
    make
    sudo make install

		if [[ "${VERSION_ID}" == "16.04" ]]; then
			export PATH=$PATH:$ERL_TOP/bin:/usr/lib/erlang/lib/erl_interface-3.10/bin/
		else
			export ANT_HOME=/usr/share/ant
			export PATH=$PATH:$ERL_TOP/bin:/usr/lib/erlang/lib/erl_interface-3.10/bin/:$JAVA_HOME/bin:$ANT_HOME
		fi
	fi

	cd "${CURDIR}"
	# Install elixir
	printf -- 'Downloading and installing elixir \n'
	git clone git://github.com/elixir-lang/elixir
	cd elixir && git checkout v1.6.6
	make
	sudo make install
	elixir --version
	printf -- 'Installed elixir successfully \n'

	cd "${CURDIR}"
	# Install hex
	printf -- 'Downloading and installing hex \n'
	git clone git://github.com/hexpm/hex.git
	cd hex && git checkout v0.18.1
	mix install
	mix hex.info
	printf -- 'Installed hex successfully \n'

	cd "${CURDIR}"
	# Install rabbitmq
	printf -- 'Downloading and installing rabbitmq \n'
	wget https://dl.bintray.com/rabbitmq/all/rabbitmq-server/3.7.8/rabbitmq-server-3.7.8.tar.xz
	tar -xf rabbitmq-server-3.7.8.tar.xz
	cd rabbitmq-server-3.7.8
	sudo cp ${CURDIR}/hex/_build/dev/lib/hex/ebin/* deps/.mix/archives/hex-0.18.1/hex-0.18.1/ebin/
	make
	sudo make install
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
	echo "  build_rabbitmq.sh [-d debug] [-v package version] [-o override] [-p check-prequisite]"
	echo "       default: If no -v specified, latest version will be installed"
	echo
}

while getopts "h?dopv:" opt; do
	case "$opt" in
	h | \?)
		printHelp
		exit 0
		;;
	d)
		set -x
		;;
	v)
		PACKAGE_VERSION="$OPTARG"
		;;
	o)
		OVERRIDE=true
		;;
	p)
		checkPrequisites
		exit 0
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
checkPrequisites #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
	sudo apt-get update
	sudo apt-get install -y ant openjdk-8-jdk openssl wget tar xz-utils make python xsltproc rsync git perl gcc g++ libncurses-dev libncurses5-dev unixodbc unixodbc-dev libssl-dev libwxgtk3.0-dev fop libxml2-utils zip sed |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"ubuntu-18.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
	sudo apt-get update
	sudo apt-get install -y ant openjdk-8-jdk erlang openssl wget tar xz-utils make python xsltproc rsync git zip curl wget sed make |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"rhel-7.3" | "rhel-7.4" | "rhel-7.5" | "rhel-7.6" | "rhel-6.x")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for rabbitmq from repository \n' |& tee -a "$LOG_FILE"
	sudo yum install -y c perl gcc gcc-c++ openssl openssl-devel ncurses-devel ncurses unixODBC unixODBC-devel fop java-1.8.0-openjdk-devel gzip findutils zip unzip libxslt xmlto patch subversion ca-certificates ant ant-junit xz xz-devel git wget tar curl sed make |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

"sles-12.3")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
	printf -- 'Installing the dependencies for rabbitmq from repository \n' |& tee -a "$LOG_FILE"
	sudo zypper install -y java-1_8_0-openjdk java-1_8_0-openjdk-devel perl gcc gcc-c++ libopenssl-devel libssh-devel ncurses-devel unixODBC unixODBC-devel xmlgraphics-fop tar wget curl zip unzip libxslt xmlto patch subversion procps ant ant-junit git-core sed make |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

"sles-15")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
	printf -- 'Installing the dependencies for rabbitmq from repository \n' |& tee -a "$LOG_FILE"
	sudo zypper install -y java-1_8_0-openjdk java-1_8_0-openjdk-devel perl gcc gcc-c++ libopenssl-devel libssh-devel ncurses-devel unixODBC unixODBC-devel tar wget curl zip unzip libxslt xmlto patch subversion procps ant ant-junit git-core python-devel python-xml sed make |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

#startServer
gettingStarted |& tee -a "${LOG_FILE}"
