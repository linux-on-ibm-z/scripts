#!/bin/bash
# © Copyright IBM Corporation 2021.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/V8JavaScript/9.2/build_v8.sh
# Execute build script: bash build_v8.sh    (provide -h for help)


set -e -o pipefail
PACKAGE_NAME="v8"
PACKAGE_VERSION="9.2.230.22"
CURDIR="$(pwd)"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/V8JavaScript/9.2/patch"

FORCE="false"
TESTS="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
   mkdir -p "$CURDIR/logs/"
fi

source "/etc/os-release"

function prepare() {
    if  command -v "sudo" > /dev/null ;
    then
        printf -- 'Sudo : Yes\n' >> "$LOG_FILE"
    else
        printf -- 'Sudo : No \n' >> "$LOG_FILE"
        printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n';
    exit 1;
    fi;

    if [[ "$FORCE" == "true" ]] ;
    then
        printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
    else
        # Ask user for prerequisite installation
        printf -- "\nAs part of the installation , gn and depot will be installed, \n";
        while true; do
                    read -r -p "Do you want to continue (y/n) ? :  " yn
                    case $yn in
                            [Yy]* ) printf -- 'User responded with Yes. \n' >> "$LOG_FILE";
                            break;;
                    [Nn]* ) exit;;
                    *)  echo "Please provide confirmation to proceed.";;
                    esac
        done
    fi
}


function cleanup() {
    # Remove artifacts
    printf -- "Cleaned up the artifacts\n" >> "$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"
    # Install Depot_tools
    printf -- "\n\n Installing Depot_tools  \n"
    cd $CURDIR
    git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
    export PATH=$PATH:$CURDIR/depot_tools
    export VPYTHON_BYPASS="manually managed python not supported by chrome operations"
    gclient

    # Install gn
    printf -- 'Installing gn ..... \n'
    cd $CURDIR
    git clone https://gn.googlesource.com/gn
    cd gn
    git checkout eea3906
    python build/gen.py
    ninja -C out
    out/gn_unittests
    export PATH=$CURDIR/gn/out:$PATH

    # Install V8
    cd $CURDIR
    fetch v8
    cd v8/
    git checkout $PACKAGE_VERSION
    gclient sync
    curl -sSL $PATCH_URL/install-build-deps.diff | patch build/install-build-deps.sh
    curl -sSL https://github.com/v8/v8/commit/0d0a8b3ff979af5a87ec69689933b7565adb1e20.diff | git apply
    ./build/install-build-deps.sh --no-arm --no-nacl
    mkdir out/s390x.release
    gn gen out/s390x.release --args='is_component_build=false target_cpu="s390x" v8_target_cpu="s390x" use_goma=false goma_dir="None" v8_enable_backtrace=true v8_enable_disassembler=true v8_enable_object_print=true v8_enable_verify_heap=true'
    ninja -C $CURDIR/v8/out/s390x.release
    printf -- 'V8 built successfully \n'

    #Run tests
    runTest

    #cleanup
    cleanup

}

#Set ENV
function setENV() {
  cd $HOME
cat << EOF > setenv.sh
        #v8 ENV
        export CURDIR=$CURDIR
        export PATH=$PATH:$CURDIR/depot_tools/
        export VPYTHON_BYPASS="manually managed python not supported by chrome operations"
        export PATH=$CURDIR/gn/out:$PATH
        export LOGDIR=$LOGDIR
EOF

}
#Tests function
function runTest() {
        set +e
        if [[ "$TESTS" == "true" ]]; then
                printf -- "TEST Flag is set, continue with running test \n"
                cd $CURDIR/v8
                tools/run-tests.py --time --progress=dots --outdir=out/s390x.release
                printf -- "Tests completed. \n" |& tee -a "$LOG_FILE"
        fi
        set -e
}

function logDetails() {
    printf -- '**************************** SYSTEM DETAILS *************************************************************\n' >"$LOG_FILE"
    if [ -f "/etc/os-release" ]; then
        cat "/etc/os-release" >> "$LOG_FILE"
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
    echo " bash build_v8.sh  [-d debug] [-y install-without-confirmation] [-t install and run tests]"
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
    printf -- '\n********************************************************************************************************\n'
    printf -- "\n*Getting Started * \n"
    printf -- "\n Running v8: \n"
    printf -- "\n source \$HOME/setenv.sh \n"
    printf -- "\n $CURDIR/v8/out/s390x.release/d8  \n"
    printf -- "You have successfully started v8 shell.\n"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
    "ubuntu-20.04")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo apt-get update
        sudo -E DEBIAN_FRONTEND=noninteractive apt-get install -y python python3 curl pkg-config git wget clang g++ gcc ninja-build gcc-multilib g++-multilib python3-distutils lsb-release tzdata g++-7 gcc-7 |& tee -a "${LOG_FILE}"
        sudo dpkg-reconfigure --frontend noninteractive tzdata
        sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-7 7
        sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-7 7
        configureAndInstall |& tee -a "${LOG_FILE}"
        setENV |& tee -a "${LOG_FILE}"
        ;;
    "ubuntu-18.04")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo apt-get update
        sudo -E DEBIAN_FRONTEND=noninteractive apt-get install -y python python3 curl pkg-config git wget clang g++ gcc ninja-build gcc-multilib g++-multilib python3-distutils lsb-release tzdata |& tee -a "${LOG_FILE}"
        sudo dpkg-reconfigure --frontend noninteractive tzdata
        configureAndInstall |& tee -a "${LOG_FILE}"
        setENV |& tee -a "${LOG_FILE}"
        ;;
  *)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
        exit 1
        ;;

esac
gettingStarted |& tee -a "${LOG_FILE}"
