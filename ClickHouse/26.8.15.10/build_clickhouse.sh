#!/bin/bash
# © Copyright IBM Corporation 2026
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ClickHouse/26.8.15.10/build_clickhouse.sh
# Execute build script: bash build_clickhouse.sh    (provide -h for help)
#==============================================================================
USER_IN_GROUP_DOCKER=$(id -nGz "$USER" | tr '\0' '\n' | grep -c '^docker$')
set -e -o pipefail

PACKAGE_NAME="ClickHouse"
PACKAGE_VERSION="v26.8.15.10-lts"
SOURCE_ROOT="$(pwd)"
PATCH_VERSION="${PACKAGE_VERSION:1:-4}"
# Build artifacts always have a final "tweak" version of '1' for local builds without git history
ARTIFACTS_VERSION="${PATCH_VERSION%.*}.1"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ClickHouse/${PATCH_VERSION}/patch"

FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

#==============================================================================
mkdir -p "$SOURCE_ROOT/logs"

error() {
  echo "Error: ${*}"
  exit 1
}
errlog() {
  echo "Error: ${*}" |& tee -a "$LOG_FILE"
  exit 1
}
msg() { echo "${*}"; }
log() { echo "${*}" >>"$LOG_FILE"; }
msglog() { echo "${*}" |& tee -a "$LOG_FILE"; }

trap cleanup 0 1 2 ERR

#==============================================================================
# Set the Distro ID
if [ -f "/etc/os-release" ]; then
  source "/etc/os-release"
else
  error "Unknown distribution"
fi
DISTRO="$ID-$VERSION_ID"

#==============================================================================
checkPrequisites() {
  if command -v "sudo" >/dev/null; then
    msglog "Sudo : Yes"
  else
    msglog "Sudo : No "
    error "sudo is required. Install using apt, yum or zypper based on your distro."
  fi

  if command -v "docker" >/dev/null; then
      printf -- 'Docker : Yes\n' >>"$LOG_FILE"
  else
      printf -- 'Docker : No \n' >>"$LOG_FILE"
      printf -- 'Please install Docker based on your distro. \n'
      exit 1
  fi

  if [[ "$USER_IN_GROUP_DOCKER" == "1" ]]; then
      printf "User %s belongs to group docker\n" "$USER" |& tee -a "${LOG_FILE}"
  else
      printf "Please ensure User %s belongs to group docker.\n" "$USER" |& tee -a "${LOG_FILE}"
      exit 1
  fi

  if [[ "$FORCE" == "true" ]]; then
    msglog "Force - install without confirmation message"
  else
    # Ask user for prerequisite installation
    msg "As part of the installation , dependencies would be installed/upgraded."
    while true; do
      read -r -p "Do you want to continue (y/n) ? : " yn
      case $yn in
      [Yy]*)
        log "User responded with Yes."
        break
        ;;
      [Nn]*) exit ;;
      *) msg "Please provide confirmation to proceed." ;;
      esac
    done
  fi
}

#==============================================================================
cleanup() {
  true
}

#==============================================================================
# Build and install pkgs common to all distros.
#
configureAndInstall() {
  msg "Configuration and Installation started"


  #----------------------------------------------------------
  msg "Cloning ClickHouse $PACKAGE_VERSION"

  cd "$SOURCE_ROOT"/
  rm -rf ClickHouse
  retry git clone --recurse-submodules --shallow-submodules --depth 1 --jobs $(( $(nproc) - 1 )) -b ${PACKAGE_VERSION} https://github.com/ClickHouse/ClickHouse.git
  cd ClickHouse

  # Apply patches to add s390x support to the ClickHouse CI build system
  curl -sSL $PATCH_URL/clickhouse-ci.patch | git apply -
  # Apply patches to add s390x support to the ClickHouse source
  curl -sSL $PATCH_URL/clickhouse.patch | git apply -

  # Fix s390x sysroot which is missing an empty lib dir
  mkdir -p contrib/sysroot/linux-s390x/s390x-linux-gnu/libc/usr/lib

  msg "Building ClickHouse build environment docker images"
  buildBuilderImages

  msg "Building ClickHouse"
  cd "$SOURCE_ROOT/ClickHouse"
  python3 -m ci.praktika run --docker "clickhouse/binary-builder:latest" --param=cmake "Build (s390x_release)"

  msg "Building ClickHouse docker image"
  cd "$SOURCE_ROOT/ClickHouse"
  buildDockerImage

  msg "Build completed"

  cd "$SOURCE_ROOT/ClickHouse"
  runTest
}

patchDockerfileIds() {
  cd "$SOURCE_ROOT/ClickHouse"
  # Some Dockerfiles hard-code uid/gid 1000; patch them to match the current user to ensure files can be created
  # with the correct permissions.
  local new_uid=$(id -u)
  local new_gid=$(id -g)
  sed -i \
    -e "s/addgroup --gid 1000 clickhouse && adduser --uid 1000 --gid 1000 --disabled-password clickhouse$/addgroup --gid $new_gid clickhouse \&\& adduser --uid $new_uid --gid $new_gid --disabled-password clickhouse/g" \
    -e "s/addgroup --gid 1001 clickhouse2 && adduser --uid 1001 --gid 1001 --disabled-password clickhouse2$/addgroup --gid $(( $new_gid + 1 )) clickhouse2 \&\& adduser --uid $(( $new_uid + 1 )) --gid $(( $new_gid + 1 )) --disabled-password clickhouse2/g" \
    -e "s/groupadd --system --gid 1000 clickhouse/groupadd --system --gid $new_gid clickhouse/g" \
    -e "s/useradd --system --gid 1000 --uid 1000 -m clickhouse/useradd --system --gid $new_gid --uid $new_uid -m clickhouse/g" "$1"
}

buildBuilderImages() {
  cd "$SOURCE_ROOT/ClickHouse"
  patchDockerfileIds ci/docker/fasttest/Dockerfile
  # Build docker images needed by binary-builder
  # Note: fasttest and cctools have a recursive dependency on each other so fasttest needs to be built twice
  cd ci/docker/fasttest/
  docker build --network=host --progress=plain --build-arg=CCTOOLS_AVAILABLE=without-cctools -t clickhouse/fasttest .
  cd ../cctools/
  docker build --network=host --progress=plain --build-arg=CCTOOLS_AVAILABLE=without-cctools -t clickhouse/cctools .
  cd ../fasttest/
  docker build --network=host --progress=plain --build-arg=CCTOOLS_TAG=latest -t clickhouse/fasttest .
  cd ../binary-builder/
  docker build --network=host --progress=plain --build-arg=FROM_TAG=latest --build-arg=CCTOOLS_TAG=latest --build-arg=TOOLCHAIN_COMMIT=none -t clickhouse/binary-builder .
  cd "$SOURCE_ROOT/ClickHouse"
}

buildDockerImage() {
  cd "$SOURCE_ROOT/ClickHouse/ci/tmp/"
  local deb_urls="\
http://host.docker.internal:8888/clickhouse-common-static_${ARTIFACTS_VERSION}_s390x.deb \
http://host.docker.internal:8888/clickhouse-server_${ARTIFACTS_VERSION}_s390x.deb \
http://host.docker.internal:8888/clickhouse-client_${ARTIFACTS_VERSION}_s390x.deb"

  python3 -m http.server 8888 > /dev/null 2>&1 &
  SERVER_PID=$!

  cd "$SOURCE_ROOT/ClickHouse/docker/server/"
  docker build --progress=plain --add-host=host.docker.internal:host-gateway --build-arg=DIRECT_DOWNLOAD_URLS="${deb_urls}" -t "clickhouse-server:${PACKAGE_VERSION}" .

  kill $SERVER_PID
  cd "$SOURCE_ROOT/ClickHouse/"
}

buildTestImages() {
  cd "$SOURCE_ROOT/ClickHouse"
  patchDockerfileIds ci/docker/stateless-test/Dockerfile
  # Build docker images needed by stateless-test
  cd ci/docker/test-base/
  docker build --network=host --progress=plain --build-arg=CCTOOLS_TAG=latest -t clickhouse/test-base .
  cd ../stateless-test/
  docker build --network=host --progress=plain --build-arg=MINIO_SOURCE=local --build-arg=CCTOOLS_TAG=latest -t clickhouse/stateless-test .
  cd "$SOURCE_ROOT/ClickHouse"
}

prepareTestEnvironment() {
  cd "$SOURCE_ROOT/ClickHouse"
  # Stateless tests expect the `ci/tmp` dir to contain the clickhouse binary.
  # Temporarily move the current `ci/tmp` dir which contains the build artifacts
  # out of the way.
  rm -rf ci/tmp-build/
  mv ci/tmp/ ci/tmp-build/
  mkdir -p ci/tmp
  cp ci/tmp-build/build/programs/clickhouse ci/tmp/
}

saveTestEnvironment() {
  local test_type="$1"
  cd "$SOURCE_ROOT/ClickHouse"
  rm -rf ci/tmp-${test_type}/
  mv ci/tmp/ ci/tmp-${test_type}/
  mkdir -p ci/tmp
  cp ci/tmp-build/build/programs/clickhouse ci/tmp/
  # Some stateless test leave files behind. Clean up the known ones.
  sudo rm -rf 03371_qbit_read_write_test_* __cache__/ disks/ queries_* ssh_key tests/queries/0_stateless/00408_test_* uuid_test_* || true
}

restoreBuildEnvironment() {
  cd "$SOURCE_ROOT/ClickHouse"
  rm -rf ci/tmp/
  mv ci/tmp-build/ ci/tmp/
}

#==============================================================================
runTest() {
  if [[ "$TESTS" == "true" ]]; then
    msg "TEST Flag is set, continue with running test "

    cd "$SOURCE_ROOT/ClickHouse"
    buildTestImages

    cd "$SOURCE_ROOT/ClickHouse"
    # Randomized test settings in the stateless tests can cause the tests to run very slowly
    # and doesn't provide any value outside of ClickHouse CI. Disable it here.
    sed -i \
      's/runner_options\s*=\s*""/runner_options = " --no-random-settings --no-random-merge-tree-settings "/' \
      ci/jobs/functional_tests.py

    cd "$SOURCE_ROOT/ClickHouse"
    prepareTestEnvironment

    set +e
    python3 -m ci.praktika run --docker "clickhouse/stateless-test:latest" "Stateless tests (s390x_binary, parallel)"
    set -e
    saveTestEnvironment "parallel"

    set +e
    python3 -m ci.praktika run --docker "clickhouse/stateless-test:latest" "Stateless tests (s390x_binary, sequential)"
    set -e
    saveTestEnvironment "sequential"

    restoreBuildEnvironment
    msg "Test execution completed. "
  fi
}

#==============================================================================
logDetails() {
  log "**************************** SYSTEM DETAILS ***************************"
  cat "/etc/os-release" >>"$LOG_FILE"
  cat /proc/version >>"$LOG_FILE"
  log "***********************************************************************"

  msg "Detected $PRETTY_NAME"
  msglog "Request details: PACKAGE NAME=$PACKAGE_NAME, VERSION=$PACKAGE_VERSION"
}

#==============================================================================
printHelp() {
  cat <<eof
  Usage:
  bash build_clickhouse.sh [-y] [-t]
  where:
   -y install-without-confirmation
   -t test
eof
}

###############################################################################
while getopts "h?yt" opt; do
  case "$opt" in
  h | \?)
    printHelp
    exit 0
    ;;
  y) FORCE="true" ;;
  t) TESTS="true" ;;
  esac
done

#==============================================================================
gettingStarted() {
  printf -- '\n*********************************************************************************************\n'
  printf -- "Getting Started:\n\n"
  printf -- "ClickHouse Build Successful \n"
  printf -- "ClickHouse packages can be found here: $SOURCE_ROOT/ClickHouse/ci/tmp/ \n"
  printf -- '*********************************************************************************************\n'
  printf -- '\n'
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

#==============================================================================
logDetails
checkPrequisites

msglog "Building $PACKAGE_NAME $PACKAGE_VERSION for $DISTRO"
msglog "Installing the dependencies for ClickHouse from repository"

case "$DISTRO" in
#----------------------------------------------------------

"rhel-8.10" | "rhel-9.6" | "rhel-9.8" | "rhel-10.0" | "rhel-10.2")
  PYTHON_PKG="python3"
  if [[ $DISTRO =~ ^rhel-[89] ]]; then
    PYTHON_PKG="python3.12"
  fi
  sudo yum install -y git curl wget ${PYTHON_PKG} ${PYTHON_PKG}-requests |& tee -a "$LOG_FILE"
  if [[ $PYTHON_PKG != "python3" ]]; then
    sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/${PYTHON_PKG} 1 |& tee -a "$LOG_FILE"
    sudo update-alternatives --set python3 /usr/bin/${PYTHON_PKG} |& tee -a "$LOG_FILE"
  fi

  configureAndInstall |& tee -a "$LOG_FILE"
  ;;
#----------------------------------------------------------

"sles-15.7" | "sles-16.0")
  export DOCKER_BUILDKIT=1
  PYTHON_PKG="python3"
  if [[ $DISTRO =~ ^sles-15 ]]; then
    PYTHON_PKG="python311"
    PYTHON_EXE="python3.11"
  fi
  sudo zypper install -y git curl wget ${PYTHON_PKG} ${PYTHON_PKG}-requests |& tee -a "$LOG_FILE"
  if [[ $PYTHON_PKG != "python3" ]]; then
    sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/${PYTHON_EXE} 1 |& tee -a "$LOG_FILE"
    sudo update-alternatives --set python3 /usr/bin/${PYTHON_EXE} |& tee -a "$LOG_FILE"
  fi

  configureAndInstall |& tee -a "$LOG_FILE"
  ;;
#----------------------------------------------------------

"ubuntu-22.04" | "ubuntu-24.04")
  sudo apt-get update |& tee -a "$LOG_FILE"
  sudo apt-get install -y git curl wget python3 python3-requests |& tee -a "$LOG_FILE"

  configureAndInstall |& tee -a "$LOG_FILE"
  ;;
#----------------------------------------------------------

esac

gettingStarted |& tee -a "$LOG_FILE"
