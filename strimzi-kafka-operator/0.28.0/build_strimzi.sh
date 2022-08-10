#!/bin/bash
# ©  Copyright IBM Corporation 2022.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/strimzi-kafka-operator/0.28.0/build_strimzi.sh
# Execute build script: bash build_strimzi.sh    (provide -h for help)
#

USER_IN_GROUP_DOCKER=$(id -nGz $USER | tr '\0' '\n' | grep '^docker$' | wc -l)
set -e -o pipefail

PACKAGE_NAME="strimzi-kafka-operator"
PACKAGE_VERSION="0.28.0"
PRE_PACKAGE_VERSION="0.27.1"
PRE2_PACKAGE_VERSION="0.24.0"
BRIDGE_VERSION="0.21.4"
PRE_BRIDGE_VERSION="0.21.3"
PRE2_BRIDGE_VERSION="0.20.1"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/${PACKAGE_NAME}/${PACKAGE_VERSION}/patch"
FORCE="false"
TESTS="false"
CURDIR="$(pwd)"
CURPATH="$(echo $PATH)"
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
NON_ROOT_USER="$(whoami)"
JAVA_PROVIDED="IBMSemeru11"
BUILD_ENV="$HOME/setenv.sh"
PREFIX="/usr/local"
PUSH_TO_REGISTRY="N"
INSECURE_REGISTRY="N"
REGISTRY_NEED_LOGIN="N"
BUILD_SYSTEMTESTS_DEPS="N"
DOCKER_DJSON_FILE="/etc/docker/daemon.json"
S390X_JNI_JAR_DIR="/tmp/opertemp/libs"
#export DOCKER_ORG=your_organization_name
#export DOCKER_REGISTRY=registry_url
#export REGISTRY_PASS=your_password_on_docker_registry
#export DOCKERHUB_USER=your_username
#export DOCKERHUB_PASS=your_password

trap cleanup 1 2 ERR

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
        mkdir -p "$CURDIR/logs/"
fi

if [ -f "/etc/os-release" ]; then
        source "/etc/os-release"
fi

function prepare() {
        if command -v "sudo" >/dev/null; then
                printf -- 'Sudo : Yes\n'
        else
                printf -- 'Sudo : No \n'
                printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n'
                exit 1
        fi

        if [[ "$JAVA_PROVIDED" != "IBMSemeru11" && "$JAVA_PROVIDED" != "Temurin11" && "$JAVA_PROVIDED" != "OpenJDK11" ]]; then
                printf "$JAVA_PROVIDED is not supported, Please use valid java from {IBMSemeru11, Temurin11, OpenJDK11} only\n"
                exit 1
        fi

        if [[ "$PUSH_TO_REGISTRY" == "Y" ]]; then
                if [[ "$DOCKER_REGISTRY" == "" || "$DOCKER_ORG" == "" ]]; then
                        printf "DOCKER_REGISTRY or DOCKER_ORG is not set yet, Please set up corresponding environment variables\n"
                        exit 1
                fi

                if [[ "$REGISTRY_NEED_LOGIN" == "Y" && "$REGISTRY_PASS" == "" ]]; then
                        printf "REGISTRY_PASS is not set yet, Please set up corresponding environment variables\n"
                        exit 1
                fi
        fi

        if [[ "$DOCKERHUB_USER" == "" ||  "$DOCKERHUB_PASS" == "" ]]; then
                printf "DOCKERHUB_USER or DOCKERHUB_PASS is not set yet, Please set up corresponding environment variables to avoid reaching pull rate limit on docker.io\n"
                exit 1
        fi

        if [[ "$USER_IN_GROUP_DOCKER" == "1" ]]; then
                printf "User $USER belongs to group docker\n" |& tee -a "${LOG_FILE}"
        else
                printf "Please ensure User $USER belongs to group docker\n"
                exit 1
        fi

        if [[ "$FORCE" == "true" ]]; then
                printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "${LOG_FILE}"
        else
                # Ask user for prerequisite installation
                printf -- "\nAs part of the installation, dependencies would be installed/upgraded. \n"
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

        # zero out
        true > "$BUILD_ENV"
}

function cleanup() {
        sudo rm -rf "${CURDIR}/apache-maven-3.8.4-bin.tar.gz" "${CURDIR}/cabal-install-2.0.0.1.tar.gz" "${CURDIR}/adoptjdk.tar.gz" "${CURDIR}/OpenJDK8U-jdk*.tar.gz" "${CURDIR}/openssl-1.1.1g.tar.gz" "${CURDIR}/sbt.tgz" "${CURDIR}/v2_5_9.tar.gz" "${CURDIR}/yq_linux_s390x.tar.gz" 
        printf -- 'Cleaned up the artifacts\n' >>"${LOG_FILE}"
}

function setupGCC()
{
        local GCC_VERSION=$1
        sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-$GCC_VERSION 40
        sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-$GCC_VERSION 40
        sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-$GCC_VERSION 40
        sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-$GCC_VERSION 40
}

function buildGCC()
{
        local ver=7.3.0
        local url
        printf -- "Building GCC $ver"

        cd $CURDIR
        url=http://ftp.mirrorservice.org/sites/sourceware.org/pub/gcc/releases/gcc-${ver}/gcc-${ver}.tar.gz
        curl -sSL $url | tar xzf - || error "gcc $ver"

        cd gcc-${ver}
        ./contrib/download_prerequisites
        mkdir build-gcc; cd build-gcc
        ../configure --enable-languages=c,c++ --disable-multilib
        make -j$(nproc)
        sudo make install

        sudo update-alternatives --install /usr/bin/cc cc /usr/local/bin/gcc 40
}

function buildRuby()
{
        printf -- "Building Ruby 2.5.9\n"
        cd $CURDIR
        wget https://github.com/ruby/ruby/archive/refs/tags/v2_5_9.tar.gz
        tar xvf v2_5_9.tar.gz
        cd ruby-2_5_9
        autoconf
        ./configure --prefix=$PREFIX
        make
        sudo make install
        if [[ -f "/usr/bin/ruby" ]]; then
            sudo mv /usr/bin/ruby /usr/bin/ruby.old
        fi
        if [[ -f "/usr/bin/gem" ]]; then
            sudo mv /usr/bin/gem /usr/bin/gem.old
        fi
        sudo update-alternatives --install /usr/bin/ruby ruby /usr/local/bin/ruby 40
        sudo update-alternatives --install /usr/bin/gem gem /usr/local/bin/gem 40
}

function buildOpenssl()
{
        local ver=1.1.1g
        printf -- "Building openssl $ver \n"

        cd $CURDIR
        wget --no-check-certificate https://www.openssl.org/source/old/1.1.1/openssl-${ver}.tar.gz
        tar xvf openssl-${ver}.tar.gz
        cd openssl-${ver}
        ./config --prefix=${PREFIX}
        make
        sudo make install

        sudo mkdir -p /usr/local/etc/openssl
        cd /usr/local/etc/openssl
        sudo wget --no-check-certificate https://curl.se/ca/cacert.pem
}

function buildCmake(){
        local ver=3.21.2
        printf -- "Building cmake $ver"

        cd "$CURDIR"
        URL=https://github.com/Kitware/CMake/releases/download/v${ver}/cmake-${ver}.tar.gz
        curl -sSL $URL | tar xzf - || error "cmake $ver"
        cd cmake-${ver}
        ./bootstrap
        make
        sudo make install
}

function buildZstd()
{
        local ver=1.4.9
        printf -- "Building zstd $ver"

        cd "$CURDIR"
        URL=https://github.com/facebook/zstd/releases/download/v${ver}/zstd-${ver}.tar.gz
        curl -sSL $URL | tar xzf - || error "zstd $ver"
        cd zstd-${ver}/lib
        make
        sudo make install
}

function configureAndInstall() {

        printf -- 'Configuration and Installation started \n'

        printf -- "Building rocksdbjni require java 8: Installing AdoptOpenJDK8 + OpenJ9 with Large heap \n"
        cd $CURDIR
        wget https://github.com/AdoptOpenJDK/openjdk8-binaries/releases/download/jdk8u282-b08_openj9-0.24.0/OpenJDK8U-jdk_s390x_linux_openj9_linuxXL_8u282b08_openj9-0.24.0.tar.gz
        sudo tar zxf OpenJDK8U-jdk_s390x_linux_openj9_linuxXL_8u282b08_openj9-0.24.0.tar.gz -C /opt/
        export JAVA_HOME=/opt/jdk8u282-b08
        export PATH=$JAVA_HOME/bin:$CURPATH
        printf -- "Java version is :\n"
        java -version

        # Build and Create rocksdbjni-6.x.jar for s390x
        printf -- "Installing gflags 2.0\n"
        cd $CURDIR
        git clone https://github.com/gflags/gflags.git
        cd gflags
        git checkout v2.0
        ./configure --prefix="$PREFIX"
        make
        sudo make install
        sudo ldconfig /usr/local/lib
        
        printf -- "Build and Create rocksdbjni-6.19.3.jar for s390x\n"
        cd $CURDIR
        git clone https://github.com/facebook/rocksdb.git
        cp -r rocksdb rocksdb-6.19 && cd rocksdb-6.19/
        git checkout v6.19.3
        curl -sSL https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/RocksDB/v6.19.3/patch/rocksdb.diff | patch -p1 || error "rocksdb.diff"
        curl -sSL https://github.com/facebook/rocksdb/commit/b4326b5273f677f28d5709e0f2ff86cf2d502bb3.patch | git apply --include="table/table_test.cc" - || error "c++-11 patch"
	sed -i 's/1.2.11/1.2.12/g' Makefile
	sed -i 's/c3e5e9fdd5004dcb542feda5ee4f0ff0744628baf8ed2dd5d66f8ca1197cb1a1/91844808532e5ce316b3c010929493c0244f3d37593afd6de04f71821d5136d9/g' Makefile
        PORTABLE=1 make -j$(nproc) rocksdbjavastatic
        printf -- "Built rocksdb and created rocksdbjni-6.19.3.jar successfully.\n"
        mkdir -p $S390X_JNI_JAR_DIR
        cp -f java/target/rocksdbjni-6.19.3-linux64.jar $S390X_JNI_JAR_DIR/rocksdbjni-6.19.3.jar
        sha1sum $S390X_JNI_JAR_DIR/rocksdbjni-6.19.3.jar > $S390X_JNI_JAR_DIR/rocksdbjni-6.19.3.jar.sha1
        sed -i "s/ .*$//g" $S390X_JNI_JAR_DIR/rocksdbjni-6.19.3.jar.sha1

        printf -- "Build and Create rocksdbjni-6.22.1.1.jar for s390x\n"
        cd $CURDIR
        cp -r rocksdb rocksdb-6.22 && cd rocksdb-6.22/
        git checkout v6.22.1
        curl -sSL https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/RocksDB/v6.22.1/patch/rocksdb.diff | patch -p1 || error "rocksdb_v6.22.1.diff"
        sed -i 's/1.2.11/1.2.12/g' Makefile
	sed -i 's/c3e5e9fdd5004dcb542feda5ee4f0ff0744628baf8ed2dd5d66f8ca1197cb1a1/91844808532e5ce316b3c010929493c0244f3d37593afd6de04f71821d5136d9/g' Makefile
        PORTABLE=1 make -j$(nproc) rocksdbjavastatic
        printf -- "Built rocksdb and created rocksdbjni-6.22.1.jar successfully.\n"
        cp -f java/target/rocksdbjni-6.22.1-linux64.jar $S390X_JNI_JAR_DIR/rocksdbjni-6.22.1.1.jar
        sha1sum $S390X_JNI_JAR_DIR/rocksdbjni-6.22.1.1.jar > $S390X_JNI_JAR_DIR/rocksdbjni-6.22.1.1.jar.sha1
        sed -i "s/ .*$//g" $S390X_JNI_JAR_DIR/rocksdbjni-6.22.1.1.jar.sha1

        if [[ $BUILD_SYSTEMTESTS_DEPS == "Y" ]]; then
            # Build and Create rocksdbjni-5.18.4.jar for s390x
            printf -- "Build and Create rocksdbjni-5.18.4.jar for s390x\n"
            cd $CURDIR
            mv rocksdb rocksdb-5 && cd rocksdb-5/
            git checkout v5.18.4
            sed -i '1656s/ARCH/MACHINE/g' Makefile
            PORTABLE=1 make shared_lib
            make rocksdbjava
            printf -- "Built rocksdb and created rocksdbjni-5.18.4.jar successfully.\n"
            # Store rocksdbjni.jar in a temporary directory
            cp -f java/target/rocksdbjni-5.18.4-linux64.jar $S390X_JNI_JAR_DIR/rocksdbjni-5.18.4.jar
            sha1sum $S390X_JNI_JAR_DIR/rocksdbjni-5.18.4.jar > $S390X_JNI_JAR_DIR/rocksdbjni-5.18.4.jar.sha1
            sed -i "s/ .*$//g" $S390X_JNI_JAR_DIR/rocksdbjni-5.18.4.jar.sha1

            # Build and Create zstd-jni-1.4.5-6.jar for s390x
            printf -- "Build and Create zstd-jni-1.4.5-6.jar for s390x\n"
            # Install SBT (required for Zstd JNI)
            cd $CURDIR
            wget -O sbt.tgz https://github.com/sbt/sbt/releases/download/v1.3.13/sbt-1.3.13.tgz
            tar -zxvf sbt.tgz
            export PATH=${PATH}:$CURDIR/sbt/bin/

            # Build SBT-JNI 
            cd $CURDIR
            git clone https://github.com/joprice/sbt-jni.git
            cd sbt-jni/ && git checkout v0.2.0
            sbt compile package && sbt +publishLocal

            # Build Zstd JNI
            cd $CURDIR
            git clone -b v1.4.5-6 https://github.com/luben/zstd-jni.git
            cd zstd-jni
            wget -O - "https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ApacheSpark/3.0.1/patch/ZstdBuild.diff" | git apply
            sbt compile package
            # Store zstd-jni.jar in a temporary directory
            cp -f target/zstd-jni-1.4.5-6.jar $S390X_JNI_JAR_DIR/zstd-jni-1.4.5-6.jar
            sha1sum $S390X_JNI_JAR_DIR/zstd-jni-1.4.5-6.jar > $S390X_JNI_JAR_DIR/zstd-jni-1.4.5-6.jar.sha1
            sed -i "s/ .*$//g" $S390X_JNI_JAR_DIR/zstd-jni-1.4.5-6.jar.sha1
        fi
        export PATH=$CURPATH

        # Install maven-3.8.4
        cd $CURDIR
        wget https://archive.apache.org/dist/maven/maven-3/3.8.4/binaries/apache-maven-3.8.4-bin.tar.gz
        tar -zxf apache-maven-3.8.4-bin.tar.gz
        export PATH=$CURDIR/apache-maven-3.8.4/bin:$PATH
        mvn --version

        # Copy locally built rocksdbjni-6.x.jar into local maven repo
        for ROCKSDB_VERSION in 6.19.3 6.22.1.1
        do
            mkdir -p $HOME/.m2/repository/org/rocksdb/rocksdbjni/$ROCKSDB_VERSION
            cp -f $S390X_JNI_JAR_DIR/rocksdbjni-$ROCKSDB_VERSION.jar $HOME/.m2/repository/org/rocksdb/rocksdbjni/$ROCKSDB_VERSION/rocksdbjni-$ROCKSDB_VERSION.jar
            cp -f $S390X_JNI_JAR_DIR/rocksdbjni-$ROCKSDB_VERSION.jar.sha1 $HOME/.m2/repository/org/rocksdb/rocksdbjni/$ROCKSDB_VERSION/rocksdbjni-$ROCKSDB_VERSION.jar.sha1
        done

        # Start docker service
        printf -- "Starting docker service\n"
        sudo service docker start
        sleep 20s
        if [[ $INSECURE_REGISTRY == "Y" ]]; then
            if [ ! -f $DOCKER_DJSON_FILE ]; then
                sudo mkdir -p /etc/docker
                sudo touch $DOCKER_DJSON_FILE
            fi
            sudo chmod 666 $DOCKER_DJSON_FILE
            if [[ "${ID}" == "sles" ]]; then
                cd $CURDIR
                wget --no-check-certificate $PATCH_URL/daemon.json
                sed -i "s/INSECUREREGISTRY/${DOCKER_REGISTRY}/g" daemon.json
                sudo mv -f daemon.json $DOCKER_DJSON_FILE
            else
                sudo printf "{\n\"insecure-registries\": [\"${DOCKER_REGISTRY}\"]\n}\n" >> $DOCKER_DJSON_FILE
            fi
            sudo service docker restart
            sleep 20s
        fi
        printf -- "Login to docker.io to increase pull rate limits\n"
        docker login --username=$DOCKERHUB_USER --password=$DOCKERHUB_PASS

        if [[ "${DOCKER_REGISTRY}" != "docker.io" ]]; then
            if [[ "${REGISTRY_NEED_LOGIN}" == "Y" ]]; then
                printf -- "Login to ${DOCKER_REGISTRY}\n"
                docker login --username=$DOCKER_ORG --password=$REGISTRY_PASS $DOCKER_REGISTRY
            fi
        fi
	
        if [[ "${DISTRO}" == "rhel-8.4" ]] || [[ "${DISTRO}" == "ubuntu-18.04" ]] || [[ "${DISTRO}" == "sles-12.5" ]]; then
                # Build cabal-install
                printf -- "Building cabal-install\n"
                cd $CURDIR
                wget https://downloads.haskell.org/~cabal/cabal-install-2.0.0.1/cabal-install-2.0.0.1.tar.gz
                tar -xvf cabal-install-2.0.0.1.tar.gz
                cd cabal-install-2.0.0.1
                ./bootstrap.sh
            
            export PATH=$HOME/.cabal/bin:$PATH
            cabal --version
            cabal update

            # Build Shellcheck
            printf -- "Building Shellcheck v0.7.2\n"
            cd $CURDIR
            git clone https://github.com/koalaman/shellcheck.git
            cd shellcheck/
            git checkout v0.7.2
            cabal install
            cabal test 
            shellcheck --version
        fi

        if [[ ${DISTRO} =~ rhel-7\.[8-9] ]] || [[ "${DISTRO}" == "sles-15.3" ]]; then
            #Run shellcheck binary in Ubuntu container
            printf -- "Running Shellcheck v0.7.0 in Ubuntu container\n"
            cd $CURDIR
            mkdir shellcheck_docker
            cd shellcheck_docker
            wget --no-check-certificate $PATCH_URL/shellcheck.Dockerfile
            docker build -t local/shellcheck-ubuntu:latest -f ./shellcheck.Dockerfile .
            echo "docker run --rm -v \$(pwd):/opt/project local/shellcheck-ubuntu:latest /usr/bin/shellcheck \"\$@\"" > shellcheck.sh
            chmod +x shellcheck.sh
            sudo mv shellcheck.sh /usr/bin/
            sudo ln -s /usr/bin/shellcheck.sh /usr/bin/shellcheck
            shellcheck --version
        fi

        if [[ "$JAVA_PROVIDED" == "IBMSemeru11" ]]; then
                # Install IBM Semeru Runtime 11 (With OpenJ9)
                cd "$CURDIR"
                sudo mkdir -p /opt/semuru/java

                curl -SL -o semurujdk.tar.gz https://github.com/ibmruntimes/semeru11-binaries/releases/download/jdk-11.0.14.1%2B1_openj9-0.30.1/ibm-semeru-open-jdk_s390x_linux_11.0.14.1_1_openj9-0.30.1.tar.gz
                # Everytime new jdk is downloaded, Ensure that --strip valueis correct
                sudo tar -zxvf semurujdk.tar.gz -C /opt/semuru/java --strip-components 1

                export JAVA_HOME=/opt/semuru/java

                printf -- "export JAVA_HOME=/opt/semuru/java\n" >> "$BUILD_ENV"
                printf -- "Installation of IBM Semeru Runtime 11 (With OpenJ9) is successful\n" >> "$LOG_FILE"

        elif [[ "$JAVA_PROVIDED" == "Temurin11" ]]; then
                # Install Eclipse Temurin Runtime 11 (With Hotspot)
                cd "$CURDIR"
                sudo mkdir -p /opt/temurin/java

                curl -SL -o temurinjdk.tar.gz https://adoptium.net/download?link=https://github.com/adoptium/temurin11-binaries/releases/download/jdk-11.0.14.1%2B1/OpenJDK11U-jdk_s390x_linux_hotspot_11.0.14.1_1.tar.gz
                # Everytime new jdk is downloaded, Ensure that --strip valueis correct
                sudo tar -zxvf temurinjdk.tar.gz -C /opt/temurin/java --strip-components 1

                export JAVA_HOME=/opt/temurin/java

                printf -- "export JAVA_HOME=/opt/temurin/java\n" >> "$BUILD_ENV"
                printf -- "Installation of Eclipse Temurin Runtime 11 (With Hotspot) is successful\n" >> "$LOG_FILE"

        elif [[ "$JAVA_PROVIDED" == "OpenJDK11" ]]; then
                if [[ "${ID}" == "ubuntu" ]]; then
                        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-11-jdk
                        export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x
                        printf -- "export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x\n" >> "$BUILD_ENV"
                elif [[ "${ID}" == "rhel" ]]; then
                        sudo yum install -y java-11-openjdk java-11-openjdk-devel
                        echo "Inside $DISTRO"
                        export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
                        printf -- "export JAVA_HOME=/usr/lib/jvm/java-11-openjdk\n" >> "$BUILD_ENV"
                elif [[ "${ID}" == "sles" ]]; then
                        sudo zypper install -y java-11-openjdk java-11-openjdk-devel
                        export JAVA_HOME=/usr/lib64/jvm/java-11-openjdk
                        printf -- "export JAVA_HOME=/usr/lib64/jvm/java-11-openjdk\n" >> "$BUILD_ENV"
                fi
                printf -- "Installation of OpenJDK 11 is successful\n" >> "$LOG_FILE"
        else
                printf "$JAVA_PROVIDED is not supported, Please use valid java from {IBMSemeru11, Temurin11, OpenJDK11} only"
                exit 1
        fi
        printf -- "export PATH=$JAVA_HOME/bin:$PATH\n" >> "$BUILD_ENV"
        export PATH=$JAVA_HOME/bin:$PATH
        java -version |& tee -a "$LOG_FILE"

        # Install helm
        printf -- "Installing helm\n"
        cd $CURDIR
        curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
        chmod 700 get_helm.sh
        ./get_helm.sh

        # Install yq
        printf -- "Installing yq\n"
        cd $CURDIR
        curl -fsSL -o yq_linux_s390x.tar.gz https://github.com/mikefarah/yq/releases/download/v4.11.1/yq_linux_s390x.tar.gz
        tar xf yq_linux_s390x.tar.gz
        chmod +x yq_linux_s390x
        sudo mv yq_linux_s390x /usr/local/bin/yq

        # Install asciidoctor
        printf -- "Installing asciidoctor and asciidoctor-pdf\n"
        sudo gem install asciidoctor
        sudo gem install asciidoctor-pdf
        
        # Install Docker Buildx for Ubuntu and SLES
        if [[ "${ID}" == "ubuntu" ]] || [[ "${ID}" == "sles" ]]; then
            printf -- "Installing Docker Buildx\n"
            cd $CURDIR
            wget https://github.com/docker/buildx/releases/download/v0.6.1/buildx-v0.6.1.linux-s390x
            mkdir -p ~/.docker/cli-plugins
            mv buildx-v0.6.1.linux-s390x ~/.docker/cli-plugins/docker-buildx
            chmod a+x ~/.docker/cli-plugins/docker-buildx
        fi

        # Install minikube with docker driver
        printf -- "Installing minikube with docker driver\n"
        cd $CURDIR
        export KUBERNETES_VERSION=`curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt`
        curl -LO https://github.com/kubernetes/minikube/releases/download/v1.25.2/minikube-linux-s390x && sudo install minikube-linux-s390x /usr/bin/minikube && rm -rf minikube-linux-s390x
        curl -LO https://storage.googleapis.com/kubernetes-release/release/$KUBERNETES_VERSION/bin/linux/s390x/kubectl && chmod +x kubectl && sudo cp kubectl /usr/bin/ && rm -rf kubectl
        if [[ "${ID}" == "rhel" ]]; then
            sudo setenforce 0
        fi
        if [[ $INSECURE_REGISTRY == "N" ]]; then
            INSECURE_REGISTRY=""  
        else
            INSECURE_REGISTRY="--insecure-registry \"${DOCKER_REGISTRY}\""
        fi

        #Build s390x kaniko-executor image
        printf -- "Building s390x kaniko-executor image\n"
        cd $CURDIR
        git clone https://github.com/GoogleContainerTools/kaniko.git
        cd kaniko/
        git checkout v1.7.0
        docker buildx build --platform linux/s390x --load --build-arg GOARCH=s390x -t local/kaniko-project/executor:v1.7.0 -f ./deploy/Dockerfile .
        docker tag local/kaniko-project/executor:v1.7.0 gcr.io/kaniko-project/executor:v1.7.0

        #Build and push Strimzi-kafka-operator images
        printf -- "Building and pushing Strimzi-kafka-operator images\n"
        cd $CURDIR
        wget --no-check-certificate $PATCH_URL/operator_$PACKAGE_VERSION.diff
        export DOCKER_TAG=$PACKAGE_VERSION
        printf -- "export DOCKER_REGISTRY=$DOCKER_REGISTRY\n" >> "$BUILD_ENV"
        printf -- "export DOCKER_ORG=$DOCKER_ORG\n" >> "$BUILD_ENV"
        printf -- "export DOCKER_TAG=$PACKAGE_VERSION\n" >> "$BUILD_ENV"
        export TEST_CLUSTER=minikube
        printf -- "export TEST_CLUSTER=minikube\n" >> "$BUILD_ENV"
        export DOCKER_BUILDX=buildx
        printf -- "export DOCKER_BUILDX=buildx\n" >> "$BUILD_ENV"
        export DOCKER_BUILD_ARGS="--platform linux/s390x --load"
        printf -- "export DOCKER_BUILD_ARGS=\"--platform linux/s390x --load\"\n" >> "$BUILD_ENV"
        git clone https://github.com/strimzi/strimzi-kafka-operator.git
        cd strimzi-kafka-operator/
        git checkout $PACKAGE_VERSION
        patch -p1 < ${CURDIR}/operator_$PACKAGE_VERSION.diff
        if [[ "$PUSH_TO_REGISTRY" == "Y" ]]; then
            make MVN_ARGS='-DskipTests' all
        else
            make MVN_ARGS='-DskipTests' java_install
            make MVN_ARGS='-DskipTests' docker_build
        fi

        if [[ "$PUSH_TO_REGISTRY" == "Y" ]]; then
                sed -Ei -e "s#(image|value): quay.io/strimzi/([a-z0-9-]+):latest#\1: $DOCKER_REGISTRY/$DOCKER_ORG/\2:latest#" \
                        -e "s#(image|value): quay.io/strimzi/([a-zA-Z0-9-]+:[0-9.]+)#\1: $DOCKER_REGISTRY/$DOCKER_ORG/\2#" \
                        -e "s#([0-9.]+)=quay.io/strimzi/([a-zA-Z0-9-]+:[a-zA-Z0-9.-]+-kafka-[0-9.]+)#\1=$DOCKER_REGISTRY/$DOCKER_ORG/\2#" \
                        packaging/install/cluster-operator/060-Deployment-strimzi-cluster-operator.yaml
        fi

        #Retag and push Strimzi-bridge image
        printf -- "Retagging and pushing Strimzi-kafka-bridge image\n"
        docker pull quay.io/strimzi/kafka-bridge:$BRIDGE_VERSION
        docker tag quay.io/strimzi/kafka-bridge:$BRIDGE_VERSION $DOCKER_REGISTRY/$DOCKER_ORG/kafka-bridge:$BRIDGE_VERSION
        docker push $DOCKER_REGISTRY/$DOCKER_ORG/kafka-bridge:$BRIDGE_VERSION

        if [[ $BUILD_SYSTEMTESTS_DEPS == "Y" ]]; then

            #Build and push keycloak-operator image
            printf -- "Building and pushing keycloak-operator image\n"
            cd $CURDIR
            wget --no-check-certificate $PATCH_URL/keycloak-operator.diff
            git clone https://github.com/keycloak/keycloak-operator.git
            cd keycloak-operator
            git checkout 15.0.2
            sed -i "s/YOUR_OWN_REPO/${DOCKER_REGISTRY}/g" ${CURDIR}/keycloak-operator.diff
            patch -p1 < ${CURDIR}/keycloak-operator.diff
            docker buildx build --platform linux/s390x --push --tag ${DOCKER_REGISTRY}/keycloak/keycloak-operator:15.0.2 .

            #Build and push keycloak related images
            printf -- "Building and pushing keycloak and keycloak-init-container images\n"
            cd $CURDIR
            git clone https://github.com/keycloak/keycloak-containers.git
            cd keycloak-containers
            git checkout 15.0.2
            cd server
            docker buildx build --platform linux/s390x --push --tag ${DOCKER_REGISTRY}/keycloak/keycloak:15.0.2 .
            cd ..
            #git checkout main
            git checkout a03d3e8c54c3ad364d4ee912fca0298bc5a7099c
            cd keycloak-init-container
            docker buildx build --platform linux/s390x --push --tag ${DOCKER_REGISTRY}/keycloak/keycloak-init-container:master .
        
            #Build and push test-client-http-consumer, test-client-http-producer, test-client-kafka-admin, test-client-kafka-consumer, test-client-kafka-producer and test-client-kafka-streams images
            printf -- "Building and pushing test-client-http-consumer, test-client-http-producer, test-client-kafka-admin, test-client-kafka-consumer, test-client-kafka-producer and test-client-kafka-streams images\n"
            cd $CURDIR
            DOCKER_ORG_TMP=$DOCKER_ORG
            git clone https://github.com/strimzi/test-clients.git
            cd test-clients
            git checkout 0.1.1
            export DOCKER_TAG=0.1.1
            export DOCKER_VERSION_ARG=0.1.1
            ./docker-images/build-images.sh build
            export DOCKER_ORG=strimzi-test-clients
            ./docker-images/build-images.sh
            export DOCKER_ORG=$DOCKER_ORG_TMP
            export DOCKER_TAG=$PACKAGE_VERSION
        
            #Build Golang 1.17 toolchain image 
            printf -- "Build Golang 1.17 toolchain image\n"
            cd $CURDIR
            mkdir golang-wasmtime && cd golang-wasmtime
            wget https://github.com/bytecodealliance/wasmtime/releases/download/v0.31.0/wasmtime-v0.31.0-s390x-linux-c-api.tar.xz
            tar xvf wasmtime-v0.31.0-s390x-linux-c-api.tar.xz
            wget --no-check-certificate $PATCH_URL/golang-wasmtime.Dockerfile
            docker build -t golang-wasmtime:1.17 -f ./golang-wasmtime.Dockerfile .

            #Build and push opa-wasm-builder and opa images
            printf -- "Building and pushing opa-wasm-builder and opa images\n"
            cd $CURDIR
            wget --no-check-certificate $PATCH_URL/opa.diff
            git clone https://github.com/open-policy-agent/opa.git
            cd opa
            git checkout v0.34.0
            patch -p1 < ${CURDIR}/opa.diff
            #Build opa-wasm-builder image and wasm lib, then use Golang toolchain image to build opa_linux_s390x binary
            make ci-go-ci-build-linux
            sudo chown -R $(id -u):$(id -g) _release
            #Build and push opa image
            make image-s390x
            docker tag openpolicyagent/opa:0.34.0 ${DOCKER_REGISTRY}/openpolicyagent/opa:latest
            docker push ${DOCKER_REGISTRY}/openpolicyagent/opa:latest

            #Build s390x kaniko-executor image v1.6.0
            printf -- "Building s390x kaniko-executor image v1.6.0\n"
            cd $CURDIR
            mkdir system_test && cd system_test
            wget --no-check-certificate $PATCH_URL/kaniko.diff
            git clone https://github.com/GoogleContainerTools/kaniko.git
            cd kaniko/
            git checkout v1.6.0
            patch -p1 < ../kaniko.diff
            docker buildx build --platform linux/s390x --load --build-arg GOARCH=s390x -t local/kaniko-project/executor:v1.6.0 -f ./deploy/Dockerfile .

            #Patch systemtests
            printf -- "Apply patches for systemtests\n"
            cd $CURDIR
            wget --no-check-certificate $PATCH_URL/systemtests.diff
            sed -i "s/YOUR_OWN_REPO/${DOCKER_REGISTRY}/g" systemtests.diff
            sed -i "s/YOUR_OWN_ORG/${DOCKER_ORG}/g" systemtests.diff
            cd strimzi-kafka-operator/
            patch -p1 < ${CURDIR}/systemtests.diff

            #Build and publish strimzi-kafka-operator v0.27.1 images
            printf -- "Building and pushing Strimzi-kafka-operator v0.27.1 images\n"
            cd $CURDIR
            mkdir -p system_test/${PRE_PACKAGE_VERSION}
            mkdir -p system_test/${PRE2_PACKAGE_VERSION}
            cd system_test/${PRE_PACKAGE_VERSION}
            wget --no-check-certificate $PATCH_URL/operator_${PRE_PACKAGE_VERSION}.diff
            git clone https://github.com/strimzi/strimzi-kafka-operator.git
            cp -r strimzi-kafka-operator ../${PRE2_PACKAGE_VERSION}/
            cd strimzi-kafka-operator/
            git checkout $PRE_PACKAGE_VERSION
            patch -p1 < ../operator_${PRE_PACKAGE_VERSION}.diff
            export DOCKER_TAG=$PRE_PACKAGE_VERSION
            make MVN_ARGS='-DskipTests' all

            #Build and publish strimzi-kafka-operator v0.24.0 images
            printf -- "Building and pushing Strimzi-kafka-operator v0.24.0 images\n"
            cd $CURDIR/system_test/${PRE2_PACKAGE_VERSION}
            wget --no-check-certificate $PATCH_URL/operator_${PRE2_PACKAGE_VERSION}.diff
            wget --no-check-certificate $PATCH_URL/operator_log4j_${PRE2_PACKAGE_VERSION}.diff
            if [[ "$JAVA_PROVIDED" == "IBMSemeru11" ]]; then
                wget --no-check-certificate $PATCH_URL/incompatible_types_${PRE2_PACKAGE_VERSION}.diff
            fi
            cd strimzi-kafka-operator/
            git checkout $PRE2_PACKAGE_VERSION
            patch -p1 < ../operator_${PRE2_PACKAGE_VERSION}.diff
            patch -p1 < ../operator_log4j_${PRE2_PACKAGE_VERSION}.diff
            if [[ "${DISTRO}" == "sles-12.5" ]]; then
                sed -i 's/"$code" == "404"/"$code" == "404" || "$code" == "000"/g' docker-images/build.sh
            fi
            if [[ "$JAVA_PROVIDED" == "IBMSemeru11" ]]; then
                patch -p1 < ../incompatible_types_${PRE2_PACKAGE_VERSION}.diff
            fi
            export DOCKER_TAG=$PRE2_PACKAGE_VERSION
            make MVN_ARGS='-DskipTests' all

            #Build and publish strimzi-kafka-bridge v0.21.3 image
            printf -- "Building and pushing Strimzi-kafka-bridge v0.21.3 image\n"
            cd $CURDIR/system_test/${PRE_PACKAGE_VERSION}
            export DOCKER_TAG=$PRE_BRIDGE_VERSION
            git clone https://github.com/strimzi/strimzi-kafka-bridge.git
            cp -r strimzi-kafka-bridge ../${PRE2_PACKAGE_VERSION}/
            cd strimzi-kafka-bridge/
            git checkout $PRE_BRIDGE_VERSION
            make all

            #Build and publish strimzi-kafka-bridge v0.20.1 image
            printf -- "Building and pushing Strimzi-kafka-bridge v0.20.1 image\n"
            cd $CURDIR/system_test/${PRE2_PACKAGE_VERSION}
            wget --no-check-certificate $PATCH_URL/bridge_${PRE2_BRIDGE_VERSION}.diff
            wget --no-check-certificate $PATCH_URL/bridge_log4j_${PRE2_BRIDGE_VERSION}.diff
            export DOCKER_TAG=$PRE2_BRIDGE_VERSION
            cd strimzi-kafka-bridge/
            git checkout $PRE2_BRIDGE_VERSION
            patch -p1 < ../bridge_${PRE2_BRIDGE_VERSION}.diff
            patch -p1 < ../bridge_log4j_${PRE2_BRIDGE_VERSION}.diff
            make all

            export DOCKER_TAG=$PACKAGE_VERSION

        fi

        # run tests
        runTest
        
	# Cleanup
        cleanup
        
        printf -- "%s installation completed. Please check the Usage.\n" "$PACKAGE_NAME"
}

function runTest() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
	    printf -- "TEST Flag is set, continue with running test \n"  >> "$LOG_FILE"
	    cd ${CURDIR}
        printf -- "Preparing for running tests. \n" 
        # Starting minikube with the latest K8s release
        printf -- "Starting minikube with the latest K8s release.\n"
        minikube start --driver docker --cpus=4 --memory=8192 $INSECURE_REGISTRY
        sleep 60s
        cd strimzi-kafka-operator
        mvn -e -V -B -Dmaven.javadoc.skip=true -Dsurefire.rerunFailingTestsCount=5 -Dfailsafe.rerunFailingTestsCount=2 install
        printf -- "Tests completed. \n" 
        # Stopping minikube and deleting the local cluster
        printf -- "Stopping minikube.\n"
        minikube stop
        minikube delete
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
        echo "Please set up environment variables DOCKER_REGISTRY, DOCKER_ORG, DOCKERHUB_USER and DOCKERHUB_PASS first, ensure user $USER belongs to group docker."
        echo "  build_strimzi.sh  [-d debug] [-y install-without-confirmation] [-t run-test] [-p push-to-registry] [-i insecure-registry] [-l registry-need-login] [-s build-systemtests-deps] [-j Java to use from {IBMSemeru11, Temurin11, OpenJDK11}]"
        echo "  default: If no -j specified, IBM Semeru Runtime 11 will be installed"
        echo
}

while getopts "h?dytpilsj:" opt; do
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
        p)
                PUSH_TO_REGISTRY="Y"
                ;;
        i)
                INSECURE_REGISTRY="Y"
                ;;
        l)
                REGISTRY_NEED_LOGIN="Y"
                ;;
        s)
                BUILD_SYSTEMTESTS_DEPS="Y"
                ;;
        j)
                JAVA_PROVIDED="$OPTARG"
                ;;
        esac
done

function gettingStarted() {
        if [[ $INSECURE_REGISTRY == "N" ]]; then
            INSECURE_REGISTRY=""  
        else
            INSECURE_REGISTRY="--insecure-registry \"${DOCKER_REGISTRY}\""
        fi
        printf -- '\n********************************************************************************************************\n'
        printf -- "\n* Getting Started * \n"
        printf -- "Note: Environmental Variables needed have been added to $HOME/setenv.sh\n"
        printf -- "Note: To set the Environmental Variables needed for Strimzi-kafka-operator, please run: source $HOME/setenv.sh \n\n"
        if [[ "$PUSH_TO_REGISTRY" == "Y" ]]; then
                printf -- "Before deploying Strmzi Operators, you can start minikube locally with the below command: \n"
                printf -- "    minikube start --driver docker --cpus=4 --memory=8192 $INSECURE_REGISTRY \n"
                printf -- "You can deploy the Cluster Operator by running the following command(replace myproject with your desired namespace if necessary): \n"
                printf -- "    kubectl -n myproject create -f strimzi-kafka-operator/packaging/install/cluster-operator \n\n"
                printf -- "Then you can deploy the cluster custom resource by running: \n"
                printf -- "    kubectl -n myproject create -f strimzi-kafka-operator/packaging/examples/kafka/kafka-ephemeral.yaml \n\n"
                if [[ "$BUILD_SYSTEMTESTS_DEPS" == "Y" ]]; then
                      printf -- "Please refer to the Building Instructions on how to run system tests.\n\n"  
                fi
        else
                printf -- "The docker images of Strimzi-kafka-operator $PACKAGE_VERSION have been built locally. \n\n"
        fi
        printf -- "Visit https://strimzi.io/docs/operators/latest/overview.html for more information.\n\n"
        printf -- '********************************************************************************************************\n'
}

###############################################################################################################

logDetails
prepare

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-18.04")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo apt-get update
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends tzdata |& tee -a "${LOG_FILE}"
        sudo apt-get install -y git make cmake gcc-8 g++-8 docker.io tar wget patch ruby curl conntrack cabal-install openssl libsnappy-dev zlib1g-dev libbz2-dev liblz4-dev libzstd-dev libarchive-dev diffutils gzip file procps python3 perl |& tee -a "${LOG_FILE}"
        setupGCC 8 |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"ubuntu-20.04")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo apt-get update
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends tzdata |& tee -a "${LOG_FILE}"
        sudo apt-get install -y apt-utils
        sudo apt-get install -y git make cmake gcc-8 g++-8 docker.io tar wget patch ruby curl conntrack shellcheck openssl libsnappy-dev zlib1g-dev libbz2-dev liblz4-dev libzstd-dev libarchive-dev diffutils gzip file procps python3 perl |& tee -a "${LOG_FILE}"
        setupGCC 8 |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"rhel-7.8" | "rhel-7.9")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo yum install -y yum-utils
        sudo yum-config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
        sudo yum-config-manager --enable docker-ce-stable
        sudo yum install -y git make autoconf gcc gcc-c++ docker-ce tar wget patch curl conntrack ruby bison flex openssl-devel libyaml-devel libffi-devel readline-devel zlib-devel gdbm-devel ncurses-devel tcl-devel tk-devel snappy-devel bzip2 bzip2-devel lz4-devel unzip python3 perl libarchive gzip file procps diffutils |& tee -a "${LOG_FILE}"
        buildRuby |& tee -a "$LOG_FILE"
        buildGCC |& tee -a "$LOG_FILE"
        buildOpenssl |& tee -a "$LOG_FILE"
        PATH=${PREFIX}/bin${PATH:+:${PATH}}
        export PATH
        PKG_CONFIG_PATH=${PREFIX}/lib/pkgconfig:${PREFIX}/lib64/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}
        export PKG_CONFIG_PATH
        printf -- "export PKG_CONFIG_PATH=$PKG_CONFIG_PATH\n" >> "$BUILD_ENV"
        LD_LIBRARY_PATH=${PREFIX}/lib:${PREFIX}/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
        export LD_LIBRARY_PATH
        printf -- "export LD_LIBRARY_PATH=$LD_LIBRARY_PATH\n" >> "$BUILD_ENV"
        LD_RUN_PATH=${PREFIX}/lib:${PREFIX}/lib64${LD_RUN_PATH:+:${LD_RUN_PATH}}
        export LD_RUN_PATH
        printf -- "export LD_RUN_PATH=$LD_RUN_PATH\n" >> "$BUILD_ENV"
        export SSL_CERT_FILE=/usr/local/etc/openssl/cacert.pem
        printf -- "export SSL_CERT_FILE=/usr/local/etc/openssl/cacert.pem\n" >> "$BUILD_ENV"
        buildCmake |& tee -a "${LOG_FILE}"
        buildZstd |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"rhel-8.4")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo yum remove -y podman buildah
        sudo yum install -y yum-utils
        sudo yum-config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
        sudo yum install -y git make cmake gcc gcc-c++ ghc ghc-Cabal ghc-Cabal-devel zlib-devel docker-ce docker-ce-cli containerd.io tar wget patch ruby curl openssl-devel conntrack hostname unzip procps snappy snappy-devel binutils bzip2 bzip2-devel lz4-devel libzstd-devel libasan python3 unzip which libarchive diffutils gzip file perl |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"sles-12.5")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo zypper install -y git gcc7 gcc7-c++ make autoconf tar wget patch curl which zip unzip ruby conntrack-tools ghc cabal-install docker-20.10.6_ce-98.66.1 bison flex libopenssl-devel readline-devel gdbm-devel gawk libsnappy1 snappy-devel libz1 zlib-devel bzip2 libbz2-devel liblz4-devel libzstd-devel python3 perl diffutils gzip file procps |& tee -a "${LOG_FILE}"
        setupGCC 7
        buildOpenssl |& tee -a "$LOG_FILE"
        PATH=${PREFIX}/bin${PATH:+:${PATH}}
        export PATH
        PKG_CONFIG_PATH=${PREFIX}/lib/pkgconfig:${PREFIX}/lib64/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}
        export PKG_CONFIG_PATH
        printf -- "export PKG_CONFIG_PATH=$PKG_CONFIG_PATH\n" >> "$BUILD_ENV"
        LD_LIBRARY_PATH=${PREFIX}/lib:${PREFIX}/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
        export LD_LIBRARY_PATH
        printf -- "export LD_LIBRARY_PATH=$LD_LIBRARY_PATH\n" >> "$BUILD_ENV"
        LD_RUN_PATH=${PREFIX}/lib:${PREFIX}/lib64${LD_RUN_PATH:+:${LD_RUN_PATH}}
        export LD_RUN_PATH
        printf -- "export LD_RUN_PATH=$LD_RUN_PATH\n" >> "$BUILD_ENV"
        export SSL_CERT_FILE=/usr/local/etc/openssl/cacert.pem
        printf -- "export SSL_CERT_FILE=/usr/local/etc/openssl/cacert.pem\n" >> "$BUILD_ENV"
        buildRuby |& tee -a "$LOG_FILE"
        buildCmake |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"sles-15.3")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo zypper install -y git gcc gcc-c++ make cmake tar wget patch curl which zip unzip ruby conntrack-tools libatomic1 docker-20.10.6_ce-6.49.3 libopenssl-devel libsnappy1 snappy-devel libz1 zlib-devel bzip2 libbz2-devel liblz4-devel libzstd-devel python3 perl diffutils awk gzip file procps |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

*)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "${LOG_FILE}"
        exit 1

        ;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
