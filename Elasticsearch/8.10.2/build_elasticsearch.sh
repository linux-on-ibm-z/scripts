#!/bin/bash
# ©  Copyright IBM Corporation 2023.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Elasticsearch/8.10.2/build_elasticsearch.sh
# Execute build script: bash build_elasticsearch.sh    (provide -h for help)
#
set -e -o pipefail

PACKAGE_NAME="elasticsearch"
PACKAGE_VERSION="8.10.2"
CURDIR="$(pwd)"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Elasticsearch/8.10.2/patch/elasticsearch.patch"
TEMURIN_URL="https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.7%2B7/OpenJDK17U-jdk_s390x_linux_hotspot_17.0.7_7.tar.gz"
ES_REPO_URL="https://github.com/elastic/elasticsearch"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
JAVA_PROVIDED="Temurin17"
NON_ROOT_USER="$(whoami)"
FORCE="false"
BUILD_ENV="$HOME/setenv.sh"
CPU_NUM="$(grep -c ^processor /proc/cpuinfo)"

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

        if [[ "$JAVA_PROVIDED" != "Temurin17" && "$JAVA_PROVIDED" != "OpenJDK17" ]]; then
                printf "$JAVA_PROVIDED is not supported.  Please use valid variant from {Temurin17, OpenJDK17} only.\n"
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
        printf -- '\nCleaned up the artifacts.\n' >>"$LOG_FILE"
}

function configureAndInstall() {
        printf -- '\nConfiguration and Installation started \n'
        # Install Java
        if [[ "$JAVA_PROVIDED" == "Temurin17" ]]; then
            printf -- "\nInstalling Temurin 17 . . . \n"
            cd "$CURDIR"
            sudo mkdir -p /opt/temurin/java
            curl -SL -o temurin.tar.gz $TEMURIN_URL
            # Everytime new jdk is downloaded, Ensure that --strip valueis correct
            sudo tar -zxf temurin.tar.gz -C /opt/temurin/java --strip-components 1
            export ES_JAVA_HOME=/opt/temurin/java
            printf -- "Installation of Temurin 17 is successful\n" >> "$LOG_FILE"
        elif [[ "$JAVA_PROVIDED" == "OpenJDK17" ]]; then
            printf -- "\nInstalling OpenJDK 17 . . . \n"
            if [[ "${ID}" == "ubuntu" ]]; then
                    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-17-jre openjdk-17-jdk ca-certificates-java
                    export ES_JAVA_HOME=/usr/lib/jvm/java-17-openjdk-s390x
            elif [[ "${ID}" == "rhel" ]]; then
                if [[ "${DISTRO}" == "rhel-7."* ]]; then
                    printf "$JAVA_PROVIDED is not available on RHEL 7.  Please use valid variant Temurin17.\n"
                    exit 1
                else
                    sudo yum install -y java-17-openjdk-devel
                    export ES_JAVA_HOME=/usr/lib/jvm/java-17-openjdk
                fi
            elif [[ "${ID}" == "sles" ]]; then
                if [[ "${DISTRO}" == "sles-12.5" ]]; then
                    printf "$JAVA_PROVIDED is not available on SLES 12 SP5.  Please use valid variant Temurin17.\n"
                    exit 1
                else
                    sudo zypper install -y java-17-openjdk java-17-openjdk-devel
                    export ES_JAVA_HOME=/usr/lib64/jvm/java-17-openjdk
                fi
            fi
            printf -- "Installation of OpenJDK 17 is successful\n" >> "$LOG_FILE"
        else
            printf "$JAVA_PROVIDED is not supported.  Please use valid variant from {Temurin17, OpenJDK17} only.\n"
            exit 1
        fi

        export LANG="en_US.UTF-8"
        export JAVA_HOME=$ES_JAVA_HOME
        export JAVA17_HOME=$ES_JAVA_HOME
        printf -- "export LANG="en_US.UTF-8"\n" >> "$BUILD_ENV"
        printf -- "export ES_JAVA_HOME=$ES_JAVA_HOME\n" >> "$BUILD_ENV"
        printf -- "export JAVA_HOME=$JAVA_HOME\n" >> "$BUILD_ENV"

        export PATH=$ES_JAVA_HOME/bin:$PATH
        printf -- "export PATH=$PATH\n" >> "$BUILD_ENV"
        java -version |& tee -a "$LOG_FILE"

        #Build JANSI v2.4.0
        cd $CURDIR
        git clone https://github.com/fusesource/jansi.git
        cd jansi
        git checkout jansi-2.4.0
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
        export sha256=$(sha256sum jansi-2.4.0.jar | awk '{print $1}')

        cd $CURDIR
        # Download and configure ElasticSearch
        printf -- 'Downloading Elasticsearch. Please wait.\n'
        git clone $ES_REPO_URL
        cd $CURDIR/elasticsearch
        git checkout v$PACKAGE_VERSION

        # Apply patch
        curl -o  elasticsearch.patch $PATCH_URL
        git apply --ignore-whitespace elasticsearch.patch
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

        # Building Elasticsearch
        printf -- 'Building Elasticsearch \n'
        printf -- 'Build might take some time. Sit back and relax\n'
        export GRADLE_USER_HOME=$CURDIR/.gradle
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
}

function runTest() {
    # Setting environment variable needed for testing --max-workers=2
        export JAVA_TOOL_OPTIONS="-Dfile.encoding=UTF8"
        source $HOME/setenv.sh
        export RUNTIME_JAVA_HOME=$ES_JAVA_HOME

        cd "${CURDIR}/elasticsearch"
        set +e
        # Run Elasticsearch test suite
        printf -- '\n Running Elasticsearch test suite.\n'
        ./gradlew --continue test -Dtests.haltonfailure=false -Dtests.jvm.argline="-Xss2m" |& tee -a ${CURDIR}/logs/test_results.log
        printf -- '***********************************************************************************************************************************'
        printf -- '\n Some X-Pack test cases will fail as X-Pack plugins are not supported on s390x, such as Machine Learning features.\n'
        printf -- '\n Certain test cases may require an individual rerun to pass.\n'
        printf -- '***********************************************************************************************************************************\n'
        set -e
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
        echo "  bash build_elasticsearch.sh [-d debug] [-y install-without-confirmation] [-t install-with-tests] [-j Java to use from {Temurin17, OpenJDK17}]"
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
                if command -v "$PACKAGE_NAME" >/dev/null; then
                        TESTS="true"
                        printf -- "%s is detected with version %s .\n" "$PACKAGE_NAME" "$PACKAGE_VERSION" |& tee -a "$LOG_FILE"
                        runTest |& tee -a "$LOG_FILE"
                        exit 0

                else
                        TESTS="true"
                fi
                ;;
        j)
                JAVA_PROVIDED="$OPTARG"
                ;;
        esac
done

function printSummary() {
        printf -- '\n***********************************************************************************************************************************\n'
        printf -- "\n* Getting Started * \n"
        printf -- "Note: Environment Variables needed have been added to $HOME/setenv.sh\n"
        printf -- "Note: To set the Environment Variables needed for Elasticsearch, please run: source $HOME/setenv.sh \n"
        printf -- '\n\nStart Elasticsearch using the following command: elasticsearch '
        printf -- '***********************************************************************************************************************************\n'
}

logDetails
prepare

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-20.04" | "ubuntu-22.04")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo apt-get update
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y curl git gzip tar wget patch locales make gcc g++ |& tee -a "$LOG_FILE"
        sudo locale-gen en_US.UTF-8
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

"rhel-7.8" | "rhel-7.9")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo yum install -y curl git gzip tar wget patch make gcc gcc-c++ rh-git227-git.s390x |& tee -a "$LOG_FILE"
        source /opt/rh/rh-git227/enable
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

"rhel-8.6" | "rhel-8.8" | "rhel-9.0" | "rhel-9.2")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo yum install -y curl git gzip tar wget patch make gcc gcc-c++ |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

"sles-12.5")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo zypper install -y curl libnghttp2-devel git gzip tar wget patch make gcc gcc-c++ | tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

"sles-15.4" | "sles-15.5")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo zypper install -y curl git gzip tar wget patch make gcc gcc-c++ | tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

*)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
        exit 1
        ;;
esac

# Run tests
if [[ "$TESTS" == "true" ]]; then
        runTest |& tee -a "$LOG_FILE"
fi

cleanup
printSummary |& tee -a "$LOG_FILE"
