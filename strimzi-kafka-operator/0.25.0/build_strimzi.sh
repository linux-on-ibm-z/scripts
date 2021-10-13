#!/bin/bash
# ©  Copyright IBM Corporation 2021.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/strimzi-kafka-operator/0.25.0/build_strimzi.sh
# Execute build script: bash build_strimzi.sh    (provide -h for help)
#

USER_IN_GROUP_DOCKER=$(id -nGz $USER | tr '\0' '\n' | grep '^docker$' | wc -l)
set -e -o pipefail

PACKAGE_NAME="strimzi-kafka-operator"
PACKAGE_VERSION="0.25.0"
BRIDGE_VERSION="0.20.2"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/${PACKAGE_NAME}/${PACKAGE_VERSION}/patch"
FORCE="false"
TESTS="false"
CURDIR="$(pwd)"
CURPATH="$(echo $PATH)"
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
NON_ROOT_USER="$(whoami)"
JAVA_PROVIDED="OpenJDK11"
BUILD_ENV="$HOME/setenv.sh"
PREFIX="/usr/local"
PUSH_TO_REGISTRY="N"
INSECURE_REGISTRY="N"
REGISTRY_NEED_LOGIN="N"
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

        if [[ "$JAVA_PROVIDED" != "AdoptJDK11_openj9" && "$JAVA_PROVIDED" != "AdoptJDK11_hotspot" && "$JAVA_PROVIDED" != "OpenJDK11" ]]; then
                printf "$JAVA_PROVIDED is not supported, Please use valid java from {AdoptJDK11_openj9, AdoptJDK11_hotspot, OpenJDK11} only\n"
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
        sudo rm -rf "${CURDIR}/apache-maven-3.8.2-bin.tar.gz" "${CURDIR}/cabal-install-2.0.0.1.tar.gz" "${CURDIR}/adoptjdk.tar.gz" "${CURDIR}/OpenJDK8U-jdk*.tar.gz" "${CURDIR}/openssl-1.1.1g.tar.gz" "${CURDIR}/sbt.tgz" "${CURDIR}/v2_5_9.tar.gz" "${CURDIR}/yq_linux_s390x.tar.gz" 
        printf -- 'Cleaned up the artifacts\n' >>"${LOG_FILE}"
}

function setupGCC()
{
        sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-7 40
        sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-7 40
        sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-7 40
        sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-7 40
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

        sudo update-alternatives --install /usr/bin/cc cc /usr/local/bin/gcc-7 40
        sudo update-alternatives --install /usr/bin/gcc gcc /usr/local/bin/gcc-7 40
        sudo update-alternatives --install /usr/bin/g++ g++ /usr/local/bin/g++-7 40
        sudo update-alternatives --install /usr/bin/c++ c++ /usr/local/bin/g++-7 40
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
        wget https://www.openssl.org/source/old/1.1.1/openssl-${ver}.tar.gz
        tar xvf openssl-${ver}.tar.gz
        cd openssl-${ver}
        ./config --prefix=${PREFIX}
        make
        sudo make install

        sudo mkdir -p /usr/local/etc/openssl
        cd /usr/local/etc/openssl
        sudo wget https://curl.se/ca/cacert.pem
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

        # Build and Create rocksdbjni-5.18.4.jar for s390x
        printf -- "Build and Create rocksdbjni-5.18.4.jar for s390x\n"
        cd $CURDIR
        git clone https://github.com/facebook/rocksdb.git
        cd rocksdb
        git checkout v5.18.4
        sed -i '1656s/ARCH/MACHINE/g' Makefile
        PORTABLE=1 make shared_lib
        make rocksdbjava
        printf -- "Built rocksdb and created rocksdbjni-5.18.4.jar successfully.\n"
        mkdir -p $S390X_JNI_JAR_DIR
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
        export PATH=$CURPATH

        if [[ "${ID}" == "sles" || "${ID}" == "ubuntu" || ${DISTRO} =~ rhel-7\.[8-9] ]]; then
            # Install maven-3.8.2
            cd $CURDIR
            wget https://archive.apache.org/dist/maven/maven-3/3.8.2/binaries/apache-maven-3.8.2-bin.tar.gz
            tar -zxf apache-maven-3.8.2-bin.tar.gz
            export PATH=$CURDIR/apache-maven-3.8.2/bin:$PATH
        fi

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
	
        if [[ "${DISTRO}" == "rhel-8.2" ]]; then
            sudo yum install -y gcc-toolset-10
            source /opt/rh/gcc-toolset-10/enable
        fi

        if [[ ${DISTRO} =~ rhel-8\.[2-4] ]] || [[ "${DISTRO}" == "ubuntu-18.04" ]] || [[ "${DISTRO}" == "sles-12.5" ]] || [[ "${DISTRO}" == "sles-15.2" ]]; then
            if [[ ${DISTRO} =~ rhel-8\.[2-4] ]] || [[ "${DISTRO}" == "sles-15.2" ]]; then
                # Build cabal-install
                printf -- "Building cabal-install\n"
                cd $CURDIR
                wget https://downloads.haskell.org/~cabal/cabal-install-2.0.0.1/cabal-install-2.0.0.1.tar.gz
                tar -xvf cabal-install-2.0.0.1.tar.gz
                cd cabal-install-2.0.0.1
                ./bootstrap.sh
            fi
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

        if [[ "$JAVA_PROVIDED" == "AdoptJDK11_openj9" ]]; then
                # Install AdoptOpenJDK 11 (With OpenJ9)
                cd "$CURDIR"
                sudo mkdir -p /opt/adopt/java

                curl -SL -o adoptjdk.tar.gz https://github.com/AdoptOpenJDK/semeru11-binaries/releases/download/jdk-11.0.12%2B7_openj9-0.27.0/ibm-semeru-open-jdk_s390x_linux_11.0.12_7_openj9-0.27.0.tar.gz
                # Everytime new jdk is downloaded, Ensure that --strip valueis correct
                sudo tar -zxvf adoptjdk.tar.gz -C /opt/adopt/java --strip-components 1

                export JAVA_HOME=/opt/adopt/java

                printf -- "export JAVA_HOME=/opt/adopt/java\n" >> "$BUILD_ENV"
                printf -- "Installation of AdoptOpenJDK 11 (With OpenJ9) is successful\n" >> "$LOG_FILE"

        elif [[ "$JAVA_PROVIDED" == "AdoptJDK11_hotspot" ]]; then
                # Install AdoptOpenJDK 11 (With Hotspot)
                cd "$CURDIR"
                sudo mkdir -p /opt/adopt/java

                curl -SL -o adoptjdk.tar.gz https://github.com/adoptium/temurin11-binaries/releases/download/jdk-11.0.12%2B7/OpenJDK11U-jdk_s390x_linux_hotspot_11.0.12_7.tar.gz
                # Everytime new jdk is downloaded, Ensure that --strip valueis correct
                sudo tar -zxvf adoptjdk.tar.gz -C /opt/adopt/java --strip-components 1

                export JAVA_HOME=/opt/adopt/java

                printf -- "export JAVA_HOME=/opt/adopt/java\n" >> "$BUILD_ENV"
                printf -- "Installation of AdoptOpenJDK 11 (With Hotspot) is successful\n" >> "$LOG_FILE"

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
                printf "$JAVA_PROVIDED is not supported, Please use valid java from {AdoptJDK11_openj9, AdoptJDK11_hotspot, OpenJDK11} only"
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
        curl -LO https://github.com/kubernetes/minikube/releases/download/v1.22.0/minikube-linux-s390x && sudo install minikube-linux-s390x /usr/bin/minikube && rm -rf minikube-linux-s390x
        curl -LO https://storage.googleapis.com/kubernetes-release/release/$KUBERNETES_VERSION/bin/linux/s390x/kubectl && chmod +x kubectl && sudo cp kubectl /usr/bin/ && rm -rf kubectl
        if [[ "${ID}" == "rhel" ]]; then
            sudo setenforce 0
        fi
        if [[ $INSECURE_REGISTRY == "N" ]]; then
            INSECURE_REGISTRY=""  
        else
            INSECURE_REGISTRY="--insecure-registry \"${DOCKER_REGISTRY}\""
        fi

        git clone https://github.com/kubernetes/minikube.git
        cd minikube
        git checkout v1.22.0
        # build kicbase:latest image
        docker build -t local/kicbase:latest -f ./deploy/kicbase/Dockerfile .

        #Build s390x kaniko-executor image
        printf -- "Building s390x kaniko-executor image\n"
        cd $CURDIR
        wget --no-check-certificate $PATCH_URL/kaniko.diff
        git clone https://github.com/GoogleContainerTools/kaniko.git
        cd kaniko/
        git checkout v1.6.0
        patch -p1 < $CURDIR/kaniko.diff
        docker buildx build --platform linux/s390x --load --build-arg GOARCH=s390x -t local/kaniko-project/executor:v1.6.0 -f ./deploy/Dockerfile .

        #Build and push Strimzi-kafka-operator images
        printf -- "Building and pushing Strimzi-kafka-operator images\n"
        cd $CURDIR
        wget --no-check-certificate $PATCH_URL/operator.diff
        if [[ "$JAVA_PROVIDED" == "AdoptJDK11_openj9" ]]; then
            wget --no-check-certificate $PATCH_URL/incompatible_types.diff
        fi
        export DOCKER_TAG=$PACKAGE_VERSION
        printf -- "export DOCKER_ORG=$DOCKER_ORG\n" >> "$BUILD_ENV"
        printf -- "export DOCKER_REGISTRY=$DOCKER_REGISTRY\n" >> "$BUILD_ENV"
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
        patch -p1 < ${CURDIR}/operator.diff
        if [[ "$JAVA_PROVIDED" == "AdoptJDK11_openj9" ]]; then
            patch -p1 < ${CURDIR}/incompatible_types.diff
        fi
        if [[ "$PUSH_TO_REGISTRY" == "Y" ]]; then
                make MVN_ARGS='-DskipTests -DskipITs' all
        else
                make MVN_ARGS='-DskipTests -DskipITs' docker_build
        fi

        if [[ "$PUSH_TO_REGISTRY" == "Y" ]]; then
                sed -Ei -e "s#(image|value): quay.io/strimzi/([a-z0-9-]+):latest#\1: $DOCKER_REGISTRY/$DOCKER_ORG/\2:latest#" \
                        -e "s#(image|value): quay.io/strimzi/([a-zA-Z0-9-]+:[0-9.]+)#\1: $DOCKER_REGISTRY/$DOCKER_ORG/\2#" \
                        -e "s#([0-9.]+)=quay.io/strimzi/([a-zA-Z0-9-]+:[a-zA-Z0-9.-]+-kafka-[0-9.]+)#\1=$DOCKER_REGISTRY/$DOCKER_ORG/\2#" \
                        packaging/install/cluster-operator/060-Deployment-strimzi-cluster-operator.yaml
        fi
        
        #Replace all other jni jar files with the s390x version peers
        printf -- "Replacing all other jni jar files with the s390x version peers\n"
        cp -f $S390X_JNI_JAR_DIR/rocksdbjni-5.18.4.jar topic-operator/target/lib/org.rocksdb.rocksdbjni-5.18.4.jar
        cp -f $S390X_JNI_JAR_DIR/rocksdbjni-5.18.4.jar $HOME/.m2/repository/org/rocksdb/rocksdbjni/5.18.4/rocksdbjni-5.18.4.jar
        cp -f $S390X_JNI_JAR_DIR/rocksdbjni-5.18.4.jar.sha1 $HOME/.m2/repository/org/rocksdb/rocksdbjni/5.18.4/rocksdbjni-5.18.4.jar.sha1
        cp -f $S390X_JNI_JAR_DIR/zstd-jni-1.4.5-6.jar $HOME/.m2/repository/com/github/luben/zstd-jni/1.4.5-6/zstd-jni-1.4.5-6.jar
        cp -f $S390X_JNI_JAR_DIR/zstd-jni-1.4.5-6.jar.sha1 $HOME/.m2/repository/com/github/luben/zstd-jni/1.4.5-6/zstd-jni-1.4.5-6.jar.sha1

        #Build and push Strimzi-bridge image
        printf -- "Building and pushing Strimzi-kafka-bridge image\n"
        cd $CURDIR
        wget --no-check-certificate $PATCH_URL/bridge.diff
        export DOCKER_TAG=$BRIDGE_VERSION
        git clone https://github.com/strimzi/strimzi-kafka-bridge.git
        cd strimzi-kafka-bridge/
        git checkout $BRIDGE_VERSION
        patch -p1 < ${CURDIR}/bridge.diff
        if [[ "$PUSH_TO_REGISTRY" == "Y" ]]; then
                make all
        else
                make java_package docker_build
        fi

        export DOCKER_TAG=$PACKAGE_VERSION

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
            # Starting minikube with docker driver
            printf -- "Starting minikube with docker driver.\n"
            minikube start --driver docker --base-image=local/kicbase:latest --cpus=4 --memory=8192 $INSECURE_REGISTRY
            sleep 60s
            cd strimzi-kafka-operator
            mvn test
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
        echo "  build_strimzi.sh  [-d debug] [-y install-without-confirmation] [-t run-test] [-p push-to-registry] [-i insecure-registry] [-l registry-need-login] [-j Java to use from {AdoptJDK11_openj9, AdoptJDK11_hotspot, OpenJDK11}]"
        echo "  default: If no -j specified, openjdk-11 will be installed"
        echo
}

while getopts "h?dytpilj:" opt; do
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
                printf -- "    minikube start --driver docker --base-image=local/kicbase:latest --cpus=4 --memory=8192 $INSECURE_REGISTRY \n"
                printf -- "You can deploy the Cluster Operator by running the following command(replace myproject with your desired namespace if necessary): \n"
                printf -- "    kubectl -n myproject create -f strimzi-kafka-operator/packaging/install/cluster-operator \n\n"
                printf -- "Then you can deploy the cluster custom resource by running: \n"
                printf -- "    kubectl -n myproject create -f strimzi-kafka-operator/packaging/examples/kafka/kafka-ephemeral.yaml \n\n"
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
        sudo apt-get install -y git make gcc-7 g++-7 docker.io tar wget patch ruby curl conntrack cabal-install |& tee -a "${LOG_FILE}"
        setupGCC
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"ubuntu-20.04" | "ubuntu-21.04")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo apt-get update
        sudo apt-get install -y apt-utils
        sudo apt-get install -y git make gcc-7 g++-7 docker.io tar wget patch ruby curl conntrack shellcheck |& tee -a "${LOG_FILE}"
        setupGCC
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"rhel-7.8" | "rhel-7.9")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo yum install -y yum-utils
        sudo yum-config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
        sudo yum-config-manager --enable docker-ce-stable
        sudo yum install -y git make autoconf gcc gcc-c++ docker-ce tar wget patch curl conntrack ruby bison flex openssl-devel libyaml-devel libffi-devel readline-devel zlib-devel gdbm-devel ncurses-devel tcl-devel tk-devel bzip2 |& tee -a "${LOG_FILE}"
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
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"rhel-8.2" | "rhel-8.3" | "rhel-8.4")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo yum remove -y podman buildah
        sudo yum install -y yum-utils
        sudo yum-config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
        sudo yum install -y git make gcc gcc-c++ ghc ghc-Cabal ghc-Cabal-devel zlib-devel docker-ce docker-ce-cli containerd.io tar wget patch maven ruby curl conntrack hostname unzip procps snappy binutils bzip2 bzip2-devel which diffutils |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"sles-12.5")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo zypper install -y git gcc7 gcc7-c++ make autoconf tar wget patch curl which conntrack-tools ghc cabal-install docker-20.10.6_ce-98.66.1 bison flex libopenssl-devel readline-devel gdbm-devel gawk |& tee -a "${LOG_FILE}"
        setupGCC
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
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"sles-15.2")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo zypper install -y git gcc gcc-c++ make tar wget patch curl which ruby conntrack-tools ghc docker-20.10.6_ce-6.49.3 |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"sles-15.3")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo zypper install -y git gcc gcc-c++ make tar wget patch curl which ruby conntrack-tools libatomic1 docker-20.10.6_ce-6.49.3 |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

*)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "${LOG_FILE}"
        exit 1

        ;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
