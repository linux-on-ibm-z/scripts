#!/bin/bash
# ©  Copyright IBM Corporation 2023.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Elasticsearch/7.17.7/build_elasticsearch.sh
# Execute build script: bash build_elasticsearch.sh    (provide -h for help)
#
set -e -o pipefail

PACKAGE_NAME="elasticsearch"
PACKAGE_VERSION="7.17.7"
CURATOR_VERSION="5.8.4"
CURDIR="$(pwd)"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Elasticsearch/${PACKAGE_VERSION}/patch/elasticsearch.patch"
TEMURIN_URL="https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.5%2B8/OpenJDK17U-jdk_s390x_linux_hotspot_17.0.5_8.tar.gz"
ES_REPO_URL="https://github.com/elastic/elasticsearch"
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

        cd "${CURDIR}"
        # Download and configure ElasticSearch
        printf -- 'Downloading Elasticsearch. Please wait.\n'
        git clone $ES_REPO_URL
        cd "${CURDIR}/elasticsearch"
        git checkout v$PACKAGE_VERSION

        # Apply patch
        printf -- 'Apply patch\n'
        curl -o  elasticsearch.patch $PATCH_URL
        git apply elasticsearch.patch

        # Building Elasticsearch
        printf -- 'Building Elasticsearch \n'
        printf -- 'Build might take some time. Sit back and relax\n'
        ./gradlew :distribution:archives:oss-linux-s390x-tar:assemble --max-workers="$CPU_NUM"  --parallel

        # Verifying Elasticsearch installation
        if [[ $(grep -q "BUILD FAILED" "$LOG_FILE") ]]; then
                printf -- '\nBuild failed due to some unknown issues.\n'
                exit 1
        fi
        printf -- 'Built Elasticsearch successfully. \n\n'

        printf -- 'Creating distributions as deb, rpm and docker: \n\n'
                ./gradlew :distribution:packages:s390x-oss-deb:assemble
        printf -- 'Created deb distribution. \n\n'
                ./gradlew :distribution:packages:s390x-oss-rpm:assemble
        printf -- 'Created rpm distribution. \n\n'
                ./gradlew :distribution:docker:oss-docker-s390x-build-context:assemble
        printf -- 'Created docker distribution. \n\n'
        
        printf -- "\n\nInstalling Elasticsearch\n"

        cd "${CURDIR}/elasticsearch"
        sudo mkdir /usr/share/elasticsearch
        sudo tar -xzf distribution/archives/oss-linux-s390x-tar/build/distributions/elasticsearch-oss-"${PACKAGE_VERSION}"-SNAPSHOT-linux-s390x.tar.gz -C /usr/share/elasticsearch --strip-components 1
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
    # Setting environment variable needed for testing
        export JAVA_TOOL_OPTIONS="-Dfile.encoding=UTF8"
        source $HOME/setenv.sh
        export RUNTIME_JAVA_HOME=$ES_JAVA_HOME
        export JAVA17_HOME=$RUNTIME_JAVA_HOME

        cd "${CURDIR}/elasticsearch"
        set +e
        # Run Elasticsearch test suite
        printf -- '\n Running Elasticsearch test suite.\n'
        ./gradlew --continue test -Dtests.haltonfailure=false -Dtests.jvm.argline="-Xss2m" |& tee -a ${CURDIR}/logs/test_results_$(date +"%F-%T").log
        printf -- '***********************************************************************************************************************************'
        printf -- '\n Some X-Pack test cases will fail as X-Pack plugins are not supported on s390x, such as Machine Learning features.\n'
        printf -- '\n Certain test cases may require an individual rerun to pass. There may be false negatives due to seccomp not supporting s390x properly.\n'
        printf -- '***********************************************************************************************************************************\n'
        set -e
}

function installClient() {
        printf -- '\nInstalling Elasticsearch Curator client\n'

        if [[ "${ID}" == "ubuntu" ]]; then
            sudo apt-get update
            sudo apt-get install -y python3-pip libyaml-dev
            sudo pip3 install elasticsearch==$PACKAGE_VERSION
            sudo pip3 install elasticsearch-curator==${CURATOR_VERSION}
        elif [[ "${ID}" == "rhel" ]]; then
            sudo yum install -y python3-devel libyaml-devel
            sudo pip3 install elasticsearch==$PACKAGE_VERSION
            sudo pip3 install elasticsearch-curator==${CURATOR_VERSION}
        elif [[ "${ID}" == "sles" ]]; then
            if [[ "${DISTRO}" == "sles-15.4" ]]; then
                sudo zypper install -y python3-devel python3-pip libyaml-devel glibc-locale-base
                sudo pip3 install elasticsearch==$PACKAGE_VERSION
                sudo pip3 install elasticsearch-curator==${CURATOR_VERSION}
                printf -- "export LC_CTYPE="en_US.UTF-8"\n" >> "$BUILD_ENV"
                export LC_CTYPE="en_US.UTF-8"
            else
                sudo zypper install -y libyaml-devel
                # Installing Python 3.11.1 for SLES 12 SP5
                cd "${CURDIR}"
                wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Python3/3.11.1/build_python3.sh
                bash build_python3.sh -y
                rm -f build_python3.sh
                sudo -H env PATH=$PATH pip3 install elasticsearch==$PACKAGE_VERSION
                sudo -H env PATH=$PATH pip3 install elasticsearch-curator==${CURATOR_VERSION}
            fi
        else
            printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
        fi

        # Verifying Elasticsearch installation
        if command -v curator >/dev/null; then
                printf -- "\nInstalled Elasticsearch Curator client successfully\n"
        else
                printf -- "\nError occured in installation of Curator client\n"
                exit 127
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
        echo "  bash  build_elasticsearch.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests] [-j Java to use from {Temurin17, OpenJDK17}]"
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
        printf -- '\n\nFor more information on curator client visit: \nhttps://www.elastic.co/guide/en/elasticsearch/client/curator/current/index.html \n\n'
        printf -- '***********************************************************************************************************************************\n'
}

logDetails
prepare

case "$DISTRO" in
"ubuntu-18.04" | "ubuntu-20.04" | "ubuntu-22.04")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo apt-get update
        sudo apt-get install -y curl git gzip tar wget patch locales |& tee -a "$LOG_FILE"
        sudo locale-gen en_US.UTF-8
        configureAndInstall |& tee -a "$LOG_FILE"
        installClient |& tee -a "$LOG_FILE"
        ;;

"rhel-7.8" | "rhel-7.9" | "rhel-8.4" | "rhel-8.6" | "rhel-8.7" | "rhel-9.0" | "rhel-9.1")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo yum install -y curl git gzip tar wget patch |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        installClient |& tee -a "$LOG_FILE"
        ;;

"sles-12.5" | "sles-15.4")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo zypper install -y curl git gzip tar wget patch | tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        installClient |& tee -a "$LOG_FILE"
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
