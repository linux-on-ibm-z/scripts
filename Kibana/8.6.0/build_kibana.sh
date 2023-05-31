#!/bin/bash
# ©  Copyright IBM Corporation 2023.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Kibana/8.6.0/build_kibana.sh
# Execute build script: bash build_kibana.sh    (provide -h for help)
#
set -e -o pipefail

PACKAGE_NAME="kibana"
PACKAGE_VERSION="8.6.0"
NODE_JS_VERSION="16.18.1"

FORCE=false
CURDIR="$(pwd)"
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Kibana/${PACKAGE_VERSION}/patch"
NON_ROOT_USER="$(whoami)"

trap cleanup 1 2 ERR

# Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
   mkdir -p "$CURDIR/logs/"
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
        sudo rm -rf "${CURDIR}/node-v${NODE_JS_VERSION}-linux-s390x.tar.xz"
        sudo rm -rf "${CURDIR}/linux-s390x-93.gz"
        sudo rm -rf "{$CURDIR}/bazel-5.1.1-dist.zip"
        sudo rm -rf "${CURDIR}/bazelisk"
        sudo rm -rf "${CURDIR}/node-re2"
        sudo rm -rf "{$CURDIR}/build_go.sh"
        printf -- 'Cleaned up the artifacts\n' >>"${LOG_FILE}"
}

function configureAndInstall() {
        printf -- '\nConfiguration and Installation started.\n'

        # Building Bazel from source
        printf -- 'Building Bazel from source.\n'
        cd "${CURDIR}"
        if [[ $DISTRO == "rhel-"* || $DISTRO == "sles-"* ]]; then
           mkdir bazel && cd bazel
           wget https://github.com/bazelbuild/bazel/releases/download/5.1.1/bazel-5.1.1-dist.zip
           mkdir -p dist/bazel && cd dist/bazel
           unzip ../../bazel-5.1.1-dist.zip
           chmod -R +w .
           curl -sSL https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Bazel/5.1.1/patch/dist-md5.patch | git apply
           env EXTRA_BAZEL_ARGS="--tool_java_runtime_version=local_jdk" bash ./compile.sh

           cd "${CURDIR}"/bazel
           git clone https://github.com/bazelbuild/bazel.git
           cd bazel
           git checkout 5.1.1
           curl -sSL https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Bazel/5.1.1/patch/bazel.patch | git apply
           cd "${CURDIR}"/bazel/bazel
           ${CURDIR}/bazel/dist/bazel/output/bazel build -c opt --stamp --embed_label "5.1.1" //src:bazel //src:bazel_jdk_minimal //src:test_repos
           mkdir output
           cp bazel-bin/src/bazel output/bazel
           ./output/bazel build  -c opt --stamp --embed_label "5.1.1" //src:bazel //src:bazel_jdk_minimal //src:test_repos
           export PATH=$PATH:${CURDIR}/bazel/bazel/output/
           export USE_BAZEL_VERSION=${CURDIR}/bazel/bazel/output/bazel
        else
           wget -q https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Bazel/5.1.1/build_bazel.sh
           bash build_bazel.sh -y
           export PATH=$PATH:${CURDIR}/bazel/output/
           export USE_BAZEL_VERSION=${CURDIR}/bazel/output/bazel
        fi
        

        # Download Go binary
        printf -- 'Downloading Go binary.\n'
        cd "${CURDIR}"
        wget -q https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Go/1.18.4/build_go.sh
        bash build_go.sh -y

        # Building Bazelisk from source
        printf -- 'Building Bazelisk from source.\n'
        cd "${CURDIR}"
        git clone https://github.com/bazelbuild/bazelisk.git
        cd bazelisk
        git checkout v1.12.1
        curl -sSL $PATCH_URL/bazelisk_patch.diff | git apply --ignore-whitespace
        go build && ./bazelisk build --config=release //:bazelisk-linux-s390x

        # Installing Node.js
        printf -- 'Downloading and installing Node.js.\n'
        cd "${CURDIR}"
        sudo mkdir -p /usr/local/lib/nodejs
        wget https://nodejs.org/dist/v${NODE_JS_VERSION}/node-v${NODE_JS_VERSION}-linux-s390x.tar.xz
        sudo tar xf node-v${NODE_JS_VERSION}-linux-s390x.tar.xz -C /usr/local/lib/nodejs
        export PATH=/usr/local/lib/nodejs/node-v${NODE_JS_VERSION}-linux-s390x/bin:$PATH
        node -v  >> "${LOG_FILE}"

        # Installing Yarn and patch Bazelisk
        printf -- 'Downloading and installing Yarn and patch Bazelisk.\n'
        sudo chmod ugo+w -R /usr/local/lib/nodejs/node-v${NODE_JS_VERSION}-linux-s390x
        npm install -g yarn @bazel/bazelisk@1.12.1
        BAZELISK_DIR=/usr/local/lib/nodejs/node-v${NODE_JS_VERSION}-linux-s390x/lib/node_modules/@bazel/bazelisk
        curl -sSL $PATCH_URL/bazelisk.js.diff | patch $BAZELISK_DIR/bazelisk.js
        cp ${CURDIR}/bazelisk/bazel-out/s390x-opt-*/bin/bazelisk-linux_s390x $BAZELISK_DIR

        # Building libvips on s390x as a dependency for sharp
        printf -- 'Downloading and installing libvips.\n'
        cd "${CURDIR}"
        wget https://github.com/libvips/libvips/releases/download/v8.13.2/vips-8.13.2.tar.gz
        tar xf vips-8.13.2.tar.gz
        cd vips-8.13.2/
        ./configure
        make && sudo make install
        mkdir "${CURDIR}"/libvips-8.13.2-linux-s390x && cd "${CURDIR}"/libvips-8.13.2-linux-s390x
        wget https://github.com/lovell/sharp-libvips/releases/download/v8.13.2/libvips-8.13.2-linux-x64.tar.gz
        tar -xzf libvips-8.13.2-linux-x64.tar.gz
        rm -rf libvips-8.13.2-linux-x64.tar.gz
        cp /usr/local/lib/libvips-cpp.so.42 "${CURDIR}"/libvips-8.13.2-linux-s390x/lib/
        sed -i 's/linux-x64/linux-s390x/g' "${CURDIR}"/libvips-8.13.2-linux-s390x/platform.json
        cd "${CURDIR}"
        tar -czf libvips-8.13.2-linux-s390x.tar.br "${CURDIR}"/libvips-8.13.2-linux-s390x
        npm config set sharp_libvips_local_prebuilds "${CURDIR}/libvips-8.13.2-linux-s390x.tar.br"
        
        # Downloading and installing Kibana and apply patch
        printf -- '\nDownloading and installing Kibana.\n'
        cd "${CURDIR}"
        git clone https://github.com/elastic/kibana.git
        cd kibana
        git checkout v$PACKAGE_VERSION
        curl -sSL $PATCH_URL/kibana_patch.diff | git apply

        # Build re2
        cd "${CURDIR}"
        git clone https://github.com/uhop/node-re2.git
        cd node-re2 && git checkout 1.17.4
        git submodule update --init --recursive
        npm install
        gzip -c build/Release/re2.node > "${CURDIR}"/linux-s390x-93.gz
        mkdir -p "${CURDIR}"/kibana/.native_modules/re2/
        cp "${CURDIR}"/linux-s390x-93.gz "${CURDIR}"/kibana/.native_modules/re2/

        # Bootstrap Kibana
        cd "${CURDIR}"/kibana
        yarn kbn bootstrap --oss

        # Building Kibana
        cd "${CURDIR}"/kibana
        export NODE_OPTIONS="--max_old_space_size=4096"
        yarn build --skip-os-packages

        # Installing Kibana
        sudo mkdir /usr/share/kibana/
        sudo tar -xzf target/kibana-"$PACKAGE_VERSION"-SNAPSHOT-linux-s390x.tar.gz -C /usr/share/kibana --strip-components 1
        sudo ln -sf /usr/share/kibana/bin/* /usr/bin/

        if ([[ -z "$(cut -d: -f1 /etc/group | grep elastic)" ]]); then
                printf -- '\nCreating group elastic.\n'
                sudo /usr/sbin/groupadd elastic # If group is not already created
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
        set +e
        if [[ "$TESTS" == "true" ]]; then
                printf -- "TEST Flag is set, continue with running test \n"  >> "$LOG_FILE"
        export NODE_OPTIONS="--max-old-space-size=4096"
        export FORCE_COLOR=1
        export TEST_BROWSER_HEADLESS=1
        export DISABLE_BOOTSTRAP_VALIDATION=true
        export BROWSERSLIST_IGNORE_OLD_DATA=true

        cd "${CURDIR}"/kibana
        wget $PATCH_URL/unittest.sh
        bash unittest.sh |& tee -a "${LOG_FILE}"
        
        wget $PATCH_URL/integrationtest.sh
        bash integrationtest.sh |& tee -a "${LOG_FILE}"
        
        export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
        sudo ldconfig
              
        wget $PATCH_URL/functionaltest.sh
        bash functionaltest.sh |& tee -a "${LOG_FILE}"


        printf -- '**********************************************************************************************************\n'
        printf -- '\nCompleted test execution !! Test case failures can be ignored as they are seen on x86 also \n'
        printf -- '\nSome test case failures will pass when rerun the tests \n'
        printf -- '\nPlease refer to the building instructions for the complete set of expected failures.\n'
        printf -- '**********************************************************************************************************\n'

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
"ubuntu-18.04" | "ubuntu-20.04")
        printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo apt-get update
        sudo apt-get install -y curl git g++ gzip make python python3 openjdk-11-jdk unzip zip tar wget patch xz-utils |& tee -a "${LOG_FILE}"
        sudo apt-get install -y build-essential pkg-config libglib2.0-dev libexpat1-dev  |& tee -a "${LOG_FILE}"
        export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x
        export PATH=$JAVA_HOME/bin:$PATH
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"ubuntu-22.04")
        printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo apt-get update
        sudo apt-get install -y curl git g++ gzip make python2 python3 openjdk-11-jdk unzip zip tar wget patch xz-utils |& tee -a "${LOG_FILE}"
        sudo apt-get install -y build-essential pkg-config libglib2.0-dev libexpat1-dev  |& tee -a "${LOG_FILE}"
        export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x
        export PATH=$JAVA_HOME/bin:$PATH
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;
        
"rhel-7.8" | "rhel-7.9")
        printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo yum install -y git devtoolset-7-gcc-c++ devtoolset-7-gcc gzip make python3 java-11-openjdk-devel unzip zip tar wget patch xz pkgconfig expat-devel glib2-devel |& tee -a "${LOG_FILE}"
        sudo yum install -y python3-bind9.16 bind9.16-chroot coreutils-single ed expect file gnupg2 iproute iproute-devel iputils lcov less openssl-devel redhat-lsb netcat python2-devel python3-devel python3-pip python3-requests python3-setuptools python3-six python3-wheel python3-pyyaml zlib-devel |& tee -a "${LOG_FILE}"
        source /opt/rh/devtoolset-7/enable
        export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
        export PATH=$JAVA_HOME/bin:$PATH
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;
"rhel-8.4" | "rhel-8.6" | "rhel-8.7")
        printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo yum install -y curl git gcc-c++ gzip make python2 python3 java-11-openjdk-devel unzip zip tar wget patch xz pkg-config expat-devel glib2-devel |& tee -a "${LOG_FILE}"
        sudo yum install -y python3-bind9.16 bind9.16-chroot coreutils-single ed expect file gnupg2 iproute iproute-devel iputils lcov less openssl-devel redhat-lsb netcat python2-devel python3-devel python3-pip python3-requests python3-setuptools python3-six python3-wheel python3-pyyaml zlib-devel |& tee -a "${LOG_FILE}"
        sudo ln -sf /usr/bin/python3 /usr/bin/python
        export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
        export PATH=$JAVA_HOME/bin:$PATH
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;
        
"rhel-9.0" | "rhel-9.1")
        printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo yum install -y curl git gcc-c++ gzip make python3 java-11-openjdk-devel unzip zip tar wget patch xz pkg-config expat-devel glib2-devel |& tee -a "${LOG_FILE}"
        sudo yum install -y python3-bind bind-chroot coreutils-single ed expect file gnupg2 iproute iproute-devel iputils lcov less openssl-devel netcat python3-devel python3-pip python3-requests python3-setuptools python3-six python3-wheel python3-pyyaml zlib-devel |& tee -a "${LOG_FILE}"
        sudo ln -sf /usr/bin/python3 /usr/bin/python
        export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
        export PATH=$JAVA_HOME/bin:$PATH
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"sles-12.5")
        printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo zypper install -y curl libnghttp2-devel git gcc-c++ gcc11 gcc11-c++ gzip make python python3 java-11-openjdk-devel unzip zip tar wget patch xz which gawk |& tee -a "${LOG_FILE}"
        sudo zypper install -y pkg-config glib2-devel libexpat-devel |& tee -a "${LOG_FILE}"
        sudo zypper install -y python-bind bind-chrootenv coreutils curl ed expect file iproute2 iputils less libopenssl-devel netcat python2 python2-devel python3 python3-devel python3-pip python3-requests python3-setuptools python3-six python3-wheel unzip zlib-devel python3-PyYAML  |& tee -a "${LOG_FILE}"
        sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-11 11
        sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-11 11
        sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-11 11
        sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-11 11
        sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
        sudo ln -sf /usr/bin/cpp-11 /usr/bin/cpp
        export JAVA_HOME=/usr/lib64/jvm/java-11-openjdk
        export PATH=$JAVA_HOME/bin:$PATH
        wget -q https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Python3/3.7.4/build_python3.sh
        bash build_python3.sh -y |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"sles-15.4")
        printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo zypper install -y curl git gcc-c++ gzip make python python3 java-11-openjdk-devel unzip zip tar wget patch xz which gawk |& tee -a "${LOG_FILE}"
        sudo zypper install -y pkg-config glib2-devel libexpat-devel |& tee -a "${LOG_FILE}"
        sudo zypper install -y python3-bind bind-chrootenv coreutils curl ed expect file iproute2  iputils lcov less libopenssl-devel netcat python2 python2-devel python3 python3-devel python3-pip python3-requests python3-setuptools python3-six python3-wheel unzip zlib-devel python3-python-gnupg python3-PyYAML  |& tee -a "${LOG_FILE}"
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
