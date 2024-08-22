#!/bin/bash
# ©  Copyright IBM Corporation 2024.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Kibana/8.14.0/build_kibana.sh
# Execute build script: bash build_kibana.sh    (provide -h for help)
#
set -e -o pipefail

PACKAGE_NAME="kibana"
PACKAGE_VERSION="8.14.0"
NODE_JS_VERSION="20.13.1"

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
        sudo rm -rf "$SOURCE_ROOT/linux-s390x-93.gz"
        sudo rm -rf "$SOURCE_ROOT/bazel-5.1.1-dist.zip"
        sudo rm -rf "$SOURCE_ROOT/bazelisk"
        sudo rm -rf "$SOURCE_ROOT/node-re2"
        sudo rm -rf "$SOURCE_ROOT/build_go.sh"
        sudo rm -rf "$SOURCE_ROOT/libvips-8.14.2-linux-s390x"
        sudo rm -rf "$SOURCE_ROOT/v8.14.2.tar.gz"
        sudo rm -rf "$SOURCE_ROOT/libvips-8.14.5-linux-s390x"
        sudo rm -rf "$SOURCE_ROOT/v8.14.5.tar.gz"
        printf -- 'Cleaned up the artifacts\n' >>"${LOG_FILE}"
}

function installLibvips() {
        LIBVIPS_VER=$1
        printf -- "Downloading and installing libvips v$LIBVIPS_VER.\n"
        #Ubuntu
        LIB_DIR="lib/s390x-linux-gnu"
        if [[ $DISTRO == "rhel-"* || $DISTRO == "sles-"* ]]; then
                LIB_DIR="lib64"
        fi

        cd $SOURCE_ROOT
        wget https://github.com/libvips/libvips/archive/refs/tags/v$LIBVIPS_VER.tar.gz
        tar zxf v$LIBVIPS_VER.tar.gz
        cd libvips-$LIBVIPS_VER
        meson setup build --prefix $PWD/libvips_install 
        cd build
        meson compile
        meson install
        export LD_LIBRARY_PATH=$SOURCE_ROOT/libvips-$LIBVIPS_VER/libvips_install/LIB_DIR:$LD_LIBRARY_PATH
        echo "export LD_LIBRARY_PATH=$LD_LIBRARY_PATH" >> $ENV_VARS

        mkdir $SOURCE_ROOT/libvips-$LIBVIPS_VER-linux-s390x && cd $SOURCE_ROOT/libvips-$LIBVIPS_VER-linux-s390x
        wget https://github.com/lovell/sharp-libvips/releases/download/v$LIBVIPS_VER/libvips-$LIBVIPS_VER-linux-x64.tar.gz
        tar -xzf libvips-$LIBVIPS_VER-linux-x64.tar.gz
        rm -rf libvips-$LIBVIPS_VER-linux-x64.tar.gz
        cp $SOURCE_ROOT/libvips-$LIBVIPS_VER/libvips_install/$LIB_DIR/libvips-cpp.so.42 $SOURCE_ROOT/libvips-$LIBVIPS_VER-linux-s390x/lib/
        sed -i 's/linux-x64/linux-s390x/g' $SOURCE_ROOT/libvips-$LIBVIPS_VER-linux-s390x/platform.json
        cd $SOURCE_ROOT/libvips-$LIBVIPS_VER-linux-s390x
        tar -cf libvips-$LIBVIPS_VER-linux-s390x.tar *
        cd $SOURCE_ROOT
        mkdir v$LIBVIPS_VER && cd v$LIBVIPS_VER
        mv $SOURCE_ROOT/libvips-$LIBVIPS_VER-linux-s390x/libvips-$LIBVIPS_VER-linux-s390x.tar .
        brotli -j -Z libvips-$LIBVIPS_VER-linux-s390x.tar
}

function configureAndInstall() {
        printf -- '\nConfiguration and Installation started.\n'

        # Building Bazel from source
        printf -- 'Building Bazel from source.\n'
        cd $SOURCE_ROOT
           mkdir bazel && cd bazel
           wget https://github.com/bazelbuild/bazel/releases/download/5.1.1/bazel-5.1.1-dist.zip
           mkdir -p dist/bazel && cd dist/bazel
           unzip -q ../../bazel-5.1.1-dist.zip
           chmod -R +w .
           curl -sSL https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Bazel/5.1.1/patch/dist-md5.patch | git apply
           env EXTRA_BAZEL_ARGS="--tool_java_runtime_version=local_jdk" bash ./compile.sh

           cd $SOURCE_ROOT/bazel
           git clone --depth 1 -b 5.1.1 https://github.com/bazelbuild/bazel.git
           cd bazel
           curl -sSL https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Bazel/5.1.1/patch/bazel.patch | git apply
           cd $SOURCE_ROOT/bazel/bazel
           $SOURCE_ROOT/bazel/dist/bazel/output/bazel build -c opt --stamp --embed_label "5.1.1" //src:bazel //src:bazel_jdk_minimal //src:test_repos
           mkdir output
           cp bazel-bin/src/bazel output/bazel
           ./output/bazel build  -c opt --stamp --embed_label "5.1.1" //src:bazel //src:bazel_jdk_minimal //src:test_repos
           export PATH=$PATH:$SOURCE_ROOT/bazel/bazel/output/
           export USE_BAZEL_VERSION=$SOURCE_ROOT/bazel/bazel/output/bazel
           echo "export PATH=$PATH" >> $ENV_VARS
           echo "export USE_BAZEL_VERSION=$USE_BAZEL_VERSION" >> $ENV_VARS

        # Download Go binary
        printf -- 'Downloading Go binary.\n'
        cd $SOURCE_ROOT
        wget -q https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Go/1.18.4/build_go.sh
        bash build_go.sh -y

        # Building Bazelisk from source
        printf -- 'Building Bazelisk from source.\n'
        cd $SOURCE_ROOT
        git clone --depth 1 -b v1.12.1 https://github.com/bazelbuild/bazelisk.git
        cd bazelisk
        curl -sSL $PATCH_URL/bazelisk_patch.diff | git apply --ignore-whitespace
        go build && ./bazelisk build --config=release //:bazelisk-linux-s390x

        # Installing Node.js
        printf -- 'Downloading and installing Node.js.\n'
        cd $SOURCE_ROOT
        sudo mkdir -p /usr/local/lib/nodejs
        wget https://nodejs.org/dist/v${NODE_JS_VERSION}/node-v${NODE_JS_VERSION}-linux-s390x.tar.xz
        sudo tar xf node-v${NODE_JS_VERSION}-linux-s390x.tar.xz -C /usr/local/lib/nodejs
        export PATH=/usr/local/lib/nodejs/node-v${NODE_JS_VERSION}-linux-s390x/bin:$PATH
        echo "export PATH=$PATH" >> $ENV_VARS
        node -v  >> "${LOG_FILE}"

        # Installing Yarn and patch Bazelisk
        printf -- 'Downloading and installing Yarn and patch Bazelisk.\n'
        sudo chmod ugo+w -R /usr/local/lib/nodejs/node-v${NODE_JS_VERSION}-linux-s390x
        npm install -g yarn @bazel/bazelisk@1.12.1
        BAZELISK_DIR=/usr/local/lib/nodejs/node-v${NODE_JS_VERSION}-linux-s390x/lib/node_modules/@bazel/bazelisk
        curl -sSL $PATCH_URL/bazelisk.js.diff | patch $BAZELISK_DIR/bazelisk.js
        cp $SOURCE_ROOT/bazelisk/bazel-out/s390x-opt-*/bin/bazelisk-linux_s390x $BAZELISK_DIR

        # Building libvips on s390x as a dependency for sharp
        # Need 2 versions of libvips for different Kibana dependencies
        if [[ $DISTRO == "ubuntu-20.04" ]]; then
                cd $SOURCE_ROOT
                wget https://github.com/mesonbuild/meson/releases/download/0.55.3/meson-0.55.3.tar.gz
                tar zxf meson-0.55.3.tar.gz
                cd meson-0.55.3
                ln -s meson.py meson
                export PATH=$SOURCE_ROOT/meson-0.55.3:$PATH
                echo "export PATH=$PATH" >> $ENV_VARS
        fi

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

        export npm_config_sharp_libvips_local_prebuilds=$SOURCE_ROOT
        echo "export npm_config_sharp_libvips_local_prebuilds=${npm_config_sharp_libvips_local_prebuilds}" >> $ENV_VARS

        installLibvips "8.14.2"
        installLibvips "8.14.5"
        
        # Downloading and installing Kibana and apply patch
        printf -- '\nDownloading and installing Kibana.\n'
        cd $SOURCE_ROOT
        git clone --depth 1 -b v$PACKAGE_VERSION https://github.com/elastic/kibana.git
        cd kibana
        curl -sSL $PATCH_URL/kibana_patch.diff | git apply
        sed -i -e "s#https://packages.atlassian.com/api/npm/npm-remote/#https://registry.yarnpkg.com/#g" yarn.lock

        # Build re2
        cd $SOURCE_ROOT
        git clone --depth 1 -b 1.20.1 https://github.com/uhop/node-re2.git
        cd node-re2
        git submodule update --init --recursive
        npm install
        gzip -c build/Release/re2.node > $SOURCE_ROOT/linux-s390x-93.gz
        mkdir -p $SOURCE_ROOT/kibana/.native_modules/re2/
        cp $SOURCE_ROOT/linux-s390x-93.gz $SOURCE_ROOT/kibana/.native_modules/re2/

        # Bootstrap Kibana
        cd $SOURCE_ROOT/kibana
        yarn kbn bootstrap

        # Building Kibana
        cd $SOURCE_ROOT/kibana
        export NODE_OPTIONS="--max_old_space_size=4096"
        echo "export NODE_OPTIONS=$NODE_OPTIONS" >> $ENV_VARS
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
        export TEST_BROWSER_HEADLESS=1
        export DISABLE_BOOTSTRAP_VALIDATION=true
        export BROWSERSLIST_IGNORE_OLD_DATA=true

        cd $SOURCE_ROOT/kibana
        wget $PATCH_URL/unittest.sh
        bash unittest.sh
        
        wget $PATCH_URL/integrationtest.sh
        bash integrationtest.sh
        
        export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
        sudo ldconfig
              
        wget $PATCH_URL/functionaltest.sh
        bash functionaltest.sh


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
"ubuntu-20.04")
        printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo apt-get update
        sudo apt-get install -y curl git g++ gzip make python python3 openjdk-11-jdk unzip zip tar wget patch xz-utils |& tee -a "${LOG_FILE}"
        sudo apt-get install -y build-essential pkg-config libglib2.0-dev libexpat1-dev ninja-build brotli libgirepository1.0-dev  |& tee -a "${LOG_FILE}"
        export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x
        export PATH=$JAVA_HOME/bin:$PATH
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"ubuntu-22.04")
        printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo apt-get update
        sudo apt-get install -y curl git g++ gzip make python2 python3 openjdk-11-jdk unzip zip tar wget patch xz-utils |& tee -a "${LOG_FILE}"
        sudo apt-get install -y build-essential pkg-config libglib2.0-dev libexpat1-dev meson ninja-build brotli libgirepository1.0-dev  |& tee -a "${LOG_FILE}"
        export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x
        export PATH=$JAVA_HOME/bin:$PATH
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"rhel-8.8" | "rhel-8.9" | "rhel-8.10")
        printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo yum install -y curl git gcc-c++ gzip make python2 python3 java-11-openjdk-devel unzip zip tar wget patch xz pkg-config expat-devel glib2-devel meson ninja-build brotli gobject-introspection-devel |& tee -a "${LOG_FILE}"
        sudo yum install -y --allowerasing python3-bind bind-chroot coreutils ed expect file gnupg2 iproute iproute-devel iputils lcov less openssl-devel redhat-lsb netcat python2-devel python3-devel python3-pip python3-requests python3-setuptools python3-six python3-wheel python3-pyyaml zlib-devel |& tee -a "${LOG_FILE}"
        sudo ln -sf /usr/bin/python3 /usr/bin/python
        export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
        export PATH=$JAVA_HOME/bin:$PATH
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;
        
"rhel-9.2" | "rhel-9.3" | "rhel-9.4")
        printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo yum install -y curl git gcc-c++ gzip make python3 java-11-openjdk-devel unzip zip tar wget patch xz pkg-config expat-devel glib2-devel meson ninja-build brotli gobject-introspection-devel |& tee -a "${LOG_FILE}"
        sudo yum install -y --allowerasing python3-bind bind-chroot coreutils ed expect file gnupg2 iproute iproute-devel iputils lcov less openssl-devel netcat python3-devel python3-pip python3-requests python3-setuptools python3-six python3-wheel python3-pyyaml zlib-devel |& tee -a "${LOG_FILE}"
        sudo ln -sf /usr/bin/python3 /usr/bin/python
        export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
        export PATH=$JAVA_HOME/bin:$PATH
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"sles-15.5" | "sles-15.6")
        printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo zypper install -y curl git gcc10-c++ gzip make python python3 java-11-openjdk-devel unzip zip tar wget patch xz which gawk pkg-config glib2-devel libexpat-devel cmake meson ninja gobject-introspection-devel |& tee -a "${LOG_FILE}"
         if [[ $DISTRO == "sles-15.6" ]]; then
            sudo zypper install -y python3-bind bind-chrootenv coreutils curl ed expect file iproute2  iputils lcov less libopenssl-devel netcat python2 python3 python3-devel python3-pip python3-requests python3-setuptools python3-six python3-wheel unzip zlib-devel python3-python-gnupg python3-PyYAML  |& tee -a "${LOG_FILE}"
         else
            sudo zypper install -y python3-bind bind-chrootenv coreutils curl ed expect file iproute2  iputils lcov less libopenssl-devel netcat python2 python2-devel python3 python3-devel python3-pip python3-requests python3-setuptools python3-six python3-wheel unzip zlib-devel python3-python-gnupg python3-PyYAML  |& tee -a "${LOG_FILE}"
         fi
        sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-10 10
        sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-10 10
        sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-10 10
        sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-10 10
        gcc --version
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
