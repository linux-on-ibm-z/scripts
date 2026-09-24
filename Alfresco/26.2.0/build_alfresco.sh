#!/bin/bash
# © Copyright IBM Corporation 2026.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Alfresco/26.2.0/build_alfresco.sh
# Execute build script: bash build_alfresco.sh    (provide -h for help)
USER_IN_GROUP_DOCKER=$(id -nGz "$USER" | tr '\0' '\n' | grep -c '^docker$')
set -e -o pipefail

PACKAGE_NAME="alfresco"
PACKAGE_VERSION="26.2.0"
SOURCE_ROOT="$(pwd)"
FORCE="false"
TESTS="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
JAVA_PROVIDED="OpenJDK21"
BUILD_ENV="$HOME/setenv.sh"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Alfresco/26.2.0/patch"     
MAVEN_VERSION="3.9.11"
ACTIVEMQ_VERSION="5.18.7"
ACTIVEMQ_COMMIT="ba740d465bbe8c3f984c8f937f4d3f0b22970fca"
JAVA_BASE_COMMIT="caff57d9e20fa8fa2bac5513d1326e10e5387214"
TOMCAT_BASE_COMMIT="dc7a9e394cae91c6237cb38ca28a7da8a896bce5"
COMMUNITY_REPO_VERSION="26.2.3.1"
COMMUNITY_SHARE_VERSION="26.2.3.1"
ES_BATCH_INDEXING_VERSION="5.7.0"
TRANSFORM_CORE_VERSION="5.4.3"
CONTENT_APP_VERSION="8.0.0"
ACS_DOCKER_COMPOSE_VERSION="10.7.0"

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
        printf -- 'Please install sudo from repository using apt or yum based on your distro. \n'
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
    rm -f "$SOURCE_ROOT/apache-maven-${MAVEN_VERSION}-bin.tar.gz"
    rm -f "$SOURCE_ROOT/node-${NODEJS_VERSION}-linux-s390x.tar.gz"
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function retry() {
    local max_retries=5
    local retry=0

    until "$@"; do
        exit=$?
        wait=3
        retry=$((retry + 1))
        if [[ $retry -lt $max_retries ]]; then
            echo "Retry $retry/$max_retries exited $exit, retrying in $wait seconds..."
            sleep $wait
        else
            echo "Retry $retry/$max_retries exited $exit, no more retries left."
            return $exit
        fi
    done
    return 0
}

function installJava() {
    local jver="$1"
    printf -- "Download and install Java \n"
    cd "$SOURCE_ROOT"
	
        if [[ $ID == "ubuntu" ]]; then
            sudo apt-get install -y openjdk-${jver}-jdk
            export JAVA_HOME=/usr/lib/jvm/java-${jver}-openjdk-s390x
            printf -- "export JAVA_HOME=/usr/lib/jvm/java-${jver}-openjdk-s390x\n" >> "$BUILD_ENV"
        elif [[  $ID == "rhel" ]]; then
            sudo yum install -y java-${jver}-openjdk-devel
            export JAVA_HOME=/usr/lib/jvm/java-${jver}
            printf -- "export JAVA_HOME=/usr/lib/jvm/java-${jver}\n" >> "$BUILD_ENV"
		elif [[ $ID == "sles" ]]; then
  			sudo zypper install -y java-${jver}-openjdk  java-${jver}-openjdk-devel
	 		export JAVA_HOME=/usr/lib64/jvm/java-${jver}-openjdk
			printf -- "export JAVA_HOME=/usr/lib64/jvm/java-${jver}-openjdk\n" >> "$BUILD_ENV"
        else
			printf "%s is not supported for installing Java or " "$ID"
		 	printf "%s is not supported, Please use valid java from {OpenJDK21} only\n" "$JAVA_PROVIDED"
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
    cd "$SOURCE_ROOT"
    git clone --depth 1 -b master https://github.com/Alfresco/alfresco-docker-base-java.git
    cd alfresco-docker-base-java
    git fetch --depth 1 origin "$JAVA_BASE_COMMIT"
    git checkout "$JAVA_BASE_COMMIT"

    curl -sSL "${PATCH_URL}/base-java.patch" | git apply -
    docker build -t "alfresco/alfresco-base-java:jre${jver}-rockylinux9" . \
        --build-arg DISTRIB_NAME=rockylinux --build-arg DISTRIB_MAJOR=9 \
        --build-arg JAVA_MAJOR="${jver}" \
        --build-arg CREATED="$(date --iso-8601=seconds)" \
        --build-arg REVISION="$(git rev-parse --verify HEAD)" --no-cache
    printf -- "alfresco-base-java image is built successfully\n"
}

function buildAlfrescoBaseTomcatImage() {
    local jver="$1"
    printf -- "Building alfresco-base-tomcat image\n"
    cd "$SOURCE_ROOT"
    git clone --depth 1 -b master https://github.com/Alfresco/alfresco-docker-base-tomcat 
    cd alfresco-docker-base-tomcat
    git fetch --depth 1 origin "$TOMCAT_BASE_COMMIT"
    git checkout "$TOMCAT_BASE_COMMIT"

    curl -sSL "${PATCH_URL}/base-tomcat.patch" | git apply -
    if [[ "$DISTRO" == rhel* ]]; then
        sed -i '111s|^RUN |RUN rm -rf /var/cache/dnf/* \&\& |' Dockerfile
        sed -i '/^RUN if \[ "\$DISTRIB_MAJOR" -eq 8 \]; then \\/i RUN rm -rf /var/cache/dnf/* && dnf clean all' Dockerfile
        sed -i 's|dnf clean all \&\& \\|rm -rf /var/cache/dnf/* \&\& dnf clean all \&\& \\|' Dockerfile
        sed -i 's|dnf clean all; \\|rm -rf /var/cache/dnf/* \&\& dnf clean all; \\|' Dockerfile
    fi

    DOCKER_BUILDKIT=0 docker build -t alfresco/alfresco-base-tomcat:tomcat11-jre${jver}-rockylinux9 . \
  	--build-arg DISTRIB_NAME=rockylinux \
  	--build-arg DISTRIB_MAJOR=9 \
  	--build-arg JAVA_MAJOR="${jver}" \
  	--build-arg TOMCAT_MAJOR=11 \
  	--build-arg TOMCAT_VERSION="$(jq -r .tomcat_version tomcat11.json)" \
  	--build-arg TCNATIVE_VERSION="$(jq -r .tcnative_version tomcat11.json)" \
  	--build-arg APR_VERSION="$(jq -r .apr_version tomcat11.json)" \
  	--build-arg TOMCAT_SHA512="$(jq -r .tomcat_sha512 tomcat11.json)" \
  	--build-arg TCNATIVE_SHA512="$(jq -r .tcnative_sha512 tomcat11.json)" \
  	--build-arg APR_SHA256="$(jq -r .apr_sha256 tomcat11.json)" \
  	--no-cache
    printf -- "alfresco-base-tomcat image is built successfully\n"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"
    cd "$SOURCE_ROOT"
    local jver=`echo $JAVA_PROVIDED | tr -d -c 0-9`
    installJava "$jver"

    cd "$SOURCE_ROOT"
    printf -- "Installing Maven\n"
    wget https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz
    tar -xzf apache-maven-${MAVEN_VERSION}-bin.tar.gz
    export PATH=$SOURCE_ROOT/apache-maven-${MAVEN_VERSION}/bin:$PATH
    printf -- "export PATH=$SOURCE_ROOT/apache-maven-${MAVEN_VERSION}/bin:$PATH\n" >> "$BUILD_ENV"
    mvn --version
    printf -- "maven installed successfully \n"

    cd "$SOURCE_ROOT"
    buildAlfrescoBaseJavaImage "$jver"

    cd "$SOURCE_ROOT"
    buildAlfrescoBaseTomcatImage "$jver"

    # Build alfresco-community-repo docker image
    printf -- "Building alfresco-community-repo image\n"
    cd "$SOURCE_ROOT"
    git clone --depth 1 -b "${COMMUNITY_REPO_VERSION}" https://github.com/Alfresco/alfresco-community-repo.git
    cd alfresco-community-repo
    sed -i "s/FROM.*/FROM alfresco\/alfresco-base-tomcat:tomcat11-jre${jver}-rockylinux9/g" packaging/docker-alfresco/Dockerfile
    retry mvn clean install -DskipTests=true -Dversion.edition=Community -Pbuild-docker-images -Dimage.tag="${COMMUNITY_REPO_VERSION}"
    printf -- "alfresco-community-repo image is built successfully\n"

    # Build Alfresco share
    printf -- "Building alfresco-share image\n"
    cd "$SOURCE_ROOT"
    git clone --depth 1 -b "${COMMUNITY_SHARE_VERSION}" https://github.com/Alfresco/alfresco-community-share.git
    cd alfresco-community-share
    sed -i "s/FROM.*/FROM alfresco\/alfresco-base-tomcat:tomcat11-jre${jver}-rockylinux9/g" packaging/docker/Dockerfile
    retry mvn clean install -DskipTests=true -Dmaven.javadoc.skip=true -Pbuild-docker-images -Dimage.tag="${COMMUNITY_SHARE_VERSION}" -Drepo.image.tag="${COMMUNITY_REPO_VERSION}"
    docker tag "alfresco/alfresco-share-base:${COMMUNITY_SHARE_VERSION}" "alfresco/alfresco-share:${PACKAGE_VERSION}"
    printf -- "alfresco-share image is built successfully\n"

    # Build acs-community-packaging docker image
    printf -- "Building acs-community-packaging image\n"
    cd "$SOURCE_ROOT"
    git clone --depth 1 -b "${PACKAGE_VERSION}" https://github.com/Alfresco/acs-community-packaging.git
    cd acs-community-packaging
    retry mvn clean install -Pbuild-docker-images -Dimage.tag="${PACKAGE_VERSION}" -Drepo.image.tag="${COMMUNITY_REPO_VERSION}" -Dshare.image.tag="${COMMUNITY_SHARE_VERSION}"
    printf -- "acs-community-packaging image is built successfully\n"

 	# Build alfresco-elasticsearch-batch-indexing docker image
  	cd "$SOURCE_ROOT"
	mkdir alfresco-elasticsearch-batch-indexing && cd alfresco-elasticsearch-batch-indexing
 	curl -sSL "https://nexus.alfresco.com/nexus/repository/releases/org/alfresco/alfresco-elasticsearch-batch-indexing/${ES_BATCH_INDEXING_VERSION}/alfresco-elasticsearch-batch-indexing-${ES_BATCH_INDEXING_VERSION}-app.jar" -o app.jar
	curl -sSL "${PATCH_URL}/Batchindexing-Dockerfile" -o Dockerfile
	docker build -t alfresco/alfresco-elasticsearch-batch-indexing:${ES_BATCH_INDEXING_VERSION} . --build-arg JAVA_MAJOR="${jver}" --no-cache

    # Build Alfresco Activemq
    printf -- "Building alfresco-activemq image\n"
    cd "$SOURCE_ROOT"
    git clone --depth 1 -b master https://github.com/Alfresco/alfresco-docker-activemq.git
    cd alfresco-docker-activemq/
    git fetch --depth 1 origin "${ACTIVEMQ_COMMIT}"
    git checkout "${ACTIVEMQ_COMMIT}"
    DOCKER_BUILDKIT=0 docker build -t "alfresco/alfresco-activemq:${ACTIVEMQ_VERSION}-jre${jver}-rockylinux9" . --build-arg ACTIVEMQ_VERSION=${ACTIVEMQ_VERSION} --build-arg DISTRIB_NAME=rockylinux --build-arg DISTRIB_MAJOR=9 --build-arg JAVA_MAJOR="${jver}" --build-arg JDIST=jre --no-cache
    printf -- "alfresco-activemq image is built successfully\n"

    # Build Alfresco transform core
    printf -- "Building alfresco-transform-core image\n"
    cd "$SOURCE_ROOT"
    git clone --depth 1 -b "${TRANSFORM_CORE_VERSION}" https://github.com/Alfresco/alfresco-transform-core.git
    cd alfresco-transform-core/
    grep -RiIl 'jre17-rockylinux9@sha256' | xargs sed -i "s/jre17-rockylinux9@sha256.*/jre${jver}-rockylinux9/g"
    grep -RiIl 'jre21-rockylinux9@sha256' | xargs sed -i "s/jre21-rockylinux9@sha256.*/jre${jver}-rockylinux9/g"
    grep -RiIl '5.18.3-jre17-rockylinux8' | xargs sed -i "s/5.18.3-jre17-rockylinux8/${ACTIVEMQ_VERSION}-jre${jver}-rockylinux9/g"
    retry mvn clean install -pl '!engines/aio,!engines/pdfrenderer,!engines/imagemagick,!engines/libreoffice' -Plocal,docker-it-setup -DskipTests=true
    printf -- "Alfresco-trasform-core image is built successfully\n"

    # Build Alfresco Content App
    printf -- "Building alfresco-content-app image\n"
    cd "$SOURCE_ROOT"
    git clone --depth 1 -b "${CONTENT_APP_VERSION}" https://github.com/Alfresco/alfresco-content-app.git
    cd alfresco-content-app/
    sed -i "/RUN mkdir -p/ i RUN yarn config set network-timeout 600000 && yarn config set registry https:\/\/registry.npmjs.org\/" Dockerfile
    curl -sSL "${PATCH_URL}/content-app-angular.json" -o angular.json

    docker run --rm \
    -e CI=true \
    -e TERM=dumb \
    -e FORCE_COLOR=0 \
    --mount type=bind,source="${SOURCE_ROOT}",target=/src \
    s390x/node:24 \
    sh -c '
        cd /src/alfresco-content-app &&
        npm install --ignore-scripts &&
        npm install --save-dev @angular/cli@20 --ignore-scripts &&
        node ./node_modules/@angular/cli/bin/ng.js build content-ce --configuration=production'

    sudo chown -R "$(id -u):$(id -g)" .
    retry docker build -t "alfresco/alfresco-content-app:${CONTENT_APP_VERSION}" . --build-arg PROJECT_NAME=content-ce
    printf -- "Alfresco alfresco-content-app image is built successfully\n"

    docker pull postgres:17.9
    docker pull traefik:3.6

    # Fetch alfresco docker compose file
	cd "$SOURCE_ROOT"
	git clone --depth 1 -b v"${ACS_DOCKER_COMPOSE_VERSION}" https://github.com/Alfresco/acs-deployment.git
	cd acs-deployment/docker-compose
	curl -sSL "${PATCH_URL}/acs-deploy-compose.patch" | git apply -
	cd "$SOURCE_ROOT"
	mkdir -p docker-compose-source && cd docker-compose-source
	cp "$SOURCE_ROOT"/acs-deployment/docker-compose/community-compose.yaml docker-compose.yml

 	#Copy the Base Configuration Template
	mkdir -p commons && cd commons
	cp "$SOURCE_ROOT"/acs-deployment/docker-compose/commons/base.yaml base.yaml

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
		mvn -U clean test -pl '!engines/aio,!engines/pdfrenderer,!engines/imagemagick,!engines/libreoffice' -DadditionalOption=-Xdoclint:none -Dmaven.javadoc.skip=true -Dparent.core.deploy.skip=true -Dtransformer.base.deploy.skip=true -Plocal,docker-it-setup
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
    echo "  bash build_alfresco.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests] [-j Java to use from {OpenJDK21}] "
    echo " default: If no -j specified, OpenJDK21 will be installed"
    echo
}

function isValidJavaProvided() {
    local jp=$1
    case "$jp" in
    "OpenJDK21")
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
            printf "%s is not supported, Please use valid java from {OpenJDK21} only" "$JAVA_PROVIDED"
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
	printf -- "Please ensure Elasticsearch and Kibana docker image is built based on your distro. \n"
 	printf -- "Steps to build Elasticsearch (9.3.0) Docker Image can be found at https://github.com/linux-on-ibm-z/docs/wiki/Building-Elasticsearch/2a8c0030468daedf6bed272fd70554023f53b023 . \n"
  	printf -- "Steps to build Kibana (9.3.0) Docker Image can be found at https://github.com/linux-on-ibm-z/dockerfile-examples/blob/f43e9db47406067d58d40a0d1491abd294906e7b/Kibana/Dockerfile . \n\n"
    printf -- "Run following steps to bring up the alfresco services:\n"
    printf -- "cd $SOURCE_ROOT/docker-compose-source \n"
    printf -- "docker compose up \n"
    printf -- "\nOnce the cluster is up, the Share UI will be available at http://localhost:8080/share \n"
    printf -- '**********************************************************************************************************\n'
}

function installRhel() {
    sudo yum install -y ${ALLOWERASING} git gcc gcc-c++ python3 make wget ant iptables-services procps-ng xz curl patch jq

    configureAndInstall
}

function installsles() {
  sudo zypper install -y git gcc gcc-c++ python3 make wget ant iptables procps xz curl patch jq
  configureAndInstall
}

function installUbuntu() {
    sudo apt-get update
    sudo apt-get install -y git gcc g++ python3 make wget ant iptables procps xz-utils curl patch jq

    configureAndInstall
}

logDetails
prepare
DISTRO="$ID-$VERSION_ID"
printf -- "Installing %s %s for %s and %s\n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" "$JAVA_PROVIDED" |& tee -a "$LOG_FILE"
printf -- "Installing dependencies... it may take some time.\n"

case "$DISTRO" in
"rhel-8.10" | "rhel-9.6" | "rhel-9.7")
    installRhel |& tee -a "$LOG_FILE"
    ;;
"sles-15.7")
    installsles  |& tee -a "$LOG_FILE"
    ;;
"ubuntu-24.04")
    installUbuntu  |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"    
