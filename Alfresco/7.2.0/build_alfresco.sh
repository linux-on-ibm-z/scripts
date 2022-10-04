#!/bin/bash
# © Copyright IBM Corporation 2022.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Alfresco/7.2.0/build_alfresco.sh
# Execute build script: bash build_alfresco.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="alfresco"
PACKAGE_VERSION="7.2.0"
SOURCE_ROOT="$(pwd)"
FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
JAVA_PROVIDED="IBMSemeru11"
BUILD_ENV="$HOME/setenv.sh"
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
    
    if command -v "docker" >/dev/null; then
        printf -- 'Docker : Yes\n' >>"$LOG_FILE"
    else
        printf -- 'Docker : No \n' >>"$LOG_FILE"
        printf -- 'Install Docker based on your distro. \n'
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
    rm -rf "$SOURCE_ROOT/jffi"
    rm -rf "$SOURCE_ROOT/alfresco-docker-base-java"
    rm -rf "$SOURCE_ROOT/alfresco-docker-base-tomcat"
    rm -rf "$SOURCE_ROOT/apache-maven-3.6.3-bin.tar.gz"
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}


function configureAndInstall() {
    printf -- "Configuration and Installation started \n"
    printf -- "Download and install Java \n"
    cd $SOURCE_ROOT
    if [ -d "/opt/java" ]; then sudo rm -Rf /opt/java; fi
    sudo mkdir -p /opt/java


 if [[ "$JAVA_PROVIDED" == "Temurin11" ]]; then
    # Install IBM Temurin11 Runtime   
    curl -SL -o adoptium_temurin.tar.gz https://github.com/adoptium/temurin11-binaries/releases/download/jdk-11.0.14.1%2B1/OpenJDK11U-jdk_s390x_linux_hotspot_11.0.14.1_1.tar.gz
    sudo tar -zxvf adoptium_temurin.tar.gz -C /opt/java --strip-components 1
    export JAVA_HOME=/opt/java
                printf -- "export JAVA_HOME=/opt/java\n" >> "$BUILD_ENV"
                printf -- "Installation of IBM Temurin11 Runtime 11 is successful\n" >> "$LOG_FILE"

        elif [[ "$JAVA_PROVIDED" == "IBMSemeru11" ]]; then
                
               # Install IBM Semeru Runtime
                    curl -SL -o semeru.tar.gz https://github.com/ibmruntimes/semeru11-binaries/releases/download/jdk-11.0.14.1%2B1_openj9-0.30.1/ibm-semeru-open-jdk_s390x_linux_11.0.14.1_1_openj9-0.30.1.tar.gz
                    # Everytime new jdk is downloaded, Ensure that --strip value is correct
                    sudo tar -zxvf semeru.tar.gz -C /opt/java --strip-components 1
                export JAVA_HOME=/opt/java
                printf -- "export JAVA_HOME=/opt/java\n" >> "$BUILD_ENV"
                printf -- "Installation of Eclipse Adoptium Temurin Runtime 11 is successful\n" >> "$LOG_FILE"
        else
                printf "$JAVA_PROVIDED is not supported, Please use valid java from {Temurin11, IBMSemeru11} only"
                exit 1
        fi
        printf -- "export PATH=$JAVA_HOME/bin:$PATH\n" >> "$BUILD_ENV"
        export PATH=$JAVA_HOME/bin:$PATH
        java -version |& tee -a "$LOG_FILE"

    #Only for RHEL and SLES
    if [[ "${ID}" != "ubuntu" ]]; then
        export PATH=/usr/sbin:$PATH  #Only for RHEL and SLES
    fi
    sudo update-alternatives --install "/usr/bin/java" "java" "/opt/java/bin/java" 40
    sudo update-alternatives --install "/usr/bin/javac" "javac" "/opt/java/bin/javac" 40
    sudo update-alternatives --set java "/opt/java/bin/java"
    sudo update-alternatives --set javac "/opt/java/bin/javac"
    export JAVA_HOME="$(readlink -f /etc/alternatives/javac | sed 's:/bin/javac::')"
    printf -- "Java is installed successfully \n"

    #Install maven (for SLES and RHEL 7.x)
    if [[ "${ID}" == "sles" || "${DISTRO}" == rhel-7* ]]; then
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
    git checkout 178324f2dd7f5b010cd93a17a414cd82d916d9b5
    sed -i "s/FROM.*/FROM registry.access.redhat.com\/ubi7\/ubi:7.9-681 AS ubi7/g" Dockerfile
    cd $SOURCE_ROOT/alfresco-docker-base-java
    if [[ "$JAVA_PROVIDED" == "Temurin11" ]]; then
    # Install IBM Temurin11 Runtime   
    cp $SOURCE_ROOT/adoptium_temurin.tar.gz .
    export java_filename='adoptium_temurin.tar.gz'
      elif [[ "$JAVA_PROVIDED" == "IBMSemeru11" ]]; then
        cp $SOURCE_ROOT/semeru.tar.gz .
        export java_filename='semeru.tar.gz'         
    else
                printf "$JAVA_PROVIDED is not supported, Please use valid java from {Temurin11, IBMSemeru11} only"
                exit 1
    fi
    docker build -t alfresco/alfresco-base-java . \
      --build-arg JAVA_PKG="${java_filename}" \
      --no-cache
    printf -- "alfresco-base-java image is built successfully\n"

    #Build alfresco-base-tomcat image
    printf -- "Building alfresco-base-tomcat image\n"
    cd $SOURCE_ROOT
    git clone https://github.com/Alfresco/alfresco-docker-base-tomcat
    cd alfresco-docker-base-tomcat
    git checkout 19ac8029da07aeda6e23b7656e763650c5727f31
    sed -i "s/FROM.*/FROM alfresco\/alfresco-base-java:latest/g" java-11/centos-7/Dockerfile
    (cd java-11/centos-7 && docker build -t java-11-centos-7 .)
    sed -i "s/openssl-1.0.2k-21.el7_9/openssl-devel/g" Dockerfile
    docker build -t alfresco/alfresco-base-tomcat . \
      --build-arg CENTOS_MAJOR=7 \
      --build-arg JAVA_MAJOR=11 \
      --build-arg TOMCAT_MAJOR=9 \
      --no-cache
    printf -- "alfresco-base-tomcat image is built successfully\n"

    #Switch jdk to use OpenJDK
    if [[ "${ID}" == "ubuntu" ]]; then
        sudo update-alternatives --install "/usr/bin/java" "java" "/usr/lib/jvm/java-8-openjdk-s390x/bin/java" 20
        sudo update-alternatives --install "/usr/bin/javac" "javac" "/usr/lib/jvm/java-8-openjdk-s390x/bin/javac" 20
        sudo update-alternatives --set java "/usr/lib/jvm/java-8-openjdk-s390x/bin/java"
        sudo update-alternatives --set javac "/usr/lib/jvm/java-8-openjdk-s390x/bin/javac"
        export JAVA_HOME="$(readlink -f /etc/alternatives/javac | sed 's:/bin/javac::')"
    elif [[ "${ID}" == "sles" ]]; then
        sudo update-alternatives --install "/usr/bin/java" "java" "/usr/lib64/jvm/java-1.8.0-openjdk/bin/java" 20
        sudo update-alternatives --install "/usr/bin/javac" "javac" "/usr/lib64/jvm/java-1.8.0-openjdk/bin/javac" 20
        sudo update-alternatives --set java "/usr/lib64/jvm/java-1.8.0-openjdk/bin/java"
        sudo update-alternatives --set javac "/usr/lib64/jvm/java-1.8.0-openjdk/bin/javac"
        export JAVA_HOME="$(readlink -f /etc/alternatives/javac | sed 's:/bin/javac::')"
    else
        sudo update-alternatives --install "/usr/bin/java" "java" "/usr/lib/jvm/java-1.8.0-openjdk/bin/java" 20
        sudo update-alternatives --install "/usr/bin/javac" "javac" "/usr/lib/jvm/java-1.8.0-openjdk/bin/javac" 20
        sudo update-alternatives --set java "/usr/lib/jvm/java-1.8.0-openjdk/bin/java"
        sudo update-alternatives --set javac "/usr/lib/jvm/java-1.8.0-openjdk/bin/javac"
        export JAVA_HOME="$(readlink -f /etc/alternatives/javac | sed 's:/bin/javac::')"
    fi

    #Build native jffi-1.2.22 jar
    cd $SOURCE_ROOT
    git clone https://github.com/jnr/jffi.git
    cd jffi
    git checkout jffi-1.2.22
    ant jar && ant archive-platform-jar && mvn package
    mkdir -p ~/.m2/repository/com/github/jnr/jffi/1.2.22
    cp target/jffi-1.2.22-native.jar ~/.m2/repository/com/github/jnr/jffi/1.2.22

    #Build native jffi-1.2.16 jar
    cd $SOURCE_ROOT/jffi
    git checkout .
    git checkout jffi-1.2.16
    ant jar && ant archive-platform-jar && mvn package
    mkdir -p ~/.m2/repository/com/github/jnr/jffi/1.2.16
    cp target/jffi-1.2.16-native.jar ~/.m2/repository/com/github/jnr/jffi/1.2.16

    #Build native jffi-1.2.11 jar
    cd $SOURCE_ROOT/jffi
    git checkout .
    git checkout 1.2.11
    curl https://github.com/jnr/jffi/commit/e2c2a92d88b78b82f8803d7b16a19898ffdc8652.patch  | git apply
    ant jar && ant archive-platform-jar && mvn package
    mkdir -p ~/.m2/repository/com/github/jnr/jffi/1.2.11
    cp target/jffi-1.2.11-native.jar ~/.m2/repository/com/github/jnr/jffi/1.2.11

    #Revert to AdoptOpenJDK 11
    export JAVA_HOME=/opt/java

    #Fix libc library for SLES 12.5 and RHEL 7.x
    if [[ "${VERSION_ID}" == "12.5" || "${DISTRO}" == rhel-7* ]]; then
        printf -- "Replacing libc library\n"
        sudo cp /lib64/libc-* /lib/
    fi

    #Build alfresco-community-repo docker image
    printf -- "Building alfresco-community-repo image\n"
    cd $SOURCE_ROOT
    git clone https://github.com/Alfresco/alfresco-community-repo.git
    cd alfresco-community-repo
    git checkout 14.145
    sed -i "s/FROM.*/FROM alfresco\/alfresco-base-tomcat:latest/g" packaging/docker-alfresco/Dockerfile
    mvn clean install -DskipTests=true -Dversion.edition=Community -Pbuild-docker-images -Dimage.tag=14.145
    printf -- "alfresco-community-repo image is built successfully\n"

    #Build acs-community-packaging docker image
    printf -- "Building acs-community-packaging image\n"
    cd $SOURCE_ROOT
    git clone https://github.com/Alfresco/acs-community-packaging.git
    cd acs-community-packaging
    git checkout 7.2.0
    mvn clean install -Pbuild-docker-images -Dmaven.javadoc.skip=true  -Dimage.tag=7.2.0
    printf -- "acs-community-packaging image is built successfully\n"

    #Build Alfresco share
    printf -- "Building alfresco-share image\n"
    cd $SOURCE_ROOT
    git clone https://github.com/Alfresco/share.git
    cd share
    git checkout alfresco-share-parent-7.0.0
    cd packaging/docker
    sed -i "s/9.0.41-java-11-openjdk-centos-8/latest/g" Dockerfile
    mvn clean install -Dimage.tag=7.2.0 -Plocal
    printf -- "alfresco-share image is built successfully\n"

    #Build Alfresco Search Services
    printf -- "Building alfresco-search-services image\n"
    cd $SOURCE_ROOT
    git clone https://github.com/Alfresco/SearchServices.git
    cd SearchServices
    git checkout 2.0.3
    sed -i "220 s/true/false/g" pom.xml
    sed -i "s/11.0.13-centos-7@sha256:c1e399d1bbb5d08e0905f1a9ef915ee7c5ea0c0ede11cc9bd7ca98532a9b27fa/latest/g" search-services/packaging/src/docker/Dockerfile
    cd $SOURCE_ROOT/SearchServices/search-services
    mvn clean install -DskipTests=true
    cd packaging/target/docker-resources/
    sed -i "s/YourKit-JavaProfiler-2019.8-b142-docker/YourKit-JavaProfiler-2022.3-docker/g" Dockerfile
    sed -i "220 s/download.yourkit.com\/yjp\/2019.8/www.yourkit.com\/download\/docker/g" Dockerfile
    sed -i "64 s/download.yourkit.com\/yjp\/2019.8/www.yourkit.com\/download\/docker/g" Dockerfile
    docker build -t alfresco/alfresco-search-services:2.0.3 .
    printf -- "alfresco-search-services image is built successfully\n"

    #Build Alfresco Activemq
    printf -- "Building alfresco-activemq image\n"
    cd $SOURCE_ROOT
    git clone https://github.com/Alfresco/alfresco-docker-activemq.git
    cd alfresco-docker-activemq
    git checkout 8794bf691f0e54dc30fa203d4e7f085297d33730
    sed -i "s/FROM.*/FROM alfresco\/alfresco-base-java:latest/g" Dockerfile
    docker build -t alfresco/alfresco-activemq:5.16.4 .
    printf -- "alfresco-activemq image is built successfully\n"

    #Build Alfresco acs-community-ingress
    printf -- "Building alfresco-acs-nginx image\n"
    cd $SOURCE_ROOT
    git clone https://github.com/Alfresco/acs-ingress.git
    cd acs-ingress
    git checkout alfresco-acs-nginx-3.2.0
    docker build -t alfresco/alfresco-acs-nginx:3.2.0 .
    printf -- "alfresco-acs-nginx image is built successfully\n"

    #Fetch alfresco docker compose file
    cd $SOURCE_ROOT
    mkdir -p docker-compose-source
    cd docker-compose-source
    wget -O docker-compose.yml https://raw.githubusercontent.com/Alfresco/acs-deployment/v5.2.0/docker-compose/community-docker-compose.yml

    #Remove code relavant to third Party alfresco transformers (alfresco-pdf-renderer, imagemagick, libreoffice etc. )
    sed -i -e '45d' -e '50,56d' docker-compose.yml
    sed -i "s/5.16.4-jre11-centos7/5.16.4/g" docker-compose.yml

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
    echo "  bash build_alfresco.sh  [-d debug] [-y install-without-confirmation] [-j Java to use from {IBMSemeru11, Temurin11}] "
    echo
}

while getopts "h?dyj:" opt; do
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
    j)
        JAVA_PROVIDED="$OPTARG"
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
"ubuntu-18.04" | "ubuntu-20.04" | "ubuntu-21.10" | "ubuntu-22.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y git gcc maven make openjdk-8-jdk wget ant iptables procps xz-utils curl patch |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-7.8" | "rhel-7.9")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y git gcc make java-1.8.0-openjdk-devel wget ant iptables-services procps-ng xz texinfo curl patch |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-8.4" | "rhel-8.5" | "rhel-8.6")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y git gcc maven make java-1.8.0-openjdk-devel wget ant iptables-services procps-ng xz curl patch |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-12.5" | "sles-15.3"| "sles-15.4")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y awk git gcc make java-1_8_0-openjdk-devel wget ant iptables procps xz curl patch |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
