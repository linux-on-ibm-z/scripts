#!/bin/bash
# © Copyright IBM Corporation 2024.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/SonarQube/10.5.0/build_sonarqube.sh
# Execute build script: bash build_sonarqube.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="sonarqube"
PACKAGE_VERSION="10.5.0.89998"
SONAR_VERSION="10.5.0"
SCANNER_VERSION="5.0.1.3006"
NODEJS_VERSION="v20.12.2"
ES_VERSION="8.11.0" #https://github.com/SonarSource/sonarqube/blob/10.5.0.89998/gradle.properties#L16

SOURCE_ROOT="$(pwd)"
BUILD_DIR="/usr/local"
BUILD_ENV="$HOME/setenv.sh"
TESTS="false"
FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
JAVA_PROVIDED="Temurin_17"

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

    if [[ "$JAVA_PROVIDED" != "Temurin_17" && "$JAVA_PROVIDED" != "OpenJDK" ]]
    then
        printf --  "$JAVA_PROVIDED is not supported, Please use valid java from {Temurin_17, OpenJDK} only." |& tee -a "$LOG_FILE"
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
    sudo rm -rf sonar-scanner-cli-${SCANNER_VERSION}-linux.zip sonarqube-${PACKAGE_VERSION}.zip

    if [[ "$JAVA_PROVIDED" == "Temurin_17" ]]; then
        sudo rm -rf temurin17.tar.gz
    fi
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function installJava() {
    printf -- "Installing Java \n"
    echo "Java provided by user $JAVA_PROVIDED"
    if [[ "$JAVA_PROVIDED" == "Temurin_17" ]]; then
        # Install Eclipse Adoptium Temurin Runtime 17
        sudo mkdir -p /opt/java
        cd "$SOURCE_ROOT"
        sudo wget -O temurin17.tar.gz -q https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.10%2B7/OpenJDK17U-jdk_s390x_linux_hotspot_17.0.10_7.tar.gz
        sudo tar -C /opt/java -xzf temurin17.tar.gz --strip 1

        printf -- 'export JAVA_HOME=/opt/java\n'  >> "$BUILD_ENV"
        printf -- 'Eclipse Adoptium Temurin Runtime 17 installed\n'
    
    elif [[ "$JAVA_PROVIDED" == "OpenJDK" ]]; then
        if [[ "$ID" == "rhel" ]]; then
            # OpenJDK17 is not available in RHEL 7.x repo
            if [[ $VERSION_ID == 7* ]]; then
              printf --  'OpenJDK 17 is not supported for RHEL 7.x distro, Please use valid java from {Temurin_17} only' |& tee -a "$LOG_FILE"
              exit 1
            fi
            sudo yum install -y java-17-openjdk-devel
            printf -- 'export JAVA_HOME=/usr/lib/jvm/java-17-openjdk\n'  >> "$BUILD_ENV"
        elif [[ "$ID" == "sles" ]]; then
            # OpenJDK17 is not available in SLES 12.5 repo
            if [[ $VERSION_ID == 12.5 ]]; then
              printf --  'OpenJDK 17 is not supported for SLES 12.5, Please use valid java from {Temurin_17} only' |& tee -a "$LOG_FILE"
              exit 1
            fi
            sudo zypper install -y java-17-openjdk-devel
            printf -- 'export JAVA_HOME=/usr/lib64/jvm/java-17-openjdk\n'  >> "$BUILD_ENV"
        elif [[ "$ID" == "ubuntu" ]]; then
            sudo apt-get install -y openjdk-17-jdk
            printf -- 'export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-s390x\n'  >> "$BUILD_ENV"
        fi

    else
        printf --  '$JAVA_PROVIDED is not supported, Please use valid java from {Temurin_17, OpenJDK} only' >> "$LOG_FILE"
        exit 1
    fi

    printf -- 'export JAVA_HOME for "$ID"  \n'  >> "$LOG_FILE"

    printf -- 'export PATH=$JAVA_HOME/bin:$PATH\n'  >> "$BUILD_ENV"
}

function installElasticsearch() {
    source "$BUILD_ENV"

    java -version

    printf -- "Installing Elasticsearch \n"
    cd $SOURCE_ROOT
    PATCH_URL=https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/SonarQube/10.5.0/patch/elasticsearch.diff
    export LANG="en_US.UTF-8"
    export ES_JAVA_HOME=$JAVA_HOME
    export JAVA17_HOME=$JAVA_HOME

    git clone https://github.com/elastic/elasticsearch
    cd elasticsearch
    git checkout v$ES_VERSION
    
    wget $PATCH_URL
    git apply elasticsearch.diff

    ./gradlew :distribution:archives:linux-s390x-tar:assemble --max-workers=`nproc`  --parallel

    elasticsearch=`pwd`/distribution/archives/linux-s390x-tar/build/distributions/elasticsearch-"$ES_VERSION"-SNAPSHOT-linux-s390x.tar.gz
    #check target
    if [ ! -f $elasticsearch ]
    then
        echo "can not find the target at: $elasticsearch"
        exit 1
    fi

    # save the artifact link to an env variable.
    echo "export elasticsearch=$elasticsearch" >> "$BUILD_ENV"
}

function configureAndInstall() {
    source "$BUILD_ENV"
    printf -- "Configuration and Installation started \n"

    #Download Sonarqube
    cd "$SOURCE_ROOT"
    wget -q https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-${PACKAGE_VERSION}.zip
    unzip -q sonarqube-${PACKAGE_VERSION}.zip
    wget -q https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SCANNER_VERSION}-linux.zip
    unzip -q sonar-scanner-cli-${SCANNER_VERSION}-linux.zip
    printf -- "Download sonarqube success\n"

    rm $SOURCE_ROOT/sonarqube-${PACKAGE_VERSION}/bin/elasticsearch
    rm -rfd $SOURCE_ROOT/sonarqube-${PACKAGE_VERSION}/elasticsearch/*
    tar -xzf $elasticsearch -C $SOURCE_ROOT/sonarqube-${PACKAGE_VERSION}/elasticsearch --strip-components 1
    cp $SOURCE_ROOT/sonarqube-${PACKAGE_VERSION}/elasticsearch/bin/elasticsearch $SOURCE_ROOT/sonarqube-${PACKAGE_VERSION}/bin/

    if ([[ -z "$(cut -d: -f1 /etc/group | grep sonarqube)" ]]); then
            printf -- '\nCreating group sonarqube\n'
            sudo groupadd sonarqube      # If group is not already created

    fi
    sudo usermod -aG sonarqube $(whoami)

    # Update configurations to disable unsupported xpack.ml
    sudo echo 'xpack.ml.enabled: false' >> "$SOURCE_ROOT"/sonarqube-${PACKAGE_VERSION}/elasticsearch/config/elasticsearch.yml
    
    sudo cp -Rf "$SOURCE_ROOT"/sonarqube-${PACKAGE_VERSION} "$BUILD_DIR"

    #Give permission to user
    sudo chown $(whoami):sonarqube -R "$BUILD_DIR/sonarqube-${PACKAGE_VERSION}"
    echo "export SONAR_HOME=$BUILD_DIR/sonarqube-${PACKAGE_VERSION}/bin/linux-x86-64" >> "$BUILD_ENV"
    #Run Test
    runTest

    #cleanup
    cleanup

}

function waitForSonarQube() {
    local count=60
    local sonarqube_started="false"
    while (($count > 0)); do
        if grep -q "Web Server is operational" "$BUILD_DIR/sonarqube-${PACKAGE_VERSION}/logs/web.log" && grep -q "SonarQube is operational" "$BUILD_DIR/sonarqube-${PACKAGE_VERSION}/logs/sonar.log" ; then
            sonarqube_started="true"
            break
        fi
        sleep 15s
        ((count--))
    done

    if [[ $sonarqube_started == "true" ]]; then
        sudo netstat -nlp | grep :9000
        wget -q -O- http://localhost:9000
        printf -- "Success !! You have successfully started sonarqube.\n"
    else
        printf -- "Did not detect successful sonarqube start after 15min.\nAttempting tests but there may be failures.\n"
    fi
}

function runTest() {
    set +e
    if [[ "$TESTS" == "true" ]]; then
        printf -- 'Running tests \n\n' |& tee -a "$LOG_FILE"
        source "$BUILD_ENV"
        java -version >> "$LOG_FILE"
        cd /usr/local/sonarqube-${PACKAGE_VERSION}
        $SONAR_HOME/sonar.sh start
        waitForSonarQube

        cd "$SOURCE_ROOT"
        sed -i 's/use_embedded_jre=true/use_embedded_jre=false/g' "$SOURCE_ROOT"/sonar-scanner-${SCANNER_VERSION}-linux/bin/sonar-scanner

        git clone https://github.com/SonarSource/sonar-scanning-examples.git

        #Run Java Scanner
        cd $SOURCE_ROOT/sonar-scanning-examples/sonar-scanner-gradle/gradle-basic
        ./gradlew --no-daemon -Dsonar.host.url=http://localhost:9000 -Dsonar.login="admin" -Dsonar.password="admin" sonar
        wget -q -O- http://localhost:9000/dashboard?id=sonarqube-scanner-gradle
    
        cd $SOURCE_ROOT/sonar-scanning-examples/sonar-scanner-gradle/gradle-multimodule
        ./gradlew --no-daemon -Dsonar.host.url=http://localhost:9000 -Dsonar.login="admin" -Dsonar.password="admin" sonar
        wget -q -O- http://localhost:9000/dashboard?id=org.sonarqube%3Agradle-multimodule

        cd $SOURCE_ROOT/sonar-scanning-examples/sonar-scanner-gradle/gradle-multimodule-coverage
        ./gradlew --no-daemon clean build codeCoverageReport -Dsonar.host.url=http://localhost:9000 -Dsonar.login="admin" -Dsonar.password="admin" sonar	  
        wget -q -O- http://localhost:9000/dashboard?id=org.sonarqube.gradle-multi-module-jacoco
    
        #Run Javacript scanner (except for RHEL 7.x and SLES 12 SP5)
	if [[ "$DISTRO" != "sles-12.5" ]] && [[ "$DISTRO" != "rhel-7."* ]]; then
          cd "$SOURCE_ROOT"
          wget -q https://nodejs.org/dist/${NODEJS_VERSION}/node-${NODEJS_VERSION}-linux-s390x.tar.xz
          chmod ugo+r node-${NODEJS_VERSION}-linux-s390x.tar.xz
          sudo tar -C /usr/local -xf node-${NODEJS_VERSION}-linux-s390x.tar.xz
          export PATH=$PATH:/usr/local/node-${NODEJS_VERSION}-linux-s390x/bin
          node -v

          cd "$SOURCE_ROOT"/sonar-scanning-examples/sonar-scanner/src/javascript
          "$SOURCE_ROOT"/sonar-scanner-${SCANNER_VERSION}-linux/bin/sonar-scanner -Dsonar.projectKey=myproject-js -Dsonar.sources=. -Dsonar.login="admin" -Dsonar.password="admin"
          wget -q -O- http://localhost:9000/dashboard?id=myproject-js
        fi
		
        # Run Python scanner
        cd "$SOURCE_ROOT"/sonar-scanning-examples/sonar-scanner/src/python
        "$SOURCE_ROOT"/sonar-scanner-${SCANNER_VERSION}-linux/bin/sonar-scanner -Dsonar.projectKey=myproject-py -Dsonar.sources=. -Dsonar.login="admin" -Dsonar.password="admin"
        wget -q -O- http://localhost:9000/dashboard?id=myproject-py

        # Run PHP scanner
        cd "$SOURCE_ROOT"/sonar-scanning-examples/sonar-scanner/src/php
        "$SOURCE_ROOT"/sonar-scanner-${SCANNER_VERSION}-linux/bin/sonar-scanner -Dsonar.projectKey=myproject-php -Dsonar.sources=. -Dsonar.login="admin" -Dsonar.password="admin"
        wget -q -O- http://localhost:9000/dashboard?id=myproject-php

        $SONAR_HOME/sonar.sh stop
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
    echo " bash build_sonarqube.sh  [-d debug] [-y install-without-confirmation] [-t install and run tests] [-j Java to use from {Temurin_17, OpenJDK}]"
    echo "       default: If no -j specified, Temurin_17 Runtime will be installed."
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
    source $HOME/setenv.sh
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
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"ubuntu-20.04" | "ubuntu-22.04" | "ubuntu-23.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y wget git unzip tar net-tools xz-utils curl gzip patch locales make gcc g++ procps |& tee -a "$LOG_FILE"
    sudo locale-gen en_US.UTF-8
    ;;
"rhel-7.8" | "rhel-7.9" | "rhel-8.8" | "rhel-8.9" | "rhel-9.2" | "rhel-9.3")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y wget git unzip tar which net-tools curl gzip patch make gcc gcc-c++ xz procps |& tee -a "$LOG_FILE"
    ;;
"sles-12.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y git wget unzip tar which gzip xz net-tools curl patch make gcc gcc-c++ procps libnghttp2-devel |& tee -a "$LOG_FILE"
    ;;
"sles-15.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y git wget unzip tar which gzip xz net-tools curl patch make gcc gcc-c++ procps |& tee -a "$LOG_FILE"
    ;;

*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac
installJava |& tee -a "$LOG_FILE"
installElasticsearch |& tee -a "$LOG_FILE"
configureAndInstall |& tee -a "$LOG_FILE"
gettingStarted |& tee -a "$LOG_FILE"
