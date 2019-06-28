#!/bin/bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/IstioProxy/1.1.7/build_istio_proxy.sh
# Execute build script: bash build_istio_proxy.sh    (provide -h for help)
#

set -e -o pipefail

PACKAGE_NAME="Istio Proxy"
PACKAGE_VERSION="1.1.7"
GO_VERSION="1.10.5"
CURDIR="$(pwd)"
REPO_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/IstioProxy/1.1.7/patch"
ISTIO_PROXY_REPO_URL="https://github.com/istio/proxy.git"
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
		printf -- '1:Bazel\t\tVersion: 0.24.1\n'
		printf -- '2:Envoy\n'
		printf -- '3:BoringSSL\n'
		printf -- '4:GCC\t\tVersion: gcc-7.3.0 \n'
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
	if [[ "$TESTS" == "true" ]]; then
		printf -- 'Running tests \n\n' |& tee -a "$LOG_FILE"
		if [ "${VERSION_ID}" == "12.4" ]; then
			cd "${CURDIR}"
			curl -o Makefile_test_sl12.4.diff $REPO_URL/Makefile_test_sl12.4.diff
			patch "${CURDIR}/proxy/Makefile" Makefile_test_sl12.4.diff
		else
			cd "${CURDIR}"
			curl -o Makefile_test.diff $REPO_URL/Makefile_test.diff
			patch "${CURDIR}/proxy/Makefile" Makefile_test.diff
		fi
		cd "${CURDIR}/proxy"
		make test
		printf -- '\nNote: One test case ( `//test/integration:mixer_fault_test` ) is failing on both x86 and s390x platform \n' |& tee -a "$LOG_FILE"
		printf -- 'Kindly ignore this failure and proceed with further instructions.\n' |& tee -a "$LOG_FILE"
	fi
	set -e
}

function cleanup() {
	printf -- '\nCleaned up the artifacts\n' |& tee -a "$LOG_FILE"
	rm -rf "${CURDIR}/cmake-3.7.2.tar.gz"
	rm -rf "${CURDIR}/go1.10.5.linux-s390x.tar.gz"
	rm -rf "${CURDIR}/BUILD.diff"
	rm -rf "${CURDIR}/WORKSPACE.diff"
	rm -rf "${CURDIR}/Makefile_debug.diff"
	rm -rf "${CURDIR}/Makefile_test.diff"
	rm -rf "${CURDIR}/Makefile_release.diff"
	rm -rf "${CURDIR}/Makefile_release_ub18.diff"
	rm -rf "${CURDIR}/compile.sh.diff"
	rm -rf "${CURDIR}/libcc.diff"
	rm -rf "${CURDIR}/repository_locations.bzl.patch"
	rm -rf "${CURDIR}/repositories-envoy.bzl.patch"
	rm -rf "${CURDIR}/patch_utility.diff"
	rm -rf "${CURDIR}/luajit-patch.patch"
	rm -rf "${CURDIR}/BUILD-envoy.patch"
	rm -rf "${CURDIR}/BUILD-exe.patch"
	rm -rf "${CURDIR}/BUILD-api.patch"
	rm -rf "${CURDIR}/gcc-7.3.0.tar.xz"

}

function buildGCC() {

	printf -- 'Building GCC \n' |& tee -a "$LOG_FILE"
	cd "${CURDIR}"
	wget https://ftpmirror.gnu.org/gcc/gcc-7.3.0/gcc-7.3.0.tar.xz
	tar -xf gcc-7.3.0.tar.xz
	cd gcc-7.3.0/
	./contrib/download_prerequisites
	mkdir gcc_build
	cd gcc_build/
	../configure --prefix=/opt/gcc --enable-languages=c,c++ --with-arch=zEC12 --with-long-double-128 \
		--build=s390x-linux-gnu --host=s390x-linux-gnu --target=s390x-linux-gnu \
		--enable-threads=posix --with-system-zlib --disable-multilib
	make -j 8
	sudo make install
	sudo ln -sf /opt/gcc/bin/gcc /usr/bin/gcc
	sudo ln -sf /opt/gcc/bin/g++ /usr/bin/g++
	sudo ln -sf /opt/gcc/bin/g++ /usr/bin/c++
	export PATH=/opt/gcc/bin:"$PATH"
	export LD_LIBRARY_PATH=/opt/gcc/lib64:"$LD_LIBRARY_PATH"
	export C_INCLUDE_PATH=/opt/gcc/lib/gcc/s390x-linux-gnu/7.3.0/include
	export CPLUS_INCLUDE_PATH=/opt/gcc/lib/gcc/s390x-linux-gnu/7.3.0/include

	#for rhel
	if [[ "${ID}" == "rhel" ]]; then
		sudo ln -sf /opt/gcc/lib64/libstdc++.so.6.0.24 /lib64/libstdc++.so.6
	else
		sudo ln -sf /opt/gcc/lib64/libstdc++.so.6.0.24 /usr/lib/s390x-linux-gnu/libstdc++.so.6
	fi
	printf -- 'Built GCC successfully \n' |& tee -a "$LOG_FILE"

}

function buildGO() {
	cd "${CURDIR}"
	if command -p "go" version | grep 1.10 >/dev/null; then
		printf -- "Go detected\n"
	else
		printf -- 'Installing go\n'
		cd "${CURDIR}"
		wget "https://storage.googleapis.com/golang/go${GO_VERSION}.linux-s390x.tar.gz"
		tar -xzf "go${GO_VERSION}.linux-s390x.tar.gz"
		export PATH=${CURDIR}/go/bin:$PATH
		export GOROOT=${CURDIR}/go
		go version
		printf -- 'go installed\n'
	fi
}
function installDependency() {
	printf -- 'Installing dependencies\n' |& tee -a "$LOG_FILE"
	#only for rhel
	if [[ "${ID}" == "rhel" ]]; then
		cd "${CURDIR}"
		wget https://cmake.org/files/v3.7/cmake-3.7.2.tar.gz
		tar xzf cmake-3.7.2.tar.gz
		cd cmake-3.7.2
		./configure --prefix=/usr/local
		make && sudo make install
	fi
	cd "${CURDIR}"

	printf -- 'Installing Java\n' |& tee -a "$LOG_FILE"
	cd "${CURDIR}"
	wget https://github.com/AdoptOpenJDK/openjdk11-binaries/releases/download/jdk-11.0.2%2B9/OpenJDK11U-jdk_s390x_linux_hotspot_11.0.2_9.tar.gz
	tar -xvf OpenJDK11U-jdk_s390x_linux_hotspot_11.0.2_9.tar.gz
	export JAVA_HOME=${CURDIR}/jdk-11.0.2+9
	export PATH=$JAVA_HOME/bin:$PATH
	java -version |& tee -a "$LOG_FILE"
	printf -- 'java installed\n' |& tee -a "$LOG_FILE"
	#export CC even if bazel is pre-installed
	export CC=/usr/bin/gcc
	export CXX=/usr/bin/g++

	printf -- 'Downloading Bazel\n' |& tee -a "$LOG_FILE"
	if command "bazel" version | grep 0.24.1 >/dev/null; then
		printf -- 'Bazel detected\n' |& tee -a "$LOG_FILE"
	else

		#Bazel download
		cd "${CURDIR}"
		mkdir bazel && cd bazel
		wget https://github.com/bazelbuild/bazel/releases/download/0.24.1/bazel-0.24.1-dist.zip
		unzip bazel-0.24.1-dist.zip
		chmod -R +w .
		export CC=/usr/bin/gcc
		export CXX=/usr/bin/g++

		cd "${CURDIR}"
		curl -o BUILD.diff $REPO_URL/BUILD.diff
		patch "${CURDIR}/bazel/tools/cpp/BUILD" BUILD.diff
		cd "${CURDIR}"
		curl -o libcc.diff $REPO_URL/libcc.diff
		patch "${CURDIR}/bazel/tools/cpp/lib_cc_configure.bzl" libcc.diff
		cd "${CURDIR}"
		curl -o compile.sh.diff $REPO_URL/compile.sh.diff
		patch "${CURDIR}/bazel/scripts/bootstrap/compile.sh" compile.sh.diff
		cd ${CURDIR}/bazel
		env EXTRA_BAZEL_ARGS="--host_javabase=@local_jdk//:jdk" bash ./compile.sh
		export PATH=${CURDIR}/bazel/output/:$PATH
		bazel version |& tee -a "$LOG_FILE"
		printf -- 'Bazel installed\n' |& tee -a "$LOG_FILE"
	fi

	if [ "${ID}" == "rhel" ] || [ ${VERSION_ID} == 12.4 ]; then
		printf -- '\nDownloading ninja\n' |& tee -a "$LOG_FILE"
		cd "${CURDIR}"
		git clone -b v1.8.2 git://github.com/ninja-build/ninja.git && cd ninja
		./configure.py --bootstrap
		if [ "${ID}" == "rhel" ]; then
			sudo ln -sf ${CURDIR}/ninja/ninja /usr/local/bin/ninja
			export PATH=/usr/local/bin:$PATH
		else
			sudo ln -sf ${CURDIR}/ninja/ninja /usr/bin/ninja
		fi
		ninja --version |& tee -a "$LOG_FILE"
		printf -- '\nninja installed succesfully\n' |& tee -a "$LOG_FILE"
	fi
}

function configureAndInstall() {
	printf -- '\nConfiguration and Installation started \n'
	#Installing dependencies
	printf -- 'User responded with Yes. \n'

	#Envoy download

	cd "${CURDIR}"
	printf -- '\nDownloading Envoy\n'
	git clone https://github.com/envoyproxy/envoy
	cd envoy/
	git checkout ac7aa5a

	#multiple patches to be user here
	cd "${CURDIR}"

	curl -o BUILD-envoy.patch $REPO_URL/BUILD-envoy.patch
	patch "${CURDIR}/envoy/bazel/BUILD" BUILD-envoy.patch

	curl -o luajit-patch.patch $REPO_URL/luajit-patch.patch
	patch "${CURDIR}/envoy/bazel/foreign_cc/luajit.patch" luajit-patch.patch

	curl -o repositories-envoy.bzl.patch $REPO_URL/repositories-envoy.bzl.patch
	patch "${CURDIR}/envoy/bazel/repositories.bzl" repositories-envoy.bzl.patch

	curl -o BUILD-api.patch $REPO_URL/BUILD-api.patch
	patch "${CURDIR}/envoy/source/common/api/BUILD" BUILD-api.patch

	curl -o BUILD-exe.patch $REPO_URL/BUILD-exe.patch
	patch "${CURDIR}/envoy/source/exe/BUILD" BUILD-exe.patch

	curl -o repository_locations.bzl.patch $REPO_URL/repository_locations.bzl.patch
	patch "${CURDIR}/envoy/bazel/repository_locations.bzl" repository_locations.bzl.patch

	curl -o patch_utility.diff $REPO_URL/patch_utility.diff
	patch "${CURDIR}/envoy/source/common/network/utility.cc" patch_utility.diff

	printf -- 'Envoy installed\n'

	#BoringSSL download
	cd "${CURDIR}"
	printf -- '\nDownloading BoringSSL\n'
	git clone https://github.com/linux-on-ibm-z/boringssl
	cd boringssl
	git checkout boringssl-Istio102-s390x
	printf -- 'BoringSSL installed\n'
	printenv >>"$LOG_FILE"

	#rules_foreign_cc download
	cd "${CURDIR}"
	printf -- '\nDownloading rules_foreign_cc\n'
	git clone https://github.com/bazelbuild/rules_foreign_cc.git
	cd rules_foreign_cc/
	git checkout e3f4b5e
	bazel build
	printf -- 'rules_foreign_cc installed\n'
	printenv >>"$LOG_FILE"

	cd "${CURDIR}"

	# Download and configure  Istio Proxy
	printf -- '\nDownloading  Istio Proxy. Please wait.\n'
	git clone -b $PACKAGE_VERSION $ISTIO_PROXY_REPO_URL
	sleep 2
	cd "${CURDIR}"

	#Patch Applied
	curl -o WORKSPACE.diff $REPO_URL/WORKSPACE.diff
	sed -i "s|\$SOURCE_ROOT|${CURDIR}|" WORKSPACE.diff
	cat WORKSPACE.diff
	patch "${CURDIR}/proxy/WORKSPACE" WORKSPACE.diff

	if [ -f "$PROXY_DEBUG_BIN_PATH/envoy" ]; then
		printf -- "Istio Proxy binaries (Debug mode) are found at location $PROXY_DEBUG_BIN_PATH \n"
	else
		#Build Istio Proxy In DEBUG mode
		printf -- '\nBuilding Istio Proxy In DEBUG mode\n'
		printf -- '\nBuild might take some time.Sit back and relax\n'
		if [ "${VERSION_ID}" == "12.4" ]; then
			cd "${CURDIR}"
			curl -o Makefile_debug_sl12.4.diff $REPO_URL/Makefile_debug_sl12.4.diff
			patch "${CURDIR}/proxy/Makefile" Makefile_debug_sl12.4.diff
		else
			#Patch applied for debug mode
			cd "${CURDIR}"
			curl -o Makefile_debug.diff $REPO_URL/Makefile_debug.diff
			patch "${CURDIR}/proxy/Makefile" Makefile_debug.diff
		fi
		cd "${CURDIR}/proxy"
		make build
		mkdir -p "${PROXY_DEBUG_BIN_PATH}"
		cp -r "${CURDIR}/proxy/bazel-bin/src/envoy/envoy" "${PROXY_DEBUG_BIN_PATH}/"
		printf -- 'Built Istio Proxy successfully in DEBUG mode\n\n'
	fi

	#Build Istio Proxy In RELEASE mode
	cd "${CURDIR}"
	if [ -f "$PROXY_RELEASE_BIN_PATH/envoy" ]; then
		printf -- "Istio Proxy binaries (Release mode) are found at location $PROXY_RELEASE_BIN_PATH \n"
	else
		printf -- '\nBuilding Istio Proxy In RELEASE mode\n'
		if [ "${VERSION_ID}" == "16.04" ] || [ "${ID}" == "rhel" ] || [ "${VERSION_ID}" == "15" ]; then
			#patch applied here for ubuntu 16.04
			curl -o Makefile_release.diff $REPO_URL/Makefile_release.diff
			patch "${CURDIR}/proxy/Makefile" Makefile_release.diff
		elif [ "${VERSION_ID}" == "18.04" ]; then
			#patch applied here for ubuntu 18.04
			curl -o Makefile_release_ub18.diff $REPO_URL/Makefile_release_ub18.diff
			patch "${CURDIR}/proxy/Makefile" Makefile_release_ub18.diff
		elif [ "${VERSION_ID}" == "12.4" ]; then
			curl -o Makefile_release_sl12.4.diff $REPO_URL/Makefile_release_sl12.4.diff
			patch "${CURDIR}/proxy/Makefile" Makefile_release_sl12.4.diff
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
	sudo apt-get install -y git tar pkg-config zip g++ zlib1g-dev unzip python libtool automake cmake curl wget build-essential realpath ninja-build clang-format-5.0 golang-1.10
	export PATH=/usr/lib/go-1.10/bin:$PATH
	buildGCC
	installDependency
	configureAndInstall |& tee -a "$LOG_FILE"

	;;

"ubuntu-18.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
	sudo apt-get update
	sudo apt-get install -y git pkg-config zip zlib1g-dev unzip python libtool automake cmake curl wget build-essential rsync clang gcc-7 g++-7 libgtk2.0-0 ninja-build clang-format-5.0 golang-1.10
	sudo rm -rf /usr/bin/gcc /usr/bin/g++ /usr/bin/cc
	sudo ln -sf /usr/bin/gcc-7 /usr/bin/gcc
	sudo ln -sf /usr/bin/g++-7 /usr/bin/g++
	sudo ln -sf /usr/bin/gcc /usr/bin/cc
	export PATH=/usr/lib/go-1.10/bin:$PATH
	installDependency
	configureAndInstall |& tee -a "$LOG_FILE"

	;;

"ubuntu-19.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- '\nInstalling dependencies \n' |& tee -a "$LOG_FILE"
	sudo apt-get update
	sudo apt-get install -y git pkg-config zip zlib1g-dev unzip python libtool automake cmake curl wget build-essential rsync clang gcc-7 g++-7 libgtk2.0-0 ninja-build clang-format-8 golang-1.10
	sudo rm -rf /usr/bin/gcc /usr/bin/g++ /usr/bin/cc
	sudo ln -sf /usr/bin/gcc-7 /usr/bin/gcc
	sudo ln -sf /usr/bin/g++-7 /usr/bin/g++
	sudo ln -sf /usr/bin/gcc /usr/bin/cc
	export PATH=/usr/lib/go-1.10/bin:$PATH
	installDependency
	configureAndInstall |& tee -a "$LOG_FILE"

	;;

"rhel-7.4" | "rhel-7.5" | "rhel-7.6")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for Go from repository \n' |& tee -a "$LOG_FILE"
	sudo yum install -y hostname git tar zip gcc-c++ unzip python libtool automake cmake curl wget gcc vim patch binutils-devel bzip2 make | tee -a "${LOG_FILE}"
	buildGCC
	buildGO |& tee -a "$LOG_FILE"
	installDependency
	configureAndInstall | tee -a "${LOG_FILE}"
	;;

"sles-12.4")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- 'Installing the dependencies for Go from repository \n' |& tee -a "$LOG_FILE"
	sudo zypper install -y wget git tar pkg-config zip unzip python libtool automake cmake zlib-devel gcc7 gcc7-c++ binutils-devel patch which curl
	sudo ln -sf /usr/bin/gcc-7 /usr/bin/gcc
	sudo ln -sf /usr/bin/g++-7 /usr/bin/g++
	sudo ln -sf /usr/bin/gcc /usr/bin/cc
	buildGO |& tee -a "$LOG_FILE"
	installDependency
	configureAndInstall | tee -a "${LOG_FILE}"
	;;

"sles-15")
	sudo zypper install -y wget git tar pkg-config zip unzip python libtool automake cmake zlib-devel gcc gcc-c++ binutils-devel patch which curl python-xml libxml2-devel ninja
	buildGO |& tee -a "$LOG_FILE"
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
