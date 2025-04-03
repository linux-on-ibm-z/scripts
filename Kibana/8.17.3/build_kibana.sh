#!/bin/bash
# ©  Copyright IBM Corporation 2025.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Kibana/8.17.3/build_kibana.sh
# Execute build script: bash build_kibana.sh    (provide -h for help)
#
set -e -o pipefail

PACKAGE_NAME="kibana"
PACKAGE_VERSION="8.17.3"
NODE_JS_VERSION="20.18.2"

FORCE=false
SOURCE_ROOT=$(pwd)
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Kibana/${PACKAGE_VERSION}/patch"
NON_ROOT_USER="$(whoami)"
ENV_VARS=$SOURCE_ROOT/setenv.sh

trap cleanup 1 2 ERR

# Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
   mkdir -p "$SOURCE_ROOT/logs/"
fi

source "/etc/os-release"

function prepare() {
        if command -v "sudo" > /dev/null; then
                printf -- 'Sudo : Yes\n' >> "$LOG_FILE"
        else
                printf -- 'Sudo : No \n' >> "$LOG_FILE"
                printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n'
                exit 1
        fi

        if [[ "$FORCE" == "true" ]]; then
                printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "${LOG_FILE}"
        else
                # Ask user for prerequisite installation
                printf -- "\nAs part of the installation , dependencies would be installed/upgraded, \n"
                while true; do
                        read -r -p "Do you want to continue (y/n) ? :  " yn
                        case $yn in
                        [Yy]*)
                                printf -- 'User responded with Yes. \n' >> "${LOG_FILE}"
                                break
                                ;;
                        [Nn]*) exit ;;
                        *) echo "Please provide confirmation to proceed." ;;
                        esac
                done
        fi
}

function cleanup() {
        sudo rm -rf "$SOURCE_ROOT/node-v${NODE_JS_VERSION}-linux-s390x.tar.xz"

        sudo rm -rf "$SOURCE_ROOT/bazel-5.1.1-dist.zip"

        printf -- 'Cleaned up the artifacts\n' >>"${LOG_FILE}"
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

function buildAndInstallBazel() {
        cd $SOURCE_ROOT
        mkdir bazel && cd bazel
        wget https://github.com/bazelbuild/bazel/releases/download/5.1.1/bazel-5.1.1-dist.zip
        mkdir -p dist/bazel && cd dist/bazel
        unzip -q ../../bazel-5.1.1-dist.zip
        chmod -R +w .
        curl -sSL https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Bazel/5.1.1/patch/dist-md5.patch | git apply
        local bazel_compiler_env=()
        [[ $ID == "ubuntu" || $ID == "sles" ]] && bazel_compiler_env=("CC=gcc-11" "CXX=g++-11")
        env EXTRA_BAZEL_ARGS="--tool_java_runtime_version=local_jdk" "${bazel_compiler_env[@]}" bash ./compile.sh

        cd $SOURCE_ROOT/bazel
        git clone --depth 1 -b 5.1.1 https://github.com/bazelbuild/bazel.git
        cd bazel
        curl -sSL https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Bazel/5.1.1/patch/bazel.patch | git apply
        cd $SOURCE_ROOT/bazel/bazel
        env "${bazel_compiler_env[@]}" $SOURCE_ROOT/bazel/dist/bazel/output/bazel build -c opt --stamp --embed_label "5.1.1" \
                //src:bazel //src:bazel_jdk_minimal //src:test_repos

        sudo cp bazel-bin/src/bazel /usr/local/bin/
        bazel --version
        cd $SOURCE_ROOT
}

function installNodeAndYarn() {
        cd $SOURCE_ROOT
        sudo mkdir -p /usr/local/lib/nodejs
        wget -q https://nodejs.org/dist/v${NODE_JS_VERSION}/node-v${NODE_JS_VERSION}-linux-s390x.tar.xz
        sudo tar xf node-v${NODE_JS_VERSION}-linux-s390x.tar.xz -C /usr/local/lib/nodejs
        export PATH=/usr/local/lib/nodejs/node-v${NODE_JS_VERSION}-linux-s390x/bin:$PATH
        echo "export PATH=$PATH" >> $ENV_VARS
        node -v

        sudo chmod ugo+w -R /usr/local/lib/nodejs/node-v${NODE_JS_VERSION}-linux-s390x
        npm install -g yarn
        yarn --version
        cd $SOURCE_ROOT
}

function configureAndInstall() {
        printf -- '\nConfiguration and Installation started.\n'

        printf -- 'Building and installing Bazel.\n'
        buildAndInstallBazel

        printf -- 'Downloading and installing Node.js and yarn.\n'
        installNodeAndYarn

        if [[ $DISTRO == "sles-"* ]]; then
                cd $SOURCE_ROOT
                git clone --depth 1 -b v1.1.0 https://github.com/google/brotli.git
                cd brotli
                mkdir out && cd out
                cmake -DCMAKE_BUILD_TYPE=Release .. #need cmake 3.15+
                sudo cmake --build . --config Release --target install
                export LD_LIBRARY_PATH=/usr/local/lib64:$LD_LIBRARY_PATH
                echo "export LD_LIBRARY_PATH=$LD_LIBRARY_PATH" >> $ENV_VARS
        fi

        export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
        echo "export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1" >> $ENV_VARS
        
        # Downloading and installing Kibana and apply patch
        printf -- '\nDownloading and installing Kibana.\n'
        cd $SOURCE_ROOT
        retry git clone --depth 1 -b v$PACKAGE_VERSION https://github.com/elastic/kibana.git
        cd kibana
        curl -sSL "${PATCH_URL}/kibana_patch.diff" | git apply
        
        # Bootstrap Kibana
        cd $SOURCE_ROOT/kibana
        yarn kbn bootstrap

        # Building Kibana
        cd $SOURCE_ROOT/kibana
        export NODE_OPTIONS="--max_old_space_size=4096"
        echo "export NODE_OPTIONS=$NODE_OPTIONS" >> $ENV_VARS
        node scripts/build --release --skip-os-packages

        # Installing Kibana
        sudo mkdir /usr/share/kibana/
        sudo tar -xzf target/kibana-"$PACKAGE_VERSION"-linux-s390x.tar.gz -C /usr/share/kibana --strip-components 1
        sudo ln -sf /usr/share/kibana/bin/* /usr/bin/

        if ! grep -q '^elastic:' /etc/group; then
                printf -- '\nCreating group elastic.\n'
                sudo /usr/sbin/groupadd elastic
        fi
        sudo chown "$NON_ROOT_USER:elastic" -R /usr/share/kibana

        cd /usr/share/kibana/

        printf -- 'Installed Kibana successfully.\n'

        #Run Tests
        runTest
        # Cleanup
        cleanup

        # Verify kibana installation
        if command -v "$PACKAGE_NAME" >/dev/null; then
                printf -- "%s installation completed. Please check the Usage to start the service.\n" "$PACKAGE_NAME"
        else
                printf -- "Error while installing %s, exiting with 127 \n" "$PACKAGE_NAME"
                exit 127
        fi
}

function runTest() {
        if [[ "$TESTS" != "true" ]]; then
                return
        fi

        set +e
        printf -- "TEST Flag is set, continue with running test \n"
        export NODE_OPTIONS="--max-old-space-size=4096"
        export TEST_BROWSER_HEADLESS=1
        export DISABLE_BOOTSTRAP_VALIDATION=true
        export BROWSERSLIST_IGNORE_OLD_DATA=true

        cd $SOURCE_ROOT/kibana
        curl -sSL "${PATCH_URL}/unittest.sh" > unittest.sh
        bash unittest.sh
        
        curl -sSL "${PATCH_URL}/integrationtest.sh" > integrationtest.sh
        bash integrationtest.sh

        # In this version of kibana all functional tests require an elasticsearch
        # tar.gz distribution that is not available for s390x so skip running these
        # tests.
        # curl -sSL "${PATCH_URL}/functionaltest.sh" > functionaltest.sh
        # bash functionaltest.sh

        printf -- '**********************************************************************************************************\n'
        printf -- '\nCompleted test execution !! Test case failures can be ignored as they are seen on x86 also \n'
        printf -- '\nSome test case failures will pass when rerun the tests \n'
        printf -- '\nPlease refer to the building instructions for the complete set of expected failures.\n'
        printf -- '**********************************************************************************************************\n'

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
        echo "bash build_kibana.sh  [-d debug] [-y install-without-confirmation] [-t test]"
        echo
}

while getopts "h?dyt" opt; do
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
        esac
done

function gettingStarted() {
        printf -- '\n*********************************************************************************************\n'
        printf -- "Getting Started:\n\n"
        printf -- "Kibana requires an Elasticsearch instance to be running. \n"
        printf -- "Set Kibana home directory:\n"
        printf -- "     export KIBANA_HOME=/usr/share/kibana\n"
        printf -- "Update the Kibana configuration file \$KIBANA_HOME/config/kibana.yml accordingly.\n"
        printf -- "Start Kibana: \n"
        printf -- "     kibana & \n\n"
        printf -- "Access the Kibana UI using the below link: "
        printf -- "https://<Host-IP>:<Port>/    [Default Port = 5601] \n"
        printf -- '*********************************************************************************************\n'
        printf -- '\n'
}

###############################################################################################################

logDetails
prepare

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-22.04" | "ubuntu-24.04" )
        printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo apt-get update
        sudo apt-get install -y curl git g++-11 gzip make python3 python-is-python3 openjdk-11-jdk unzip zip tar wget patch xz-utils \
            build-essential pkg-config libglib2.0-dev libexpat1-dev meson ninja-build brotli libgirepository1.0-dev |& tee -a "${LOG_FILE}"
        gcc --version |& tee -a "${LOG_FILE}"
        export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x
        export PATH=$JAVA_HOME/bin:$PATH
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"rhel-8.8" | "rhel-8.10" | "rhel-9.2" | "rhel-9.4" | "rhel-9.5")
        printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo yum install -y --allowerasing curl git gcc-c++ gzip make python3 java-11-openjdk-devel unzip zip tar wget patch xz pkg-config expat-devel glib2-devel meson ninja-build brotli gobject-introspection-devel \
            coreutils ed expect file gnupg2 iproute iproute-devel iputils less openssl-devel python3-devel python3-pip python3-requests python3-setuptools python3-six python3-wheel python3-pyyaml zlib-devel |& tee -a "${LOG_FILE}"
        gcc --version |& tee -a "${LOG_FILE}"
        export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
        export PATH=$JAVA_HOME/bin:$PATH
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"sles-15.6")
        printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo zypper addrepo --priority 199 http://download.opensuse.org/distribution/leap/15.6/repo/oss/ oss
        sudo zypper --gpg-auto-import-keys refresh -r oss
        sudo zypper install -y curl git gcc-c++ gcc11-c++ gzip make python3 java-11-openjdk-devel unzip zip tar wget patch xz which gawk pkg-config glib2-devel libexpat-devel cmake meson ninja gobject-introspection-devel \
                coreutils ed expect file iproute2 iputils lcov less libopenssl-devel python3-devel python3-pip python3-requests python3-setuptools python3-six python3-wheel unzip zlib-devel python3-python-gnupg python3-PyYAML |& tee -a "${LOG_FILE}"
        gcc --version |& tee -a "${LOG_FILE}"
        export JAVA_HOME=/usr/lib64/jvm/java-11-openjdk
        export PATH=$JAVA_HOME/bin:$PATH
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;
*)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "${LOG_FILE}"
        exit 1
        ;;
esac

cleanup
gettingStarted |& tee -a "${LOG_FILE}"
