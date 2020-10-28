#!/usr/bin/env bash
# © Copyright IBM Corporation 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Hiredis/1.0.0/build_hiredis.sh
# Execute build script: bash build_hiredis.sh    (provide -h for help)
#


set -e -o pipefail

PACKAGE_NAME="hiredis"
PACKAGE_VERSION="1.0.0"
SOURCE_ROOT="$(pwd)"
LOG_FILE="logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
OVERRIDE=false
FORCE="false"
trap cleanup 1 2 ERR

#Check if directory exsists
if [ ! -d "logs" ]; then
   mkdir -p "logs"
fi


if [ -f "/etc/os-release" ]; then
	source "/etc/os-release"
fi

function cleanup()
{
  if [[ "${DISTRO}" == "rhel-7.6" ]] || [[ "${DISTRO}" == "rhel-7.8" ]] || [[ "${DISTRO}" == "sles-12.5" ]]; then 
    rm -rf $SOURCE_ROOT/redis-stable.tar.gz $SOURCE_ROOT/gcc/gcc-7.5.0.tar.xz 
  fi

  pgrep -d" " -f "redis-server" | xargs kill
  printf -- "Cleaned up the artifacts\n"
}

function installGCC() {
	    set +e
	    printf -- "Installing GCC 7.x \n"
	    cd $SOURCE_ROOT
	    mkdir gcc
	    cd gcc
	    wget https://ftpmirror.gnu.org/gcc/gcc-7.5.0/gcc-7.5.0.tar.xz
	    tar -xf gcc-7.5.0.tar.xz
	    cd gcc-7.5.0
	    ./contrib/download_prerequisites
	    mkdir objdir
	    cd objdir
	    ../configure --prefix=/opt/gcc --enable-languages=c,c++ --with-arch=zEC12 --with-long-double-128 --build=s390x-linux-gnu --host=s390x-linux-gnu --target=s390x-linux-gnu --enable-threads=posix --with-system-zlib --disable-multilib
	    make -j 8
	    sudo make install
	    sudo ln -sf /opt/gcc/bin/gcc /usr/bin/gcc
	    sudo ln -sf /opt/gcc/bin/g++ /usr/bin/g++
	    sudo ln -sf /opt/gcc/bin/g++ /usr/bin/c++

      gcc -v
		  printf -- "\nGCC v7.5.0 installed successfully. \n"
      set -e
}
function configureAndInstall()
{
  printf -- 'Build and install Hiredis \n'

  # Building hiredis
  cd $SOURCE_ROOT
  git clone https://github.com/redis/hiredis.git
  cd hiredis/
  git checkout v${PACKAGE_VERSION}
  make USE_SSL=1
  
  #run test
  runTest
  
  #Clean up
  cleanup

}

function runTest() {
	set +e
    if [[ "$TESTS" == "true" ]]; then
      printf -- 'Running tests \n\n'

      if [[ "${ID}" == "ubuntu" ]]; then
        #Install Redis Sever
        sudo apt-get install -y redis-server

        #start redis server
        redis-server --unixsocket /tmp/redis.sock &

      else
        if [[ ${DISTRO} =~ rhel-7\.[6-8] ]] || [[ "${DISTRO}" == "sles-12.5" ]]; then 
          #Build gcc v7.5.0

          if [[ "${DISTRO}" == "sles-12.5" ]]; then
            sudo zypper install -y glib2-devel gcc-c++
          else  
            sudo yum install -y glib2-devel libmpc-devel gcc-c++ bzip2
          fi

          installGCC
          export PATH=/opt/gcc/bin:"$PATH"
        fi

        #Build and install Redis Sever

        printf -- 'Installing Redis Server. \n'
        cd $SOURCE_ROOT
        wget http://download.redis.io/redis-stable.tar.gz
        tar xvzf redis-stable.tar.gz
        cd redis-stable

        if [[ ${DISTRO} =~ rhel-7\.[6-8] ]] || [[ "${DISTRO}" == "sles-12.5" ]]; then
          make CC=/opt/gcc/bin/gcc 
          sudo make install
        else
          make && sudo make install
        fi

        #Start redis server
        src/redis-server --unixsocket /tmp/redis.sock &

      fi

      if [ -z "$(sudo netstat -tupln | grep 6379)" ];
      then
        printf -- 'Redis is not running! redis-server should be running to run tests. \n\n'
      else
        printf -- 'Redis is running! \n'
        cd $SOURCE_ROOT/hiredis
        ./hiredis-test
        printf -- 'Test Completed \n\n'
      fi
          
    fi

  set -e
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
  echo " Usage: "
  echo "  install.sh [-d debug] [-t install-with-tests] [-y install-without-confirmation]"
  echo ""
  echo " Note: Redis server should be running to run tests."
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
  printf -- "  Hiredis installed successfully. \n"
  printf -- '\n'
}

logDetails

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-18.04" | "ubuntu-20.04")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  sudo apt-get update > /dev/null
  sudo apt-get install -y git gcc g++ make libssl-dev net-tools wget tar |& tee -a "${LOG_FILE}"
  configureAndInstall |& tee -a "${LOG_FILE}"
  ;;

"rhel-7.6" | "rhel-7.7" | "rhel-7.8" | "rhel-8.1" | "rhel-8.2")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	sudo yum install -y  git gcc make openssl-devel net-tools wget tar procps bzip2  |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
  ;;
"sles-12.5")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  sudo zypper  install -y  git gcc make libopenssl-devel net-tools wget tar  |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
  ;;
"sles-15.1" | "sles-15.2")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	sudo zypper  install -y  git gcc make libopenssl-devel gawk net-tools-deprecated wget tar gzip |& tee -a "${LOG_FILE}" 
	configureAndInstall |& tee -a "${LOG_FILE}"
  ;;

*)
  printf -- "%s not supported \n" "$DISTRO"|& tee -a "$LOG_FILE"
  exit 1 ;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
