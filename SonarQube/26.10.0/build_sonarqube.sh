#!/bin/bash
# © Copyright IBM Corporation 2026.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/SonarQube/26.10.0/build_sonarqube.sh
# Execute build script: bash build_sonarqube.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="sonarqube"
PACKAGE_VERSION="26.10.0.133078"
SONAR_VERSION="26.10.0"
SCANNER_VERSION="8.2.0.6438"
NODEJS_VERSION="v24.22.1"
ES_VERSION="9.4.7"
ZSTD_VERSION="1.5.7"
TEMURIN21_URL="https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.13%2B9/OpenJDK21U-jdk_s390x_linux_hotspot_21.0.13_9.tar.gz"
SOURCE_ROOT="$(pwd)"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/SonarQube/26.10.0/patch"
BUILD_DIR="/usr/local"
BUILD_ENV="$HOME/setenv.sh"
TESTS="false"
FORCE="false"
ES9_OPTS="-x :libs:entitlement:compileMain25Java -x :libs:entitlement:compileMain26Java -x :libs:entitlement:compileMain27Java -x :libs:entitlement:qa:entitlement-test-plugin:compileMain25Java -x :libs:entitlement:qa:entitlement-test-plugin:compileMain26Java -x :libs:native:compileMain22Java"

LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
JAVA_PROVIDED="Temurin_21"

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
        printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n'
        exit 1
    fi

    if [[ "$JAVA_PROVIDED" != "Temurin_21" && "$JAVA_PROVIDED" != "OpenJDK_21" ]]; then
        printf -- "$JAVA_PROVIDED is not supported, Please use valid java from {Temurin_21, OpenJDK_21} only." |& tee -a "$LOG_FILE"
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
    sudo rm -rf sonar-scanner-cli-${SCANNER_VERSION}-linux-x64.zip sonarqube-${PACKAGE_VERSION}.zip node-${NODEJS_VERSION}-linux-s390x.tar.xz v$ZSTD_VERSION.tar.gz sonar-application.build.gradle es_remove_list.txt

    if [[ "$JAVA_PROVIDED" == "Temurin_21" ]]; then
        sudo rm -rf temurin21.tar.gz
    fi
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function installTemurin21() {
    if [ ! -x /opt/temurin21/bin/java ]; then
        sudo mkdir -p /opt/temurin21
        cd "$SOURCE_ROOT"
        wget -O temurin21.tar.gz -q "$TEMURIN21_URL"
        sudo tar -C /opt/temurin21 -xzf temurin21.tar.gz --strip-components=1
    fi
    printf -- 'export JAVA_HOME=/opt/temurin21\n' >> "$BUILD_ENV"
    printf -- 'export PATH=$JAVA_HOME/bin:$PATH\n' >> "$BUILD_ENV"
}

function installOpenJDK21() {
    case "$ID" in
      rhel) sudo yum install -y java-21-openjdk-devel ;;
      ubuntu) sudo apt-get update && sudo apt-get install -y openjdk-21-jdk ;;
      sles) sudo zypper install -y java-21-openjdk-devel ;;
    esac
    JAVA_HOME=$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")
    printf -- 'export JAVA_HOME=%s\n' "$JAVA_HOME" >> "$BUILD_ENV"
}

function installJava() {
    printf -- "Installing Java\n"

    if [[ "$JAVA_PROVIDED" == "Temurin_21" ]]; then
        installTemurin21
    elif [[ "$JAVA_PROVIDED" == "OpenJDK_21" ]]; then
        installOpenJDK21
    else
        echo "Unsupported Java"; exit 1
    fi

    printf -- 'export PATH=$JAVA_HOME/bin:$PATH\n' >> "$BUILD_ENV"
}

function installElasticsearch() {
    installTemurin21
    source "$BUILD_ENV"

    java -version

    printf -- "Installing Zstd \n"
    cd "$SOURCE_ROOT"
    wget -q https://github.com/facebook/zstd/archive/refs/tags/v$ZSTD_VERSION.tar.gz
    tar -xzf v$ZSTD_VERSION.tar.gz
    cd zstd-$ZSTD_VERSION
    make -j$(nproc) lib
    make DESTDIR=$(pwd)/_build install

    printf -- "Installing Elasticsearch \n"
    cd "$SOURCE_ROOT"

    export LANG="en_US.UTF-8"
    export ES_JAVA_HOME=$JAVA_HOME

    git clone -b v$ES_VERSION https://github.com/elastic/elasticsearch.git
    cd elasticsearch

    curl -sSL "$PATCH_URL/elasticsearch.patch" | git apply -

    mkdir -p "$SOURCE_ROOT/elasticsearch/distribution/packages/s390x-rpm/"
    mkdir -p "$SOURCE_ROOT/elasticsearch/distribution/packages/s390x-deb/"
    mkdir -p "$SOURCE_ROOT/elasticsearch/distribution/archives/linux-s390x-tar/"
    mkdir -p "$SOURCE_ROOT/elasticsearch/distribution/docker/docker-s390x-export/"

    touch $SOURCE_ROOT/elasticsearch/distribution/packages/s390x-rpm/build.gradle
    touch $SOURCE_ROOT/elasticsearch/distribution/packages/s390x-deb/build.gradle
    touch $SOURCE_ROOT/elasticsearch/distribution/archives/linux-s390x-tar/build.gradle
    touch $SOURCE_ROOT/elasticsearch/distribution/docker/docker-s390x-export/build.gradle

    ./gradlew :distribution:archives:linux-s390x-tar:assemble $ES9_OPTS --max-workers=2 --parallel --console=plain

    elasticsearch="$(pwd)/distribution/archives/linux-s390x-tar/build/distributions/elasticsearch-${ES_VERSION}-SNAPSHOT-linux-s390x.tar.gz"
    # check target
    if [ ! -f "$elasticsearch" ]; then
        echo "can not find the target at: $elasticsearch"
        exit 1
    fi

    # save the artifact link to an env variable.
    echo "export elasticsearch=$elasticsearch" >> "$BUILD_ENV"
}

function configureAndInstall() {
    source "$BUILD_ENV"
    printf -- "Configuration and Installation started \n"

    # Download Sonarqube
    cd "$SOURCE_ROOT"
    wget -q https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-${PACKAGE_VERSION}.zip
    unzip -q sonarqube-${PACKAGE_VERSION}.zip
    wget -q https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SCANNER_VERSION}-linux-x64.zip
    unzip -q sonar-scanner-cli-${SCANNER_VERSION}-linux-x64.zip
    printf -- "Download SonarQube success\n"

    rm -f "$SOURCE_ROOT/sonarqube-${PACKAGE_VERSION}/bin/elasticsearch"
    rm -rf "$SOURCE_ROOT/sonarqube-${PACKAGE_VERSION}/elasticsearch/"*
    tar -xzf "$elasticsearch" -C "$SOURCE_ROOT/sonarqube-${PACKAGE_VERSION}/elasticsearch" --strip-components 1

    # derive module/bin exclusion list from sonar-application/build.gradle at tag
    curl -sSfL "https://raw.githubusercontent.com/SonarSource/sonarqube/${PACKAGE_VERSION}/sonar-application/build.gradle" -o sonar-application.build.gradle
    grep -E "^\s+exclude '\*\*/(modules|bin|jdk)/" sonar-application.build.gradle | sed -E "s/^\s+exclude '\*\*\///; s/'.*//; s/\/\*\*$//" | sort -u > es_remove_list.txt
    while read -r p; do rm -rf "$SOURCE_ROOT/sonarqube-${PACKAGE_VERSION}/elasticsearch/$p"; done < es_remove_list.txt
    cp "$SOURCE_ROOT/sonarqube-${PACKAGE_VERSION}/elasticsearch/bin/elasticsearch" "$SOURCE_ROOT/sonarqube-${PACKAGE_VERSION}/bin/"

    if [[ -z "$(cut -d: -f1 /etc/group | grep -w sonarqube)" ]]; then
        printf -- '\nCreating group sonarqube\n'
        if [[ "$DISTRO" == "sles-16.0" ]]; then
           sudo /usr/sbin/groupadd sonarqube
        else
           sudo groupadd sonarqube      # If group is not already created
        fi
    fi
    if [[ "$DISTRO" == "sles-16.0" ]]; then
       sudo /usr/sbin/usermod -aG sonarqube $(whoami)
    else
       sudo usermod -aG sonarqube $(whoami)
    fi

    #reset
    sudo rm -rf "$BUILD_DIR/sonarqube-${PACKAGE_VERSION}"

    sudo cp -Rf "$SOURCE_ROOT/sonarqube-${PACKAGE_VERSION}" "$BUILD_DIR"

    # Give permission to user
    sudo chown $(whoami):sonarqube -R "$BUILD_DIR/sonarqube-${PACKAGE_VERSION}"

    mkdir -p "$BUILD_DIR/sonarqube-${PACKAGE_VERSION}/elasticsearch/lib/platform/linux-s390x"
    cp "$SOURCE_ROOT/zstd-$ZSTD_VERSION/lib/libzstd.so" "$BUILD_DIR/sonarqube-${PACKAGE_VERSION}/elasticsearch/lib/platform/linux-s390x"

    echo "export SONAR_HOME=$BUILD_DIR/sonarqube-${PACKAGE_VERSION}/bin/linux-x86-64" >> "$BUILD_ENV"

    # Run Test
    runTest

    # cleanup
    cleanup
}

function waitForSonarQube() {
    local count=60
    local sonarqube_started="false"
    while (($count > 0)); do
        if grep -q "Web Server is operational" "$BUILD_DIR/sonarqube-${PACKAGE_VERSION}/logs/web.log" 2>/dev/null && grep -q "SonarQube is operational" "$BUILD_DIR/sonarqube-${PACKAGE_VERSION}/logs/sonar.log" 2>/dev/null; then
            sonarqube_started="true"
            break
        fi
        sleep 15s
        ((count--))
    done

    if [[ "$sonarqube_started" == "true" ]]; then
        sudo ss -nlp | grep :9000 || true
        wget -q -O- http://localhost:9000 >/dev/null
        printf -- "Success !! You have successfully started SonarQube.\n"
    else
        printf -- "Did not detect successful SonarQube start after 15min.\nAttempting tests but there may be failures.\n"
    fi
}

function runTest() {
    set +e
    if [[ "$TESTS" == "true" ]]; then
        printf -- 'Running tests \n\n'
        printf -- 'export SONAR_JAVA_PATH=$JAVA_HOME/bin/java\n' >> "$BUILD_ENV"
        source "$BUILD_ENV"
        java -version

        cd "$BUILD_DIR/sonarqube-${PACKAGE_VERSION}"
        $SONAR_HOME/sonar.sh start
        waitForSonarQube

        cd "$SOURCE_ROOT"
        sed -i 's/use_embedded_jre=true/use_embedded_jre=false/g' "$SOURCE_ROOT/sonar-scanner-${SCANNER_VERSION}-linux-x64/bin/sonar-scanner"
        echo 'sonar.host.url=http://localhost:9000' >> "$SOURCE_ROOT/sonar-scanner-${SCANNER_VERSION}-linux-x64/conf/sonar-scanner.properties"
        echo 'sonar.scanner.skipJreProvisioning=true' >> "$SOURCE_ROOT/sonar-scanner-${SCANNER_VERSION}-linux-x64/conf/sonar-scanner.properties"

        if [ ! -d "sonar-scanning-examples" ]; then
            git clone https://github.com/SonarSource/sonar-scanning-examples.git
        fi

        # Generating a token
        SONAR_TOKEN=$(curl -s -u admin:admin -X POST "http://localhost:9000/api/user_tokens/generate" -d "name=my-token-$(date +%s)" | jq -r .token)

        # Install Node.js for Javascript scanner
        cd "$SOURCE_ROOT"
        wget -q "https://nodejs.org/dist/${NODEJS_VERSION}/node-${NODEJS_VERSION}-linux-s390x.tar.xz"
        chmod ugo+r "node-${NODEJS_VERSION}-linux-s390x.tar.xz"
        sudo tar -C /usr/local -xf "node-${NODEJS_VERSION}-linux-s390x.tar.xz"
        export PATH=$PATH:/usr/local/node-${NODEJS_VERSION}-linux-s390x/bin
        node -v

        printf -- 'Running tests for Javascript Scanner... \n\n'
        cd "$SOURCE_ROOT/sonar-scanning-examples/sonar-scanner/src/javascript"
        "$SOURCE_ROOT/sonar-scanner-${SCANNER_VERSION}-linux-x64/bin/sonar-scanner" -Dsonar.projectKey=myproject-js -Dsonar.sources=. -Dsonar.token="$SONAR_TOKEN"
        wget -q -O- http://localhost:9000/dashboard?id=myproject-js >/dev/null

        # Run Python scanner
        printf -- 'Running tests for Python Scanner... \n\n'
        cd "$SOURCE_ROOT/sonar-scanning-examples/sonar-scanner/src/python"
        grep -q "^sonar.sources=\." sonar-project.properties 2>/dev/null || sed -i '6isonar.sources=.' sonar-project.properties
        grep -q "sonar.exclusions=tests" sonar-project.properties 2>/dev/null || sed -i '7isonar.exclusions=tests/**' sonar-project.properties

        "$SOURCE_ROOT/sonar-scanner-${SCANNER_VERSION}-linux-x64/bin/sonar-scanner" -Dsonar.projectKey=myproject-py -Dsonar.sources=. -Dsonar.token="$SONAR_TOKEN"
        wget -q -O- http://localhost:9000/dashboard?id=myproject-py >/dev/null

        # Run PHP scanner
        printf -- 'Running tests for PHP Scanner... \n\n'
        cd "$SOURCE_ROOT/sonar-scanning-examples/sonar-scanner/src/php"
        "$SOURCE_ROOT/sonar-scanner-${SCANNER_VERSION}-linux-x64/bin/sonar-scanner" -Dsonar.projectKey=myproject-php -Dsonar.sources=. -Dsonar.token="$SONAR_TOKEN"
        wget -q -O- http://localhost:9000/dashboard?id=myproject-php >/dev/null

        $SONAR_HOME/sonar.sh stop || pkill -9 -f "sonar|elasticsearch" || true
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
    printf -- "Detected %s \n" "$PRETTY_NAME" |& tee -a "$LOG_FILE"
    printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" |& tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
    echo
    echo "Usage: "
    echo " bash build_sonarqube.sh  [-d debug] [-y install-without-confirmation] [-t install and run tests] [-j Java to use from {Temurin_21, OpenJDK_21}]"
    echo "       default: If no -j specified, Temurin_21 Runtime will be installed."
    echo
}

while getopts "h?dytj:" opt; do
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
    j)
        JAVA_PROVIDED="$OPTARG"
        ;;
    esac
done

function gettingStarted() {
    source "$HOME/setenv.sh"
    printf -- '\n********************************************************************************************************\n'
    printf -- "\n*Getting Started * \n"
    printf -- "Running sonarqube: \n"
    printf -- "Set Environment variable JAVA_HOME and PATH \n"
    printf -- "export PATH=$JAVA_HOME/bin:\"\$PATH\" \n"
    printf -- "Start SonarQube:\n"
    printf -- "$SONAR_HOME/sonar.sh start\n"
    printf -- "Stop SonarQube:\n"
    printf -- "$SONAR_HOME/sonar.sh stop\n\n"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare # Check Prerequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"rhel-8.10" | "rhel-9.6" | "rhel-9.8" | "rhel-10.0" | "rhel-10.2")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y wget git unzip tar which net-tools curl gzip patch make gcc gcc-c++ xz jq procps iproute --allowerasing |& tee -a "$LOG_FILE"
    ;;
"sles-15.7" | "sles-16.0")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y git wget unzip tar which gzip xz net-tools curl patch make gcc gcc-c++ jq procps gawk iproute2 findutils |& tee -a "$LOG_FILE"
    ;;
"ubuntu-22.04" | "ubuntu-24.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y wget git unzip tar net-tools xz-utils curl gzip patch locales make gcc g++ jq procps iproute2 ca-certificates |& tee -a "$LOG_FILE"
    sudo locale-gen en_US.UTF-8
    ;;

*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac
installElasticsearch |& tee -a "$LOG_FILE"
installJava |& tee -a "$LOG_FILE"
configureAndInstall |& tee -a "$LOG_FILE"
gettingStarted |& tee -a "$LOG_FILE"
