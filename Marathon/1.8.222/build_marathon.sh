#!/bin/bash
# © Copyright IBM Corporation 2020, 2021.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Marathon/1.8.222/build_marathon.sh
# Execute build script: bash build_marathon.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="marathon"
PACKAGE_VERSION="1.8.222"
CURDIR="$(pwd)"
SOURCE_ROOT="$(pwd)"
JAVA_FLAV="ibmsdk"
VERSION=`cat /etc/os-release | grep VERSION_ID| cut -d '"' -f 2`

TESTS="false"
FORCE="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

# Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
    mkdir -p "$CURDIR/logs/"
fi

if [ -f "/etc/os-release" ]; then
    source "/etc/os-release"
fi

function prepare() {
    if command -v "sudo" >/dev/null; then
        printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
    else
        printf -- 'Sudo : No \n' >>"$LOG_FILE"
        printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n'
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
   	rm -rf "$SOURCE_ROOT/sbt-1.1.1.tgz"
	rm -rf "$SOURCE_ROOT/marathon"

    printf -- "Cleaned up the artifacts\n"
}

function configureAndInstall() {
  printf -- "Configuration and Installation started \n"

 	# Installing IBM SDK 8 for Ubuntu
	if [[ "$ID" == "ubuntu" ]]  ;then
		if [[ "$JAVA_FLAV" == "ibmsdk" ]]  ;then
			printf -- "Installing IBM SDK 8 for %s \n" "$DISTRO"
			cd "$SOURCE_ROOT"
			wget http://public.dhe.ibm.com/ibmdl/export/pub/systems/cloud/runtimes/java/8.0.6.15/linux/s390x/ibm-java-s390x-sdk-8.0-6.15.bin
			echo -en 'INSTALLER_UI=silent\nUSER_INSTALL_DIR=/opt/java-1.8.0-ibm\nLICENSE_ACCEPTED=TRUE' > installer.properties
			sudo bash ibm-java-s390x-sdk-8.0-6.15.bin -i silent -f installer.properties || true
		fi
	fi

  # Setting up Java environment variables
  if [[ "$ID" == "rhel"  ]] ;then
		if [[ "$JAVA_FLAV" == "openjdk" ]]; then
			export JAVA_HOME=/usr/lib/jvm/java-1.8.0
		else
			export JAVA_HOME=/usr/lib/jvm/java-1.8.0-ibm
		fi
  fi

  if [[ "$ID" == "sles"  ]] ;then
		if [[ "$JAVA_FLAV" == "openjdk" ]]; then
			export JAVA_HOME=/usr/lib64/jvm/java-1.8.0
		else
			export JAVA_HOME=/usr/lib64/jvm/java-1.8.0-ibm
		fi
  fi

  if [[ "$ID" == "ubuntu"  ]] ;then
		if [[ "$JAVA_FLAV" == "openjdk" ]]; then
			export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk-s390x
		else
			export JAVA_HOME=/opt/java-1.8.0-ibm
		fi
  fi

  export JAVA_TOOL_OPTIONS='-Xmx2048M'
	export PATH=$JAVA_HOME/bin:$PATH
	export SBT_OPTS="-Xmx2g"

	printf -- "Java version is :\n"
	java -version

	#Installing sbt
	printf -- "Installing sbt..\n"
	cd $SOURCE_ROOT
	wget https://github.com/sbt/sbt/releases/download/v1.2.7/sbt-1.2.7.tgz
	tar -zxvf sbt-1.2.7.tgz
	sudo cp $SOURCE_ROOT/sbt/bin/* /usr/local/bin

   	#Building Marathon
	printf -- "Building Marathon\n"
	cd $SOURCE_ROOT
	git clone https://github.com/mesosphere/marathon.git
	cd marathon
	git checkout v1.8.222
	sbt stage

	#Package Marathon into a tarball
    sbt universal:packageZipTarball

	sudo cp -r $SOURCE_ROOT/marathon /usr/share

cd $HOME
cat << EOF > setenv.sh
#MARATHON ENV
export JAVA_HOME=$JAVA_HOME
export JAVA_TOOL_OPTIONS='-Xmx2048M'
export PATH=$JAVA_HOME/bin:$PATH
export SBT_OPTS="-Xmx2g"
export LD_LIBRARY_PATH=/usr/local/lib:/usr/lib
EOF

    	printf -- "Built and installed Marathon successfully.\n"

    	cleanup
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
    echo "Usage: Builds using IBM_SDK java by default."
    echo " build_marathon.sh  [-o build-with-OpenJDK] [-d debug] [-y install-without-confirmation] "
    echo
}

while getopts "h?dyo" opt; do
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
    o)
	JAVA_FLAV="openjdk"
	;;
    esac
done

function gettingStarted() {
    printf -- '\n********************************************************************************************************\n'
    printf -- "\n* Getting Started * \n"
    printf -- "Running Marathon on your local machine:\n\n"
    printf -- "Start Zookeeper service using following commands:  \n"
    printf -- "  $ cd /usr/share/mesos/build/3rdparty/zookeeper-3.4.8\n"
    printf -- "  $ cp conf/zoo_sample.cfg conf/zoo.cfg\n"
    printf -- "  $ sudo env PATH=\$PATH ./bin/zkServer.sh start\n\n"
    printf -- "Start Marathon master using following commands: \n"
    printf -- "  $ source $HOME/setenv.sh \n"
    printf -- "  $ mesos-local --ip=<ip_address>\n"
    printf -- "  $ cd /usr/share/marathon \n"
    printf -- "  $ sbt 'run --master <ip_address>:5050 --zk zk://<ip_address>:2181/marathon'\n\n"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare # Check Prerequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"ubuntu-18.04" | "ubuntu-20.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
  if [[ "$JAVA_FLAV" == "openjdk" ]]; then
		printf -- "\nOpenJDK dependencies\n" |& tee -a "$LOG_FILE"
		sudo apt-get install -y git tar wget openjdk-8-jdk patch |& tee -a "$LOG_FILE"
	else
		printf -- "\nIBMSDK dependencies\n" |& tee -a "$LOG_FILE"
		sudo apt-get install -y git tar wget patch |& tee -a "$LOG_FILE"
	fi
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-7.6" | "rhel-7.7" | "rhel-7.8")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
	if [[ "$JAVA_FLAV" == "openjdk" ]]; then
		printf -- "\nOpenJDK dependencies\n" |& tee -a "$LOG_FILE"
		sudo yum install -y git tar wget java-1.8.0-openjdk-devel patch which |& tee -a "$LOG_FILE"
	else
		printf -- "\nIBMSDK dependencies\n" |& tee -a "$LOG_FILE"
		sudo yum -y install git tar wget java-1.8.0-ibm-devel patch which |& tee -a "$LOG_FILE"
	fi
	configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-8.1" | "rhel-8.2")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
		printf -- "\nOpenJDK dependencies\n" |& tee -a "$LOG_FILE"
		sudo yum install -y git tar wget java-1.8.0-openjdk-devel patch which |& tee -a "$LOG_FILE"
	  configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-12.5" | "sles-15.1")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    if [[ "$JAVA_FLAV" == "openjdk" ]]; then
		printf -- "\nOpenJDK dependencies\n" |& tee -a "$LOG_FILE"
		sudo zypper install --auto-agree-with-licenses -y git wget tar java-1_8_0-openjdk-devel patch which |& tee -a "$LOG_FILE"
	else
		printf -- "\nIBMSDK dependencies\n" |& tee -a "$LOG_FILE"
		if [[ "$VERSION_ID" == "12.4" ]]; then
			sudo zypper install --auto-agree-with-licenses -y git wget tar patch which |& tee -a "$LOG_FILE"
		else
			sudo zypper install --auto-agree-with-licenses -y git wget tar java-1_8_0-ibm-devel patch which |& tee -a "$LOG_FILE"
		fi
	fi
	configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
