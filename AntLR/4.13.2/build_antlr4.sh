#!/bin/bash
# ©  Copyright IBM Corporation 2024.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/antlr/4.13.2/build_antlr4.sh
# Execute build script: bash build_antlr4.sh    (provide -h for help)
#

set -e -o pipefail

PACKAGE_NAME='antlr4'
PACKAGE_VERSION='4.13.2'
FORCE="false"
FULL="false"
TESTS='false'
SOURCE_ROOT="$(pwd)"
LOG_FILE="$SOURCE_ROOT/logs/$PACKAGE_NAME-$PACKAGE_VERSION-$(date +"%F-%T").log"
JAVA_PROVIDED='OpenJDK11'
BUILD_ENV="$HOME/setenv.sh"
GOLANG_VERSION='1.19.5'
GO_URL="https://golang.org/dl/go$GOLANG_VERSION.linux-s390x.tar.gz"
GO_DEFAULT="$SOURCE_ROOT/go"
OPENSSL_VERSION='openssl-1.1.1h'
OPENSSL_URL="https://www.openssl.org/source/$OPENSSL_VERSION.tar.gz"
PYTHON_VERSION='3.8.8'
PYTHON_URL="https://www.python.org/ftp/python/$PYTHON_VERSION/Python-$PYTHON_VERSION.tgz"
CMAKE_VERSION='3.24.2'
CMAKE_URL="https://github.com/Kitware/CMake/releases/download/v$CMAKE_VERSION/cmake-$CMAKE_VERSION.tar.gz"
LLVM_VERSION='8.0.1'
LLVM_URL="https://github.com/llvm/llvm-project/releases/download/llvmorg-$LLVM_VERSION/llvm-$LLVM_VERSION.src.tar.xz"
CLANG_VERSION=$LLVM_VERSION
CLANG_URL="https://github.com/llvm/llvm-project/releases/download/llvmorg-$CLANG_VERSION/cfe-$CLANG_VERSION.src.tar.xz"
NODEJS_VERSION='v16.17.1'
NODEJS_URL="https://nodejs.org/dist/$NODEJS_VERSION/node-$NODEJS_VERSION-linux-s390x.tar.xz"
MAVEN_VERSION='3.8.6'
MAVEN_URL="https://archive.apache.org/dist/maven/maven-3/$MAVEN_VERSION/binaries/apache-maven-$MAVEN_VERSION-bin.tar.gz"
ANTLR_SOURCE_URL="https://github.com/antlr/$PACKAGE_NAME/archive/$PACKAGE_VERSION.zip"

trap cleanup 1 2 ERR

#Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
        mkdir -p "$SOURCE_ROOT/logs/"
fi

if [ -f "/etc/os-release" ]; then
        source "/etc/os-release"
fi

function prepare() {
        if command -v "sudo" >/dev/null; then
                printf -- 'Sudo : Yes\n'
        else
                printf -- 'Sudo : No \n'
                printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n'
                exit 1
        fi

        if [[ "$JAVA_PROVIDED" != "Temurin11" && "$JAVA_PROVIDED" != "Temurin17" && "$JAVA_PROVIDED" != "Temurin21" && "$JAVA_PROVIDED" != "Semeru11" && "$JAVA_PROVIDED" != "Semeru17" && "$JAVA_PROVIDED" != "Semeru21" && "$JAVA_PROVIDED" != "OpenJDK11" && "$JAVA_PROVIDED" != "OpenJDK17" && "$JAVA_PROVIDED" != "OpenJDK21" ]]; then
                printf "$JAVA_PROVIDED is not supported, Please use valid java from {Temurin11, Temurin17, Temurin21, Semeru11, Semeru17, Semeru21, OpenJDK11, OpenJDK17, OpenJDK21} only"
                exit 1
        fi

        if [[ "$FULL" == "true" ]]; then
                LOG_FILE="$SOURCE_ROOT/logs/$PACKAGE_NAME-$PACKAGE_VERSION-$JAVA_PROVIDED-FULL-$(date +"%F-%T").log"
        else
                LOG_FILE="$SOURCE_ROOT/logs/$PACKAGE_NAME-$PACKAGE_VERSION-$JAVA_PROVIDED-$(date +"%F-%T").log"
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
                                printf -- 'User responded with Yes. \n' |& tee -a "$LOG_FILE"
                                break
                                ;;
                        [Nn]*) exit ;;
                        *) echo "Please provide confirmation to proceed." ;;
                        esac
                done
        fi

        if [[ "$FORCE" == "true" ]] && [[ "$FULL" == "true" ]]; then
                printf -- 'Force attribute provided continuing with FULL BUILD without confirmation\n' |& tee -a "$LOG_FILE"
        else
                if [[ "$FULL" == "true" ]]; then
                        printf -- '\nFull build selected. [-f] \n' |& tee -a "$LOG_FILE"
                        printf -- "This will build all AntLR-4 runtimes.\n"
                        printf -- "This process will take a while longer and install additional packages.\n\n"
                        while true; do
                                read -r -p "Do you wish to continue (y/n) ? :  " yn
                                case $yn in
                                [Yy]*)
                                        printf -- 'User responded with Yes. \n' |& tee -a "$LOG_FILE"
                                        break
                                        ;;
                                [Nn]*) exit ;;
                                *) echo "Please provide confirmation to proceed." ;;
                                esac
                        done
                fi
        fi
        # zero out
        true > "$BUILD_ENV"
}

function cleanup() {
        sudo rm -rf \
          "$SOURCE_ROOT/antlrtest" \
          "$SOURCE_ROOT/go$GOLANG_VERSION.linux-s390x.tar.gz"* \
          "$SOURCE_ROOT/node-$NODEJS_VERSION-linux-s390x.tar.xz"* \
          "$SOURCE_ROOT/apache-maven-$MAVEN_VERSION-bin.tar.gz"* \
          "$SOURCE_ROOT/openssl-$OPENSSL_VERSION.tar.gz"* \
          "$SOURCE_ROOT/llvm-$LLVM_VERSION.src.tar.gz"* \
          "$SOURCE_ROOT/cfe-$CLANG_VERSION.src.tar.gz"* \
          "$SOURCE_ROOT/cmake-$CMAKE_VERSION.tar.gz"* \
          "$SOURCE_ROOT/Python-$PYTHON_VERSION.tgz"* \
          "$SOURCE_ROOT/OpenJDK11U-jdk_s390x_linux_hotspot_11.0.24_8.tar.gz"* \
          "$SOURCE_ROOT/OpenJDK17U-jdk_s390x_linux_hotspot_17.0.12_7.tar.gz"* \
          "$SOURCE_ROOT/OpenJDK21U-jdk_s390x_linux_hotspot_21.0.4_7.tar.gz"* \
          "$SOURCE_ROOT/ibm-semeru-open-jdk_s390x_linux_11.0.24_8_openj9-0.46.0.tar.gz"* \
          "$SOURCE_ROOT/ibm-semeru-open-jdk_s390x_linux_17.0.12_7_openj9-0.46.0.tar.gz"* \
          "$SOURCE_ROOT/ibm-semeru-open-jdk_s390x_linux_21.0.4_7_openj9-0.46.0.tar.gz"*

        printf -- 'Cleaned up the artifacts\n' >>"$LOG_FILE"
}

function configureAndInstallJava() {
    printf -- 'Configuring and Installing of Java started \n'

    if [[ "$JAVA_PROVIDED" == "Temurin11" ]]; then
        # Install Temurin 11
        printf -- "\nInstalling Temurin 11 . . . \n"
        cd $SOURCE_ROOT
        wget https://github.com/adoptium/temurin11-binaries/releases/download/jdk-11.0.24%2B8/OpenJDK11U-jdk_s390x_linux_hotspot_11.0.24_8.tar.gz
        tar -xzf OpenJDK11U-jdk_s390x_linux_hotspot_11.0.24_8.tar.gz
        export ANT_JAVA_HOME=$PWD/jdk-11.0.24+8
        export JAVA_HOME=$PWD/jdk-11.0.24+8
        printf -- "Installation of Temurin 11 is successful\n" >> "$LOG_FILE"

    elif [[ "$JAVA_PROVIDED" == "Temurin17" ]]; then
        # Install Temurin 17
        printf -- "\nInstalling Temurin 17 . . . \n"
        cd $SOURCE_ROOT
        wget https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.12%2B7/OpenJDK17U-jdk_s390x_linux_hotspot_17.0.12_7.tar.gz
        tar -xzf OpenJDK17U-jdk_s390x_linux_hotspot_17.0.12_7.tar.gz
        export ANT_JAVA_HOME=$PWD/jdk-17.0.12+7
        export JAVA_HOME=$PWD/jdk-17.0.12+7
        printf -- "Installation of Temurin17 is successful\n" >> "$LOG_FILE"

    elif [[ "$JAVA_PROVIDED" == "Temurin21" ]]; then
        # Install Temurin 21
        printf -- "\nInstalling Temurin 21 . . . \n"
        cd $SOURCE_ROOT
        wget https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.4%2B7/OpenJDK21U-jdk_s390x_linux_hotspot_21.0.4_7.tar.gz
        tar -xzf OpenJDK21U-jdk_s390x_linux_hotspot_21.0.4_7.tar.gz
        export ANT_JAVA_HOME=$PWD/jdk-21.0.4+7
        export JAVA_HOME=$PWD/jdk-21.0.4+7
        printf -- "Installation of Temurin21 is successful\n" >> "$LOG_FILE"

    elif [[ "$JAVA_PROVIDED" == "Semeru11" ]]; then
        # Install Semeru 11
        printf -- "\nInstalling Semeru 11 . . . \n"
        cd $SOURCE_ROOT
        wget https://github.com/ibmruntimes/semeru11-binaries/releases/download/jdk-11.0.24%2B8_openj9-0.46.0/ibm-semeru-open-jdk_s390x_linux_11.0.24_8_openj9-0.46.0.tar.gz
        tar -xzf ibm-semeru-open-jdk_s390x_linux_11.0.24_8_openj9-0.46.0.tar.gz
        export ANT_JAVA_HOME=$PWD/jdk-11.0.24+8
        export JAVA_HOME=$PWD/jdk-11.0.24+8
        printf -- "Installation of Semeru 11 is successful\n" >> "$LOG_FILE"

    elif [[ "$JAVA_PROVIDED" == "Semeru17" ]]; then
        # Install Semeru 17
        printf -- "\nInstalling Semeru 17 . . . \n"
        cd $SOURCE_ROOT
        wget https://github.com/ibmruntimes/semeru17-binaries/releases/download/jdk-17.0.12%2B7_openj9-0.46.0/ibm-semeru-open-jdk_s390x_linux_17.0.12_7_openj9-0.46.0.tar.gz
        tar -xzf ibm-semeru-open-jdk_s390x_linux_17.0.12_7_openj9-0.46.0.tar.gz
        export ANT_JAVA_HOME=$PWD/jdk-17.0.12+7
        export JAVA_HOME=$PWD/jdk-17.0.12+7
        printf -- "Installation of Semeru 17 is successful\n" >> "$LOG_FILE"

    elif [[ "$JAVA_PROVIDED" == "Semeru21" ]]; then
        # Install Semeru 21
        printf -- "\nInstalling Semeru 21 . . . \n"
        cd $SOURCE_ROOT
        wget https://github.com/ibmruntimes/semeru21-binaries/releases/download/jdk-21.0.4%2B7_openj9-0.46.0/ibm-semeru-open-jdk_s390x_linux_21.0.4_7_openj9-0.46.0.tar.gz
        tar -xzf ibm-semeru-open-jdk_s390x_linux_21.0.4_7_openj9-0.46.0.tar.gz
        export ANT_JAVA_HOME=$PWD/jdk-21.0.4+7
        export JAVA_HOME=$PWD/jdk-21.0.4+7
        printf -- "Installation of Semeru 21 is successful\n" >> "$LOG_FILE"

    elif [[ "$JAVA_PROVIDED" == "OpenJDK21" ]]; then
        printf -- "\nInstalling OpenJDK 21 . . . \n"
        if [[ "$ID" == "ubuntu" ]]; then
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-21-jre openjdk-21-jdk
            export ANT_JAVA_HOME=/usr/lib/jvm/java-21-openjdk-s390x
            export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-s390x
        elif [[ "$ID" == "rhel" ]]; then
            sudo yum install -y java-21-openjdk-devel
            export ANT_JAVA_HOME=/usr/lib/jvm/java-21-openjdk
            export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
        elif [[ "$ID" == "sles" ]]; then
            sudo zypper install -y java-21-openjdk java-21-openjdk-devel
            export ANT_JAVA_HOME=/usr/lib64/jvm/java-21-openjdk
            export JAVA_HOME=/usr/lib64/jvm/java-21-openjdk
        fi
        printf -- "Installation of OpenJDK 21 is successful\n" >> "$LOG_FILE"

    elif [[ "$JAVA_PROVIDED" == "OpenJDK17" ]]; then
        printf -- "\nInstalling OpenJDK 17 . . . \n"
        if [[ "$ID" == "ubuntu" ]]; then
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-17-jre openjdk-17-jdk
            export ANT_JAVA_HOME=/usr/lib/jvm/java-17-openjdk-s390x
            export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-s390x
        elif [[ "$ID" == "rhel" ]]; then
            sudo yum install -y java-17-openjdk-devel
            export ANT_JAVA_HOME=/usr/lib/jvm/java-17-openjdk
            export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
        elif [[ "$ID" == "sles" ]]; then
            sudo zypper install -y java-17-openjdk java-17-openjdk-devel
            export ANT_JAVA_HOME=/usr/lib64/jvm/java-17-openjdk
            export JAVA_HOME=/usr/lib64/jvm/java-17-openjdk
        fi
        printf -- "Installation of OpenJDK 17 is successful\n" >> "$LOG_FILE"

    elif [[ "$JAVA_PROVIDED" == "OpenJDK11" ]]; then
         printf -- "\nInstalling OpenJDK 11 . . . \n"
        if [[ "$ID" == "ubuntu" ]]; then
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-11-jre openjdk-11-jdk
            export ANT_JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x
            export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x
        elif [[ "$ID" == "rhel" ]]; then
            sudo yum install -y java-11-openjdk-devel
            export ANT_JAVA_HOME=/usr/lib/jvm/java-11-openjdk
            export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
        elif [[ "$ID" == "sles" ]]; then
            sudo zypper install -y java-11-openjdk java-11-openjdk-devel
            export ANT_JAVA_HOME=/usr/lib64/jvm/java-11-openjdk
            export JAVA_HOME=/usr/lib64/jvm/java-11-openjdk
        fi
        printf -- "Installation of OpenJDK 11 is successful\n" >> "$LOG_FILE"

    else
        printf "$JAVA_PROVIDED is not supported, Please use valid variant from {Temurin11, Temurin17, Temurin21, Semeru11, Semeru17, Semeru21, OpenJDK11, OpenJDK17, OpenJDK21} only"
        exit 1
    fi

    printf -- "export ANT_JAVA_HOME=$ANT_JAVA_HOME\n" >> "$BUILD_ENV"

    export PATH=$ANT_JAVA_HOME/bin:$PATH
    printf -- "export PATH=$PATH\n" >> "$BUILD_ENV"
    java -version |& tee -a "$LOG_FILE"
}

function onlyJavaRuntime() {
    # Downloading and installing Antlr
    printf -- '\nDownloading and installing AntLR-4 Java Runtime.\n'
    cd $SOURCE_ROOT
    curl -s -S -L -O https://www.antlr.org/download/antlr-$PACKAGE_VERSION-complete.jar
    JAR=$PWD/antlr-$PACKAGE_VERSION-complete.jar
    export CLASSPATH=".:$JAR:$CLASSPATH"
    printf -- "export CLASSPATH=$CLASSPATH\n" >> "$BUILD_ENV"
}

function validateJavaRuntime() {
    cd $SOURCE_ROOT
    if [ ! -d antlrtest ]; then
        mkdir -p antlrtest
    fi
    cd antlrtest
    cat > Hello.g4 <<'EOF'
  grammar Hello;
  r  : 'hello' ID ;
  ID : [a-z]+ ;
  WS : [ \t\r\n]+ -> skip ;
EOF

    java -Xmx500M -cp $CLASSPATH org.antlr.v4.Tool Hello.g4
    javac Hello*.java
    GRUN=$(java -Xmx500M -cp $CLASSPATH org.antlr.v4.gui.TestRig Hello r -tree <<<"hello world")
    COMP_VALUE='(r hello world)'
    ret=$(diff -wd <(echo "$GRUN") <(echo "$COMP_VALUE"))
}

function installAdditionalDependencies() {
  case "$DISTRO" in
  "rhel-8.10")
    printf -- "Installing additional dependencies for %s %s on %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO"
    sudo yum install -y unzip xz libuuid-devel curl wget git make diffutils gcc gcc-c++ python2 python38 cmake \
      libarchive clang
    ;;

  "rhel-9.4" | "rhel-9.5")
    printf -- "Installing additional dependencies for %s %s on %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO"
    sudo yum install -y unzip xz libuuid-devel curl wget git make diffutils gcc gcc-c++ python3 cmake libarchive clang
    ;;


  "sles-15.6")
    printf -- "Installing additional dependencies for %s %s on %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO"
    sudo zypper install -y unzip xz xz-devel libuuid-devel curl wget git make diffutils gcc13 gcc13-c++ \
    python cmake clang13 gawk gdbm-devel libbz2-devel libdb-4_8-devel libffi-devel libnsl-devel libopenssl-devel \
    libuuid-devel make ncurses-devel readline-devel sqlite3-devel tar tk-devel zlib-devel gzip

    #switch to GCC 13
    sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-13 40
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-13 40
    sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-13 40
    sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-13 40
    ;;

  "ubuntu-22.04")
    printf -- "Installing additional dependencies for %s %s on %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO"
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive TZ=America/Toronto apt-get install -y unzip xz-utils uuid-dev curl wget git \
    make python2 bzip2 tk-dev libghc-bzlib-dev gcc g++ cmake clang pkg-config
    ;;

  "ubuntu-24.04" | "ubuntu-24.10")
    printf -- "Installing additional dependencies for %s %s on %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO"
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive TZ=America/Toronto apt-get install -y unzip xz-utils uuid-dev curl wget git \
    make bzip2 tk-dev libghc-bzlib-dev gcc g++ cmake clang pkg-config
    ;;

  *)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
  esac
}

function installGO() {
  printf -- "\nInstalling Go ... \n" | tee -a "$LOG_FILE"
  cd $SOURCE_ROOT
  wget $GO_URL
  tar -xzf "go$GOLANG_VERSION.linux-s390x.tar.gz"

  export GOROOT="$GO_DEFAULT"
  printf -- "export GOROOT=$GOROOT\n" >> "$BUILD_ENV"

  sudo cp $GO_DEFAULT/bin/go /usr/bin/
  sudo cp $GO_DEFAULT/bin/gofmt /usr/bin/
  export CC=gcc
  printf -- "export CC=gcc\n" >> "$BUILD_ENV"

  go env -w GO111MODULE=auto
  printf -- "go env -w GO111MODULE=auto\n" >> "$BUILD_ENV"
}

function installNodeJS() {
  cd $SOURCE_ROOT
  curl -s -S -L -O $NODEJS_URL
  tar xJf "node-$NODEJS_VERSION-linux-s390x.tar.xz"
}

function installMaven() {
  cd $SOURCE_ROOT
  curl -s -S -L -O $MAVEN_URL
  tar xzf "apache-maven-$MAVEN_VERSION-bin.tar.gz"
}

function downloadAntlrSource() {
  cd $SOURCE_ROOT
  curl -s -S -L -o "$PACKAGE_NAME-$PACKAGE_VERSION.zip" $ANTLR_SOURCE_URL
  unzip -o -q "$PACKAGE_NAME-$PACKAGE_VERSION.zip"
}

function fullBuildAllRuntimes() {
  installGO
  installNodeJS
  installMaven
  cd $SOURCE_ROOT
  export PATH=$PWD/node-$NODEJS_VERSION-linux-s390x/bin:$PWD/apache-maven-$MAVEN_VERSION/bin:$PATH
  printf -- "export PATH=$PATH\n" >> "$BUILD_ENV"

  downloadAntlrSource
  export MAVEN_OPTS="-Xmx1G"
  printf -- 'export MAVEN_OPTS="-Xmx1G"\n' >> "$BUILD_ENV"

  cd $SOURCE_ROOT
  cd $PACKAGE_NAME-$PACKAGE_VERSION
  mvn install -DskipTests=true
  cd runtime/Cpp
  mkdir -p build && mkdir -p run
  cd build
  cmake -DWITH_LIBCXX=Off -DCMAKE_BUILD_TYPE=release ../
  make -j$(nproc)
  DESTDIR=$PWD/../run make install
}

function runFullBuildTests() {
  set +e
  printf -- 'Running tests \n\n'
  export MAVEN_OPTS="-Xmx1G"
  cd $SOURCE_ROOT
  cd $PACKAGE_NAME-$PACKAGE_VERSION/runtime-testsuite
  mvn -Dtest=java.** test
  if [[ "$DISTRO" != "rhel-9."* ]] && [[ "$DISTRO" != "sles-15."* ]] && [[ "$DISTRO" != "ubuntu-24.04" ]] && [[ "$DISTRO" != "ubuntu-24.10" ]]; then
    mvn -Dtest=python2.** test     # except for RHEL 9.x, SLES 15.x and Ubuntu 24.x as Python 2 has been removed from these distros
  fi
  mvn -Dtest=python3.** test
  sudo env "PATH=$PATH" "GOROOT=$GOROOT" mvn -Dtest=go.** test
  mvn -Dtest=javascript.** test
  mvn -Dtest=cpp.** test
  set -e
}

function configureAndInstall() {
    printf -- 'Configuration and Installation started \n'

    configureAndInstallJava

    if [[ "$FULL" == "true" ]]; then
      cd $SOURCE_ROOT && rm -rf "$SOURCE_ROOT/antlr-$PACKAGE_VERSION-complete.jar"
      installAdditionalDependencies
      fullBuildAllRuntimes
      if [[ "$TESTS" == "true" ]]; then
        runFullBuildTests
      fi
    else
      onlyJavaRuntime
      if [[ "$TESTS" == "true" ]]; then
        validateJavaRuntime
      fi
    fi

    # Cleanup
    cleanup

    # Verifying AntLR-4 installation
    shopt -s expand_aliases
    alias antlr4="java -Xmx500M -cp $CLASSPATH org.antlr.v4.Tool"
    printf -- "alias antlr4='java -Xmx500M -cp $CLASSPATH org.antlr.v4.Tool'\n" >> "$BUILD_ENV"
    if command -v "$PACKAGE_NAME" >/dev/null; then
        printf -- "\n%s installation completed. Please check the Usage to start the service.\n\n" "$PACKAGE_NAME"
    else
        printf -- "Error while installing %s, exiting with 127 \n" "$PACKAGE_NAME"
        exit 127
    fi
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
        echo "  bash build_antrl4.sh  [-d debug] [-y install-without-confirmation] [-f full-build (All Antlr runtimes)] [-t run-tests] [-j Java to use from {Semeru11, Semeru17, Semeru21, Temurin11, Temurin17, Temurin21, OpenJDK11, OpenJDK17, OpenJDK21}]"
        echo "  default: If no -j specified, OpenJDK 11 will be installed"
        echo
}

while getopts "h?dyftj:" opt; do
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
        f)
                FULL="true"
                ;;
        t)
                TESTS="true"
                ;;
        j)
                JAVA_PROVIDED="$OPTARG"
                ;;
        esac
done

function gettingStarted() {
        printf -- '\n********************************************************************************************************\n'
        printf -- "\n* Getting Started * \n"
        printf -- "Note: Environmental Variables needed have been added to $HOME/setenv.sh\n"
        printf -- "Note: To set the Environmental Variables needed for $PACKAGE_NAME, please run:\nsource $HOME/setenv.sh \n"
        printf -- "Run $PACKAGE_NAME: \n"
        printf -- "    $PACKAGE_NAME \n\n"
        printf -- '********************************************************************************************************\n'
}

###############################################################################################################

prepare
logDetails

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"rhel-8.10" | "rhel-9.4" | "rhel-9.5")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        sudo yum install -y wget tar which curl diffutils --allowerasing |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

"sles-15.6")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        sudo zypper install -y wget gzip tar curl xz diffutils |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

"ubuntu-22.04" | "ubuntu-24.04" | "ubuntu-24.10")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        sudo apt-get update
        sudo DEBIAN_FRONTEND=noninteractive TZ=America/Toronto apt-get install -y wget tar curl diffutils |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;

*)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
        exit 1
        ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
