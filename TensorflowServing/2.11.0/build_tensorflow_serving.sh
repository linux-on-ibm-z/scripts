#!/bin/bash
# © Copyright IBM Corporation 2023.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/TensorflowServing/2.11.0/build_tensorflow_serving.sh
# Execute build script: bash build_tensorflow_serving.sh    (provide -h for help)
#

set -e  -o pipefail

PACKAGE_NAME="tensorflow-serving"
PACKAGE_VERSION="2.11.0"
SOURCE_ROOT="$(pwd)"
USER="$(whoami)"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/TensorflowServing/2.11.0/patch"

FORCE="false"
TESTS="false"
LOG_FILE="${SOURCE_ROOT}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
   mkdir -p "$SOURCE_ROOT/logs/"
fi


if [ -f "/etc/os-release" ]; then
        source "/etc/os-release"
fi

function prepare() {
        if command -v "sudo" >/dev/null; then
                printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
        else
                printf -- 'Sudo : No \n' >>"$LOG_FILE"
                printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n'
                exit 1
        fi

        if [[ "$FORCE" == "true" ]]; then
                printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
        else
                # Ask user for prerequisite installation
                printf -- "\nAs part of the installation, dependencies would be installed/upgraded. \n"
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
    # Remove artifacts
        rm -rf $SOURCE_ROOT/build_tensorflow.sh
        printf -- "Cleaned up the artifacts\n" | tee -a "$LOG_FILE"

}
function configureAndInstall() {
        printf -- 'Configuration and Installation started \n'
        
        #Install Tensorflow
        printf -- '\nInstalling Tensoflow..... \n'
        cd $SOURCE_ROOT
        wget -q https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Tensorflow/2.11.0/build_tensorflow.sh
        bash build_tensorflow.sh -y 2>&1 | tee build-tf.log  
             
        #Build Tensorflow serving
        printf -- '\nDownload Tensorflow serving source code..... \n'
        cd $SOURCE_ROOT
        rm -rf serving
        git clone https://github.com/tensorflow/serving
        cd serving
        git checkout $PACKAGE_VERSION

        #Apply Patches
        printf -- '\nPatching Tensorflow Serving..... \n'
        wget -O tfs_patch.diff $PATCH_URL/tfs_patch.diff
        sed -i "s?SOURCE_ROOT?$SOURCE_ROOT?" tfs_patch.diff
        MEMSIZE=`expr $(free -g | grep Mem: | awk '{print $2}') / 4`
        sed -i "s?_MEMSIZE_?$MEMSIZE?g" tfs_patch.diff
        CPUCOUNT=$(nproc)
        sed -i "s?JOB_COUNT?$CPUCOUNT?" tfs_patch.diff
        git apply tfs_patch.diff

        printf -- '\nBuilding Tensorflow Serving..... \n'
        cd $SOURCE_ROOT/serving
        bazel build tensorflow_serving/...
        sudo pip3 install tensorflow-serving-api==2.11.0

        sudo cp $SOURCE_ROOT/serving/bazel-bin/tensorflow_serving/model_servers/tensorflow_model_server /usr/local/bin

        # Run Tests
        runTest

        #Cleanup
        cleanup

        printf -- "\n Installation of %s %s was successful \n\n" $PACKAGE_NAME $PACKAGE_VERSION
}

function runTest() {
        set +e
        if [[ "$TESTS" == "true" ]]; then
                printf -- "TEST Flag is set , Continue with running test \n"

                cd $SOURCE_ROOT/serving
                bazel test tensorflow_serving/...
                printf -- "Tests completed. \n"

        fi
        set -e
}

function logDetails() {
        printf -- '**************************** SYSTEM DETAILS *************************************************************\n' >>"$LOG_FILE"
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
        echo "  bash build_tensorflow_serving.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests]"
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
        printf -- '\n***********************************************************************************************\n'
        printf -- "Getting Started: \n"
        printf -- "To verify, run TensorFlow Serving from command Line : \n"
        printf -- "  $ cd $SOURCE_ROOT  \n"
        printf -- "  $ export TESTDATA=$SOURCE_ROOT/serving/tensorflow_serving/servables/tensorflow/testdata  \n"
        printf -- "  $ tensorflow_model_server --rest_api_port=8501 --model_name=half_plus_two --model_base_path=\$TESTDATA/saved_model_half_plus_two_cpu &  \n"
        printf -- "  $ curl -d '{\"instances\": [1.0, 2.0, 5.0]}'     -X POST http://localhost:8501/v1/models/half_plus_two:predict\n"
        printf -- "Output should look like:\n"
        printf -- "  $ predictions: [2.5, 3.0, 4.5 \n"
        printf -- "  $ ]\n"
        printf -- 'Make sure JAVA_HOME is set and bazel binary is in your path in case of test case execution.'
        printf -- '*************************************************************************************************\n'
        printf -- '\n'
}

###############################################################################################################

logDetails
prepare #Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-20.04" | "ubuntu-22.04")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        sudo apt-get install -y wget
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;
*)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
        exit 1
        ;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
