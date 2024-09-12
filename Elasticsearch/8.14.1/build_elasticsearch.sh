#!/bin/bash
# ©  Copyright IBM Corporation 2024.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Elasticsearch/8.14.1/build_elasticsearch.sh
# Execute build script: bash build_elasticsearch.sh    (provide -h for help)
#
set -e -o pipefail

PACKAGE_NAME="elasticsearch"
PACKAGE_VERSION="8.14.1"
CURDIR="$(pwd)"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Elasticsearch/${PACKAGE_VERSION}/patch"
ES_REPO_URL="https://github.com/elastic/elasticsearch"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
JAVA_PROVIDED="Temurin17"
NON_ROOT_USER="$(whoami)"
FORCE="false"
BUILD_ENV="$HOME/setenv.sh"
CPU_NUM="$(grep -c ^processor /proc/cpuinfo)"
USER_IN_GROUP_DOCKER=$(id -nGz "$USER" | tr '\0' '\n' | grep -c '^docker$')

trap cleanup 0 1 2 ERR

# Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
        mkdir -p "$CURDIR/logs/"
fi

if [ -f "/etc/os-release" ]; then
        source "/etc/os-release"
fi

DISTRO="$ID-$VERSION_ID"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-${DISTRO}-$(date +"%F-%T").log"

function prepare() {

        if command -v "sudo" >/dev/null; then
                printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
        else
                printf -- 'Sudo : No \n' >>"$LOG_FILE"
                printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n'
                exit 1
        fi

        if command -v "docker" >/dev/null; then
            printf -- 'Docker : Yes\n' |& tee -a "${LOG_FILE}"
        else
            printf -- 'Docker : No \n' |& tee -a "${LOG_FILE}"
            printf -- 'Please install Docker based on your distro. \n' |& tee -a "${LOG_FILE}"
            exit 1
        fi

        local have_docker_compose="false"
        if docker compose version >/dev/null 2>&1; then
            have_docker_compose="true"
        elif [[ $DISTRO =~ ^sles-12 ]]; then
            have_docker_compose="skip"
        fi
        if [[ $have_docker_compose == "true" ]]; then
            printf -- 'Docker Compose : Yes\n' |& tee -a "${LOG_FILE}"
        elif [[ $have_docker_compose == "skip" ]]; then
            printf -- 'Docker Compose : Not Available\n' |& tee -a "${LOG_FILE}"
            printf -- 'This platform does not provide a recent Docker Compose plugin required to run some integration tests. \n' |& tee -a "${LOG_FILE}"
            printf -- 'Tests that require Docker Compose will be skipped. \n' |& tee -a "${LOG_FILE}"
        else
            printf -- 'Docker Compose : Not Installed \n' |& tee -a "${LOG_FILE}"
            printf -- 'The Docker Compose plugin is required to run some integration tests. \n' |& tee -a "${LOG_FILE}"
            printf -- 'Tests that require Docker Compose will be skipped. \n' |& tee -a "${LOG_FILE}"
        fi

        if [[ "$USER_IN_GROUP_DOCKER" == "1" ]]; then
            printf -- "User %s belongs to group docker\n" "$USER" |& tee -a "${LOG_FILE}"
        else
            printf -- "Please ensure User %s belongs to group docker.\n" "$USER" |& tee -a "${LOG_FILE}"
            exit 1
        fi

        if [[ "$FORCE" == "true" ]]; then
                printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
        else
                printf -- 'As part of the installation, dependencies would be installed/upgraded.\n'

                while true; do
                        read -r -p "Do you want to continue (y/n) ? :  " yn
                        case $yn in
                        [Yy]*)

                                break
                                ;;
                        [Nn]*) exit ;;
                        *) echo "Please provide Correct input to proceed." ;;
                        esac
                done
        fi

        # zero out
        true > "$BUILD_ENV"
}

function cleanup() {
        rm -rf "${CURDIR}/temurin.tar.gz"
        rm -rf "${CURDIR}/v1.5.5.tar.gz"
        rm -rf "${CURDIR}/jansi"
        rm -rf "${CURDIR}/jansi-jar"
        printf -- '\nCleaned up the artifacts.\n' >>"$LOG_FILE"
}

function getJavaUrl() {
    local jruntime=$1
    local jdist=$2
    case "${jruntime}" in
    "Temurin17")
        echo "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.11%2B9/OpenJDK17U-${jdist}_s390x_linux_hotspot_17.0.11_9.tar.gz"
        ;;
    "Temurin21")
        echo "https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.3%2B9/OpenJDK21U-${jdist}_s390x_linux_hotspot_21.0.3_9.tar.gz"
        ;;
    esac
    echo ""
}

function isValidJavaProvided() {
    local jp=$1
    case "$jp" in
    "Temurin17")
        return 0
        ;;
    "OpenJDK17")
        if [[ ! $DISTRO =~ ^sles-12 && ! $DISTRO =~ ^rhel-7 ]]; then
                return 0
        fi
        ;;
    "Temurin21")
        return 0
        ;;
    "OpenJDK21")
        # OpenJDK 21 is not currently available on RHEL 7, SLES 12/15
        if [[ ! $DISTRO =~ ^sles-12 && ! $DISTRO =~ ^rhel-7 && ! $DISTRO =~ ^sles-15 ]]; then
                return 0
        fi
        ;;
    esac
    return 1
}

function installJava() {
        local jver="$1"
        printf -- "Download and install Java \n"
        cd $SOURCE_ROOT
        if [ -d "/opt/java" ]; then sudo rm -Rf /opt/java; fi

        if [[ $JAVA_PROVIDED =~ ^Temurin ]]; then
            sudo mkdir -p /opt/java/jdk
            curl -SL -o jdk.tar.gz "$(getJavaUrl $JAVA_PROVIDED jdk)"
            sudo tar -zxf jdk.tar.gz -C /opt/java/jdk --strip-components 1
	    sudo update-alternatives --install "/usr/bin/java" "java" "/opt/java/jdk/bin/java" 40
	    sudo update-alternatives --install "/usr/bin/javac" "javac" "/opt/java/jdk/bin/javac" 40
	    sudo update-alternatives --set java "/opt/java/jdk/bin/java"
	    sudo update-alternatives --set javac "/opt/java/jdk/bin/javac"
            export ES_JAVA_HOME=/opt/java/jdk
        elif [[ $JAVA_PROVIDED =~ ^OpenJDK ]]; then
            sudo mkdir -p /opt/java/
            if [[ $ID == "ubuntu" ]]; then
	        sudo apt-get install -y openjdk-${jver}-jdk
	        export ES_JAVA_HOME=/usr/lib/jvm/java-${jver}-openjdk-s390x
            elif [[  $ID == "rhel" ]]; then
    	        sudo yum install -y java-${jver}-openjdk-devel
	        export ES_JAVA_HOME=/usr/lib/jvm/java-${jver}-openjdk
            elif [[  $ID == "sles" ]]; then
    	        sudo zypper install -y java-${jver}-openjdk java-${jver}-openjdk-devel
	        export ES_JAVA_HOME=/usr/lib64/jvm/java-${jver}-openjdk-${jver}
            else
                printf "%s is not supported for installing Java" "$ID"
                exit 1
            fi
            sudo ln -s "$ES_JAVA_HOME" /opt/java/jdk
        else
            printf "%s is not supported, Please use valid java from {Temurin17, OpenJDK17} only\n" "$JAVA_PROVIDED"
            exit 1
        fi
}

function configureAndInstall() {
        printf -- '\nConfiguration and Installation started \n'
        # Install Java
        local jver=17
        if [[ $JAVA_PROVIDED =~ 21$ ]]; then
            jver=21
        fi
        installJava "$jver"

        export LANG="en_US.UTF-8"
        export JAVA_HOME=$ES_JAVA_HOME
        printf -- "export LANG="en_US.UTF-8"\n" >> "$BUILD_ENV"
        printf -- "export ES_JAVA_HOME=$ES_JAVA_HOME\n" >> "$BUILD_ENV"
        printf -- "export JAVA_HOME=$JAVA_HOME\n" >> "$BUILD_ENV"

        export PATH=$ES_JAVA_HOME/bin:$PATH
        printf -- "export PATH=$PATH\n" >> "$BUILD_ENV"
        java -version
        printf -- "Installation of %s is successful\n" "$JAVA_PROVIDED"

        #Build JANSI v2.4.0
        cd $CURDIR
        git clone -b jansi-2.4.0 https://github.com/fusesource/jansi.git
        cd jansi
        make clean-native native OS_NAME=Linux OS_ARCH=s390x

        mkdir -p $CURDIR/jansi-jar
        cd $CURDIR/jansi-jar
        wget https://repo1.maven.org/maven2/org/fusesource/jansi/jansi/2.4.0/jansi-2.4.0.jar
        jar xvf jansi-2.4.0.jar
        cd org/fusesource/jansi/internal/native/Linux
        mkdir s390x
        cp $CURDIR/jansi/target/native-Linux-s390x/libjansi.so s390x/
        cd $CURDIR/jansi-jar
        jar cvf jansi-2.4.0.jar .

        mkdir -p $CURDIR/.gradle/caches/modules-2/files-2.1/org.fusesource.jansi/jansi/2.4.0/321c614f85f1dea6bb08c1817c60d53b7f3552fd/
        cp jansi-2.4.0.jar $CURDIR/.gradle/caches/modules-2/files-2.1/org.fusesource.jansi/jansi/2.4.0/321c614f85f1dea6bb08c1817c60d53b7f3552fd/
        sha256=$(sha256sum jansi-2.4.0.jar | awk '{print $1}')

        # Build images for osixia/openldap needed by x-pack/test/idp-fixture/docker-compose.yml
        cd $CURDIR
        git clone -b v1.2.0 https://github.com/osixia/docker-light-baseimage.git
        cd docker-light-baseimage/
        curl -sSL "${PATCH_URL}/docker-light-baseimage.patch" | git apply -
        make build
        cd $CURDIR
        git clone -b v1.4.0 https://github.com/osixia/docker-openldap.git
        cd docker-openldap/
        curl -sSL "${PATCH_URL}/docker-openldap.patch" | git apply -
        make build

        cd $CURDIR
        ZSTD_VERSION=1.5.5
        wget https://github.com/facebook/zstd/archive/refs/tags/v$ZSTD_VERSION.tar.gz
        tar -xzvf v$ZSTD_VERSION.tar.gz
        cd zstd-$ZSTD_VERSION
        make DESTDIR=$(pwd)/_build install
        
        cd $CURDIR
        # Download and configure ElasticSearch
        printf -- 'Downloading Elasticsearch. Please wait.\n'
        git clone -b v$PACKAGE_VERSION $ES_REPO_URL
        cd $CURDIR/elasticsearch

        # get the latest tag version and replace it in x-pack/plugin/ml/build.gradle to avoid build issue
        git fetch --tags
        latest_tag=$(git tag | sort -V | tail -n1)
        latest_tag="${latest_tag:1}-SNAPSHOT"

        echo $latest_tag
        sed -i 's|${project.version}|'"${latest_tag}"'|g' ${CURDIR}/elasticsearch/x-pack/plugin/ml/build.gradle

        # Apply patch
        curl -sSL "${PATCH_URL}/elasticsearch.patch" | git apply -
        
        mkdir -p $CURDIR/elasticsearch/libs/
        cp -r $CURDIR/zstd-$ZSTD_VERSION/_build/usr/local/lib/ $CURDIR/elasticsearch/libs/zstd/
        export LD_LIBRARY_PATH=$CURDIR/elasticsearch/libs/zstd/${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
        sudo ldconfig

        mkdir -p $CURDIR/elasticsearch/distribution/packages/s390x-rpm/
        echo '
                // This file is intentionally blank. All configuration of the
                // export is done in the parent project.
             ' | tee $CURDIR/elasticsearch/distribution/packages/s390x-rpm/build.gradle
        mkdir -p $CURDIR/elasticsearch/distribution/packages/s390x-deb/
        echo '
                // This file is intentionally blank. All configuration of the
                // export is done in the parent project.
             ' | tee $CURDIR/elasticsearch/distribution/packages/s390x-deb/build.gradle
        mkdir -p $CURDIR/elasticsearch/distribution/archives/linux-s390x-tar/
        echo '
                // This file is intentionally blank. All configuration of the
                // export is done in the parent project.
             ' | tee $CURDIR/elasticsearch/distribution/archives/linux-s390x-tar/build.gradle

        mkdir -p $CURDIR/elasticsearch/distribution/docker/ubi-docker-s390x-export/
        echo '
                // This file is intentionally blank. All configuration of the
                // export is done in the parent project.
             ' | tee $CURDIR/elasticsearch/distribution/docker/ubi-docker-s390x-export/build.gradle
        mkdir -p $CURDIR/elasticsearch/distribution/docker/cloud-docker-s390x-export/
        echo '
                // This file is intentionally blank. All configuration of the
                // export is done in the parent project.
             ' | tee $CURDIR/elasticsearch/distribution/docker/cloud-docker-s390x-export/build.gradle
        mkdir -p $CURDIR/elasticsearch/distribution/docker/cloud-ess-docker-s390x-export/
        echo '
                // This file is intentionally blank. All configuration of the
                // export is done in the parent project.
             ' | tee $CURDIR/elasticsearch/distribution/docker/cloud-ess-docker-s390x-export/build.gradle
        mkdir -p $CURDIR/elasticsearch/distribution/docker/docker-s390x-export/
        echo '
                // This file is intentionally blank. All configuration of the
                // export is done in the parent project.
             ' | tee $CURDIR/elasticsearch/distribution/docker/docker-s390x-export/build.gradle
        mkdir -p $CURDIR/elasticsearch/distribution/docker/ironbank-docker-s390x-export/
        echo '
                // This file is intentionally blank. All configuration of the
                // export is done in the parent project.
             ' | tee $CURDIR/elasticsearch/distribution/docker/ironbank-docker-s390x-export/build.gradle
        sed -i 's|6cd91991323dd7b2fb28ca93d7ac12af5a86a2f53279e2b35827b30313fd0b9f|'"${sha256}"'|g' ${CURDIR}/elasticsearch/gradle/verification-metadata.xml

        # build image for :x-pack:qa:openldap-tests:test
        cd $CURDIR/elasticsearch/x-pack/test/idp-fixture/src/main/resources/openldap/
        docker build -f Dockerfile -t docker.elastic.co/elasticsearch-dev/openldap-fixture:1.0 .

        cd $CURDIR/elasticsearch 

        # Building Elasticsearch
        printf -- 'Building Elasticsearch \n'
        printf -- 'Build might take some time. Sit back and relax\n'
        export GRADLE_USER_HOME=$CURDIR/.gradle
        printf -- "export GRADLE_USER_HOME=$GRADLE_USER_HOME\n" >> "$BUILD_ENV"
       ./gradlew :distribution:archives:linux-s390x-tar:assemble --max-workers="$CPU_NUM"  --parallel

        # Verifying Elasticsearch installation
        if [[ $(grep -q "BUILD FAILED" "$LOG_FILE") ]]; then
                printf -- '\nBuild failed due to some unknown issues.\n'
                exit 1
        fi
        printf -- 'Built Elasticsearch successfully. \n\n'

        printf -- 'Creating distributions as deb, rpm and docker: \n\n'
        ./gradlew :distribution:packages:s390x-deb:assemble
        printf -- 'Created deb distribution. \n\n'
        ./gradlew :distribution:packages:s390x-rpm:assemble
        printf -- 'Created rpm distribution. \n\n'
        ./gradlew :distribution:docker:docker-s390x-export:assemble
        printf -- 'Created docker distribution. \n\n'

        printf -- "\n\nInstalling Elasticsearch\n"

        cd "${CURDIR}/elasticsearch"
        sudo mkdir /usr/share/elasticsearch
        sudo tar -xzf distribution/archives/linux-s390x-tar/build/distributions/elasticsearch-"${PACKAGE_VERSION}"-SNAPSHOT-linux-s390x.tar.gz -C /usr/share/elasticsearch --strip-components 1
        sudo ln -sf /usr/share/elasticsearch/bin/* /usr/bin/

        if ([[ -z "$(cut -d: -f1 /etc/group | grep elastic)" ]]); then
                printf -- '\nCreating group elastic.\n'
                sudo /usr/sbin/groupadd elastic # If group is not already created
        fi
        sudo chown "$NON_ROOT_USER:elastic" -R /usr/share/elasticsearch

        #update config to disable xpack.ml
        sudo echo 'xpack.ml.enabled: false' >> /usr/share/elasticsearch/config/elasticsearch.yml

        # Verifying Elasticsearch installation
        if command -v "$PACKAGE_NAME" >/dev/null; then
                printf -- "%s installation completed.\n" "$PACKAGE_NAME"
        else
                printf -- "Error while installing %s, exiting with 127 \n" "$PACKAGE_NAME"
                exit 127
        fi

        # Run tests
        runTest
}

function runTest() {
        if [[ "$TESTS" == "true" ]]; then
                export JAVA_TOOL_OPTIONS="-Dfile.encoding=UTF8"
                grep -q "JAVA_TOOL_OPTIONS" "$BUILD_ENV" || printf -- "export JAVA_TOOL_OPTIONS=$JAVA_TOOL_OPTIONS\n" >> "$BUILD_ENV"
                # Always set RUNTIME_JAVA_HOME=/opt/java/jdk to make sure that the tests use it when using the distro provided OpenJDK.
                # This works around a gradle problem where gradle does not recognize the distro provided OpenJDK.
                export RUNTIME_JAVA_HOME=/opt/java/jdk
                grep -q "RUNTIME_JAVA_HOME" "$BUILD_ENV" || printf -- "export RUNTIME_JAVA_HOME=$RUNTIME_JAVA_HOME\n" >> "$BUILD_ENV"

                cd "${CURDIR}/elasticsearch"
                set +e
                # Run Elasticsearch test suite
                printf -- '\n Running Elasticsearch test suite.\n'
                ./gradlew --continue test internalClusterTest -Dtests.haltonfailure=false -Dtests.jvm.argline="-Xss2m" |& tee -a ${CURDIR}/logs/test_results_${JAVA_PROVIDED}.log
                printf -- '*****************************************************************************************************\n'
                printf -- 'Some X-Pack test cases may fail as not all X-Pack plugins are not supported on s390x, such as Machine Learning features.\n\n'
                printf -- 'Certain test cases such as RuleQueryBuilderTests may require an individual rerun to pass.\nTests can be rerun with a command like:\n'
                printf -- '  ./gradlew :x-pack:plugin:ent-search:test -Dtests.jvm.argline="-Xss2m" --tests org.elasticsearch.xpack.application.rules.RuleQueryBuilderTests \n\n'
                printf -- "Note: Environment Variables needed for rerunning tests have been added to $HOME/setenv.sh\n"
                printf -- "      To set the Environment Variables needed to rerun tests, please run: source $HOME/setenv.sh \n"
                printf -- "Note: On RHEL 8 and SLES with OpenJDK, you may need to change the system crypto policy with a command like:\n"
                printf -- "        sudo update-crypto-policies --set LEGACY\n"
                printf -- "      in order for all security tests to pass.\n"
                printf -- "Note: On RHEL 9 with OpenJDK, some security tests will fail even with the LEGACY crypto policy.\n"
                printf -- '*****************************************************************************************************\n'
                set -e
        fi
}

function logDetails() {
        printf -- 'SYSTEM DETAILS\n' >"$LOG_FILE"
        if [ -f "/etc/os-release" ]; then
                cat "/etc/os-release" >>"$LOG_FILE"
        fi

        cat /proc/version >>"$LOG_FILE"
        printf -- "\nDetected %s \n" "$PRETTY_NAME"
        printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" |& tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
        echo
        echo "Usage: "
        echo "  bash build_elasticsearch.sh [-d debug] [-y install-without-confirmation] [-t install-with-tests] [-j Java to use from {Temurin17, OpenJDK17, Temurin21, OpenJDK21}]"
        echo "  default: If no -j specified, Temurin 17 will be installed"
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
                if command -v "$PACKAGE_NAME" >/dev/null; then
                        esversion=$(elasticsearch --version |& sed -En 's/Version:\s+([0-9.]+).*/\1/p')
                        printf -- "%s is detected with version %s .\n" "$PACKAGE_NAME" "$esversion" |& tee -a "$LOG_FILE"
                        source $HOME/setenv.sh
                        runTest |& tee -a "$LOG_FILE"
                        exit 0
                fi
                ;;
        j)
                JAVA_PROVIDED="$OPTARG"
                if ! isValidJavaProvided "$JAVA_PROVIDED"; then
                        printf "%s is not supported, Please use valid java from {Temurin17, OpenJDK17, Temurin21, OpenJDK21} only" "$JAVA_PROVIDED"
                        printf -- "Please note OpenJDK17 is not available on RHEL 7.* and SLES 12SP5"
                        exit 1
                fi
                ;;
        esac
done

function printSummary() {
        printf -- '\n*****************************************************************************************************\n'
        printf -- "\n* Getting Started * \n"
        printf -- "Note: Environment Variables needed have been added to $HOME/setenv.sh\n"
        printf -- "      To set the Environment Variables needed for Elasticsearch, please run: source $HOME/setenv.sh \n"
        printf -- '\n\nStart Elasticsearch using the following command: elasticsearch '
        printf -- '\n*****************************************************************************************************\n'
}

logDetails
prepare

printf -- "Installing %s %s for %s and %s\n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" "$JAVA_PROVIDED" |& tee -a "$LOG_FILE"
printf -- "Installing dependencies... it may take some time.\n"

case "$DISTRO" in
"rhel-8.8" | "rhel-8.10" | "rhel-9.2" | "rhel-9.4" )
        sudo yum install -y curl git gzip tar wget patch make gcc gcc-c++ |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

"sles-12.5")
        sudo zypper install -y curl libnghttp2-devel git gzip tar wget patch make gcc gcc-c++ fontconfig dejavu-fonts | tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

"sles-15.5" | "sles-15.6")
        sudo zypper install -y curl git gzip tar wget patch make gcc gcc-c++ fontconfig dejavu-fonts | tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

"ubuntu-20.04" | "ubuntu-22.04" )
        sudo apt-get update
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y curl git gzip tar wget patch locales make gcc g++ |& tee -a "$LOG_FILE"
        sudo locale-gen en_US.UTF-8
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

*)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
        exit 1
        ;;
esac

cleanup
printSummary |& tee -a "$LOG_FILE"
