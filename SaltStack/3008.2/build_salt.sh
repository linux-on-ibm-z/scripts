#!/usr/bin/env bash
# © Copyright IBM Corporation 2026
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/SaltStack/3008.2/build_salt.sh
# Execute build script: bash build_salt.sh    (provide -t for test)
#
set -e -o pipefail
PACKAGE_NAME="salt"
PACKAGE_VERSION="3008.2"
PYTHON_VERSION="3.10.18"
PATCH_URL="${PATCH_URL:-https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/SaltStack/3008.2/patch/}"
CURDIR="$PWD"
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
trap cleanup 1 2 ERR
TESTS="false"
FORCE="false"
#Check if directory exists
if [ ! -d "logs" ]; then
   mkdir -p "logs"
fi
if [ -f "/etc/os-release" ]; then
        source "/etc/os-release"
fi

function checkPrequisites()
{
  if command -v "sudo" > /dev/null ;
  then
        printf -- 'Sudo : Yes\n' >> "$LOG_FILE"
  else
        printf -- 'Sudo : No \n' >> "$LOG_FILE"
        printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n';
        exit 1;
  fi;

if [[ "$FORCE" == "true" ]]; then
                printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
        else
                # Ask user for prerequisite installation
                printf -- "\nAs part of the installation , dependencies would be installed/upgraded.\n"
                while true; do
                        read -r -p "Do you want to continue (y/n) ? :  " yn
                        case $yn in
                        [Yy]*)
                                printf -- 'User responded with Yes. \n' >>"$LOG_FILE"
                                break
                                ;;
                        [Nn]*) exit ;;
                        *) echo "Please provide confirmation to proceed." ;;
                        esac
                done
        fi
}

function prepareRepos()
{
        if [[ "$ID" != "rhel" ]]; then
                return 0
        fi
        local RHEL_MAJOR="${VERSION_ID%%.*}"
        printf -- "Enabling EPEL and CodeReady Builder repos for RHEL %s\n" "$RHEL_MAJOR"
        sudo yum install -y "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${RHEL_MAJOR}.noarch.rpm" || true
        sudo yum config-manager --set-enabled "codeready-builder-for-rhel-${RHEL_MAJOR}-s390x-rpms" || true
}

function cleanup()
{
        rm -rf ${CURDIR}/Python-${PYTHON_VERSION}.tgz ${CURDIR}/v1.7.1.tar.gz
        printf -- 'Cleaned up the artifacts\n'  >> "$LOG_FILE"
}

function runTest() {
    if [[ "$TESTS" != "true" ]]; then
        return 0
    fi
    printf -- 'Running tests \n\n'
        cd "${CURDIR}/${PACKAGE_NAME}"

    # Create directories that Salt tests expect to exist and be writable
    sudo mkdir -p /var/log/salt /etc/salt/pki/minion /var/cache/salt/minion /var/run/salt /srv/salt
    sudo chown -R $(whoami) /var/log/salt /etc/salt /var/cache/salt /var/run/salt /srv/salt

    # Fix __pycache__ ownership so setup.py clean doesn't fail with permission denied
    find "${CURDIR}/${PACKAGE_NAME}" -name '__pycache__' -exec chmod -R u+rw {} + 2>/dev/null || true
    find "${CURDIR}/${PACKAGE_NAME}" -name '*.pyc' -exec chmod u+rw {} + 2>/dev/null || true

    # Match upstream CI tolerance for FD-leak test (default 5 is too tight)
    export SALT_FD_LEAK_TOLERANCE=20

    pip3 install nox
    # Create the nox venv without running tests (--install-only), then ensure
    # salt is installed as editable (nox may skip this on some distros, causing
    # cmd.run subprocesses in tests to fail with ModuleNotFoundError)
    python3 -m nox -e "test-3(coverage=False)" --install-only
    for NOX_VENV in $(find .nox -maxdepth 1 -name 'test-*' -type d); do
        if [ -f "$NOX_VENV/bin/activate" ]; then
            source "$NOX_VENV/bin/activate"
            pip install -e .
            deactivate
        fi
    done
    if python3 -m nox -e "test-3(coverage=False)" --reuse-existing-virtualenvs -- --core-tests -o "asyncio_mode=auto" ; then
        printf -- 'Test Completed \n\n'
    else
        printf -- 'Some Tests Failed \n\n'
    fi
}

function configureAndInstall()
{
  printf -- 'Configuration and Installation started \n'

        printf -- 'Building Python \n'
        cd "${CURDIR}"
        wget https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz
        tar -xzf Python-${PYTHON_VERSION}.tgz
        cd Python-${PYTHON_VERSION}
        ./configure --prefix=/usr/local --exec-prefix=/usr/local --enable-loadable-sqlite-extensions
        make
        sudo make install
        export PATH=/usr/local/bin/python3.10:$PATH
        sudo mkdir -p /usr/bin
        sudo ln -sf "$(command -v python3)" /usr/bin/python3
        python3 -V

        sudo mkdir -p /var/cache/salt/minion /var/run/salt /srv/salt /var/log/salt /etc/salt/pki/minion
        sudo chown -R $(whoami) /var/cache/salt /var/run/salt /srv/salt /var/log/salt /etc/salt
        export PATH=$PATH:/usr/sbin:/sbin
        SFTP_PATH=$(sudo find /usr -name sftp-server 2>/dev/null | head -n 1)
        TARGET="/usr/lib/ssh/sftp-server"
        [ -n "$SFTP_PATH" ] && \
        [ "$SFTP_PATH" != "$TARGET" ] && \
        sudo mkdir -p /usr/lib/ssh && \
        sudo ln -sf "$SFTP_PATH" "$TARGET"
        if [[ "$ID" == "rhel" && "$VERSION_ID" == 8.* ]]; then
                pip3 install "M2Crypto<0.40"
        elif [[ "$ID" == "rhel" && "${VERSION_ID%%.*}" -lt 10 ]]; then
                pip3 install M2Crypto
        fi
        # M2Crypto skipped on RHEL 10+ (swig unavailable); Salt uses cryptography instead

        printf -- 'Building Libgit2 \n'
        cd "${CURDIR}"
        wget https://github.com/libgit2/libgit2/archive/refs/tags/v1.9.0.tar.gz
        tar xzf v1.9.0.tar.gz
        cd libgit2-1.9.0/
        cmake .
        make
        sudo make install

        #Install Rust and Cargo
        if ! command -v rustup >/dev/null 2>&1; then
                curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
        fi
        export PATH="$HOME/.cargo/bin:$PATH"

        if [[ "$ID" == "rhel" && "$VERSION_ID" == 8.* ]]; then
                sudo yum install -y openssl3 openssl3-devel
                export OPENSSL_INCLUDE_DIR=/usr/include/openssl3
                export OPENSSL_LIB_DIR=/usr/lib64/openssl3
                export OPENSSL_NO_VENDOR=1
                export LD_LIBRARY_PATH=/usr/lib64/openssl3:/usr/lib64:${LD_LIBRARY_PATH:-}
        fi
        #Install python packages
        python3 -m pip install setuptools wheel && python3 -m pip wheel cassandra-driver==3.28.0 websocket-client==0.40.0 --no-build-isolation
        pip3 install pyzmq PyYAML cryptography==49.0.0 msgpack jinja2 psutil tornado python-dateutil genshi looseversion packaging distro

        #Download Salt
        cd "${CURDIR}"
        printf -- 'Downloading Salt \n'
        git clone --depth 1 -b v${PACKAGE_VERSION} https://github.com/saltstack/salt.git
        cd salt
        curl -sSL $PATCH_URL/salt.patch | git apply -
        sed -i '/^lxml==/c\lxml==5.2.1' requirements/static/ci/py3.10/linux.lock
        # Fix test_interrupt_on_long_running_job: earlier tests pollute the
        # SIGINT handler (Reactor/SignalHandlingProcess leak). The test's own
        # comments prescribe the fix: use default_signals to reset signal
        # disposition before spawning the child CLI process.
        python3 -c "
import re, pathlib
p = pathlib.Path('tests/pytests/integration/cli/test_salt.py')
t = p.read_text()
t = t.replace(
    'from tests.conftest import FIPS_TESTRUN',
    'from tests.conftest import FIPS_TESTRUN\nfrom salt.utils.process import default_signals')
t = re.sub(
    r'    # If this test starts failing.*?universal_newlines=True,\n    \)\n    # and uncomment the following block of code\n\n    # with default_signals',
    '    with default_signals',
    t, count=1, flags=re.DOTALL)
t = t.replace('#    proc = subprocess.Popen(', '        proc = subprocess.Popen(')
t = t.replace('#        cmdline,', '            cmdline,')
t = t.replace('#        shell=False,', '            shell=False,')
t = t.replace('#        stdout=terminal_stdout,', '            stdout=terminal_stdout,')
t = t.replace('#        stderr=terminal_stderr,', '            stderr=terminal_stderr,')
t = t.replace('#        universal_newlines=True,', '            universal_newlines=True,')
t = t.replace('#    )', '        )')
p.write_text(t)
"
        # Pin protobuf<6 (protobuf 6.x C extension segfaults on s390x)
        find requirements/static -name '*.lock' -exec sed -i 's/^protobuf==.*/protobuf==5.29.5/' {} +
        echo 'protobuf>=5.29,<6' >> requirements/base.txt
        # Pin cryptography<43 in pkg lock files on RHEL 8 (cryptography>=43 requires OpenSSL 3.0+,
        # RHEL 8 has 1.1).  Only pkg/ locks are affected — ci/ locks use pre-built wheels.
        if [[ "$ID" == "rhel" && "$VERSION_ID" == 8.* ]]; then
                find requirements/static/pkg -name '*.lock' -exec sed -i 's/^cryptography==.*/cryptography==42.0.8/' {} +
                find requirements/static/pkg -name '*.lock' -exec sed -i 's/^pyopenssl==.*/pyopenssl==24.2.1/' {} +
                # Also cap in base.txt so USE_STATIC_REQUIREMENTS=0 tests can resolve
                sed -i 's/cryptography>=48.0.0; python_version >= .3.10./cryptography>=42.0.8,<43.0.0; python_version >= "3.10"/' requirements/base.txt
                sed -i 's/pyopenssl>=26.2.0/pyopenssl>=24.2.1,<26.0.0/' requirements/base.txt
        fi
        pip3 install -e .
        # Install logrotate config (normally deployed by RPM/deb package)
        # Debian-family expects "salt-common", RedHat-family expects "salt"
        if [[ "$ID" == "ubuntu" ]] || [[ "$ID" == "debian" ]] || [[ "$ID_LIKE" == *"debian"* ]]; then
                sudo cp pkg/rpm/logrotate.salt /etc/logrotate.d/salt-common
        else
                sudo cp pkg/rpm/logrotate.salt /etc/logrotate.d/salt
        fi

        # Fix test_logrotate_config: upstream fixture only handles RedHat/Debian
        python3 -c "
import pathlib
p = pathlib.Path('tests/pytests/pkg/integration/test_logrotate_config.py')
t = p.read_text()
if 'Suse' not in t:
    t = t.replace(
        '        return pathlib.Path(\"/etc/logrotate.d\", \"salt-common\")',
        '        return pathlib.Path(\"/etc/logrotate.d\", \"salt-common\")\n    elif grains[\"os_family\"] == \"Suse\":\n        return pathlib.Path(\"/etc/logrotate.d\", \"salt\")')
    p.write_text(t)
"

        # Make test_fd_leak honor SALT_FD_LEAK_TOLERANCE without CI=true
        sed -i 's/if os.environ.get("CI") or os.environ.get("GITHUB_ACTIONS"):/if os.environ.get("SALT_FD_LEAK_TOLERANCE") or os.environ.get("CI") or os.environ.get("GITHUB_ACTIONS"):/' tests/pytests/functional/minion/test_fd_leak.py

        #Install libzmq from source if system package not available (SLES, Ubuntu s390x)
        if [[ "$ID-$VERSION_ID" == sles* ]] || [[ "$ID" == "ubuntu" ]]; then
                cd "${CURDIR}"
                wget https://github.com/zeromq/libzmq/releases/download/v4.3.5/zeromq-4.3.5.tar.gz
                tar -xzf zeromq-4.3.5.tar.gz
                cd zeromq-4.3.5
                ./configure
                make
                sudo make install
                sudo ldconfig
                pip3 install pyzmq
        fi

#Run tests
  runTest

#Verify installation
  export PATH=${HOME}/.local/bin:$PATH
  printf -- 'path for Salt : $PATH \n'
  echo $PATH
  salt-master --version
}

function logDetails()
{
        printf -- '**************************** SYSTEM DETAILS *************************************************************\n' > "$LOG_FILE";
if [ -f "/etc/os-release" ]; then
   cat "/etc/os-release" >> "$LOG_FILE"
fi
cat /proc/version >> "$LOG_FILE"
        printf -- '*********************************************************************************************************\n' >> "$LOG_FILE";
printf -- "Detected %s \n" "$PRETTY_NAME"
        printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" |& tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
  echo
  echo "Usage: "
  echo "bash build_salt.sh [-d debug] [-t install-with-tests] [-y install-without-confirmation]"
  echo
}
while getopts "dthy?" opt; do
  case "$opt" in
  d)
        set -x
        ;;
  t)
        TESTS="true"
        ;;
  y)
        FORCE="true"
        ;;
  h | \?)
        printHelp
        exit 0
        ;;
  esac
done

function gettingStarted()
{
  printf -- "\n\nUsage: \n"
  printf -- "  Salt installed successfully \n"
  printf -- "  More information can be found here : https://github.com/saltstack/salt \n"
  printf -- '\n'
}
###############################################################################################################
logDetails
checkPrequisites  #Check Prequisites
DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"rhel-8.10")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  prepareRepos |& tee -a "${LOG_FILE}"
  sudo yum install -y procps-ng zeromq-devel cyrus-sasl-devel gcc gcc-c++ git libffi-devel libtool libxml2-devel libxslt-devel make man swig tar wget cmake bzip2-devel gdbm-devel libdb-devel libnsl2-devel libuuid-devel ncurses-devel openssl openssl-devel readline-devel sqlite-devel tk-devel xz xz-devel zlib-devel glibc-langpack-en diffutils cargo file iproute |& tee -a "${LOG_FILE}"
  configureAndInstall |& tee -a "${LOG_FILE}"
;;
"rhel-9.6" | "rhel-9.8")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  prepareRepos |& tee -a "${LOG_FILE}"
  sudo yum install -y procps-ng zeromq-devel cyrus-sasl-devel gcc gcc-c++ git rust cargo libffi-devel libtool libxml2-devel libxslt-devel make man openssl-devel swig tar wget cmake python3-devel python3-pip bzip2-devel sqlite-devel file iproute |& tee -a "${LOG_FILE}"
  configureAndInstall |& tee -a "${LOG_FILE}"
;;
"rhel-10.0" | "rhel-10.2")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  prepareRepos |& tee -a "${LOG_FILE}"
  sudo yum install -y procps-ng zeromq-devel cyrus-sasl-devel gcc gcc-c++ git rust cargo libffi-devel libtool libxml2-devel libxslt-devel make man openssl-devel tar wget cmake python3-devel python3-pip bzip2-devel sqlite-devel file iproute autoconf automake |& tee -a "${LOG_FILE}"
  configureAndInstall |& tee -a "${LOG_FILE}"
;;
"sles-15.7" | "sles-16.0")
  printf -- "Inst  %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  sudo zypper install -y curl cyrus-sasl-devel gawk gcc gcc-c++ git openssh-clients systemd python3-devel python3-pip libopenssl-devel libxml2-devel libxslt-devel make man tar wget cmake libnghttp2-devel gdbm-devel libbz2-devel libdb-4_8-devel libffi-devel libuuid-devel ncurses-devel readline-devel sqlite3-devel tk-devel xz-devel zlib-devel gzip bzip2 cargo |& tee -a "${LOG_FILE}"
  configureAndInstall |& tee -a "${LOG_FILE}"
;;
"ubuntu-22.04" | "ubuntu-24.04" )
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  export DEBIAN_FRONTEND=noninteractive
  sudo ln -fs /usr/share/zoneinfo/UTC /etc/localtime
  echo "UTC" | sudo tee /etc/timezone
  sudo apt-get update
  sudo apt-get install -y wget g++ gcc git libffi-dev libsasl2-dev libssl-dev libxml2-dev libxslt1-dev make man tar libz-dev pkg-config apt-utils curl cmake libbz2-dev libdb-dev libgdbm-dev liblzma-dev libncurses-dev libreadline-dev libsqlite3-dev tk-dev uuid-dev xz-utils zlib1g-dev file iproute2 autoconf automake libtool |& tee -a "${LOG_FILE}"
  configureAndInstall |& tee -a "${LOG_FILE}"
;;
*)
  printf -- "%s not supported \n" "$DISTRO"|& tee -a "$LOG_FILE"
  exit 1 ;;
esac
gettingStarted |& tee -a "${LOG_FILE}"
