#!/bin/bash
# © Copyright IBM Corporation 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/SonarQube/8.4/build_sonarqube.sh
# Execute build script: bash build_sonarqube.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="sonarqube"
PACKAGE_VERSION="8.4.0.35506"
SCANNER_VERSION="4.4.0.2170"

SOURCE_ROOT="$(pwd)"
BUILD_DIR="/usr/local"
BUILD_ENV="$HOME/setenv.sh"

TESTS="false"
FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
JAVA_PROVIDED="AdoptJDK11"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
    mkdir -p "$SOURCE_ROOT/logs/"
fi

source "/etc/os-release"


function prepare() {
    if command -v "sudo" >/dev/null; then
        printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
    else
        printf -- 'Sudo : No \n' >>"$LOG_FILE"
        printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n'
        exit 1
    fi

    if [[ "$JAVA_PROVIDED" != "AdoptJDK11" && "$JAVA_PROVIDED" != "OpenJDK" ]]
    then
        printf --  "$JAVA_PROVIDED is not supported, Please use valid java from {AdoptJDK11, OpenJDK} only." |& tee -a "$LOG_FILE"
        exit 1
    fi

    if [[ "$JAVA_PROVIDED" == "OpenJDK" ]];
    then
        if [[ "$ID-$VERSION_ID" == "ubuntu-16.04" ]];
        then
            printf --  "OpenJDK is not supported on $ID-$VERSION_ID.\n" |& tee -a "$LOG_FILE"

            while true; do
                read -r -p "Do you want to build with AdoptJDK11 (y/n) ? :  " yn
                case $yn in
                [Yy]*)
                    JAVA_PROVIDED="AdoptJDK11"
                    printf -- 'SonarQube will be built with AdoptOpenJDK11. \n' >>"$LOG_FILE" |& tee -a "$LOG_FILE"
                    break
                    ;;
                [Nn]*) exit ;;
                *) echo "Please provide confirmation to proceed." ;;
                esac
            done
        fi
    fi

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

function cleanup() {
    # Remove artifacts
    sudo rm -rf sonar-scanner-cli-${SCANNER_VERSION}-linux.zip sonarqube-${PACKAGE_VERSION}.zip
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

    echo "Java provided by user $JAVA_PROVIDED" >> "$LOG_FILE"
    if [[ "$JAVA_PROVIDED" == "AdoptJDK11" ]]; then
        # Install AdoptOpenJDK 11 (With OpenJ9)

        cd "$SOURCE_ROOT"
        sudo wget https://github.com/AdoptOpenJDK/openjdk11-binaries/releases/download/jdk-11.0.4%2B11_openj9-0.15.1/OpenJDK11U-jdk_s390x_linux_openj9_11.0.4_11_openj9-0.15.1.tar.gz
        sudo tar -C /usr/local -xzf OpenJDK11U-jdk_s390x_linux_openj9_11.0.4_11_openj9-0.15.1.tar.gz
        export JAVA_HOME=/usr/local/jdk-11.0.4+11

        printf -- 'export JAVA_HOME=/usr/local/jdk-11.0.4+11\n'  >> "$BUILD_ENV"
        printf -- 'AdoptOpenJDK 11 installed\n' >> "$LOG_FILE"
    elif [[ "$JAVA_PROVIDED" == "OpenJDK" ]]; then
        if [[ "$ID" == "rhel" ]]; then
            sudo yum install -y java-11-openjdk-devel   
            export JAVA_HOME=/usr/lib/jvm/java-11-openjdk     
            printf -- 'export JAVA_HOME=/usr/lib/jvm/java-11-openjdk\n'  >> "$BUILD_ENV"   
        elif [[ "$ID" == "sles" ]]; then
            sudo zypper install -y java-11-openjdk-devel
            export JAVA_HOME=/usr/lib64/jvm/java-11-openjdk
            printf -- 'export JAVA_HOME=/usr/lib64/jvm/java-11-openjdk\n'  >> "$BUILD_ENV"
        else
            if [[ "$VERSION_ID" == "20.04" || "$VERSION_ID" == "18.04" ]]; then
                sudo apt-get install -y openjdk-11-jdk
                export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x
                printf -- 'export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x\n'  >> "$BUILD_ENV"
            fi
        fi
        
    else
        printf --  '$JAVA_PROVIDED is not supported, Please use valid java from {AdoptJDK11, OpenJDK} only' >> "$LOG_FILE"
        exit 1
    fi

    export PATH=$JAVA_HOME/bin:$PATH
    java -version >> "$LOG_FILE"
    printf -- 'export JAVA_HOME for "$ID"  \n'  >> "$LOG_FILE"

    printf -- 'export PATH=$JAVA_HOME/bin:$PATH\n'  >> "$BUILD_ENV"
    
    #Download Sonarqube
    cd "$SOURCE_ROOT"
    wget https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-${PACKAGE_VERSION}.zip
    unzip sonarqube-${PACKAGE_VERSION}.zip
    wget https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SCANNER_VERSION}-linux.zip
    unzip sonar-scanner-cli-${SCANNER_VERSION}-linux.zip
    printf -- "Download sonarqube success\n"

        if ([[ -z "$(cut -d: -f1 /etc/group | grep sonarqube)" ]]); then
                printf -- '\nCreating group sonarqube\n'
                sudo groupadd sonarqube      # If group is not already created

        fi
        sudo usermod -aG sonarqube $(whoami)

    sudo cp -Rf "$SOURCE_ROOT"/sonarqube-${PACKAGE_VERSION} "$BUILD_DIR"

    #Give permission to user
    sudo chown $(whoami):sonarqube -R "$BUILD_DIR/sonarqube-${PACKAGE_VERSION}"

    #Run Test
    runTest

    #cleanup
    cleanup

}

function runTest() {

    set +e
    if [[ "$TESTS" == "true" ]]; then
        printf -- 'Running tests \n\n' |& tee -a "$LOG_FILE"
        source $HOME/setenv.sh
        java -version >> "$LOG_FILE"
        cd /usr/local/sonarqube-${PACKAGE_VERSION}/lib/
        java -jar sonar-application-${PACKAGE_VERSION}.jar &
        pid=$!
        sleep 15m

        if grep -q "HTTP connector enabled on port 9000" "$BUILD_DIR/sonarqube-${PACKAGE_VERSION}/logs/web.log" && grep -q "SonarQube is up" "$BUILD_DIR/sonarqube-${PACKAGE_VERSION}/logs/sonar.log" ; then
		    sudo netstat -nlp | grep :9000
            curl http://localhost:9000
            printf -- "Success !! You have successfully started sonarqube.\n" 
        fi

        cd "$SOURCE_ROOT"
        sed -i "40d" "$SOURCE_ROOT"/sonar-scanner-${SCANNER_VERSION}-linux/bin/sonar-scanner
        sed -i '40 i use_embedded_jre=false' "$SOURCE_ROOT"/sonar-scanner-${SCANNER_VERSION}-linux/bin/sonar-scanner
        git clone https://github.com/khatilov/sonar-examples.git

        #Run Java Scanner
        cd "$SOURCE_ROOT"/sonar-examples/projects/languages/java/sonar-runner/java-sonar-runner-simple/
        "$SOURCE_ROOT"/sonar-scanner-${SCANNER_VERSION}-linux/bin/sonar-scanner
        curl http://localhost:9000/dashboard/index/java-sonar-runner-simple

        #Run Javacript scanner
        if [[ $DISTRO = "rhel-8."* ]]; then	
			# Inside rhel 8.x
		    sudo yum install -y wget tar make gcc gcc-c++ procps
		elif [[ $DISTRO = "rhel-7."* ]]; then	
			# Inside rhel 7.x
		    cd $SOURCE_ROOT
		    sudo yum install -y wget tar make flex gcc gcc-c++ binutils-devel bzip2
		    wget https://ftpmirror.gnu.org/gcc/gcc-5.4.0/gcc-5.4.0.tar.gz
		    tar -xf gcc-5.4.0.tar.gz && cd gcc-5.4.0/
		    ./contrib/download_prerequisites && cd ..
		    mkdir gccbuild && cd gccbuild
		    ../gcc-5.4.0/configure --prefix=/opt/gcc-5.4.0 --enable-checking=release --enable-languages=c,c++ --disable-multilib
		    make -j4 && sudo make install
		    export PATH=/opt/gcc-5.4.0/bin:$PATH
		    export LD_LIBRARY_PATH=/opt/gcc-5.4.0/lib64/
		    gcc --version
		fi

        cd "$SOURCE_ROOT"
        wget https://nodejs.org/dist/latest-v10.x/node-v10.21.0-linux-s390x.tar.xz
        chmod ugo+r node-v10.21.0-linux-s390x.tar.xz
        sudo tar -C /usr/local -xf node-v10.21.0-linux-s390x.tar.xz
		export PATH=$PATH:/usr/local/node-v10.21.0-linux-s390x/bin
		node -v
        
        cd "$SOURCE_ROOT"/sonar-examples/projects/languages/javascript/javascript-sonar-runner/
		"$SOURCE_ROOT"/sonar-scanner-${SCANNER_VERSION}-linux/bin/sonar-scanner
		curl http://localhost:9000/dashboard/index/org.codehaus.sonar:javascript-sonar-runner

        # Run Python scanner
		cd "$SOURCE_ROOT"/sonar-examples/projects/languages/python/python-sonar-runner
		"$SOURCE_ROOT"/sonar-scanner-${SCANNER_VERSION}-linux/bin/sonar-scanner
		curl http://localhost:9000/dashboard/index/org.codehaus.sonar:example-python-sonar-runner

		# Run PHP scanner
		cd "$SOURCE_ROOT"/sonar-examples/projects/languages/php/php-sonar-runner
		"$SOURCE_ROOT"/sonar-scanner-${SCANNER_VERSION}-linux/bin/sonar-scanner
		curl http://localhost:9000/dashboard/index/org.codehaus.sonar:php-sonar-runner
        if [[ $(ps -A| grep $pid |wc -l) -ne 0 ]]; then #check whether process is still running
                sudo pkill -P $pid
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
    echo " build_sonarqube.sh  [-d debug] [-y install-without-confirmation] [-t install and run tests] [-j Java to use from {AdoptJDK11, OpenJDK}]"
    echo "       default: If no -j specified, AdoptJDK11 will be installed."
    echo
}

while getopts "h?dytj:" opt; do
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
    j)
        JAVA_PROVIDED="$OPTARG"
        ;;
    esac
done

function gettingStarted() {
    source $HOME/setenv.sh
    printf -- '\n********************************************************************************************************\n'
    printf -- "\n*Getting Started * \n"
    printf -- "Running sonarqube: \n"
    printf -- "Set Environment variable JAVA_HOME and PATH \n"
    printf -- " export PATH=$JAVA_HOME/bin:\"\$PATH\" \n"
    printf -- "cd /usr/local/sonarqube-$PACKAGE_VERSION/lib/ \n"
    printf -- "java -jar sonar-application-$PACKAGE_VERSION.jar \n\n"
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04" | "ubuntu-20.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y wget git unzip tar curl |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-7.6" | "rhel-7.7" | "rhel-7.8" | "rhel-8.1" | "rhel-8.2")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y git wget unzip tar which curl net-tools xz |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-12.5" | "sles-15.1")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y git wget unzip tar which gzip curl |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
