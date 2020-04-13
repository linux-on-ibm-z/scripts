#!/bin/bash
# ©  Copyright IBM Corporation 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Logstash/7.6.1/build_logstash.sh
# Execute build script: bash build_logstash.sh    (provide -h for help)
#

set -e -o pipefail

PACKAGE_NAME="logstash"
PACKAGE_VERSION="7.6.1"
FORCE=false
CURDIR="$(pwd)"
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
NON_ROOT_USER="$(whoami)"

trap cleanup 1 2 ERR

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
        mkdir -p "$CURDIR/logs/"
fi


if [ -f "/etc/os-release" ]; then
        source "/etc/os-release"
fi

function prepare() {
        if command -v "sudo" >/dev/null; then
                printf -- 'Sudo : Yes\n'
        else
                printf -- 'Sudo : No \n'
                printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n'
                exit 1
        fi

        if [[ "$FORCE" == "true" ]]; then
                printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "${LOG_FILE}"
        else
                # Ask user for prerequisite installation
                printf -- "\nAs part of the installation, dependencies would be installed/upgraded. \n"
                while true; do
                        read -r -p "Do you want to continue (y/n) ? :  " yn
                        case $yn in
                        [Yy]*)
                                printf -- 'User responded with Yes. \n' |& tee -a "${LOG_FILE}"
                                break
                                ;;
                        [Nn]*) exit ;;
                        *) echo "Please provide confirmation to proceed." ;;
                        esac
                done
        fi
}

function cleanup() {
        sudo rm -rf "${CURDIR}/jffi-1.2.21.tar.gz" "${CURDIR}/logstash-oss-${PACKAGE_VERSION}.tar.gz"
        printf -- 'Cleaned up the artifacts\n' >>"${LOG_FILE}"
}

function configureAndInstall() {

        printf -- 'Configuration and Installation started \n'

        # Set JAVA_HOME
        if [[ "$ID" == "rhel" ]]; then
            export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk/
        elif [[ "$ID" == "sles" ]]; then
            export JAVA_HOME=/usr/lib64/jvm/java-1.8.0-openjdk/
        else
            export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk-s390x/
        fi
        export PATH=$JAVA_HOME/bin:$PATH

        # Install jffi ( RHEL/SLES )
	if [[ "$ID" == "rhel" || "$ID" == "sles" ]]; then
		printf -- 'Installing jffi.\n'
		cd "${CURDIR}"
		sudo mkdir -p /usr/local/jffi
		sudo wget https://github.com/jnr/jffi/archive/jffi-1.2.21.tar.gz
		sudo tar -xzvf jffi-1.2.21.tar.gz -C /usr/local/jffi --strip-components 1
		sudo chown "$(whoami)" -R /usr/local/jffi
		cd /usr/local/jffi
		ant
		export LD_LIBRARY_PATH=$CURDIR/jffi-jffi-1.2.21/build/jni/:$CURDIR/jffi-jffi-1.2.21/build/jni/libffi-s390x-linux/.libs:$LD_LIBRARY_PATH
	fi

        # Downloading and installing Logstash
        printf -- 'Downloading and installing Logstash.\n'
        cd "${CURDIR}"
        wget https://artifacts.elastic.co/downloads/logstash/logstash-"$PACKAGE_VERSION".tar.gz

        sudo mkdir /usr/share/logstash
        sudo tar -xzf logstash-"$PACKAGE_VERSION".tar.gz  -C /usr/share/logstash --strip-components 1
        sudo ln -sf /usr/share/logstash/bin/* /usr/bin

        if ([[ -z "$(cut -d: -f1 /etc/group | grep elastic)" ]]); then
                printf -- '\nCreating group elastic.\n'
                sudo /usr/sbin/groupadd elastic # If group is not already created
        fi
        sudo chown "$NON_ROOT_USER:elastic" -R /usr/share/logstash

        # Recreating jruby-complete jar file to include platform.conf
        printf -- 'Applying fix for ffi java.lang.NullPointerException exception.\n' |& tee -a "${LOG_FILE}"
        cd /usr/share/logstash/logstash-core/lib/jars
        unzip jruby-complete-9.2.9.0.jar -d jruby-complete-9.2.9.0
        cd jruby-complete-9.2.9.0/META-INF/jruby.home/lib/ruby/stdlib/ffi/platform/s390x-linux
        cp -n types.conf platform.conf
        cd /usr/share/logstash/logstash-core/lib/jars/jruby-complete-9.2.9.0
        zip -r ../jruby-complete-9.2.9.0.jar *
        cd  /usr/share/logstash/
        rm -rf /usr/share/logstash/logstash-core/lib/jars/jruby-complete-9.2.9.0
        printf -- 'Recreated jruby-complete jar file to include platform.conf\n' |& tee -a "${LOG_FILE}"

        printf -- 'Installed Logstash successfully \n'

        # Cleanup
        cleanup

        # Verifying Logstash installation
        if command -v "$PACKAGE_NAME" >/dev/null; then
                printf -- "%s installation completed. Please check the Usage to start the service.\n" "$PACKAGE_NAME"
        else
                printf -- "Error while installing %s, exiting with 127 \n" "$PACKAGE_NAME"
                exit 127
        fi
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
        echo "  install.sh  [-d debug] [-y install-without-confirmation]"
        echo
}

while getopts "h?dy" opt; do
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
        esac
done

function gettingStarted() {
        printf -- '\n********************************************************************************************************\n'
        printf -- "\n* Getting Started * \n"
        printf -- "Run Logstash: \n"
        printf -- "    export LD_LIBRARY_PATH=/usr/local/jffi/build/jni:\$LD_LIBRARY_PATH (For RHEL/SLES) \n"
	printf -- "    export LD_LIBRARY_PATH=/usr/lib/s390x-linux-gnu/jni:\$LD_LIBRARY_PATH (For Ubuntu) \n"
        printf -- "    logstash -V \n\n"
        printf -- "You may use either JDK 8 or 11 for running Logstash. Be sure to set JAVA_HOME accordingly.\n"
        printf -- "Visit https://www.elastic.co/support/matrix#matrix_jvm for more information.\n\n"
        printf -- '********************************************************************************************************\n'
}

###############################################################################################################

logDetails
prepare

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo apt-get update
        sudo apt-get install -y ant gcc gzip openjdk-8-jdk make tar unzip wget zip libjffi-jni |& tee -a "${LOG_FILE}"
        export LD_LIBRARY_PATH=/usr/lib/s390x-linux-gnu/jni/:$LD_LIBRARY_PATH
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"rhel-7.5" | "rhel-7.6" | "rhel-7.7")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo yum install -y ant gcc gzip java-1.8.0-openjdk make tar unzip wget zip |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"sles-12.4" | "sles-12.5")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo zypper install -y ant gawk gcc gzip java-1_8_0-openjdk-devel make tar unzip wget zip |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

*)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "${LOG_FILE}"
        exit 1
        ;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
