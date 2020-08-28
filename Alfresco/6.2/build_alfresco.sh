#!/bin/bash
# © Copyright IBM Corporation 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Alfresco/6.2/build_alfresco.sh
# Execute build script: bash build_alfresco.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="alfresco"
PACKAGE_VERSION="6.2"
SOURCE_ROOT="$(pwd)"
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
    rm -rf "$SOURCE_ROOT/OpenJDK11U-jdk_s390x_linux_hotspot_11.0.7_10.tar.gz"
    rm -rf "$SOURCE_ROOT/jffi"
    rm -rf "$SOURCE_ROOT/jdk-11.0.7+10"
    rm -rf "$SOURCE_ROOT/alfresco-docker-base-java"
    rm -rf "$SOURCE_ROOT/alfresco-docker-base-tomcat"
    rm -rf "$SOURCE_ROOT/apache-maven-3.6.3-bin.tar.gz"
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}


function configureAndInstall() {
    printf -- "Configuration and Installation started \n"
    printf -- "Download and install Java \n"
    cd $SOURCE_ROOT
    wget https://github.com/AdoptOpenJDK/openjdk11-binaries/releases/download/jdk-11.0.7%2B10/OpenJDK11U-jdk_s390x_linux_hotspot_11.0.7_10.tar.gz
    tar -xf OpenJDK11U-jdk_s390x_linux_hotspot_11.0.7_10.tar.gz
    sudo mkdir -p /usr/lib/jvm
    sudo cp -r jdk-11.0.7+10 /usr/lib/jvm/
    #Only for RHEL and SLES
    if [[ "${ID}" != "ubuntu" ]]; then
        export PATH=/usr/sbin:$PATH  #Only for RHEL and SLES
    fi
    sudo update-alternatives --install "/usr/bin/java" "java" "/usr/lib/jvm/jdk-11.0.7+10/bin/java" 0
    sudo update-alternatives --install "/usr/bin/javac" "javac" "/usr/lib/jvm/jdk-11.0.7+10/bin/javac" 0
    sudo update-alternatives --set java "/usr/lib/jvm/jdk-11.0.7+10/bin/java"
    sudo update-alternatives --set javac "/usr/lib/jvm/jdk-11.0.7+10/bin/javac"
    export JAVA_HOME="$(readlink -f /etc/alternatives/javac | sed 's:/bin/javac::')"
    printf -- "Java is installed successfully \n"
    
    #Install maven (for SLES and RHEL 7.x)
    if [[ "${ID}" == "sles" || "${VERSION_ID}" =~ "7." ]]; then
        
        printf -- "Installing Maven\n"
        cd $SOURCE_ROOT
        wget https://archive.apache.org/dist/maven/maven-3/3.6.3/binaries/apache-maven-3.6.3-bin.tar.gz
        tar -xvzf apache-maven-3.6.3-bin.tar.gz
        export PATH=$SOURCE_ROOT/apache-maven-3.6.3/bin:$PATH
        printf -- "maven installed successfully \n"
    fi

    # Build alfresco-base-java image
    printf -- "Building alfresco-base-java image\n"
    cd $SOURCE_ROOT
    git clone https://github.com/Alfresco/alfresco-docker-base-java
    cd alfresco-docker-base-java
    sed -i "s/centos/s390x\/clefos/g" Dockerfile
    cp $SOURCE_ROOT/OpenJDK11U-jdk_s390x_linux_hotspot_11.0.7_10.tar.gz .
    export java_filename='OpenJDK11U-jdk_s390x_linux_hotspot_11.0.7_10.tar.gz'
    docker build --build-arg JAVA_PKG="${java_filename}" -t alfresco/alfresco-base-java .
    printf -- "alfresco-base-java image is built successfully\n"
    #Build alfresco-base-tomcat image
    cd $SOURCE_ROOT
    git clone https://github.com/Alfresco/alfresco-docker-base-tomcat
    cd alfresco-docker-base-tomcat
    docker build -t alfresco/alfresco-base-tomcat:8.5.43-java-11-openjdk-centos-7 --build-arg ALFRESCO_BASE_JAVA=alfresco/alfresco-base-java:latest .


    #Build acs-community-packaging docker image
    cd $SOURCE_ROOT
    git clone https://github.com/Alfresco/acs-community-packaging.git
    cd acs-community-packaging
    git checkout acs-community-packaging-6.2.0-ga
    cd docker-alfresco 
    mvn clean install
    docker build --tag alfresco/alfresco-content-repository-community:6.2.0-ga .

    #Build Alfresco share
    #Switch jdk to use Openjdk
    if [[ "${ID}" == "ubuntu" ]]; then
        sudo update-alternatives --set java "/usr/lib/jvm/java-8-openjdk-s390x/jre/bin/java"
        sudo update-alternatives --set javac "/usr/lib/jvm/java-8-openjdk-s390x/bin/javac"
        export JAVA_HOME="$(readlink -f /etc/alternatives/javac | sed 's:/bin/javac::')"
    elif [[ "${ID}" == "sles" ]]; then
        sudo update-alternatives --set java "/usr/lib64/jvm/jre-1.8.0-openjdk/bin/java"
        sudo update-alternatives --set javac "/usr/lib64/jvm/java-1.8.0-openjdk/bin/javac"
        export JAVA_HOME="$(readlink -f /etc/alternatives/javac | sed 's:/bin/javac::')"       
    else
        sudo update-alternatives --set java "java-1.8.0-openjdk.s390x"
        sudo update-alternatives --set javac "java-1.8.0-openjdk.s390x"
        export JAVA_HOME="$(readlink -f /etc/alternatives/javac | sed 's:/bin/javac::')"
    fi

    #Build native jffi jar
    cd $SOURCE_ROOT
    git clone https://github.com/jnr/jffi.git
    cd jffi
    git checkout 1.2.11
    curl https://github.com/jnr/jffi/commit/e2c2a92d88b78b82f8803d7b16a19898ffdc8652.patch  | git apply
    ant jar && ant archive-platform-jar && mvn package
    mkdir -p ~/.m2/repository/com/github/jnr/jffi/1.2.11
    cp target/jffi-1.2.11-native.jar ~/.m2/repository/com/github/jnr/jffi/1.2.11

    #Revert to Adoptopenjdk 11
    sudo update-alternatives --set java "/usr/lib/jvm/jdk-11.0.7+10/bin/java"
    sudo update-alternatives --set javac "/usr/lib/jvm/jdk-11.0.7+10/bin/javac"
    export JAVA_HOME="$(readlink -f /etc/alternatives/javac | sed 's:/bin/javac::')"

    #Fix libc library for SLES 12.x
    if [[ "${VERSION_ID}" == "12.5" || "${VERSION_ID}" == "7.8" ]]; then
        printf -- "Replacing libc library\n"
        sudo cp /lib64/libc-* /lib/
    fi

    #Build share docker image
    cd $SOURCE_ROOT
    git clone https://github.com/Alfresco/share.git
    cd share
    git checkout alfresco-share-parent-6.2.0
    cd packaging/docker
    mvn install -Dimage.tag=6.2.0 -Plocal

    #Build Alfresco Search Services
    cd $SOURCE_ROOT
    git clone https://github.com/Alfresco/SearchServices.git
    cd SearchServices
    git checkout 1.4.0
    sed  -i "/yum update/d" search-services/packaging/src/docker/Dockerfile
    sed -i "s/11.0.1-openjdk-centos-7-3e4e9f4e5d6a/latest/g" search-services/packaging/src/docker/Dockerfile
    cd $SOURCE_ROOT/SearchServices/search-services
    mvn clean install -DskipTests=true
    cd packaging/target/docker-resources/
    docker build -t alfresco/alfresco-search-services:1.4.0 .

    #Build Alfresco Activemq
    cd $SOURCE_ROOT
    git clone https://github.com/Alfresco/alfresco-docker-activemq.git
    cd alfresco-docker-activemq
    sed -i "s/FROM.*/FROM alfresco\/alfresco-base-java:latest/g" Dockerfile
    docker build -t alfresco/alfresco-activemq:5.15.8 .

    #Build Alfresco acs-community-ingress
    cd $SOURCE_ROOT
    git clone https://github.com/Alfresco/acs-ingress.git
    cd acs-ingress
    git checkout acs-community-ngnix-1.0.0
    docker build -t alfresco/acs-community-ngnix:1.0.0 .

    #Fetch alfresco docker compose file
    cd $SOURCE_ROOT
    mkdir -p docker-compose-source
    cd docker-compose-source
    wget https://www.alfresco.com/system/files_force/docker-compose-6.2-ga.zip
    unzip docker-compose-6.2-ga.zip

    #Remove code relavant to third Party alfresco transformers (alfresco-pdf-renderer, imagemagick, libreoffice etc. ) 
    sed -i -e '34,41s/true/false/g' -e '35,39d' -e '42,46d' -e '52,90d' docker-compose.yml
    
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
    echo " build_alfresco.sh  [-d debug] [-y install-without-confirmation] "
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
    printf -- "\n*Getting Started * \n"
    printf -- "Run following steps to bring up alfresco service:\n"
    printf -- "cd $SOURCE_ROOT/docker-compose-source \n"
    printf -- "docker-compose up \n"
    printf -- "\n\nOnce cluster is up Share UI will be available at https://localhost:8080/share \n"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"ubuntu-18.04" | "ubuntu-20.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y ant git gcc make sudo wget curl maven openjdk-8-jdk unzip |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-7.6" | "rhel-7.7" | "rhel-7.8")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y ant git gcc make sudo wget curl java-1.8.0-openjdk.s390x java-1.8.0-openjdk-devel.s390x unzip |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-8.1" | "rhel-8.2")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y ant texinfo git gcc make sudo wget curl maven java-1.8.0-openjdk.s390x java-1.8.0-openjdk-devel.s390x unzip |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;  
"sles-12.5" | "sles-15.1" | "sles-15.2")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y awk texinfo ant git gcc make sudo wget curl java-1_8_0-openjdk-devel unzip |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
