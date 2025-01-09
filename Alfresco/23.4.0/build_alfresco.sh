#!/bin/bash
# © Copyright IBM Corporation 2025.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Alfresco/23.4.0/build_alfresco.sh
# Execute build script: bash build_alfresco.sh    (provide -h for help)
USER_IN_GROUP_DOCKER=$(id -nGz "$USER" | tr '\0' '\n' | grep -c '^docker$')
set -e -o pipefail

PACKAGE_NAME="alfresco"
PACKAGE_VERSION="23.4.0"
SOURCE_ROOT="$(pwd)"
FORCE="false"
TESTS="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
JAVA_PROVIDED="IBMSemeru17"
BUILD_ENV="$HOME/setenv.sh"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Alfresco/${PACKAGE_VERSION}/patch"
MAVEN_VERSION="3.9.9"
ACTIVEMQ_VERSION="5.18.3"
ACTIVEMQ_COMMIT="f7283c546ec8a1c137a38ea3fc1db8b93299cc35"
UBI8_VERSION="8.8-1067.1698056881"
QEMU_VERSION="v7.1.0"
JAVA_BASE_COMMIT="a73707370d15987b62a8f82746a72219374deabb"
JAVA_BASE_GENERIC_COMMIT="178324f2dd7f5b010cd93a17a414cd82d916d9b5"
TOMCAT_BASE_COMMIT="3dcbc74d36fc3c14610ca8c31bf07a5be90639b2"
COMMUNITY_REPO_VERSION="23.4.0.67"
COMMUNITY_SHARE_VERSION="23.4.0.46"
SEARCH_SERVICES_COMMIT="cb82521140ff8828814474b773bbb6aa50c11b25"
SEARCH_SERVICES_VERSION="2.0.11"
ACS_NGINX_VERSION="3.4.2"
TRANSFORM_CORE_VERSION="5.1.4"
CONTENT_APP_VERSION="5.0.1"
ACS_DOCKER_COMPOSE_VERSION="v8.4.0"

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
    rm -f "$SOURCE_ROOT/apache-maven-${MAVEN_VERSION}-bin.tar.gz"
    rm -f "$SOURCE_ROOT/node-${NODEJS_VERSION}-linux-s390x.tar.gz"
    rm -f "$SOURCE_ROOT/jre.tar.gz"
    rm -f "$SOURCE_ROOT/jdk.tar.gz"
    docker run --rm --privileged "qus:${QEMU_VERSION}" --unregister
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

function getJavaUrl() {
    local jruntime=$1
    local jdist=$2
    case "${jruntime}" in
    "Temurin17")
        echo "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.9%2B9/OpenJDK17U-${jdist}_s390x_linux_hotspot_17.0.9_9.tar.gz"
        return 0
        ;;
    "IBMSemeru17")
        echo "https://github.com/ibmruntimes/semeru17-binaries/releases/download/jdk-17.0.9%2B9_openj9-0.41.0/ibm-semeru-open-${jdist}_s390x_linux_17.0.9_9_openj9-0.41.0.tar.gz"
        return 0
        ;;
    "Temurin21")
	echo "https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.5%2B11/OpenJDK21U-${jdist}_s390x_linux_hotspot_21.0.5_11.tar.gz"
        return 0
        ;;
    "IBMSemeru21")
    	echo "https://github.com/ibmruntimes/semeru21-binaries/releases/download/jdk-21.0.5%2B11_openj9-0.48.0/ibm-semeru-open-${jdist}_s390x_linux_21.0.5_11_openj9-0.48.0.tar.gz"
        return 0
        ;;
    esac
    echo ""
    return 1
}

function installJava() {
    local jver="$1"
    printf -- "Download and install Java \n"
    cd "$SOURCE_ROOT"
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
        elif [[ $ID == "sles" ]]; then
            sudo zypper install -y java-${jver}-openjdk  java-${jver}-openjdk-devel
            export JAVA_HOME=/usr/lib64/jvm/java-${jver}-openjdk
            printf -- "export JAVA_HOME=/usr/lib64/jvm/java-${jver}-openjdk\n" >> "$BUILD_ENV"
        else
        	printf "%s is not supported for installing Java" "$ID"
        	exit 1
        fi
    else
        printf "%s is not supported, Please use valid java from {Temurin17, IBMSemeru17, OpenJDK17, Temurin21, IBMSemeru21, OpenJDK21} only\n" "$JAVA_PROVIDED"
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
    if [[ $JAVA_PROVIDED =~ ^OpenJDK ]]; then
        git fetch --depth 1 origin "$JAVA_BASE_COMMIT"
        git checkout "$JAVA_BASE_COMMIT"
        sed -i "s#FROM rockylinux:8.*#FROM registry.access.redhat.com/ubi8:${UBI8_VERSION} AS ubi8#g" Dockerfile
        docker build -t "alfresco/alfresco-base-java:jre${jver}-ubi8" . \
          --build-arg DISTRIB_NAME=ubi --build-arg DISTRIB_MAJOR=8 \
          --build-arg JAVA_MAJOR="${jver}" --build-arg JDIST=jre \
          --build-arg CREATED="$(date --iso-8601=seconds)" --build-arg REVISION="$(git rev-parse --verify HEAD)" --no-cache
    else
        git fetch --depth 1 origin "$JAVA_BASE_GENERIC_COMMIT"
        git checkout "$JAVA_BASE_GENERIC_COMMIT"
        sed -i "s#FROM.*#FROM registry.access.redhat.com/ubi8:${UBI8_VERSION} AS ubi8#g" Dockerfile
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
    cd "$SOURCE_ROOT"
    git clone --depth 1 -b master https://github.com/Alfresco/alfresco-docker-base-tomcat 
    cd alfresco-docker-base-tomcat
    git fetch --depth 1 origin "$TOMCAT_BASE_COMMIT"
    git checkout "$TOMCAT_BASE_COMMIT"
    sed -i 's/quay.io\///g' Dockerfile
    docker build -t "alfresco/alfresco-base-tomcat:tomcat10-jre${jver}-ubi8" . \
      --build-arg DISTRIB_NAME=ubi --build-arg DISTRIB_MAJOR=8 \
      --build-arg JAVA_MAJOR="${jver}" --build-arg JDIST=jre --build-arg TOMCAT_MAJOR=10 \
      --build-arg TOMCAT_VERSION="$(jq -r .tomcat_version tomcat10.json)" \
      --build-arg TOMCAT_SHA512="$(jq -r .tomcat_sha512 tomcat10.json)" \
      --build-arg TCNATIVE_VERSION="$(jq -r .tcnative_version tomcat10.json)" \
      --build-arg TCNATIVE_SHA512="$(jq -r .tcnative_sha512 tomcat10.json)" \
      --build-arg CREATED="$(date --iso-8601=seconds)" --build-arg REVISION="$(git rev-parse --verify HEAD)" --no-cache
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

    export MAVEN_ARGS="--no-transfer-progress --batch-mode -Daether.transport.http.connectTimeout=100000 -Daether.transport.http.retryHandler.count=10 -Daether.transport.http.reuseConnections=false"

    # Build alfresco-community-repo docker image
    printf -- "Building alfresco-community-repo image\n"
    cd "$SOURCE_ROOT"
    git clone --depth 1 -b "${COMMUNITY_REPO_VERSION}" https://github.com/Alfresco/alfresco-community-repo.git
    cd alfresco-community-repo
    sed -i "s/FROM.*/FROM alfresco\/alfresco-base-tomcat:tomcat10-jre${jver}-ubi8/g" packaging/docker-alfresco/Dockerfile
    sed -i 's,fontconfig-2.14.0-2.el9_1,fontconfig-2.13.1-4.el8 dejavu-fonts-common-2.35-7.el8 fontpackages-filesystem-1.44-22.el8 freetype-2.9.1-9.el8 libpng-1.6.34-5.el8 dejavu-sans-fonts-2.35-7.el8,g' packaging/docker-alfresco/Dockerfile
    retry mvn clean install -DskipTests=true -Dversion.edition=Community -Pbuild-docker-images -Dimage.tag="${COMMUNITY_REPO_VERSION}"
    printf -- "alfresco-community-repo image is built successfully\n"

    # Build Alfresco share
    printf -- "Building alfresco-share image\n"
    cd "$SOURCE_ROOT"
    git clone --depth 1 -b "${COMMUNITY_SHARE_VERSION}" https://github.com/Alfresco/alfresco-community-share.git
    cd alfresco-community-share
    sed -i "s/FROM.*/FROM alfresco\/alfresco-base-tomcat:tomcat10-jre${jver}-ubi8/g" packaging/docker/Dockerfile
    retry mvn clean install -DskipTests=true -Dmaven.javadoc.skip=true -Pbuild-docker-images -Dimage.tag="${COMMUNITY_SHARE_VERSION}" -Drepo.image.tag="${COMMUNITY_REPO_VERSION}"
    docker tag "alfresco/alfresco-share-base:${COMMUNITY_SHARE_VERSION}" "alfresco/alfresco-share:${PACKAGE_VERSION}"
    printf -- "alfresco-share image is built successfully\n"

    # Build acs-community-packaging docker image
    printf -- "Building acs-community-packaging image\n"
    cd "$SOURCE_ROOT"
    git clone --depth 1 -b "${PACKAGE_VERSION}" https://github.com/Alfresco/acs-community-packaging.git
    cd acs-community-packaging
    retry mvn clean install -DskipTests=true -Pbuild-docker-images -Dmaven.javadoc.skip=true -Dimage.tag="${PACKAGE_VERSION}" -Drepo.image.tag="${COMMUNITY_REPO_VERSION}" -Dshare.image.tag="${COMMUNITY_SHARE_VERSION}"
    printf -- "acs-community-packaging image is built successfully\n"

    # Build Alfresco Search Services
    printf -- "Building alfresco-search-services image\n"
    cd "$SOURCE_ROOT"
    git clone --depth 1 -b master https://github.com/Alfresco/SearchServices.git
    cd SearchServices/
    git fetch --depth 1 origin "${SEARCH_SERVICES_COMMIT}"
    git checkout "${SEARCH_SERVICES_COMMIT}"
    sed -i "s/FROM.*/FROM alfresco\/alfresco-base-java:jre${jver}-ubi8/g" search-services/packaging/src/docker/Dockerfile
    cd search-services/
    curl -sSL "${PATCH_URL}/search-restlet.patch" | git apply -
    retry mvn clean install -DskipTests=true
    cd packaging/target/docker-resources
    docker build -t alfresco/alfresco-search-services:${SEARCH_SERVICES_VERSION} .
    printf -- "alfresco-search-services image is built successfully\n"

    # Build Alfresco Activemq
    printf -- "Building alfresco-activemq image\n"
    cd "$SOURCE_ROOT"
    git clone --depth 1 -b master https://github.com/Alfresco/alfresco-docker-activemq.git
    cd alfresco-docker-activemq/
    git fetch --depth 1 origin "${ACTIVEMQ_COMMIT}"
    git checkout "${ACTIVEMQ_COMMIT}"
    docker build -t "alfresco/alfresco-activemq:${ACTIVEMQ_VERSION}-jre${jver}-ubi8" . --build-arg ACTIVEMQ_VERSION=${ACTIVEMQ_VERSION} --build-arg DISTRIB_NAME=ubi --build-arg DISTRIB_MAJOR=8 --build-arg JAVA_MAJOR="${jver}" --build-arg JDIST=jre --no-cache
    printf -- "alfresco-activemq image is built successfully\n"

    # Build Alfresco alfresco-acs-nginx
    printf -- "Building alfresco-acs-nginx image\n"
    cd "$SOURCE_ROOT"
    git clone --depth 1 -b "${ACS_NGINX_VERSION}" https://github.com/Alfresco/acs-ingress.git
    cd acs-ingress
    docker build -t alfresco/alfresco-acs-nginx:${ACS_NGINX_VERSION} .
    printf -- "alfresco-acs-nginx image is built successfully\n"

    # Build Alfresco transform core
    printf -- "Building alfresco-transform-core image\n"
    cd "$SOURCE_ROOT"
    git clone --depth 1 -b "${TRANSFORM_CORE_VERSION}" https://github.com/Alfresco/alfresco-transform-core.git
    cd alfresco-transform-core
    grep -RiIl 'jre17-rockylinux9@sha256:1f6cc5acfe73b3dc80b0f3850c23a171d13ae1693a09ba32d7f8e0c71800116a' | xargs sed -i "s/jre17-rockylinux9@sha256:1f6cc5acfe73b3dc80b0f3850c23a171d13ae1693a09ba32d7f8e0c71800116a/jre${jver}-ubi8/g"
    grep -RiIl '5.18.3-jre17-rockylinux8' | xargs sed -i "s/5.18.3-jre17-rockylinux8/${ACTIVEMQ_VERSION}-jre${jver}-ubi8/g"
    grep -RiIl '2.0.1.alfresco-2' | xargs sed -i 's/2.0.1.alfresco-2/2.0.0/g'
    retry mvn clean install -pl '!engines/aio,!engines/pdfrenderer,!engines/tika,!engines/imagemagick,!engines/libreoffice' -Plocal,docker-it-setup -DskipTests=true
    printf -- "Alfresco-trasform-core image is built successfully\n"

    # Install qemu x86_64 emulator
    printf -- "Installing qemu x86_64 emulator\n"
    cd "$SOURCE_ROOT"
    mkdir qemu
    cd qemu
    curl -sSL "${PATCH_URL}/qus-Dockerfile" > Dockerfile
    curl -sSL "${PATCH_URL}/qus-configure-qemu.sh" > configure-qemu.sh 
    curl -sSL "https://raw.githubusercontent.com/tonistiigi/binfmt/refs/heads/master/patches/preserve-argv0/0001-linux-user-default-to-preserve-argv0.patch" > linux-user-default-to-preserve-argv0.patch
    curl -sSL "${PATCH_URL}/qus-register.sh" > register.sh
    docker build -t "qus:${QEMU_VERSION}" --build-arg "QEMU_TAG=${QEMU_VERSION}" .
    docker run --rm --privileged "qus:${QEMU_VERSION}"
    printf -- "qemu x86_64 emulator installed successfully\n"

    # Build Alfresco Content App
    printf -- "Building alfresco-content-app image\n"
    cd "$SOURCE_ROOT"
    git clone --depth 1 -b "${CONTENT_APP_VERSION}" https://github.com/Alfresco/alfresco-content-app.git
    cd alfresco-content-app/
    docker run --rm -it --platform=linux/amd64 \
        --mount type=bind,source="${SOURCE_ROOT}",target=/src \
        amd64/node:18 \
        sh -c "cd /src/alfresco-content-app && npm install && npm run build.release"
    sudo chown -R "$(id -u):$(id -g)" .
    retry docker build -t "alfresco/alfresco-content-app:${CONTENT_APP_VERSION}" . --build-arg PROJECT_NAME=content-ce
    printf -- "Alfresco alfresco-content-app image is built successfully\n"

    # Fetch alfresco docker compose file
    cd "$SOURCE_ROOT"
    mkdir -p docker-compose-source
    cd docker-compose-source
    wget -O docker-compose.yml https://raw.githubusercontent.com/Alfresco/acs-deployment/${ACS_DOCKER_COMPOSE_VERSION}/docker-compose/community-docker-compose.yml

    # Update alfresco transformers and remove control-center
    cat << EOF | sed -i '128r /dev/stdin' docker-compose.yml
      DISABLE_CONTROL_CENTER: "true"
EOF
    cat << EOF | sed -i '58r /dev/stdin' docker-compose.yml
  transform-misc:
    image: alfresco/alfresco-transform-misc:latest
    mem_limit: 1536m
    environment:
      JAVA_OPTS: " -XX:MinRAMPercentage=50 -XX:MaxRAMPercentage=80"
    ports:
      - "8094:8090"
EOF
    cat << EOF | sed -i '47r /dev/stdin' docker-compose.yml
        -DlocalTransform.misc.url=http://transform-misc:8090/
EOF
    sed -i '47d;51,59d;122,128d' docker-compose.yml
    sed -i "s#alfresco/alfresco-activemq:5.18-jre17-rockylinux8#alfresco/alfresco-activemq:${ACTIVEMQ_VERSION}-jre${jver}-ubi8#" docker-compose.yml
    sed -i '/control-center/d' docker-compose.yml

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
        mvn -U clean test -DadditionalOption=-Xdoclint:none -Dmaven.javadoc.skip=true -Dparent.core.deploy.skip=true -Dtransformer.base.deploy.skip=true -Plocal,docker-it-setup,misc
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
    echo "  bash build_alfresco.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests] [-j Java to use from {IBMSemeru17, Temurin17, OpenJDK17}] "
    echo " default: If no -j specified, Semeru 17 will be installed"
    echo
}

function isValidJavaProvided() {
    local jp=$1
    case "$jp" in
    "Temurin17" | "IBMSemeru17" | "OpenJDK17" | "Temurin21" | "IBMSemeru21" | "OpenJDK21")
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
            printf "%s is not supported, Please use valid java from {Temurin17, IBMSemeru17, OpenJDK17} only" "$JAVA_PROVIDED"
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
    printf -- "\nOnce the cluster is up, the Share UI will be available at http://localhost:8080/share \n"
    printf -- '**********************************************************************************************************\n'
}

function installRhel() {
    ALLOWERASING=""
    if [[ "$DISTRO" == rhel-9* ]]; then
        ALLOWERASING="--allowerasing"
    fi
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
"rhel-8.8" | "rhel-8.10" | "rhel-9.2" | "rhel-9.4" | "rhel-9.5")
    installRhel |& tee -a "$LOG_FILE"
    ;;
"sles-15.6")
    installsles  |& tee -a "$LOG_FILE"
    ;;
"ubuntu-22.04")
    installUbuntu  |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
