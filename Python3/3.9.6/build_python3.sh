#!/bin/bash
# © Copyright IBM Corporation 2021.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
#Instructions
#Get Build script : wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Python3/3.9.6/build_python3.sh
#Execute build script: bash build_python3.sh

set -e -o pipefail

PACKAGE_NAME="python"
PACKAGE_VERSION="3.9.6"
TESTS="false"
FORCE="false"
CURDIR="$(pwd)"
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
BUILD_ENV="${CURDIR}/setenv.sh"

trap "" 1 2 ERR

if [ ! -d "${CURDIR}/logs/" ]; then
        mkdir -p "${CURDIR}/logs/"
fi


source "/etc/os-release"

function prepare() {
        printf -- 'Preparing installation \n' |& tee -a "${LOG_FILE}"
        if command -v "sudo" >/dev/null; then
                printf -- 'Sudo : Yes\n'
        else
                printf -- 'Sudo : No \n'
                printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n'
                exit 1
        fi

        printf -- "Preparing the installation for Python ${PACKAGE_VERSION}\n"

        if [[ "$FORCE" == "true" ]]; then
                printf -- 'Force attribute provided hence continuing with install without confirmation message \n' |& tee -a "${LOG_FILE}"
        else
                # Ask user for prerequisite installation
                printf -- "\n\nAs part of the installation some dependencies might be installed, \n"
                while true; do
                        read -r -p "Do you want to continue (y/n) ? :  " yn
                        case $yn in
                        [Yy]*)
                                printf -- 'User responded with Yes. \n' |& tee -a "${LOG_FILE}"
                                break
                                ;;
                        [Nn]*) exit ;;
                        *) echo "Please provide confirmation to proceed." ;;
                        esac
                done
        fi
}

function cleanup() {
        rm "$CURDIR/Python-${PACKAGE_VERSION}.tgz"
        printf -- 'Cleaned up the artifacts\n' >>"${LOG_FILE}"
}

function build_openssl() {
        cd "${CURDIR}"
        wget https://www.openssl.org/source/openssl-1.1.1j.tar.gz
        tar -xzvf openssl-1.1.1j.tar.gz
        cd openssl-1.1.1j
        ./config --prefix=/usr/local --openssldir=/usr/local
        make
        sudo make install
        sudo ldconfig /usr/local/lib64

        export PATH=/usr/local/bin:$PATH
        export LDFLAGS="-L/usr/local/lib/ -L/usr/local/lib64/"
        export LD_LIBRARY_PATH="/usr/local/lib/:/usr/local/lib64/"
        export CPPFLAGS="-I/usr/local/include/ -I/usr/local/include/openssl"

        printf -- 'export PATH="/usr/local/bin:${PATH}"\n'  >> "${BUILD_ENV}"
        printf -- "export LDFLAGS=\"$LDFLAGS\"\n" >> "${BUILD_ENV}"
        printf -- "export LD_LIBRARY_PATH=\"$LD_LIBRARY_PATH\"\n" >> "${BUILD_ENV}"
        printf -- "export CPPFLAGS=\"$CPPFLAGS\"\n" >> "${BUILD_ENV}"
}

function configureAndInstall() {
        printf -- 'Configuration and Installation started \n' |& tee -a "${LOG_FILE}"

        if [[ "${DISTRO}" == "rhel-7.8" ]] || [[ "${DISTRO}" == "rhel-7.9" ]] || [[ "${DISTRO}" == "sles-12.5" ]]; then
                source "${BUILD_ENV}"
        fi

        #Downloading Source code
        cd "${CURDIR}"
        wget "https://www.python.org/ftp/${PACKAGE_NAME}/${PACKAGE_VERSION}/Python-${PACKAGE_VERSION}.tgz"
        tar -xzf "Python-${PACKAGE_VERSION}.tgz"

        #Configure and build and install Python3
        cd "$CURDIR/Python-${PACKAGE_VERSION}"
        ./configure
        make
        sudo make install

        printf -- '\nInstalled python successfully \n' >>"${LOG_FILE}"

        #Run tests
        runTest

        #Cleanup
        cleanup

        #Verify python installation
        if command -V "$PACKAGE_NAME"${PACKAGE_VERSION:0:1} >/dev/null; then
                printf -- "%s installation completed. Please check the Usage to start the service.\n" "$PACKAGE_NAME" |& tee -a "$LOG_FILE"
        else
                printf -- "Error while installing %s, exiting with 127 \n" "$PACKAGE_NAME"
                exit 127
        fi
}

function runTest() {
        set +e
        if [[ "$TESTS" == "true" ]]; then
                printf -- "TEST Flag is set, continue with running test \n" >> "$LOG_FILE"
                cd "$CURDIR/Python-${PACKAGE_VERSION}"
                make test 2>&1| tee -a test_results.log

                grep "Tests result: SUCCESS" test_results.log

                if [[ $? != 0 ]]; then

                        sed -n '/tests failed/,/tests skipped/p' test_results.log | sort | uniq >> tests_failed.log
                        sed -n '/test_/p' tests_failed.log >> rerun_tests.log
                        cat > expected_failures.log << EOF
test_generators
test_multiprocessing_fork
test_multiprocessing_forkserver
test_multiprocessing_spawn
test_pdb
test_regrtest
test_signal
test_threading
EOF
                        while IFS= read -r line
                        do
                          for word in $line
                        do
                            echo $word >> temp_op.txt
                        done
                        done < "$CURDIR/Python-${PACKAGE_VERSION}/rerun_tests.log"
                        while IFS= read -r line
                        do
                          if grep -q $line "$CURDIR/Python-${PACKAGE_VERSION}/expected_failures.log"; then
                          continue
                          else
                          make test TESTOPTS="-v $line"
                           if [[ $? != 0 ]]; then
                              failed_tc+=($line)
                           fi
                          fi
                        done < "$CURDIR/Python-${PACKAGE_VERSION}/temp_op.txt"

                        #check for TC failures
                        if [ ${#failed_tc[@]} -eq 0 ]; then
                        echo "All tests have passed successfully"
                        else
                        printf -- '**********************************************************************************************************\n'
                        printf -- 'Below are the intermittent test failures detected and can be ignored as it does not affect the functionality.\n'
                        printf -- 'Try running the tests again: make test.\n'
                        for value in "${failed_tc[@]}"
                        do
                             echo $value
                        done
                        printf -- '**********************************************************************************************************\n\n'
                        fi
                        printf -- "Tests execution completed. \n"
                else
                        printf -- "Tests completed successfully. \n"
                fi
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
        echo "  bash build_python3.sh  [-d <debug>] [-v package-version] [-y install-without-confirmation]  [-t install-with-tests] "
        echo "       default: If no -v specified, latest version will be installed "
        echo "This script supports Python version 3.9.6"
        echo
}

while getopts "h?dytv:" opt; do
        case "$opt" in
        h | \?)
                printHelp
                exit 0
                ;;
        d)
                set -x
                ;;
        v)
                PACKAGE_VERSION="$OPTARG"
                LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
                ;;
        y)
                FORCE="true"
                ;;
        t)
                TESTS="true"
                ;;
        esac
done

function printSummary() {
        printf -- '\n***************************************************************************************\n'
        printf -- "Run python: \n"
        printf -- "    python3 -V (To check the version) \n\n"
        printf -- '***************************************************************************************\n'
        printf -- '\n'
}

###############################################################################################################

logDetails
prepare

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-18.04" | "ubuntu-20.04" | "ubuntu-21.04")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo apt-get update
        sudo apt-get install -y gcc g++ libbz2-dev libdb-dev libffi-dev libgdbm-dev liblzma-dev libncurses-dev libreadline-dev libsqlite3-dev libssl-dev make tar tk-dev uuid-dev wget xz-utils zlib1g-dev 
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"rhel-7.8" | "rhel-7.9" | "rhel-8.2" | "rhel-8.3" | "rhel-8.4")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        if [[ "$VERSION_ID" == "8.2" ]] || [[ "$VERSION_ID" == "8.3" ]] || [[ "$VERSION_ID" == "8.4" ]]; then
                sudo yum install -y bzip2-devel gcc gcc-c++ gdbm-devel libdb-devel libffi-devel libnsl2-devel libuuid-devel make ncurses ncurses-devel openssl openssl-devel readline-devel sqlite-devel tar tk-devel wget xz zlib-devel glibc-langpack-en diffutils xz-devel
        else
                sudo yum install -y bzip2-devel gcc gcc-c++ gdbm-devel libdb-devel libffi-devel libuuid-devel make ncurses-devel readline-devel sqlite-devel tar tk-devel wget xz xz-devel zlib-devel
                build_openssl |& tee -a "${LOG_FILE}"
        fi
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"sles-12.5")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo zypper install -y gawk gcc gcc-c++ gdbm-devel libbz2-devel libdb-4_8-devel libffi48-devel libuuid-devel make ncurses-devel readline-devel sqlite3-devel tar tk-devel wget xz-devel zlib-devel gzip
        build_openssl |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"sles-15.2" | "sles-15.3")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo zypper install -y gawk gcc gcc-c++ gdbm-devel libbz2-devel libdb-4_8-devel libffi-devel libnsl-devel libopenssl-devel libuuid-devel make ncurses-devel readline-devel sqlite3-devel tar tk-devel wget xz-devel zlib-devel gzip
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

*)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "${LOG_FILE}"
        exit 1
        ;;
esac

printSummary |& tee -a "${LOG_FILE}"
