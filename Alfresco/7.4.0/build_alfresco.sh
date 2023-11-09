#!/bin/bash
# © Copyright IBM Corporation 2023.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Alfresco/7.4.0/build_alfresco.sh
# Execute build script: bash build_alfresco.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="alfresco"
PACKAGE_VERSION="7.4.0.1"
SOURCE_ROOT="$(pwd)"
FORCE="false"
TESTS="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
JAVA_PROVIDED="IBMSemeru11"
BUILD_ENV="$HOME/setenv.sh"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Alfresco/7.4.0/patch"
USER_IN_GROUP_DOCKER=$(id -nGz "$USER" | tr '\0' '\n' | grep -c '^docker$')

trap cleanup 0 1 2 ERR

# Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
    mkdir -p "$SOURCE_ROOT/logs/"
fi

source "/etc/os-release"

function prepare() {
    if command -v "sudo" >/dev/null; then
        printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
    else
        printf -- 'Sudo : No \n' >>"$LOG_FILE"
        printf -- 'Please install sudo from repository using apt, yum or zypper based on your distro. \n'
        exit 1
    fi
    
    if command -v "docker" >/dev/null; then
        printf -- 'Docker : Yes\n' >>"$LOG_FILE"
    else
        printf -- 'Docker : No \n' >>"$LOG_FILE"
        printf -- 'Please install Docker based on your distro. \n'
        exit 1
    fi

    if [[ "$USER_IN_GROUP_DOCKER" == "1" ]]; then
        printf "User %s belongs to group docker\n" "$USER" |& tee -a "${LOG_FILE}"
    else
        printf "Please ensure User %s belongs to group docker.\n" "$USER" |& tee -a "${LOG_FILE}"
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
    rm -f "$SOURCE_ROOT/apache-maven-3.9.2-bin.tar.gz"
    rm -f "$SOURCE_ROOT/node-v16.19.0-linux-s390x.tar.gz"
    rm -f "$SOURCE_ROOT/jre.tar.gz"
    rm -f "$SOURCE_ROOT/jdk.tar.gz"
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function getJavaUrl() {
    local jruntime=$1
    local jdist=$2
    case "${jruntime}" in
    "Temurin11")
        echo "https://github.com/adoptium/temurin11-binaries/releases/download/jdk-11.0.19%2B7/OpenJDK11U-${jdist}_s390x_linux_hotspot_11.0.19_7.tar.gz"
        ;;
    "Temurin17")
        echo "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.7%2B7/OpenJDK17U-${jdist}_s390x_linux_hotspot_17.0.7_7.tar.gz"
        ;;
    "IBMSemeru11")
        echo "https://github.com/ibmruntimes/semeru11-binaries/releases/download/jdk-11.0.19%2B7_openj9-0.38.0/ibm-semeru-open-${jdist}_s390x_linux_11.0.19_7_openj9-0.38.0.tar.gz"
        ;;
    "IBMSemeru17")
        echo "https://github.com/ibmruntimes/semeru17-binaries/releases/download/jdk-17.0.7%2B7_openj9-0.38.0/ibm-semeru-open-${jdist}_s390x_linux_17.0.7_7_openj9-0.38.0.tar.gz"
        ;;
    esac
    echo ""
}

function installJava() {
    local jver="$1"
    printf -- "Download and install Java \n"
    cd $SOURCE_ROOT
    if [ -d "/opt/java" ]; then sudo rm -Rf /opt/java; fi
    sudo mkdir -p /opt/java/jdk
    sudo mkdir -p /opt/java/jre

    if [[ $JAVA_PROVIDED =~ ^Temurin || $JAVA_PROVIDED =~ ^IBMSemeru ]]; then
        curl -SL -o jdk.tar.gz "$(getJavaUrl $JAVA_PROVIDED jdk)"
        curl -SL -o jre.tar.gz "$(getJavaUrl $JAVA_PROVIDED jre)"
        sudo tar -zxvf jdk.tar.gz -C /opt/java/jdk --strip-components 1
        sudo tar -zxvf jre.tar.gz -C /opt/java/jre --strip-components 1
		sudo update-alternatives --install "/usr/bin/java" "java" "/opt/java/jdk/bin/java" 40
		sudo update-alternatives --install "/usr/bin/javac" "javac" "/opt/java/jdk/bin/javac" 40
		sudo update-alternatives --set java "/opt/java/jdk/bin/java"
		sudo update-alternatives --set javac "/opt/java/jdk/bin/javac"
        export JAVA_HOME=/opt/java/jdk
        printf -- "export JAVA_HOME=/opt/java/jdk\n" >> "$BUILD_ENV"
	elif [[ $JAVA_PROVIDED =~ ^OpenJDK ]]; then
        if [[ $ID == "ubuntu" ]]; then
		    sudo apt-get install -y openjdk-${jver}-jdk
		    export JAVA_HOME=/usr/lib/jvm/java-${jver}-openjdk-s390x
            printf -- "export JAVA_HOME=/usr/lib/jvm/java-${jver}-openjdk-s390x\n" >> "$BUILD_ENV"
        elif [[  $ID == "rhel" ]]; then
    		sudo yum install -y java-${jver}-openjdk-devel
	    	export JAVA_HOME=/usr/lib/jvm/java-${jver}
            printf -- "export JAVA_HOME=/usr/lib/jvm/java-${jver}\n" >> "$BUILD_ENV"
        else
            printf "%s is not supported for installing Java" "$ID"
            exit 1
        fi
    else
        printf "%s is not supported, Please use valid java from {Temurin11/17, IBMSemeru11/17, OpenJDK11/17} only\n" "$JAVA_PROVIDED"
        exit 1
    fi

    export PATH=$JAVA_HOME/bin:$PATH
	printf -- "export PATH=$JAVA_HOME/bin:$PATH\n" >> "$BUILD_ENV"
    java -version
    javac -version
    printf -- "Installation of %s is successful\n" "$JAVA_PROVIDED"
}

function buildAlfrescoBaseJavaImage() {
    local jver="$1"
    printf -- "Building alfresco-base-java image\n"
    cd $SOURCE_ROOT
    git clone https://github.com/Alfresco/alfresco-docker-base-java.git
    cd alfresco-docker-base-java
    if [[ $JAVA_PROVIDED =~ ^OpenJDK ]]; then
        git checkout c5eafffef255e0fcb79e276afdd3146f3850c5da
        sed -i "s#FROM rockylinux:8.*#FROM registry.access.redhat.com/ubi8:8.7-1112 AS ubi8#g" Dockerfile
    	docker build -t "alfresco/alfresco-base-java:jre${jver}-ubi8" . \
          --build-arg DISTRIB_NAME=ubi --build-arg DISTRIB_MAJOR=8 \
          --build-arg JAVA_MAJOR="${jver}" --build-arg JDIST=jre \
          --build-arg CREATED="$(date --iso-8601=seconds)" --build-arg REVISION="$(git rev-parse --verify HEAD)" --no-cache
    else
        git checkout 178324f2dd7f5b010cd93a17a414cd82d916d9b5
        sed -i "s#FROM.*#FROM registry.access.redhat.com/ubi8:8.7-1112 AS ubi8#g" Dockerfile
        sed -i "s#RUN export#RUN yum install -y glibc-langpack-en \&\& \\\\\n    yum clean all \&\& \\\\\n    export#" Dockerfile
        cp $SOURCE_ROOT/jre.tar.gz .
        docker build -t "alfresco/alfresco-base-java:jre${jver}-ubi8" . \
          --build-arg JAVA_PKG="jre.tar.gz" \
          --build-arg CREATED="$(date --iso-8601=seconds)" \
          --build-arg REVISION="$(git rev-parse --verify HEAD)" \
          --no-cache
    fi
    printf -- "alfresco-base-java image is built successfully\n"
}

function buildAlfrescoBaseTomcatImage() {
    local jver="$1"
    printf -- "Building alfresco-base-tomcat image\n"
    cd $SOURCE_ROOT
    git clone https://github.com/Alfresco/alfresco-docker-base-tomcat 
    cd alfresco-docker-base-tomcat
    git checkout 36a98e9f593b0ac9727e40354f2db224c62ff08f
    sed -i 's/quay.io\///g' Dockerfile
	docker build -t "alfresco/alfresco-base-tomcat:tomcat9-jre${jver}-ubi8" . \
      --build-arg DISTRIB_NAME=ubi --build-arg DISTRIB_MAJOR=8 \
      --build-arg JAVA_MAJOR="${jver}" --build-arg JDIST=jre --build-arg TOMCAT_MAJOR=9 \
      --build-arg CREATED="$(date --iso-8601=seconds)" --build-arg REVISION="$(git rev-parse --verify HEAD)" --no-cache
    printf -- "alfresco-base-tomcat image is built successfully\n"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"
    cd $SOURCE_ROOT
    local jver=11
    if [[ $JAVA_PROVIDED =~ 17$ ]]; then
        jver=17
    fi
    installJava "$jver"

    cd $SOURCE_ROOT
    printf -- "Installing Maven\n"
    wget https://archive.apache.org/dist/maven/maven-3/3.9.2/binaries/apache-maven-3.9.2-bin.tar.gz
    tar -xzf apache-maven-3.9.2-bin.tar.gz
    export PATH=$SOURCE_ROOT/apache-maven-3.9.2/bin:$PATH
    printf -- "export PATH=$SOURCE_ROOT/apache-maven-3.9.2/bin:$PATH\n" >> "$BUILD_ENV"
    mvn --version
    printf -- "maven installed successfully \n"

    cd $SOURCE_ROOT
	# Install nodejs
	wget https://nodejs.org/dist/v16.19.0/node-v16.19.0-linux-s390x.tar.gz
	sudo tar -C /opt -xzf node-v16.19.0-linux-s390x.tar.gz
    sudo chown -R root:root /opt/node-v16.19.0-linux-s390x/
	export PATH=$PATH:/opt/node-v16.19.0-linux-s390x/bin
	printf -- "export PATH=$PATH:/opt/node-v16.19.0-linux-s390x/bin\n" >> "$BUILD_ENV"
	node -v
	printf -- "Nodejs installed successfully \n"

    cd $SOURCE_ROOT
    buildAlfrescoBaseJavaImage "$jver"

    cd $SOURCE_ROOT
    buildAlfrescoBaseTomcatImage "$jver"

    # Build alfresco-community-repo docker image
    printf -- "Building alfresco-community-repo image\n"
    COMMUNITY_REPO_VERSION=20.164
    cd $SOURCE_ROOT
    git clone https://github.com/Alfresco/alfresco-community-repo.git
    cd alfresco-community-repo
    git checkout "${COMMUNITY_REPO_VERSION}"
    curl -sSL "${PATCH_URL}/threadmxbean.patch" | git apply -
    sed -i "s/FROM.*/FROM alfresco\/alfresco-base-tomcat:tomcat9-jre${jver}-ubi8/g" packaging/docker-alfresco/Dockerfile
    mvn clean install -DskipTests=true -Dversion.edition=Community -Pbuild-docker-images -Dimage.tag="${COMMUNITY_REPO_VERSION}"
    printf -- "alfresco-community-repo image is built successfully\n"

    # Build Alfresco share
    printf -- "Building alfresco-share image\n"
    COMMUNITY_SHARE_VERSION=20.165
    cd $SOURCE_ROOT
	git clone https://github.com/Alfresco/alfresco-community-share.git
	cd alfresco-community-share
	git checkout "${COMMUNITY_SHARE_VERSION}"
	sed -i "s/FROM.*/FROM alfresco\/alfresco-base-tomcat:tomcat9-jre${jver}-ubi8/g" packaging/docker/Dockerfile
	mvn clean install -DskipTests=true -Dmaven.javadoc.skip=true -Pbuild-docker-images -Dimage.tag="${COMMUNITY_SHARE_VERSION}" -Drepo.image.tag="${COMMUNITY_REPO_VERSION}"
    docker tag "alfresco/alfresco-share-base:${COMMUNITY_SHARE_VERSION}" "alfresco/alfresco-share:${PACKAGE_VERSION}"
    printf -- "alfresco-share image is built successfully\n"

    # Build acs-community-packaging docker image
    printf -- "Building acs-community-packaging image\n"
    cd $SOURCE_ROOT
    git clone https://github.com/Alfresco/acs-community-packaging.git
    cd acs-community-packaging
    git checkout "${PACKAGE_VERSION}"
    mvn clean install -DskipTests=true -Pall-tas-tests -Pbuild-docker-images -Dmaven.javadoc.skip=true -Dimage.tag="${PACKAGE_VERSION}" -Drepo.image.tag="${COMMUNITY_REPO_VERSION}" -Dshare.image.tag="${COMMUNITY_SHARE_VERSION}"
    printf -- "acs-community-packaging image is built successfully\n"

    # Build Alfresco Search Services
    printf -- "Building alfresco-search-services image\n"
    cd $SOURCE_ROOT
	git clone https://github.com/Alfresco/SearchServices.git
	cd SearchServices/
	git checkout "2.0.7"
	sed -i "s/FROM.*/FROM alfresco\/alfresco-base-java:jre${jver}-ubi8/g" search-services/packaging/src/docker/Dockerfile
	cd search-services/
    curl -sSL "${PATCH_URL}/search-restlet.patch" | git apply -
	mvn clean install -DskipTests=true
	cd packaging/target/docker-resources
	docker build -t alfresco/alfresco-search-services:2.0.7 .
    printf -- "alfresco-search-services image is built successfully\n"

    # Build Alfresco Activemq
    printf -- "Building alfresco-activemq image\n"
    ACTIVEMQ_VERSION="5.17.1"
    cd $SOURCE_ROOT
    git clone https://github.com/Alfresco/alfresco-docker-activemq.git
    cd alfresco-docker-activemq/
    git checkout bbfe1f2f3d6fe7fdfe785445cfc26df79c025df9
    docker build -t "alfresco/alfresco-activemq:${ACTIVEMQ_VERSION}-jre${jver}-ubi8" . --build-arg ACTIVEMQ_VERSION=${ACTIVEMQ_VERSION} --build-arg DISTRIB_NAME=ubi --build-arg DISTRIB_MAJOR=8 --build-arg JAVA_MAJOR="${jver}" --build-arg JDIST=jre --no-cache
    printf -- "alfresco-activemq image is built successfully\n"

    # Build Alfresco acs-community-ingress
    printf -- "Building alfresco-acs-nginx image\n"
    cd $SOURCE_ROOT
    git clone https://github.com/Alfresco/acs-ingress.git
    cd acs-ingress
    git checkout 3.4.2
    docker build -t alfresco/alfresco-acs-nginx:3.4.2 .
    printf -- "alfresco-acs-nginx image is built successfully\n"

    # Build Alfresco transform core
    printf -- "Building alfresco-transform-core image\n"
    cd $SOURCE_ROOT
    git clone https://github.com/Alfresco/alfresco-transform-core.git
    cd alfresco-transform-core
    git checkout 3.1.0
    grep -RiIl 'jre17-rockylinux8-202302221525' | xargs sed -i "s/jre17-rockylinux8-202302221525/jre${jver}-ubi8/g"
    grep -RiIl '5.17.1-jre11-rockylinux8' | xargs sed -i "s/5.17.1-jre11-rockylinux8/${ACTIVEMQ_VERSION}-jre${jver}-ubi8/g"
    grep -RiIl '2.0.1.alfresco-2' | xargs sed -i 's/2.0.1.alfresco-2/2.0.0/g'
    grep -RiIl 'alfresco-activemq:5.16.1' | xargs sed -i "s/alfresco-activemq:5.16.1/alfresco-activemq:${ACTIVEMQ_VERSION}-jre${jver}-ubi8/g"
    grep -RiIl 'Apache ActiveMQ 5.16.1' | xargs sed -i "s/Apache ActiveMQ 5.16.1/Apache ActiveMQ ${ACTIVEMQ_VERSION}/g"
    mvn clean install -pl '!engines/aio,!engines/pdfrenderer,!engines/tika,!engines/imagemagick,!engines/libreoffice' -Plocal,docker-it-setup -DskipTests=true
    printf -- "Alfresco-trasform-core image is built successfully\n"

    # Build Alfresco Content App
    printf -- "Building alfresco-content-app image\n"
    cd $SOURCE_ROOT
    git clone https://github.com/Alfresco/alfresco-content-app.git
    cd alfresco-content-app/
    git checkout 4.0.0
    sudo chmod 777 /opt/node-v16.19.0-linux-s390x/lib/node_modules/ /opt/node-v16.19.0-linux-s390x/bin/
    npm link @angular/cli
    sudo chmod 755 /opt/node-v16.19.0-linux-s390x/lib/node_modules/ /opt/node-v16.19.0-linux-s390x/bin/
    sudo chown -R root:root /opt/node-v16.19.0-linux-s390x/lib/node_modules/
    NX_NON_NATIVE_HASHER=true npm run build.release
    docker build -t alfresco/alfresco-content-app:4.0.0 . --build-arg PROJECT_NAME=content-ce
    printf -- "Alfresco alfresco-content-app image is built successfully\n"

    # Fetch alfresco docker compose file
    cd $SOURCE_ROOT
    mkdir -p docker-compose-source
    cd docker-compose-source
    wget -O docker-compose.yml https://raw.githubusercontent.com/Alfresco/acs-deployment/v6.0.0/docker-compose/community-docker-compose.yml

    # Update alfresco transformers
    cat << EOF | sed -i '64r /dev/stdin' docker-compose.yml
  transform-misc:
    image: alfresco/alfresco-transform-misc:latest
    mem_limit: 1536m
    environment:
      JAVA_OPTS: " -XX:MinRAMPercentage=50 -XX:MaxRAMPercentage=80"
    ports:
      - "8094:8090"
EOF
    cat << EOF | sed -i '53r /dev/stdin' docker-compose.yml
        -DlocalTransform.misc.url=http://transform-misc:8090/
EOF
    sed -i '53d;57,65d' docker-compose.yml
    sed -i "s#alfresco/alfresco-activemq:5.17.1-jre11-rockylinux8#alfresco/alfresco-activemq:${ACTIVEMQ_VERSION}-jre${jver}-ubi8#" docker-compose.yml

    # Run Tests
    runTest
}

function runTest() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- "TEST Flag is set , Continue with running test \n"
        # Run a subset of tests that do not require a full docker compose build env to be setup
		cd "$SOURCE_ROOT/alfresco-community-repo"
        mvn -B test -pl core,data-model -am -DfailIfNoTests=false
        mvn -B test -pl "repository,mmt" -am "-Dtest=AllUnitTestsSuite,AllMmtUnitTestSuite" -DfailIfNoTests=false
        cd "$SOURCE_ROOT/alfresco-transform-core"
        mvn -U -Dmaven.wagon.http.pool=false clean test -DadditionalOption=-Xdoclint:none -Dmaven.javadoc.skip=true -Dparent.core.deploy.skip=true -Dtransformer.base.deploy.skip=true -Plocal,docker-it-setup,misc
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
    echo "  bash build_alfresco.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests] [-j Java to use from {IBMSemeru11/17, Temurin11/17, OpenJDK11/17}] "
    echo
}

function isValidJavaProvided() {
    local jp=$1
    case "$jp" in
    "Temurin11" | "Temurin17" | "IBMSemeru11" | "IBMSemeru17" | "OpenJDK11" | "OpenJDK17")
        return 0
        ;;
    esac
    return 1
}

while getopts "h?dyj:t" opt; do
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
        if ! isValidJavaProvided "$JAVA_PROVIDED"; then
            printf "%s is not supported, Please use valid java from {Temurin11/17, IBMSemeru11/17, OpenJDK11/17} only" "$JAVA_PROVIDED"
            exit 1
        fi
        ;;
    t)
        TESTS="true"
        ;;
    esac
done

function gettingStarted() {
    printf -- '\n********************************************************************************************************\n'
    printf -- "\n* Getting Started * \n\n"
    printf -- "The Docker Compose plugin is required to start the alfresco docker-compose.yml script\n"
    printf -- "Please ensure the docker-compose-plugin package is installed based on your distro.\n\n"
    printf -- "Run following steps to bring up the alfresco services:\n"
    printf -- "cd $SOURCE_ROOT/docker-compose-source \n"
    printf -- "docker compose up \n"
    printf -- "\n\nOnce the cluster is up, the Share UI will be available at http://localhost:8080/share \n"
    printf -- '**********************************************************************************************************\n'
}

function installUbuntu() {
    sudo apt-get update
    sudo apt-get install -y git gcc g++ python3 make wget ant iptables procps xz-utils curl patch

    configureAndInstall
}

function installRhel() {
    sudo yum install -y git gcc gcc-c++ python3 make wget ant iptables-services procps-ng xz curl patch

    configureAndInstall
}

logDetails
prepare
DISTRO="$ID-$VERSION_ID"
printf -- "Installing %s %s for %s and %s\n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" "$JAVA_PROVIDED" |& tee -a "$LOG_FILE"
printf -- "Installing dependencies... it may take some time.\n"

case "$DISTRO" in
"ubuntu-20.04" | "ubuntu-22.04")
    installUbuntu  |& tee -a "$LOG_FILE"
    ;;
"rhel-8.6")
    installRhel |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
