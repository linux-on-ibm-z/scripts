#!/bin/bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Swift/5.1/build_swift.sh
# Note: Please configure global variables user.email and user.name in script
# Execute build script: bash build_swift.sh (provide -h for help)
#
set -e -o pipefail

PACKAGE_NAME="swift"
PACKAGE_VERSION="5.1"
FORCE="false"
CURDIR="$(pwd)"
REPO_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Swift/5.1/patch"
SWIFT_SOURCE_DIR=$CURDIR/swift-5.1
if [ ! -d $SWIFT_SOURCE_DIR ]; then
        mkdir -p $SWIFT_SOURCE_DIR
fi
cd $SWIFT_SOURCE_DIR
SWIFT_BUILD_DIR=$SWIFT_SOURCE_DIR/build/buildbot_linux
SWIFT_INSTALL_DIR=$SWIFT_SOURCE_DIR/swift-install
SWIFT_INSTALL_PKG=$SWIFT_INSTALL_DIR/install.tar.gz
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
BUILD_DIR="/usr/local"
TESTS="false"

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
        mkdir -p "$CURDIR/logs/"
fi

# Need handling for RHEL 6.10 as it doesn't have os-release file
if [ -f "/etc/os-release" ]; then
        source "/etc/os-release"
else
        cat /etc/redhat-release >>"${LOG_FILE}"
        export ID="rhel"
        export VERSION_ID="6.x"
        export PRETTY_NAME="Red Hat Enterprise Linux 6.x"
fi

function prepare() {
        if command -v "sudo" >/dev/null; then
                printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
        else
                printf -- 'Sudo : No \n' >>"$LOG_FILE"
                printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n'
                exit 1
        fi

        if [[ "$FORCE" == "true" ]]; then
                printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
        else
                # Ask user for prerequisite installation
                printf -- "\nAs part of the installation , some dependencies will be installed, \n"
                while true; do
                        read -r -p "Do you want to continue (y/n) ? :  " yn
                        case $yn in
                        [Yy]*)
                                printf -- 'User responded with Yes. \n' >> "$LOG_FILE"
                                break
                                ;;
                        [Nn]*) exit ;;
                        *) echo "Please provide confirmation to proceed." ;;
                        esac
                done
        fi
}

function cleanup() {

        #Check if swift build directory exists
        if [ -d "$SWIFT_BUILD_DIR" ]; then
                sudo rm -rf "$SWIFT_BUILD_DIR"
        fi

        #Check if swift install package exists
        if [ -f "$SWIFT_INSTALL_PKG" ]; then
                sudo rm "$SWIFT_INSTALL_PKG"
        fi

        printf -- 'Cleaned up the artifacts\n'
}

function configureAndInstall() {
        printf -- 'Configuration and Installation started \n'

        # Install swift 5.1
        printf -- "\nInstalling %s..... \n" "$PACKAGE_NAME"

        # Swift 5.1 installation
        cd "$SWIFT_SOURCE_DIR"
        git clone -b swift-${PACKAGE_VERSION}-branch https://github.com/apple/swift.git
        cd swift
        ./utils/update-checkout --clone --scheme swift-${PACKAGE_VERSION}-branch
        printf -- 'Git clone Swift 5.1 success \n'

        # Apply patches for swift
        printf -- 'Apply patches for Swift\n'
        git fetch
        git config --global user.email "<user_email>"
        git config --global user.name "<user_name>"
        git cherry-pick cacf9c72b6f5ca7249dcf4b1cb81de6d8b120acb
        git cherry-pick 04976e1a75d37592d6d6d688de07a210d0c046ef
        git cherry-pick 6bb79cafd9e4de34ffc4b2c798960466cf3da70f
        git cherry-pick 25a075cbb6abba3d71d833abe704bc13f12350a2
        git cherry-pick d3262ec10d7e41b9403f83f2f89474795f9eed3a
        git cherry-pick 253d5b5d18c9be2eae2b94be60976ab91f3e4ef6
        git cherry-pick a06abbb3b5f3b6cae3ec5dfefe883dbfb6993118
        git cherry-pick 931eccb34d34548c8d3e86bf08b471185988fe8b
        git cherry-pick e08359c2013a154e1bc740e1984a1c3b645cd7fe
        git cherry-pick ce3aff12da2821314b6555c6ff98de4abeaa5cdc
        git cherry-pick 2f8b5ac9e2f4395f2633b0dfe03b7d6fd1685b7d
        git cherry-pick 6ab83122acf6cc8f98e24a3d47e62483d63c4df9
        git cherry-pick 71fa7ece3fcfe4900f5a75b775efe2a7e94663db
        git cherry-pick 43bfbd5f38bbc72a4d79f103c962f4a9e9adefff
        git cherry-pick 8b3c1a459b13a27f63e7a967f6071d146606d4bc
        git cherry-pick bb2740e540a4679c26d80d9e58d29ef50a38349f
        git cherry-pick 192bcb2007b89bc941d7ea6f348301f3ecf5ee86
        git cherry-pick eb1c203cbf0a306cf084579f090b1ea6ebd55125
        git cherry-pick 6ac15e93482ccd988b2bbc7d3d50a72899c62ed7
        git cherry-pick 81ece42b1847d6cb647fd8f21910d0f0aa71df42

        git remote add loz https://github.com/linux-on-ibm-z/swift.git
        git fetch loz
        git cherry-pick cbf68876f51fa804fd538b4f2ad0b2f70c893a57

        # Apply patches for Swift Foundation
        cd ../swift-corelibs-foundation/
        git remote add loz https://github.com/linux-on-ibm-z/swift-corelibs-foundation.git
        git fetch loz
        git cherry-pick 68412be28a843e37e0be2557669d13024443d718

        # Apply patches for LLDB
        cd ../llvm-project
        curl -o lldb.patch $REPO_URL/lldb.patch
        git apply lldb.patch

        # Apply patches for Swift Package Manager
        cd ../swiftpm
        git cherry-pick b8768525da66690622b37ce8ebc034945604154e

        cd $SWIFT_SOURCE_DIR
        env LD_LIBRARY_PATH=$SWIFT_BUILD_DIR/swift-linux-s390x/lib/swift/linux/s390x/:$SWIFT_BUILD_DIR/swift-linux-s390x/libdispatch-prefix/lib/ $SWIFT_SOURCE_DIR/swift/utils/build-script --preset=buildbot_linux,no_test install_destdir=$SWIFT_INSTALL_DIR installable_package=$SWIFT_INSTALL_PKG
        printf -- 'Build swift success \n'

        # Run the test
        runTest

        #Verify swift installation
        if command -v "$SWIFT_INSTALL_DIR/usr/bin/swift" >/dev/null; then
                printf -- "%s installation completed. Please check the Usage to start the service.\n" "$PACKAGE_NAME"
        else
                printf -- "Error while installing %s, exiting with 127 \n" "$PACKAGE_NAME"
                exit 127
        fi

}

function runTest() {
        set +e
        if [[ "$TESTS" == "true" ]]; then
                printf -- "TEST Flag is set, continue with running test \n"

                # Test build
                cd $SWIFT_SOURCE_DIR
                cp -r ./build/buildbot_linux/swift-linux-s390x/lib/swift/linux/s390x/* build/buildbot_linux/swift-linux-s390x/lib/swift/linux/
                cp -r ./build/buildbot_linux/swift-linux-s390x/libdispatch-prefix/lib/* build/buildbot_linux/swift-linux-s390x/lib/swift/linux/
                env LD_LIBRARY_PATH=$SWIFT_INSTALL_DIR/usr/lib/swift/linux $SWIFT_SOURCE_DIR/swift/utils/build-script --assertions --no-swift-stdlib-assertions --swift-enable-ast-verifier=0 '--swift-install-components=autolink-driver;compiler;clang-resource-dir-symlink;stdlib;swift-remote-mirror;sdk-overlay;parser-lib;toolchain-tools;license;sourcekit-inproc' '--llvm-install-components=llvm-cov;llvm-profdata;IndexStore;clang;clang-headers;compiler-rt;clangd' --llbuild --swiftpm --xctest --libicu --libcxx --build-ninja --install-swift --install-lldb --install-llbuild --install-swiftpm --install-xctest --install-libicu --install-prefix=/usr --install-libcxx --install-sourcekit-lsp --build-swift-static-stdlib --build-swift-static-sdk-overlay --build-swift-stdlib-unittest-extra --test-installable-package --install-destdir=$SWIFT_INSTALL_DIR --installable-package=$SWIFT_INSTALL_PKG --build-subdir=buildbot_linux --lldb --release --test --validation-test --long-test --stress-test --test-optimized --foundation --libdispatch --indexstore-db --sourcekit-lsp '--lit-args=-v --time-tests' --lldb-test-swift-only --install-foundation --install-libdispatch --reconfigure --skip-test-cmark --skip-test-lldb --skip-test-llbuild --skip-test-xctest --skip-test-libdispatch --skip-test-playgroundsupport --skip-test-libicu --skip-test-indexstore-db --skip-test-sourcekit-lsp
                printf -- "Tests completed. \n"

        fi
        set -e
}

function logDetails() {
        printf -- '**************************** SYSTEM DETAILS *************************************************************\n' >"$LOG_FILE"
        if [ -f "/etc/os-release" ]; then
                cat "/etc/os-release" >>"$LOG_FILE"
        else
                cat "/etc/redhat-release" >>"${LOG_FILE}"
        fi

        cat /proc/version >>"$LOG_FILE"
        printf -- '*********************************************************************************************************\n' >>"$LOG_FILE"

        printf -- "Detected %s \n" "$PRETTY_NAME"
        printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" |& tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
        echo "Usage: "
        echo "bash build_swift_51.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests] [-c clean-up]"
        echo "Note: With tests , the build may take approx 30 mins."
}

while getopts "h?dytc" opt; do
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
                printf -- "\n Build with tests may take approx 30 mins (may vary based on machine configuration) \n"
                ;;
        c)
                cleanup
                exit 0
                ;;
        esac
done

function gettingStarted() {
        printf -- '\n***************************************************************************************\n'
        printf -- "Getting Started: \n"
        printf -- "%s/usr/bin/swift --version \n" "$SWIFT_INSTALL_DIR"
        printf -- '***************************************************************************************\n'
        printf -- '\n'
}

###############################################################################################################

logDetails
prepare #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-18.04")
        printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        sudo apt-get update
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y autoconf libtool git cmake ninja-build python python-dev python3-dev uuid-dev libicu-dev icu-devtools libbsd-dev libedit-dev libxml2-dev libsqlite3-dev swig libpython-dev libncurses5-dev pkg-config libcurl4-openssl-dev systemtap-sdt-dev tzdata clang git rsync |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
