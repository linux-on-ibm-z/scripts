#!/bin/bash
# © Copyright IBM Corporation 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Elasticsearch/7.10.0/build_elasticsearch.sh
# Execute build script: bash build_elasticsearch.sh    (provide -h for help)
#
set -e -o pipefail

PACKAGE_NAME="elasticsearch"
PACKAGE_VERSION="7.10.0"
CURDIR="$(pwd)"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Elasticsearch/${PACKAGE_VERSION}/patch"
ES_REPO_URL="https://github.com/elastic/elasticsearch"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
NON_ROOT_USER="$(whoami)"
JAVA_PROVIDED="OpenJDK11"
FORCE="false"
BUILD_ENV="$HOME/setenv.sh"

trap cleanup 0 1 2 ERR

# Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
        mkdir -p "$CURDIR/logs/"
fi

if [ -f "/etc/os-release" ]; then
        source "/etc/os-release"
fi

function prepare() {

        if command -v "sudo" >/dev/null; then
                printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
        else
                printf -- 'Sudo : No \n' >>"$LOG_FILE"
                printf -- 'You can install sudo from repository using apt, yum or zypper based on your distro. \n'
                exit 1
        fi

        if [[ "$JAVA_PROVIDED" != "AdoptJDK15_openj9" && "$JAVA_PROVIDED" != "AdoptJDK15_hotspot" && "$JAVA_PROVIDED" != "OpenJDK11" ]]; then
                printf "$JAVA_PROVIDED is not supported, Please use valid java from {AdoptJDK15_openj9, AdoptJDK15_hotspot, OpenJDK11} only"
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
        rm -rf "${CURDIR}/adoptjdk.tar.gz"
        printf -- '\nCleaned up the artifacts.\n' >>"$LOG_FILE"
}

function configureAndInstall() {
        printf -- '\nConfiguration and Installation started \n'
        echo "Java provided by user: $JAVA_PROVIDED" >> "$LOG_FILE"

    if [[ "$JAVA_PROVIDED" == "AdoptJDK15_openj9" ]]; then
        # Install AdoptOpenJDK 15 (With OpenJ9)
        cd "$CURDIR"
        sudo mkdir -p /opt/adopt/java

        curl -SL -o adoptjdk.tar.gz https://github.com/AdoptOpenJDK/openjdk15-binaries/releases/download/jdk-15.0.1%2B9_openj9-0.23.0/OpenJDK15U-jdk_s390x_linux_openj9_15.0.1_9_openj9-0.23.0.tar.gz
        # Everytime new jdk is downloaded, Ensure that --strip valueis correct
        sudo tar -zxvf adoptjdk.tar.gz -C /opt/adopt/java --strip-components 1

        export JAVA_HOME=/opt/adopt/java
        export JAVA15_HOME=/opt/adopt/java

        printf -- "export JAVA_HOME=/opt/adopt/java\n" >> "$BUILD_ENV"
        printf -- "Installation of AdoptOpenJDK 15 (With OpenJ9) is successful\n" >> "$LOG_FILE"

    elif [[ "$JAVA_PROVIDED" == "AdoptJDK15_hotspot" ]]; then
        # Install AdoptOpenJDK 15 (With Hotspot)
        cd "$CURDIR"
        sudo mkdir -p /opt/adopt/java

        curl -SL -o adoptjdk.tar.gz https://github.com/AdoptOpenJDK/openjdk15-binaries/releases/download/jdk-15.0.1%2B9/OpenJDK15U-jdk_s390x_linux_hotspot_15.0.1_9.tar.gz
        # Everytime new jdk is downloaded, Ensure that --strip valueis correct
        sudo tar -zxvf adoptjdk.tar.gz -C /opt/adopt/java --strip-components 1

        export JAVA_HOME=/opt/adopt/java
        export JAVA15_HOME=/opt/adopt/java

        printf -- "export JAVA_HOME=/opt/adopt/java\n" >> "$BUILD_ENV"
        printf -- "Installation of AdoptOpenJDK 15 (With Hotspot) is successful\n" >> "$LOG_FILE"

    elif [[ "$JAVA_PROVIDED" == "OpenJDK11" ]]; then
        if [[ "${ID}" == "ubuntu" ]]; then
                sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-11-jdk
                export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x
                export JAVA11_HOME=/usr/lib/jvm/java-11-openjdk-s390x
                printf -- "export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x\n" >> "$BUILD_ENV"
        elif [[ "${ID}" == "rhel" ]]; then
                sudo yum install -y java-11-openjdk java-11-openjdk-devel
                export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
                export JAVA11_HOME=/usr/lib/jvm/java-11-openjdk
                printf -- "export JAVA_HOME=/usr/lib/jvm/java-11-openjdk\n" >> "$BUILD_ENV"
        elif [[ "${ID}" == "sles" ]]; then
                sudo zypper install -y java-11-openjdk java-11-openjdk-devel
                export JAVA_HOME=/usr/lib64/jvm/java-11-openjdk
                export JAVA11_HOME=/usr/lib64/jvm/java-11-openjdk
                printf -- "export JAVA_HOME=/usr/lib64/jvm/java-11-openjdk\n" >> "$BUILD_ENV"
        fi
        printf -- "Installation of OpenJDK 11 is successful\n" >> "$LOG_FILE"
    else
        printf "$JAVA_PROVIDED is not supported, Please use valid java from {AdoptJDK15_openj9, AdoptJDK15_hotspot, OpenJDK11} only"
        exit 1
    fi

        export PATH=$JAVA_HOME/bin:$PATH
        printf -- "export PATH=$JAVA_HOME/bin:$PATH\n" >> "$BUILD_ENV"
        java -version |& tee -a "$LOG_FILE"

        cd "${CURDIR}"
        # Download and configure ElasticSearch
        printf -- 'Downloading Elasticsearch. Please wait.\n'
        git clone $ES_REPO_URL
        cd "${CURDIR}/elasticsearch"
        git checkout v$PACKAGE_VERSION

        # Download required files and apply patch
	wget $PATCH_URL/build.gradle -P ${CURDIR}/elasticsearch/distribution/archives/linux-s390x-tar
        wget $PATCH_URL/build.gradle -P ${CURDIR}/elasticsearch/distribution/archives/oss-linux-s390x-tar
        wget $PATCH_URL/build.gradle -P ${CURDIR}/elasticsearch/distribution/packages/s390x-deb
        wget $PATCH_URL/build.gradle -P ${CURDIR}/elasticsearch/distribution/packages/s390x-oss-deb
        wget $PATCH_URL/build.gradle -P ${CURDIR}/elasticsearch/distribution/packages/s390x-oss-rpm
        wget $PATCH_URL/build.gradle -P ${CURDIR}/elasticsearch/distribution/packages/s390x-rpm
        wget $PATCH_URL/build.gradle -P ${CURDIR}/elasticsearch/distribution/docker/docker-s390x-export
        wget $PATCH_URL/build.gradle -P ${CURDIR}/elasticsearch/distribution/docker/oss-docker-s390x-export
	
	wget $PATCH_URL/docker_build_context_build.gradle -P ${CURDIR}/elasticsearch/distribution/docker/docker-s390x-build-context
	mv ${CURDIR}/elasticsearch/distribution/docker/docker-s390x-build-context/docker_build_context_build.gradle ${CURDIR}/elasticsearch/distribution/docker/docker-s390x-build-context/build.gradle
	
	wget $PATCH_URL/oss_docker_build_context_build.gradle -P ${CURDIR}/elasticsearch/distribution/docker/oss-docker-s390x-build-context
        mv ${CURDIR}/elasticsearch/distribution/docker/oss-docker-s390x-build-context/oss_docker_build_context_build.gradle ${CURDIR}/elasticsearch/distribution/docker/oss-docker-s390x-build-context/build.gradle
        
        wget -O - $PATCH_URL/diff.patch | git apply
     
        # Building Elasticsearch
        printf -- 'Building Elasticsearch \n'
        printf -- 'Build might take some time. Sit back and relax\n'
        ./gradlew :distribution:archives:oss-linux-s390x-tar:assemble --parallel

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
        export RUNTIME_JAVA_HOME=$JAVA_HOME

        cd "${CURDIR}/elasticsearch"
        set +e
        # Run Elasticsearch test suite
        printf -- '\n Running Elasticsearch test suite.\n'
        ./gradlew --continue test -Dtests.haltonfailure=false -Dtests.jvm.argline="-Xss2m" |& tee -a ${CURDIR}/logs/test_results.log
	        printf -- '***********************************************************************************************************************************'
        printf -- '\n Some X-Pack test cases will fail as X-Pack plugins are not supported on s390x, such as Machine Learning features.\n'
	        printf -- '\n Certain test cases may require an individual rerun to pass. There may be false negatives due to seccomp not supporting s390x properly.\n'
        printf -- '***********************************************************************************************************************************\n'
        set -e
}

function installClient() {
        printf -- '\nInstalling Elasticsearch Curator client\n'
        if [[ "${ID}" == "sles" ]]; then
          sudo zypper install -y python3 python3-pip
        fi

        if [[ "${ID}" == "ubuntu" ]]; then
          sudo apt-get update
          sudo apt-get install -y python3-pip
        fi

        if [[ "${ID}" == "rhel" ]]; then
          sudo yum install -y python3-devel
	  sudo mkdir -p /usr/local/lib/python3.6
	  sudo ln -sf /usr/lib/python3.6/site-packages /usr/local/lib/python3.6/
        fi
        wget https://github.com/elastic/curator/archive/V5.8.3.tar.gz -O elasticsearch-curator.tar.gz
	tar -xzvf elasticsearch-curator.tar.gz
	rm -rf elasticsearch-curator.tar.gz
	cd curator-5.8.3/
	curl  -o requirements.patch $PATCH_URL/requirements.patch
	curl  -o setup.py.patch $PATCH_URL/setup.py.patch
	curl  -o setup.cfg.patch $PATCH_URL/setup.cfg.patch
	
	patch requirements.txt < requirements.patch
	patch setup.py < setup.py.patch
	patch setup.cfg < setup.cfg.patch
	sudo python3 setup.py install
 	cd ../	
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
        echo "  build_elasticsearch.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests] [-j Java to be used from {AdoptJDK15_openj9, AdoptJDK15_hotspot, OpenJDK11}]"
        echo "  default: If no -j specified, openjdk-11 will be installed"
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

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-18.04" | "ubuntu-20.04" )
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo apt-get update
        sudo apt-get install -y curl git gzip tar wget patch locales libyaml-dev |& tee -a "$LOG_FILE"
        sudo locale-gen en_US.UTF-8
        configureAndInstall |& tee -a "$LOG_FILE"
        installClient |& tee -a "$LOG_FILE"
        ;;

"rhel-7.8" | "rhel-7.9" | "rhel-8.1" | "rhel-8.2" | "rhel-8.3")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo yum install -y curl git gzip tar wget patch libyaml-devel |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        installClient |& tee -a "$LOG_FILE"
        ;;

"sles-12.5" | "sles-15.1" | "sles-15.2")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo zypper install -y curl git gzip tar wget patch libyaml-devel | tee -a "$LOG_FILE"
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
