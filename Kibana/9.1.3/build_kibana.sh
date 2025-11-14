#!/bin/bash
# ©  Copyright IBM Corporation 2025.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Kibana/9.1.3/build_kibana.sh
# Execute build script: bash build_kibana.sh    (provide -h for help)
#
set -e -o pipefail

PACKAGE_NAME="kibana"
PACKAGE_VERSION="9.1.3"
NODE_JS_VERSION="22.17.1"

FORCE=false
SOURCE_ROOT=$(pwd)
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Kibana/${PACKAGE_VERSION}/patch"
NON_ROOT_USER="$(whoami)"
ENV_VARS=$SOURCE_ROOT/setenv.sh
ES_BUILD_SCRIPT_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Elasticsearch/${PACKAGE_VERSION}/build_elasticsearch.sh"
ES_DIST="$SOURCE_ROOT/elasticsearch/elasticsearch/distribution/archives/linux-s390x-tar/build/distributions/elasticsearch-${PACKAGE_VERSION}-SNAPSHOT-linux-s390x.tar.gz"
HAVE_ES_DIST="false"
HAVE_FIREFOX="false"

trap cleanup 1 2 ERR

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

    if [[ "$FORCE" == "true" ]]; then
        printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "${LOG_FILE}"
    else
        # Ask user for prerequisite installation
        printf -- "\nAs part of the installation , dependencies would be installed/upgraded, \n"
        while true; do
            read -r -p "Do you want to continue (y/n) ? :  " yn
            case $yn in
            [Yy]*)
                printf -- 'User responded with Yes. \n' >>"${LOG_FILE}"
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

function installNodeAndYarn() {
    cd $SOURCE_ROOT
    sudo mkdir -p /usr/local/lib/nodejs
    wget -q https://nodejs.org/dist/v${NODE_JS_VERSION}/node-v${NODE_JS_VERSION}-linux-s390x.tar.xz
    sudo tar xf node-v${NODE_JS_VERSION}-linux-s390x.tar.xz -C /usr/local/lib/nodejs
    export PATH=/usr/local/lib/nodejs/node-v${NODE_JS_VERSION}-linux-s390x/bin:$PATH
    echo "export PATH=$PATH" >>$ENV_VARS
    node -v

    sudo chmod ugo+w -R /usr/local/lib/nodejs/node-v${NODE_JS_VERSION}-linux-s390x
    npm install -g yarn
    yarn --version
    cd $SOURCE_ROOT
}

function configureAndInstall() {
    printf -- '\nConfiguration and Installation started.\n'

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
        echo "export LD_LIBRARY_PATH=$LD_LIBRARY_PATH" >>$ENV_VARS
    fi

    export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
    echo "export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1" >>$ENV_VARS

    # Downloading and installing Kibana and apply patch
    printf -- '\nDownloading and installing Kibana.\n'
    cd $SOURCE_ROOT
    retry git clone --depth 1 -b v$PACKAGE_VERSION https://github.com/elastic/kibana.git
    cd kibana
    curl -sSL "${PATCH_URL}/kibana_patch.diff" | git apply

    # Bootstrap Kibana
    cd $SOURCE_ROOT/kibana
    yarn kbn bootstrap --network-timeout 1000000

    # Building Kibana
    cd $SOURCE_ROOT/kibana
    export NODE_OPTIONS="--max_old_space_size=4096"
    echo "export NODE_OPTIONS=$NODE_OPTIONS" >>$ENV_VARS
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

function buildElasticsearchTar() {
    printf -- "Building elasticsearch distribution\n"
    mkdir -p "$SOURCE_ROOT/elasticsearch"
    cd "$SOURCE_ROOT/elasticsearch"
    curl -sSL "${ES_BUILD_SCRIPT_URL}" >build_elasticsearch.sh
    sed -i '48,77d;201,211d;247,258d' ./build_elasticsearch.sh
    bash ./build_elasticsearch.sh -y -k
    if [[ -f "$ES_DIST" ]]; then
        HAVE_ES_DIST="true"
        printf -- "Successfully build elasticsearch tar distribution for testing.\n"
    else
        printf -- "Did not build elasticsearch tar distribution for testing. Tests that depend on it will fail.\n"
    fi
    cd "$SOURCE_ROOT"
}

function buildAndInstallParcelWatcher() {
    printf -- "Building and installing selenium support\n"
    cd $SOURCE_ROOT
    git clone --depth 1 -b v2.5.1 https://github.com/parcel-bundler/watcher.git
    cd watcher
    yarn --frozen-lockfile --ignore-scripts
    npm install node-gyp -g
    yarn prebuild --arch s390x -t 22.0.0
    mkdir -p "${SOURCE_ROOT}/kibana/node_modules/@parcel/watcher-linux-s390x-glibc/"
    cp build/Release/obj.target/watcher.node "${SOURCE_ROOT}/kibana/node_modules/@parcel/watcher-linux-s390x-glibc/"
    cat << "EOF" > "${SOURCE_ROOT}/kibana/node_modules/@parcel/watcher-linux-s390x-glibc/package.json"
{
  "name": "@parcel/watcher-linux-s390x-glibc",
  "version": "2.5.1",
  "main": "watcher.node",
  "repository": {
    "type": "git",
    "url": "https://github.com/parcel-bundler/watcher.git"
  },
  "description": "A native C++ Node module for querying and subscribing to filesystem events. Used by Parcel 2.",
  "license": "MIT",
  "publishConfig": {
    "access": "public"
  },
  "funding": {
    "type": "opencollective",
    "url": "https://opencollective.com/parcel"
  },
  "files": [
    "watcher.node"
  ],
  "engines": {
    "node": ">= 10.0.0"
  },
  "os": [
    "linux"
  ],
  "cpu": [
    "s390x"
  ],
  "libc": [
    "glibc"
  ]
}
EOF
    cd $SOURCE_ROOT
}

function buildAndInstallSelenium() {
    if [[ "$ID" == "rhel" ]]; then
        sudo dnf install -y firefox
        sudo dnf -y groupinstall 'Development Tools'
    fi

    printf -- "Building and installing selenium support\n"
    mkdir -p "$SOURCE_ROOT/selenium"
    cd "$SOURCE_ROOT/selenium"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh /dev/stdin -y
    source "$HOME/.cargo/env"
    git clone --depth=1 -b FIREFOX_128_14_0esr_RELEASE https://github.com/mozilla-firefox/firefox.git
    cd firefox/testing/geckodriver/
    cargo build
    ../../target/debug/geckodriver --version
    sudo cp ../../target/debug/geckodriver /usr/local/bin/

    cd "$SOURCE_ROOT/selenium"
    git clone --depth=1 -b selenium-4.34.0 https://github.com/SeleniumHQ/selenium.git
    cd selenium/rust
    cargo build
    ./target/debug/selenium-manager --version
    cp ./target/debug/selenium-manager "$SOURCE_ROOT"/kibana/node_modules/selenium-webdriver/bin/linux/selenium-manager

    cd "$SOURCE_ROOT"
}

function runTest() {
    if [[ "$TESTS" != "true" ]]; then
        return
    fi

    cd "$SOURCE_ROOT"
    buildElasticsearchTar
    buildAndInstallParcelWatcher
    if [[ $HAVE_FIREFOX == "true" ]]; then
        buildAndInstallSelenium
    fi

    set +e
    printf -- "TEST Flag is set, continue with running test \n"
    export NODE_OPTIONS="--max-old-space-size=4096"
    export TEST_BROWSER_HEADLESS=1
    echo "export TEST_BROWSER_HEADLESS=$TEST_BROWSER_HEADLESS" >>$ENV_VARS
    export DISABLE_BOOTSTRAP_VALIDATION=true
    echo "export DISABLE_BOOTSTRAP_VALIDATION=$DISABLE_BOOTSTRAP_VALIDATION" >>$ENV_VARS
    export BROWSERSLIST_IGNORE_OLD_DATA=true
    echo "export BROWSERSLIST_IGNORE_OLD_DATA=$BROWSERSLIST_IGNORE_OLD_DATA" >>$ENV_VARS
    if [[ $HAVE_ES_DIST == "true" ]]; then
        export TEST_ES_FROM="$ES_DIST"
        echo "export TEST_ES_FROM=$TEST_ES_FROM" >>$ENV_VARS
    fi

    cd $SOURCE_ROOT/kibana
    node scripts/build_kibana_platform_plugins

    printf -- "Starting Kibana Unit Tests\n"
    curl -sSL "${PATCH_URL}/unittest.sh" >unittest.sh
    bash unittest.sh

    printf -- "Starting Kibana Integration Tests\n"
    curl -sSL "${PATCH_URL}/integrationtest.sh" >integrationtest.sh
    bash integrationtest.sh

    printf -- "Starting Kibana Functional Tests\n"
    curl -sSL "${PATCH_URL}/functionaltest.sh" >functionaltest.sh
    bash functionaltest.sh

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
"ubuntu-22.04" | "ubuntu-24.04")
    printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
    sudo apt-get update
    sudo apt-get install -y curl git gzip make python3 python-is-python3 unzip zip tar wget patch xz-utils \
        build-essential pkg-config libglib2.0-dev libexpat1-dev meson ninja-build brotli libgirepository1.0-dev |& tee -a "${LOG_FILE}"
    gcc --version |& tee -a "${LOG_FILE}"
    configureAndInstall |& tee -a "${LOG_FILE}"
    ;;

"rhel-8.10" | "rhel-9.4" | "rhel-9.6")
    printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
    PYVER="3"
    if [[ $VERSION_ID =~ ^8 ]]; then
        PYVER="39"
    fi
    sudo dnf install -y --allowerasing curl git gcc-c++ gzip make python${PYVER} java-11-openjdk-devel unzip zip tar wget patch xz pkg-config expat-devel glib2-devel meson ninja-build brotli \
        coreutils ed expect file gnupg2 iproute iputils less openssl-devel python${PYVER}-devel python${PYVER}-pip python${PYVER}-requests python${PYVER}-setuptools python${PYVER}-six python${PYVER}-wheel python${PYVER}-pyyaml \
        zlib-devel |& tee -a "${LOG_FILE}"
    gcc --version |& tee -a "${LOG_FILE}"
    export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
    export PATH=$JAVA_HOME/bin:$PATH
    if [[ $VERSION_ID =~ ^8 ]]; then
        export npm_config_python="/usr/bin/python3.9"
        export PYTHON="/usr/bin/python3.9"
    fi
    HAVE_FIREFOX="true"
    configureAndInstall |& tee -a "${LOG_FILE}"
    ;;

"sles-15.6" | "sles-15.7")
    printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
    SLES_GCC_VERSION="14"
    if [[ $VERSION_ID == "15.6" ]]; then
        SLES_GCC_VERSION="13"
    fi
    sudo zypper install -y curl git gcc-c++ gcc${SLES_GCC_VERSION}-c++ gzip make python311 java-11-openjdk-devel unzip zip tar wget patch xz which gawk pkg-config glib2-devel libexpat-devel cmake meson ninja gobject-introspection-devel \
        coreutils ed expect file iproute2 iputils less libopenssl-devel python311-devel python311-pip python311-requests python311-setuptools python311-six python311-wheel unzip zlib-devel python311-python-gnupg python311-PyYAML |& tee -a "${LOG_FILE}"
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-${SLES_GCC_VERSION} 50
    sudo update-alternatives --install /usr/bin/cpp cpp /usr/bin/cpp-${SLES_GCC_VERSION} 50
    sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-${SLES_GCC_VERSION} 50
    gcc --version |& tee -a "${LOG_FILE}"
    export JAVA_HOME=/usr/lib64/jvm/java-11-openjdk
    export PATH=$JAVA_HOME/bin:$PATH
    export npm_config_python="/usr/bin/python3.11"
    export PYTHON="/usr/bin/python3.11"
    configureAndInstall |& tee -a "${LOG_FILE}"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "${LOG_FILE}"
    exit 1
    ;;
esac

cleanup
gettingStarted |& tee -a "${LOG_FILE}"
