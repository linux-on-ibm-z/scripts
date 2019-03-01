#!/bin/bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/IstioProxy/build_istio_proxy.sh
# Execute build script: bash build_istio_proxy.sh    (provide -h for help)
#

set -e -o pipefail

PACKAGE_NAME="Istio Proxy"
PACKAGE_VERSION="1.0.5"
CURDIR="$(pwd)"
REPO_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/IstioProxy/patch"
ISTIO_PROXY_REPO_URL="https://github.com/istio/proxy.git"
BAZEL_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Bazel/build_bazel.sh"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
FORCE="false"
TESTS="false"
PROXY_DEBUG_BIN_PATH="$CURDIR/proxy/debug"
PROXY_RELEASE_BIN_PATH="$CURDIR/proxy/release"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
	mkdir -p "$CURDIR/logs/"
fi

#
if [ -f "/etc/os-release" ]; then
	source "/etc/os-release"
fi

function prepare() {

	if command -v "sudo" >/dev/null; then
		printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
	else
		printf -- 'Sudo : No \n' >>"$LOG_FILE"
		printf -- 'You can install sudo from repository using apt, yum or zypper based on your distro. \n'
		exit 1
	fi

	if [[ "$FORCE" == "true" ]]; then
		printf -- 'Force attribute provided hence continuing with install without confirmation message'
	else
		printf -- '\nFollowing packages are needed before going ahead\n'
		printf -- '1:Bazel\t\tVersion: 0.15.2\n'
		printf -- '2:Envoy\n'
		printf -- '3:BoringSSL\n'
		printf -- '4:GCC\t\tVersion: gcc-6.3.0 \n'
		printf -- '5:Go\t\tVersion: go1.10.5\n\n'

		printf -- '\nBuild might take some time.Sit back and relax'
		while true; do
			read -r -p "Do you want to continue (y/n) ? :  " yn
			case $yn in
			[Yy]*)

				break
				;;
			[Nn]*) exit ;;
			*) echo "Please provide Correct input to proceed." ;;
			esac
		done
	fi
}

function runTest() {
	set +e
	cd "${CURDIR}"
	if [[ "$TESTS" == "true" ]]; then
		curl -o referenced.cc.diff $REPO_URL/referenced.cc.diff
		patch "${CURDIR}/proxy/src/istio/mixerclient/referenced.cc" referenced.cc.diff
		if [[ "${ID}" == "sles" ]]; then
			#patch for sles
			curl -o Makefile_sles.diff $REPO_URL/Makefile_sles.diff
			patch "${CURDIR}/proxy/Makefile" Makefile_sles.diff
		else
			#Patch for ubuntu and rhel
			curl -o Makefile_ubuntu_rhel.diff $REPO_URL/Makefile_ubuntu_rhel.diff
			patch "${CURDIR}/proxy/Makefile" Makefile_ubuntu_rhel.diff
		fi	
		cd "${CURDIR}/proxy"
		make test
	fi
	set -e
}

function cleanup() {
	printf -- '\nCleaned up the artifacts\n' |& tee -a "$LOG_FILE"
	rm -rf "${CURDIR}/cmake-3.7.2.tar.gz"
	rm -rf "${CURDIR}/ninja"
	rm -rf "${CURDIR}/go1.10.5.linux-s390x.tar.gz"
	rm -rf "${CURDIR}/benchmark.sh.diff"
	rm -rf "${CURDIR}/luajit.sh.diff"
	rm -rf "${CURDIR}/BUILD.diff"
	rm -rf "${CURDIR}/utility.cc.diff"
	rm -rf "${CURDIR}/signal_action.cc.diff"
	rm -rf "${CURDIR}/lua.h.diff"
	rm -rf "${CURDIR}/WORKSPACE.diff"
	rm -rf "${CURDIR}/Makefile_debug_sles.diff"
	rm -rf "${CURDIR}/Makefile_ub16_rhel.diff"
	rm -rf "${CURDIR}/Makefile_ub18.diff"
	rm -rf "${CURDIR}/Makefile_release_sles.diff"
	rm -rf "${CURDIR}/gcc-6.3.0.tar.gz"
	rm -rf "${CURDIR}/referenced.cc.diff"
}

function buildGCC() {

	printf -- 'Building GCC \n'
	cd "${CURDIR}"
	wget ftp://gcc.gnu.org/pub/gcc/releases/gcc-6.3.0/gcc-6.3.0.tar.gz
	tar -xvzf gcc-6.3.0.tar.gz
	cd gcc-6.3.0/
	./contrib/download_prerequisites
	cd "${CURDIR}"
	mkdir gcc_build
	cd gcc_build/
	../gcc-6.3.0/configure --prefix="/opt/gcc" --enable-shared --with-system-zlib --enable-threads=posix --enable-__cxa_atexit --enable-checking --enable-gnu-indirect-function --enable-languages="c,c++" --disable-bootstrap --disable-multilib
	make
	sudo make install
	export PATH=/opt/gcc/bin:$PATH
	sudo ln -sf /opt/gcc/bin/gcc /usr/bin/gcc
	export C_INCLUDE_PATH=/opt/gcc/lib/gcc/s390x-ibm-linux-gnu/6.3.0/include
	export CPLUS_INCLUDE_PATH=/opt/gcc/lib/gcc/s390x-ibm-linux-gnu/6.3.0/include

	#for rhel
	if [[ "${ID}" == "rhel" ]]; then
		sudo ln -sf /opt/gcc/lib64/libstdc++.so.6.0.22 /lib64/libstdc++.so.6
	else
		sudo ln -sf /opt/gcc/lib64/libstdc++.so.6.0.22 /usr/lib/s390x-linux-gnu/libstdc++.so.6
	fi
	export LD_LIBRARY_PATH='/opt/gcc/$LIB'
	printf -- 'Built GCC successfully \n' |& tee -a "$LOG_FILE"

}

function installDependency() {
	printf -- 'Installing dependencies\n' |& tee -a "$LOG_FILE"
	cd "${CURDIR}"
	if command -v "go" >/dev/null; then
			printf -- "Go detected\n"
	else
			printf -- 'Installing go\n'
			cd "${CURDIR}"
			wget "https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Go/build_go.sh"
			bash build_go.sh -v $GO_VERSION
			export GOROOT="/usr/local/go"
			go version 
			printf -- 'go installed\n'
	fi	


	printf -- 'Downloading Bazel\n' |& tee -a "$LOG_FILE"
	if [[ -z "$(command -v bazel)" ]]; then

		#Bazel download
		cd "${CURDIR}"
		curl -o build_bazel.sh "$BAZEL_URL"
		chmod +x build_bazel.sh
		bash build_bazel.sh
		printf -- 'Bazel installed\n' |& tee -a "$LOG_FILE"
	else
		printf -- 'Bazel detected\n' |& tee -a "$LOG_FILE"
	fi
}

function configureAndInstall() {
	printf -- '\nConfiguration and Installation started \n'
	#Installing dependencies
	printf -- 'User responded with Yes. \n'

	#only for rhel
	if [[ "${ID}" == "rhel" ]]; then
		cd "${CURDIR}"
		wget https://cmake.org/files/v3.7/cmake-3.7.2.tar.gz
		tar xzf cmake-3.7.2.tar.gz
		cd cmake-3.7.2
		./configure --prefix=/usr/local
		make && sudo make install
	fi

	#Exports for GCC
	export PATH=/opt/gcc/bin:$PATH
	export C_INCLUDE_PATH=/opt/gcc/lib/gcc/s390x-ibm-linux-gnu/6.3.0/include
	export CPLUS_INCLUDE_PATH=/opt/gcc/lib/gcc/s390x-ibm-linux-gnu/6.3.0/include
	export LD_LIBRARY_PATH='/opt/gcc/$LIB'

        if [ "${ID}" == "rhel" ] || [ ${VERSION_ID} == 12.3 ]; then
                printf -- '\nDownloading ninja\n'
                cd "${CURDIR}"
                git clone -b v1.8.2 git://github.com/ninja-build/ninja.git && cd ninja
                ./configure.py --bootstrap
                if [ "${ID}" == "rhel" ]; then
                sudo ln -sf ${CURDIR}/ninja/ninja /usr/local/bin/ninja
                export PATH=/usr/local/bin:$PATH
                else
                sudo ln -sf ${CURDIR}/ninja/ninja /usr/bin/ninja
                fi
                ninja --version
                printf -- '\nninja installed succesfully\n'
        fi


	#Envoy download

	cd "${CURDIR}"
	printf -- '\nDownloading Envoy\n'
	git clone https://github.com/istio/envoy
	cd envoy/
	git checkout 2d8386532f

	#multiple patches to be user here
	cd "${CURDIR}"
	curl -o benchmark.sh.diff $REPO_URL/benchmark.sh.diff
	patch "${CURDIR}/envoy/ci/build_container/build_recipes/benchmark.sh" benchmark.sh.diff

	curl -o luajit.sh.diff $REPO_URL/luajit.sh.diff
	patch "${CURDIR}/envoy/ci/build_container/build_recipes/luajit.sh" luajit.sh.diff

	curl -o BUILD.diff $REPO_URL/BUILD.diff
	patch "${CURDIR}/envoy/ci/prebuilt/BUILD" BUILD.diff

	curl -o utility.cc.diff $REPO_URL/utility.cc.diff
	patch "${CURDIR}/envoy/source/common/network/utility.cc" utility.cc.diff

	curl -o signal_action.cc.diff $REPO_URL/signal_action.cc.diff
	patch "${CURDIR}/envoy/source/exe/signal_action.cc" signal_action.cc.diff

	curl -o lua.h.diff $REPO_URL/lua.h.diff
	patch "${CURDIR}/envoy/source/extensions/filters/common/lua/lua.h" lua.h.diff

	printf -- 'Envoy installed\n'

	#BoringSSL download
	cd "${CURDIR}"
	printf -- '\nDownloading BoringSSL\n'
	git clone -b boringssl-Istio102-s390x https://github.com/linux-on-ibm-z/boringssl
	printf -- 'BoringSSL installed\n'
	printenv >>"$LOG_FILE"
	
	cd "${CURDIR}"

	# Download and configure  Istio Proxy
	printf -- '\nDownloading  Istio Proxy. Please wait.\n'
	git clone -b $PACKAGE_VERSION $ISTIO_PROXY_REPO_URL
	sleep 2
	cd "${CURDIR}"

	#Patch Applied
	curl -o WORKSPACE.diff $REPO_URL/WORKSPACE.diff
	sed -i "s|/<source_root>|${CURDIR}|" WORKSPACE.diff
	cat WORKSPACE.diff
	patch "${CURDIR}/proxy/WORKSPACE" WORKSPACE.diff

	
	
	if [ -f "$PROXY_DEBUG_BIN_PATH/envoy" ]
	then
        printf -- "Istio Proxy binaries (Debug mode) are found at location $PROXY_DEBUG_BIN_PATH \n"
	else
		#Build Istio Proxy In DEBUG mode
		printf -- '\nBuilding Istio Proxy In DEBUG mode\n'
		printf -- '\nBuild might take some time.Sit back and relax\n'

		#Patch applied for sles
		if [[ "${ID}" == "sles" ]]; then
			cd "${CURDIR}"
			curl -o Makefile_debug_sles.diff $REPO_URL/Makefile_debug_sles.diff
			patch "${CURDIR}/proxy/Makefile" Makefile_debug_sles.diff
		fi
		cd "${CURDIR}/proxy"
		make build
		mkdir -p "${PROXY_DEBUG_BIN_PATH}"
		cp -r "${CURDIR}/proxy/bazel-bin/src/envoy/envoy" "${PROXY_DEBUG_BIN_PATH}/"
		printf -- 'Built Istio Proxy successfully in DEBUG mode\n\n'
	fi

	#Build Istio Proxy In RELEASE mode
	cd "${CURDIR}"
	if [ -f "$PROXY_RELEASE_BIN_PATH/envoy" ]
	then
		printf -- "Istio Proxy binaries (Release mode) are found at location $PROXY_RELEASE_BIN_PATH \n"
	else
		printf -- '\nBuilding Istio Proxy In RELEASE mode\n'
		if [ "${VERSION_ID}" == "16.04" ] || [ "${ID}" == "rhel" ]; then
			#patch applied here for ubuntu 16.04
			curl -o Makefile_ub16_rhel.diff $REPO_URL/Makefile_ub16_rhel.diff
			patch "${CURDIR}/proxy/Makefile" Makefile_ub16_rhel.diff
		elif [ "${VERSION_ID}" == "18.04" ]; then
			#patch applied here for ubuntu 18.04
			curl -o Makefile_ub18.diff $REPO_URL/Makefile_ub18.diff
			patch "${CURDIR}/proxy/Makefile" Makefile_ub18.diff
		else
			#Patch for sles
			curl -o Makefile_release_sles.diff $REPO_URL/Makefile_release_sles.diff
			patch "${CURDIR}/proxy/Makefile" Makefile_release_sles.diff
		fi

		printf -- '\nBuild might take some time.Sit back and relax\n'
		cd "${CURDIR}/proxy"
		make build
		mkdir -p "$PROXY_RELEASE_BIN_PATH"
		cp -r "${CURDIR}/proxy/bazel-bin/src/envoy/envoy" "${PROXY_RELEASE_BIN_PATH}/"
		printf -- 'Built Istio Proxy successfully in RELEASE mode\n\n'
	fi
	
	#Run tests
	runTest

}

function logDetails() {
	printf -- 'SYSTEM DETAILS\n' >"$LOG_FILE"
	if [ -f "/etc/os-release" ]; then
		cat "/etc/os-release" >>"$LOG_FILE"
	fi

	cat /proc/version >>"$LOG_FILE"
	printf -- "\nDetected %s \n" "$PRETTY_NAME"
	printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" |& tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
	echo
	echo "Usage: "
	echo "  install.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests]"
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

function printSummary() {
	printf -- '\n\nInstallation completed successfully.\n' |& tee -a "$LOG_FILE"
}

logDetails
#checkPrequisites
prepare |& tee -a "$LOG_FILE"

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
	sudo apt-get update
	sudo apt-get install -y patch git tar openjdk-8-jdk pkg-config zip g++ zlib1g-dev unzip python libtool automake cmake curl wget build-essential realpath ninja-build clang-format-5.0
	installDependency
	configureAndInstall |& tee -a "$LOG_FILE"

	;;

"ubuntu-18.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
	sudo apt-get update
	sudo apt-get install -y patch git openjdk-8-jdk pkg-config zip zlib1g-dev unzip python libtool automake cmake curl wget build-essential rsync clang g++-6 libgtk2.0-0 ninja-build clang-format-5.0
	sudo rm -rf /usr/bin/gcc /usr/bin/g++ /usr/bin/cc
	sudo ln -sf /usr/bin/gcc-6 /usr/bin/gcc
	sudo ln -sf /usr/bin/g++-6 /usr/bin/g++
	sudo ln -sf /usr/bin/gcc /usr/bin/cc
	installDependency
	configureAndInstall |& tee -a "$LOG_FILE"

	;;
"rhel-7.4" | "rhel-7.5" | "rhel-7.6" )
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for Go from repository \n' |& tee -a "$LOG_FILE"
	sudo yum install -y git tar java-1.8.0-openjdk java-1.8.0-openjdk-devel zip gcc-c++ unzip python libtool automake cmake curl wget gcc vim patch binutils-devel bzip2 make | tee -a "${LOG_FILE}"
	buildGCC |& tee -a "$LOG_FILE"
	installDependency	
	configureAndInstall | tee -a "${LOG_FILE}"
	;;

"sles-12.3")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for Go from repository \n' |& tee -a "$LOG_FILE"
	sudo zypper install -y java-1_8_0-openjdk java-1_8_0-openjdk-devel wget git tar pkg-config zip unzip python libtool automake cmake zlib-devel gcc6 gcc6-c++ binutils-devel patch which curl
	sudo ln -sf /usr/bin/gcc-6 /usr/bin/gcc
	sudo ln -sf /usr/bin/g++-6 /usr/bin/g++
	sudo ln -sf /usr/bin/gcc /usr/bin/cc
	installDependency
	configureAndInstall | tee -a "${LOG_FILE}"
	;;
"sles-15")
	sudo zypper install -y java-1_8_0-openjdk java-1_8_0-openjdk-devel wget git tar pkg-config zip unzip python libtool automake cmake zlib-devel gcc gcc-c++ binutils-devel patch which curl python-xml libxml2-devel ninja
	installDependency
	configureAndInstall | tee -a "${LOG_FILE}"
	;;
*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

# Print Summary
printSummary
