#!/bin/bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ApacheCassandra/3.11.4/build_cassandra.sh
# Execute build script: bash build_cassandra.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="cassandra"
PACKAGE_VERSION="3.11.4"
CURDIR="$(pwd)"
CONF_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ApacheCassandra/3.11.4/patch"

FORCE="false"
TESTS="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
   mkdir -p "$CURDIR/logs/"
fi

# Need handling for RHEL 6.10 as it doesn't have os-release file
if [ -f "/etc/os-release" ]; then
    source "/etc/os-release"
else
    cat /etc/redhat-release >> "${LOG_FILE}"
    export ID="rhel"
    export VERSION_ID="6.x"
    export PRETTY_NAME="Red Hat Enterprise Linux 6.x"
fi


function prepare() {
    if  command -v "sudo" > /dev/null ;
    then
        printf -- 'Sudo : Yes\n' >> "$LOG_FILE"
    else
        printf -- 'Sudo : No \n' >> "$LOG_FILE"
        printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n';
    exit 1;
    fi;
   
    if [[ "$FORCE" == "true" ]] ;
    then
        printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
    else
        # Ask user for prerequisite installation
        printf -- "\nAs part of the installation , dependencies would be installed/upgraded.\n";
        while true; do
		    read -r -p "Do you want to continue (y/n) ? :  " yn
		    case $yn in
  	 		    [Yy]* ) printf -- 'User responded with Yes. \n' >> "$LOG_FILE"; 
	                    break;;
    		    [Nn]* ) exit;;
    		    *) 	echo "Please provide confirmation to proceed.";;
	 	    esac
        done
    fi	
}


function cleanup() {
    # Remove artifacts
    rm -rf "${CURDIR}/jvm.options.diff"
    rm -rf "${CURDIR}/build.xml.diff"
    rm -rf "${CURDIR}/cassandra.yaml.diff"
    rm -rf "${CURDIR}/jna"

    printf -- "Cleaned up the artifacts\n" >> "$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"
    
    # Install Ant
    cd "$CURDIR"
    wget http://archive.apache.org/dist/ant/binaries/apache-ant-1.10.4-bin.tar.gz
    tar -xvf apache-ant-1.10.4-bin.tar.gz

    printf -- "Install Ant success\n" >> "$LOG_FILE"
	
    if [[ "$ID" == "sles" ]]; 
    then
		export JAVA_HOME=/usr/lib64/jvm/java-1.8.0-openjdk
		printf -- 'export JAVA_HOME for sles  \n'  >> "$LOG_FILE"
    else
		# Install AdoptOpenJDK 8 (With Hotspot)
		cd "$CURDIR"
		wget https://github.com/AdoptOpenJDK/openjdk8-binaries/releases/download/jdk8u202-b08/OpenJDK8U-jdk_s390x_linux_hotspot_8u202b08.tar.gz
		tar -xvf OpenJDK8U-jdk_s390x_linux_hotspot_8u202b08.tar.gz
		printf -- "Install AdoptOpenJDK 8 (With Hotspot) success\n" >> "$LOG_FILE"
		export JAVA_HOME=$CURDIR/jdk8u202-b08 
		printf -- 'export JAVA_HOME for "$ID"  \n'  >> "$LOG_FILE"		 
    fi

    export LANG="en_US.UTF-8"
    export JAVA_TOOL_OPTIONS="-Dfile.encoding=UTF8"  
    export PATH=$JAVA_HOME/bin:$PATH
    export ANT_OPTS="-Xms4G -Xmx4G"
    export ANT_HOME="$CURDIR/apache-ant-1.10.4"
    export PATH=$ANT_HOME/bin:$PATH
    java -version
    
    # Download  source code
    cd "$CURDIR"
    git clone -b cassandra-"${PACKAGE_VERSION}" https://github.com/apache/cassandra.git

    printf -- 'Download source code success \n'  >> "$LOG_FILE"

    cd "$CURDIR"

    # Patch build.xml file
	curl -o "build.xml.diff"  $CONF_URL/build.xml.diff
	# replace config file
	patch "${CURDIR}/cassandra/build.xml" build.xml.diff
	printf -- 'Patched build.xml \n'  >> "$LOG_FILE"
    
    # Patch jvm.options file
	curl -o "jvm.options.diff"  $CONF_URL/jvm.options.diff
	# replace config file
	patch "${CURDIR}/cassandra/conf/jvm.options" jvm.options.diff
	printf -- 'Patched jvm.options \n'  >> "$LOG_FILE" 
   
    # Patch cassandra.yaml file
	curl -o "cassandra.yaml.diff"  $CONF_URL/cassandra.yaml.diff
	# replace config file
	patch "${CURDIR}/cassandra/test/conf/cassandra.yaml" cassandra.yaml.diff
	printf -- 'Patched cassandra.yaml \n'   >> "$LOG_FILE"
    

    # Build Apache Cassandra
    cd "$CURDIR/cassandra"
    ant

    printf -- 'Build Apache Cassandra success \n'  >> "$LOG_FILE"

    # Replace Snappy-Java
    cd "$CURDIR/cassandra"
    rm lib/snappy-java-1.1.1.7.jar
    wget -O lib/snappy-java-1.1.2.6.jar http://central.maven.org/maven2/org/xerial/snappy/snappy-java/1.1.2.6/snappy-java-1.1.2.6.jar 

    printf -- 'Replace Snappy-Java success \n' >> "$LOG_FILE"

    
    # Build and replace JNA
    cd "$CURDIR"
    git clone -b 4.2.2 https://github.com/java-native-access/jna.git

    cd "$CURDIR"/jna
    ant
    
    rm "$CURDIR/cassandra/lib/jna-4.2.2.jar"
    cp build/jna.jar "$CURDIR/cassandra/lib/jna-4.2.2.jar"

    printf -- 'Build and replace JNA success \n' 

    #Copy cassandra to /usr/local/
    sudo cp -r "$CURDIR/cassandra" "/usr/local/"
    sudo chown -R "$USER" "/usr/local/cassandra"

    export PATH=/usr/local/cassandra/bin:$PATH
    #Adding dependencies to path 
    echo "export PATH=$PATH" >> ~/.bashrc
    echo export JAVA_TOOL_OPTIONS="-Dfile.encoding=UTF8" >> ~/.bashrc
    echo export LANG="en_US.UTF-8" >> ~/.bashrc
    
    # Run Tests
    runTest

    #cleanup
    cleanup

}

function runTest() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- "TEST Flag is set, continue with running test \n"  >> "$LOG_FILE"
		cd "/usr/local/cassandra"
        ant test
        printf -- "Tests completed. \n" 
	fi
	set -e
}

function logDetails() {
    printf -- '**************************** SYSTEM DETAILS *************************************************************\n' >"$LOG_FILE"
    if [ -f "/etc/os-release" ]; then
        cat "/etc/os-release" >> "$LOG_FILE"
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
    echo " build_cassandra.sh  [-d debug] [-y install-without-confirmation] [-t install and run tests]"
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
    printf -- "\n*Getting Started * \n"
    printf -- "Run following command to get started: \n"
    
	printf -- "source ~/.bashrc \n"
    printf -- "Start cassandra server: \n"
    printf -- "cassandra  -f\n\n"
    
    printf -- "Open Command line in another terminal using command :\n"
    printf -- "cqlsh\n"
    printf -- "For more help visit http://cassandra.apache.org/doc/latest/getting_started/index.html"
    printf -- '**********************************************************************************************************\n'
}
    
logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
    "ubuntu-16.04" | "ubuntu-18.04")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo apt-get update
        sudo apt-get install -y curl git tar g++ make automake autoconf libtool wget patch libx11-dev libxt-dev pkg-config texinfo locales-all unzip python |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;
    "rhel-7.4" | "rhel-7.5" | "rhel-7.6")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo yum install -y curl git which gcc-c++ make automake autoconf libtool libstdc++-static tar wget patch words libXt-devel libX11-devel texinfo unzip python |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;
    "sles-12.4")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo zypper install -y curl git which make wget tar zip unzip words gcc-c++ patch libtool automake autoconf ccache java-1_8_0-openjdk-devel xorg-x11-proto-devel xorg-x11-devel alsa-devel cups-devel libffi48-devel libstdc++6-locale glibc-locale libstdc++-devel libXt-devel libX11-devel texinfo python |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;
    "sles-15")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo zypper install -y curl git which make wget tar zip unzip gcc-c++ patch libtool automake autoconf ccache java-1_8_0-openjdk-devel xorg-x11-proto-devel xorg-x11-devel alsa-devel cups-devel libffi-devel libstdc++6-locale glibc-locale libstdc++-devel libXt-devel libX11-devel texinfo python |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;
    *)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
        exit 1
        ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
