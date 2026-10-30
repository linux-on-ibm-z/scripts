#!/bin/bash
# © Copyright IBM Corporation 2026.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/SonarQube/26.9.0/build_sonarqube.sh
# Execute build script: bash build_sonarqube.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="sonarqube"
PACKAGE_VERSION="26.9.0.129388"
SONAR_VERSION="26.9.0"
SCANNER_VERSION="8.1.0.6389"
NODEJS_VERSION="v24.2.0"
ES_VERSION="9.4.3"
ZSTD_VERSION=1.5.7
SOURCE_ROOT="$(pwd)"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/SonarQube/26.9.0/patch"
BUILD_DIR="/usr/local"
BUILD_ENV="$HOME/setenv.sh"
TESTS="false"
FORCE="false"
ES9_EXCLUDED_TASKS=(
    ":libs:entitlement:bridge:compileMain22Java"
    ":libs:entitlement:bridge:compileMain23Java"
    ":libs:entitlement:compileMain22Java"
    ":libs:entitlement:compileMain23Java"
    ":libs:entitlement:compileMain25Java"
    ":libs:entitlement:compileMain26Java"
    ":libs:native:compileMain22Java"
    ":libs:simdvec:compileMain22Java"
)

ES9_OPTS=""
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
JAVA_PROVIDED="Temurin_21"

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
    
    if [[ "$JAVA_PROVIDED" != "Temurin_21" && "$JAVA_PROVIDED" != "OpenJDK_21" ]]
    then
        printf --  "$JAVA_PROVIDED is not supported, Please use valid java from {Temurin_21, OpenJDK_21} only." |& tee -a "$LOG_FILE"
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
    sudo rm -rf sonar-scanner-cli-${SCANNER_VERSION}-linux-x64.zip sonarqube-${PACKAGE_VERSION}.zip
    sudo rm -rf temurin17.tar.gz

    if [[ "$JAVA_PROVIDED" == "Temurin_21" ]]; then
	      sudo rm -rf temurin21.tar.gz
    fi
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function installTemurin21() {
    sudo mkdir -p /opt/temurin21
    cd "$SOURCE_ROOT"
    wget -O temurin21.tar.gz -q https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.11%2B10/OpenJDK21U-jdk_s390x_linux_hotspot_21.0.11_10.tar.gz
    sudo tar -C /opt/temurin21 -xzf temurin21.tar.gz --strip-components=1
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

function installJava17() {
    sudo mkdir -p /opt/java17
    cd "$SOURCE_ROOT"
    wget -O temurin17.tar.gz -q https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.19%2B10/OpenJDK17U-jdk_s390x_linux_hotspot_17.0.19_10.tar.gz
    sudo tar -C /opt/java17 -xzf temurin17.tar.gz --strip-components=1
    printf -- 'export RUNTIME_JAVA_HOME=/opt/java17\n' >> "$BUILD_ENV"
}

function installJava() {
    printf -- "Installing Java\n"
    #installTemurin21

    if [[ "$JAVA_PROVIDED" == "Temurin_21" ]]; then
        printf -- 'export JAVA_HOME=/opt/temurin21\n' >> "$BUILD_ENV"
    elif [[ "$JAVA_PROVIDED" == "OpenJDK_21" ]]; then
        installOpenJDK21
    else
        echo "Unsupported Java"; exit 1
    fi

    printf -- 'export PATH=$JAVA_HOME/bin:$PATH\n' >> "$BUILD_ENV"
    
}

function configureEs9GradleOpts() {
    local task
    local opts=()

    for task in "${ES9_EXCLUDED_TASKS[@]}"; do
        if ./gradlew -q help --task "$task" >/dev/null 2>&1; then
            opts+=("-x" "$task")
        fi
    done

    ES9_OPTS="${opts[*]}"
}

function installElasticsearch() {
    
    installTemurin21
    installJava17
    source "$BUILD_ENV"
    
    java -version
    
	# Build ml-cpp for Elasticsearch 9.4.3
    printf -- "Building ml-cpp for Elasticsearch %s\n" "$ES_VERSION"

    cd "$SOURCE_ROOT"

    rm -rf "$SOURCE_ROOT/ml-cpp"
    rm -rf /tmp/mlcpp-ivy

    git clone --depth 1 -b "v${ES_VERSION}" \
        https://github.com/elastic/ml-cpp.git

    cd "$SOURCE_ROOT/ml-cpp"

    # Apply patch
    curl -sSL "$PATCH_URL/ml-cpp.patch" | git apply -

    chmod +x s390x/build_ml_cpp.sh

    (
        # ml-cpp must see Elasticsearch version, not SonarQube version
        export PACKAGE_VERSION="$ES_VERSION"

        export SOURCE_ROOT="$SOURCE_ROOT"
        export LOG_FILE="$LOG_FILE"
        export BUILD_ENV="$BUILD_ENV"

        export ML_CPP_REPO="/tmp/mlcpp-ivy"
        export ML_CPP_SOURCE_DIR="$SOURCE_ROOT/ml-cpp"

        # Reuse Java17 already installed by SonarQube script
        export ML_CPP_JAVA_HOME="/opt/java17"

		# RHEL 8.10 default python3 is too old for PyTorch 2.7.1
        if [[ "$DISTRO" == "rhel-8.10" || "$DISTRO" == "sles-15.7" ]]; then
			export PYTHON_BIN="python3.11"
		elif [[ "$DISTRO" == "sles-16.0" ]]; then
			export PYTHON_BIN="python3.13"
		else
			export PYTHON_BIN="${PYTHON_BIN:-python3}"
		fi

        bash "$SOURCE_ROOT/ml-cpp/s390x/build_ml_cpp.sh"
    )

    ML_CPP_GRADLE_OPTS="-Dbuild.ml_cpp.repo=file:///tmp/mlcpp-ivy"
	
    #printf -- "Installing Zstd \n"
    cd $SOURCE_ROOT
    wget -q https://github.com/facebook/zstd/archive/refs/tags/v$ZSTD_VERSION.tar.gz
    tar -xzf v$ZSTD_VERSION.tar.gz
    cd zstd-$ZSTD_VERSION
    make -j$(nproc) lib
    make DESTDIR=$(pwd)/_build install  
    
    printf -- "Installing Elasticsearch \n"
    cd $SOURCE_ROOT
        
    export LANG="en_US.UTF-8"
    export ES_JAVA_HOME=$JAVA_HOME

    git clone -b v$ES_VERSION https://github.com/elastic/elasticsearch.git
    cd elasticsearch
	
    curl -sSL "$PATCH_URL/elasticsearch.patch" | git apply -
	
	sed -i \
		"s#%S390X_ZSTD_DEP_DIR%#$SOURCE_ROOT/zstd-native-dep#g" \
		"$SOURCE_ROOT/elasticsearch/libs/native/libraries/build.gradle"
    
	# Build JANSI for s390x
    cd "$SOURCE_ROOT"

    rm -rf jansi jansi-jar

    git clone --depth 1 -b jansi-2.4.0 \
    	https://github.com/fusesource/jansi.git
   
    cd jansi
    make clean-native native OS_NAME=Linux OS_ARCH=s390x

    mkdir -p "$SOURCE_ROOT/jansi-jar"
    cd "$SOURCE_ROOT/jansi-jar"

    wget -q https://repo1.maven.org/maven2/org/fusesource/jansi/jansi/2.4.0/jansi-2.4.0.jar

    jar xf jansi-2.4.0.jar

    mkdir -p org/fusesource/jansi/internal/native/Linux/s390x

    cp "$SOURCE_ROOT/jansi/target/native-Linux-s390x/libjansi.so" \
       org/fusesource/jansi/internal/native/Linux/s390x/

    jar cf jansi-2.4.0.jar .

    export GRADLE_USER_HOME="$SOURCE_ROOT/.gradle"

    mkdir -p "$GRADLE_USER_HOME/caches/modules-2/files-2.1/org.fusesource.jansi/jansi/2.4.0/321c614f85f1dea6bb08c1817c60d53b7f3552fd/"

    cp jansi-2.4.0.jar \
       "$GRADLE_USER_HOME/caches/modules-2/files-2.1/org.fusesource.jansi/jansi/2.4.0/321c614f85f1dea6bb08c1817c60d53b7f3552fd/"

	jansi_sha256=$(sha256sum jansi-2.4.0.jar | awk '{print $1}')

	sed -i -e \
	  's|6cd91991323dd7b2fb28ca93d7ac12af5a86a2f53279e2b35827b30313fd0b9f|'"${jansi_sha256}"'|g' \
	  -e 's|616491ff68183f90e145b68874627742d796572dbfe4d8dfe64bac22a27864cb|'"${jansi_sha256}"'|g' \
	  "$SOURCE_ROOT/elasticsearch/gradle/verification-metadata.xml"
	  
	cd "$SOURCE_ROOT"

    mkdir -p "$SOURCE_ROOT/zstd-native-dep/artifacts/linux-s390x"

    cp "$SOURCE_ROOT/zstd-$ZSTD_VERSION/lib/libzstd.so" \
       "$SOURCE_ROOT/zstd-$ZSTD_VERSION/LICENSE" \
       "$SOURCE_ROOT/zstd-native-dep/artifacts/linux-s390x/"

    jar --create \
        --no-manifest \
        --file "$SOURCE_ROOT/zstd-native-dep/zstd-${ZSTD_VERSION}-linux-s390x.jar" \
        -C "$SOURCE_ROOT/zstd-native-dep/artifacts/" .
	
	for dir in \
        packages/s390x-rpm \
        packages/s390x-deb \
        archives/linux-s390x-tar \
        docker/docker-s390x-export
    do
        mkdir -p "$SOURCE_ROOT/elasticsearch/distribution/$dir"
        touch "$SOURCE_ROOT/elasticsearch/distribution/$dir/build.gradle"
    done
    
	cd "$SOURCE_ROOT/elasticsearch"
	export LOCAL_VEC_BINARY_OS="${LOCAL_VEC_BINARY_OS:-linux-s390x}"
    ./gradlew --stop >/dev/null 2>&1 || true

    configureEs9GradleOpts

    ./gradlew \
        :distribution:archives:linux-s390x-tar:assemble \
        $ES9_OPTS \
        $ML_CPP_GRADLE_OPTS \
        --max-workers=`nproc` \
        --parallel

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
    wget -q https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SCANNER_VERSION}-linux-x64.zip
    unzip -q sonar-scanner-cli-${SCANNER_VERSION}-linux-x64.zip
    printf -- "Download SonarQube success\n"
	
    rm $SOURCE_ROOT/sonarqube-${PACKAGE_VERSION}/bin/elasticsearch
    rm -rfd $SOURCE_ROOT/sonarqube-${PACKAGE_VERSION}/elasticsearch/*
    tar -xzf $elasticsearch -C $SOURCE_ROOT/sonarqube-${PACKAGE_VERSION}/elasticsearch --strip-components 1
    rm -rf $SOURCE_ROOT/sonarqube-${PACKAGE_VERSION}/elasticsearch/modules/blob-cache $SOURCE_ROOT/sonarqube-${PACKAGE_VERSION}/elasticsearch/modules/searchable-snapshots
    cp $SOURCE_ROOT/sonarqube-${PACKAGE_VERSION}/elasticsearch/bin/elasticsearch $SOURCE_ROOT/sonarqube-${PACKAGE_VERSION}/bin/
    if ([[ -z "$(cut -d: -f1 /etc/group | grep sonarqube)" ]]); then
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
    
    sudo cp -Rf "$SOURCE_ROOT"/sonarqube-${PACKAGE_VERSION} "$BUILD_DIR"
    
    #Give permission to user
    sudo chown $(whoami):sonarqube -R "$BUILD_DIR/sonarqube-${PACKAGE_VERSION}"

	# Make SonarQube startup script executable
	sudo chmod 755 \
		"$BUILD_DIR/sonarqube-${PACKAGE_VERSION}/bin/linux-x86-64/sonar.sh"
    
    mkdir -p $BUILD_DIR/sonarqube-${PACKAGE_VERSION}/elasticsearch/lib/platform/linux-s390x
    cp $SOURCE_ROOT/zstd-$ZSTD_VERSION/lib/libzstd.so $BUILD_DIR/sonarqube-${PACKAGE_VERSION}/elasticsearch/lib/platform/linux-s390x
    
    
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
        sudo ss -nlp | grep :9000
        wget -q -O- http://localhost:9000
        printf -- "Success !! You have successfully started SonarQube.\n"
    else
        printf -- "Did not detect successful SonarQube start after 15min.\nAttempting tests but there may be failures.\n"
    fi
}

function runTest() {
    set +e
    if [[ "$TESTS" == "true" ]]; then
        printf -- 'Running tests \n\n'
        printf -- 'export SONAR_JAVA_PATH=$JAVA_HOME/bin/java\n'  >> "$BUILD_ENV"
        source "$BUILD_ENV"
        java -version
        cd /usr/local/sonarqube-${PACKAGE_VERSION}
        $SONAR_HOME/sonar.sh start
        waitForSonarQube

        cd "$SOURCE_ROOT"
        sed -i 's/use_embedded_jre=true/use_embedded_jre=false/g' "$SOURCE_ROOT"/sonar-scanner-${SCANNER_VERSION}-linux-x64/bin/sonar-scanner
        echo 'sonar.host.url=http://localhost:9000' >> "$SOURCE_ROOT"/sonar-scanner-${SCANNER_VERSION}-linux-x64/conf/sonar-scanner.properties
        echo 'sonar.scanner.skipJreProvisioning=true' >> "$SOURCE_ROOT"/sonar-scanner-${SCANNER_VERSION}-linux-x64/conf/sonar-scanner.properties

        git clone https://github.com/SonarSource/sonar-scanning-examples.git

        #Genrating a token 
        SONAR_TOKEN=$(curl -u admin:admin -X POST "http://localhost:9000/api/user_tokens/generate" -d "name=my-token" | jq -r .token)
    
        #Run Javacript scanner
        cd "$SOURCE_ROOT"
        wget -q https://nodejs.org/dist/${NODEJS_VERSION}/node-${NODEJS_VERSION}-linux-s390x.tar.xz
        chmod ugo+r node-${NODEJS_VERSION}-linux-s390x.tar.xz
        sudo tar -C /usr/local -xf node-${NODEJS_VERSION}-linux-s390x.tar.xz
        export PATH=$PATH:/usr/local/node-${NODEJS_VERSION}-linux-s390x/bin
        node -v

        printf -- 'Running tests for Javascript Scanner... \n\n'
        cd "$SOURCE_ROOT"/sonar-scanning-examples/sonar-scanner/src/javascript
        "$SOURCE_ROOT"/sonar-scanner-${SCANNER_VERSION}-linux-x64/bin/sonar-scanner -Dsonar.projectKey=myproject-js -Dsonar.sources=. -Dsonar.token=$SONAR_TOKEN
        wget -q -O- http://localhost:9000/dashboard?id=myproject-js
		
        # Run Python scanner
        printf -- 'Running tests for Python Scanner... \n\n'
        cd "$SOURCE_ROOT"/sonar-scanning-examples/sonar-scanner/src/python
        sed -i '6isonar.sources=.' sonar-project.properties
        sed -i '7isonar.exclusions=tests/**' sonar-project.properties

        "$SOURCE_ROOT"/sonar-scanner-${SCANNER_VERSION}-linux-x64/bin/sonar-scanner -Dsonar.projectKey=myproject-py -Dsonar.sources=. -Dsonar.token=$SONAR_TOKEN
        wget -q -O- http://localhost:9000/dashboard?id=myproject-py

        # Run PHP scanner
        printf -- 'Running tests for PHP Scanner... \n\n'
        cd "$SOURCE_ROOT"/sonar-scanning-examples/sonar-scanner/src/php
        "$SOURCE_ROOT"/sonar-scanner-${SCANNER_VERSION}-linux-x64/bin/sonar-scanner -Dsonar.projectKey=myproject-php -Dsonar.sources=. -Dsonar.token=$SONAR_TOKEN
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
"rhel-8.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
	sudo yum install -y wget git unzip tar which net-tools curl gzip patch make gcc gcc-c++ xz jq procps iproute bzip2 zip python3.11 python3.11-devel python3.11-pip cmake ninja-build zlib-devel libxml2-devel gcc-toolset-13 gcc-toolset-13-gcc gcc-toolset-13-gcc-c++ gcc-toolset-13-binutils |& tee -a "$LOG_FILE"
    ;;
"rhel-9.6" | "rhel-9.8" | "rhel-10.0" | "rhel-10.2")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y wget git unzip tar which net-tools curl gzip patch make gcc gcc-c++ xz jq procps iproute bzip2 zip python3 python3-devel python3-pip cmake ninja-build zlib-devel libxml2-devel |& tee -a "$LOG_FILE"
	;;
"sles-15.7")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y git wget unzip tar which gzip xz net-tools curl patch make gcc gcc-c++ jq procps gawk iproute2 bzip2 zip python311 python311-devel python311-pip cmake ninja zlib-devel libxml2-devel gcc15 gcc15-c++ |& tee -a "$LOG_FILE"
    ;;
"sles-16.0")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y git wget unzip tar which gzip xz net-tools curl patch make gcc gcc-c++ jq procps gawk iproute2 bzip2 zip python313 python313-devel python313-pip cmake ninja zlib-devel libxml2-devel gcc15 gcc15-c++ |& tee -a "$LOG_FILE"
    ;;
"ubuntu-22.04" | "ubuntu-24.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y wget git unzip tar net-tools xz-utils curl gzip patch locales make gcc g++ jq procps iproute2 bzip2 zip zlib1g-dev libxml2-dev python3 python3-dev python3-pip cmake ninja-build |& tee -a "$LOG_FILE"
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
