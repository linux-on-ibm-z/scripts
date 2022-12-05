#!/bin/bash
# © Copyright IBM Corporation 2022.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Couchbase/7.0.2/build_couchbase.sh
# Execute build script: bash build_couchbase.sh  (provide -h for help)
#

set -e -o pipefail

PACKAGE_NAME="couchbase"
PACKAGE_VERSION="7.0.2"
CURDIR="$(pwd)"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Couchbase/7.0.2/patch"
DATE_AND_TIME="$(date +"%F-%T")"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-${DATE_AND_TIME}.log"
FORCE="false"
TESTS="false"
HAS_PREFIX="false"
CB_PREFIX="$CURDIR/couchbase/install"
trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
  mkdir -p "$CURDIR/logs/"
fi

if [ -f "/etc/os-release" ]; then
  source "/etc/os-release"
else
  printf -- "%s Package with version %s is currently not supported for %s .\n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
fi

function prepare() {

  if command -v "sudo" >/dev/null; then
    printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
  else
    printf -- 'Sudo : No \n' >>"$LOG_FILE"
    printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n'
    exit 1
  fi

  if [[ "$FORCE" == "true" ]]; then
    printf -- 'Force attribute provided hence continuing with install without confirmation message. \n'
  else
    printf -- '\nBuild might take some time...'
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
  cd "${CURDIR}"/couchbase/build
  if [[ "$TESTS" == "true" ]]; then
    printf -- '\nRunning Couchbase tests...\n'
    export PATH=$PATH:/usr/local/bin
    export LD_LIBRARY_PATH=/usr/local/lib64:/usr/local/lib:/usr/lib:/usr/lib64
    sudo ctest --timeout 1000
  fi
  set -e
}

function cleanup() {
  printf -- '\nCleaned up the artifacts\n' |& tee -a "$LOG_FILE"
  : '
  sudo rm -rf ${CURDIR}/boost_1_74_0
  rm -rf ${CURDIR}/crc32-s390x
  rm -rf ${CURDIR}/curl
  rm -rf ${CURDIR}/depot_tools
  rm -rf ${CURDIR}/erlang
  rm -rf ${CURDIR}/flatbuffers
  rm -rf ${CURDIR}/fmt
  rm -rf ${CURDIR}/folly
  rm -rf ${CURDIR}/gcc-10.2.0
  rm -rf ${CURDIR}/gn
  rm -rf ${CURDIR}/go
  sudo rm -rf ${HOME}/go/src/github.com/prometheus
  rm -rf ${CURDIR}/grpc
  rm -rf ${CURDIR}/jemalloc
  rm -rf ${CURDIR}/json
  rm -rf ${CURDIR}/llvm-project
  rm -rf ${CURDIR}/node-v16.14.2-linux-s390x
  rm -rf ${CURDIR}/numactl
  rm -rf ${CURDIR}/openssl-1.1.1k
  rm -rf ${CURDIR}/pcre-8.43
  rm -rf ${CURDIR}/prometheus-cpp
  rm -rf ${CURDIR}/protobuf
  rm -rf ${CURDIR}/rocksdb
  rm -rf ${CURDIR}/v8
  rm -rf ${CURDIR}/*.tar.*
  rm -rf ${CURDIR}/Miniconda3-py38_4.10.3-Linux-s390x.sh
  '
}

function installClang12() {
  cd "${CURDIR}"
  printf -- 'Installing clang\n'
  git clone https://github.com/llvm/llvm-project.git
  cd llvm-project
  git checkout llvmorg-12.0.0
  mkdir build && cd build
  cmake -DLLVM_ENABLE_PROJECTS=clang -G "Unix Makefiles" ../llvm
  make -j$(nproc)
  sudo make install
}

function installV8() {
  cd "${CURDIR}"
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
  cd "${CURDIR}"/depot_tools
  git checkout a0382d39be0d7bf0f0766633185f20dcdd32a459
  export PATH=$PATH:"${CURDIR}"/depot_tools
  export VPYTHON_BYPASS="manually managed python not supported by chrome operations"
  export DEPOT_TOOLS_UPDATE=0

  cd "${CURDIR}"
  git clone https://gn.googlesource.com/gn
  cd gn
  git checkout 8948350
  sed -i -e 's/-Wl,--icf=all//g' ./build/gen.py
  sed -i -e 's/-lpthread/-pthread/g' ./build/gen.py
  if [[ "${DISTRO}" == "sles-12.5" ]]; then
    sed -i -e 's/clang++/gcc/g' ./build/gen.py
  fi
  python build/gen.py
  ninja -C out
  export PATH="${CURDIR}"/gn/out:$PATH
  sudo ldconfig /usr/local/lib64 /usr/local/lib

  cd "${CURDIR}"
  printf -- 'Installing V8\n'
  cat > .gclient <<EOF
solutions = [
  {
    "url": "https://chromium.googlesource.com/v8/v8.git@8.3.110.9",
    "managed": False,
    "name": "v8",
    "deps_file": "DEPS",
  },
];
EOF
  gclient sync

  cd v8
  wget "${PATCH_URL}"/v8.diff -P ${CURDIR}/patch
  git apply ${CURDIR}/patch/v8.diff
  mkdir out/s390x.release
  gn gen out/s390x.release --args='is_component_build=true target_cpu="s390x" v8_target_cpu="s390x" use_goma=false goma_dir="None" v8_enable_backtrace=true treat_warnings_as_errors=false is_clang=false use_custom_libcxx_for_host=false use_custom_libcxx=false v8_use_external_startup_data=false is_debug=false'
  ninja -C "${CURDIR}"/v8/out/s390x.release -j$(nproc)
  cd out/s390x.release
  sudo cp libv8*.so /usr/local/lib
  sudo cp libchrome*.so /usr/local/lib
  sudo cp libcppgc*.so /usr/local/lib
  sudo cp libicu*.so /usr/local/lib
  sudo cp icu*.* /usr/local/lib
  if [[ "${DISTRO}" == "ubuntu-18.04" ]]; then
    cd /usr/local/lib
  	sudo ln -s libicui18n.so libicui18n.so.65
  	sudo ln -s libicuuc.so libicuuc.so.65
  fi
  cd "${CURDIR}"/v8/include
  sudo mkdir -p /usr/local/include/libplatform /usr/local/include/cppgc /usr/local/include/unicode
  sudo cp v8*.h /usr/local/include
  sudo cp libplatform/*.h /usr/local/include/libplatform
  sudo cp cppgc/[a-z]*.h /usr/local/include/cppgc
  cd "${CURDIR}"/v8
  sudo cp ./third_party/icu/source/common/unicode/*.h /usr/local/include/unicode
  sudo cp ./third_party/icu/source/io/unicode/*.h /usr/local/include/unicode
  sudo cp ./third_party/icu/source/i18n/unicode/*.h /usr/local/include/unicode
  sudo cp ./third_party/icu/source/extra/uconv/unicode/*.h /usr/local/include/unicode
}

function configureAndInstall() {
  printf -- '\nConfiguration and Installation started \n'
  printf -- 'User responded with Yes. \n'

  mkdir -p ${CURDIR}/patch

  # Go
  if [[ "${DISTRO}" != "sles-15.3" ]]; then
    export PATH=/usr/local/go/bin:$PATH
    cd "${CURDIR}"
    if [ ! -f "/usr/local/go/bin/go" ]; then
      printf -- 'Installing Go\n'
      wget https://golang.org/dl/go1.15.5.linux-s390x.tar.gz
      chmod ugo+r go1.15.5.linux-s390x.tar.gz
      sudo tar -C /usr/local -xzf go1.15.5.linux-s390x.tar.gz
      sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
      go version
    fi
  fi

  if [[ "${DISTRO}" == "rhel-7."* ]]; then
    cd "${CURDIR}"
    if [ ! -f "/usr/local/bin/git" ]; then
      printf -- 'Installing Git\n'
      sudo yum install -y gettext-devel openssl-devel perl-CPAN perl-devel zlib-devel
      wget https://github.com/git/git/archive/v2.10.1.tar.gz -O git.tar.gz
      tar -zxf git.tar.gz
      cd git-2.10.1
      make configure
      ./configure --prefix=/usr/local
      make -j$(nproc)
      sudo make install
    fi
  fi

  if [[ "${DISTRO}" != "ubuntu-20.04" ]] && [[ "${DISTRO}" != "sles-15.3" ]]; then
    # Install gcc
    cd "${CURDIR}"
    ver=10.2.0
    if [ ! -f "/usr/local/bin/gcc" ]; then
      printf -- 'Installing GCC\n'
      wget https://ftp.gnu.org/gnu/gcc/gcc-${ver}/gcc-${ver}.tar.gz
      tar xzf gcc-${ver}.tar.gz
      cd gcc-${ver}
      ./contrib/download_prerequisites
      mkdir build-gcc && cd build-gcc
      ../configure --enable-languages=c,c++ --disable-multilib
      make -j$(nproc)
      sudo make install
      if [[ "${ID}" == "ubuntu" ]]; then
        sudo update-alternatives --install /usr/bin/gcc gcc /usr/local/bin/gcc 10
        sudo update-alternatives --install /usr/bin/g++ g++ /usr/local/bin/g++ 10
        sudo ln -sf /usr/local/lib64/libstdc++.so.6 /usr/lib/s390x-linux-gnu/libstdc++.so.6
      elif [[ "${DISTRO}" == "rhel-8."* ]]; then
        sudo mv /usr/bin/gcc /usr/bin/gcc-8.5.0
        sudo mv /usr/bin/g++ /usr/bin/g++-8.5.0
        sudo mv /usr/bin/c++ /usr/bin/c++-8.5.0
        sudo mv /usr/bin/cc /usr/bin/cc-8.5.0
        sudo update-alternatives --install /usr/bin/cc cc /usr/local/bin/gcc 40
        sudo update-alternatives --install /usr/bin/gcc gcc /usr/local/bin/gcc 40
        sudo update-alternatives --install /usr/bin/g++ g++ /usr/local/bin/g++ 40
        sudo update-alternatives --install /usr/bin/c++ c++ /usr/local/bin/c++ 40
        sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
      elif [[ "${DISTRO}" == "rhel-7."* ]]; then
        sudo mv /usr/bin/gcc /usr/bin/gcc-4.8.5
        sudo mv /usr/bin/g++ /usr/bin/g++-4.8.5
        sudo mv /usr/bin/c++ /usr/bin/c++-4.8.5
        sudo update-alternatives --install /usr/bin/cc cc /usr/local/bin/gcc 40
        sudo update-alternatives --install /usr/bin/gcc gcc /usr/local/bin/gcc 40
        sudo update-alternatives --install /usr/bin/g++ g++ /usr/local/bin/g++ 40
        sudo update-alternatives --install /usr/bin/c++ c++ /usr/local/bin/c++ 40
      elif [[ "${DISTRO}" == "sles-12.5" ]]; then
        sudo update-alternatives --install /usr/bin/cc cc /usr/local/bin/gcc 40
        sudo update-alternatives --install /usr/bin/gcc gcc /usr/local/bin/gcc 40
        sudo update-alternatives --install /usr/bin/g++ g++ /usr/local/bin/g++ 40
        sudo update-alternatives --install /usr/bin/c++ c++ /usr/local/bin/c++ 40
      fi
    fi
    if [[ "${ID}" == "ubuntu" ]]; then
      export CC=/usr/local/bin/s390x-ibm-linux-gnu-gcc
      export CXX=/usr/local/bin/s390x-ibm-linux-gnu-g++
    elif [[ "${DISTRO}" == "rhel-8."* ]]; then
      export CC=/usr/local/bin/s390x-ibm-linux-gnu-gcc
      export CXX=/usr/local/bin/s390x-ibm-linux-gnu-g++
    elif [[ "${DISTRO}" == "rhel-7."* ]]; then
      export CC=/usr/local/bin/gcc
      export CXX=/usr/local/bin/g++
    elif [[ "${DISTRO}" == "sles-12.5" ]]; then
      export CC=/usr/local/bin/s390x-ibm-linux-gnu-gcc
      export CXX=/usr/local/bin/s390x-ibm-linux-gnu-g++
    fi
  fi

  gcc --version
  sudo ldconfig /usr/local/lib64 /usr/local/lib

  if [[ "${ID}" == "ubuntu" ]] || [[ "${DISTRO}" == "rhel-7."* ]] || [[ "${DISTRO}" == "sles-12.5" ]]; then
    cd "${CURDIR}"
    if [[ "${DISTRO}" != "ubuntu-20.04" ]]; then
      # CMake
      if [ ! -f "cmake-3.16.0.tar.gz" ]; then
        printf -- 'Installing CMake\n'
        wget https://cmake.org/files/v3.16/cmake-3.16.0.tar.gz
        tar -xzf cmake-3.16.0.tar.gz
        cd cmake-3.16.0
        ./bootstrap --prefix=/usr
        make -j$(nproc)
        sudo make install
        hash -r
      fi
    fi
    # curl
    cd "${CURDIR}"
    if [ ! -d "/usr/local/include/curl" ]; then
      printf -- 'Installing curl\n'
      sudo ldconfig /usr/local/lib64 /usr/local/lib
      git clone https://github.com/curl/curl.git
      cd curl
      git checkout curl-7_66_0
      cmake -G "Unix Makefiles" .
      make -j $(nproc)
      sudo make install
      hash -r
    fi
  fi

  if [[ "${ID}" == "ubuntu" ]] || [[ "${DISTRO}" == "rhel-7."* ]]; then
    # openssl
    cd "${CURDIR}"
    if [ ! -f "/usr/local/bin/openssl" ]; then
      printf -- 'Installing openssl\n'
      wget https://www.openssl.org/source/openssl-1.1.1k.tar.gz
      tar -xzf openssl-1.1.1k.tar.gz
      cd openssl-1.1.1k
      ./config --prefix=/usr/local --openssldir=/usr/local
      make -j$(nproc)
      sudo make install
      sudo rm -rf /usr/local/certs
      sudo ln -sf /etc/ssl/certs /usr/local/certs
      sudo ldconfig /usr/local/lib64 /usr/local/lib
      hash -r
    fi
  fi

  openssl version
  openssl version -d

  if [[ "${DISTRO}" == "rhel-7."* ]] || [[ "${DISTRO}" == "sles-12.5" ]]; then
    # lz4
    if [ ! -f "/usr/local/include/lz4.h" ]; then
      printf -- 'Installing lz4\n'
      cd "${CURDIR}"
      wget https://github.com/lz4/lz4/archive/v1.8.1.2.tar.gz
      tar -xzf v1.8.1.2.tar.gz
      cd lz4-1.8.1.2
      make
      sudo make install
      hash -r
    fi

    # snappy
    if [ ! -f "/usr/local/include/snappy.h" ]; then
      printf -- 'Installing snappy\n'
      cd "${CURDIR}"
      git clone https://github.com/google/snappy.git
      cd snappy
      git checkout 1.1.5
      mkdir build
      cd build && cmake ../ && make
      sudo make install
      hash -r
    fi

    # libevent
    if [ ! -f "/usr/local/include/event.h" ]; then
      printf -- 'Installing libevent\n'
      cd "${CURDIR}"
      wget https://github.com/libevent/libevent/releases/download/release-2.1.8-stable/libevent-2.1.8-stable.tar.gz
      tar -xzf libevent-2.1.8-stable.tar.gz
      cd libevent-2.1.8-stable
      ./configure
      make
      sudo make install
    fi

    #libuv
    if [ ! -f "/usr/local/lib/libuv.so" ]; then
      printf -- 'Installing libuv\n'
      cd "${CURDIR}"
      git clone https://github.com/couchbasedeps/libuv
      cd libuv
      git checkout v1.20.3
      ./autogen.sh
      ./configure --disable-silent-rules --prefix=/usr/local
      make
      sudo make install
    fi
  fi

  # Install Jemalloc
  cd "${CURDIR}"
  if [ ! -f "/usr/local/bin/jeprof" ]; then
    printf -- 'Installing Jemalloc\n'
    git clone https://github.com/couchbasedeps/jemalloc.git
    cd jemalloc && git checkout 5.2.1
    autoconf configure.ac > configure
    chmod u+x configure
    CPPFLAGS=-I/usr/local/include ./configure --prefix=/usr/local \
    --with-jemalloc-prefix=je_ --disable-cache-oblivious --disable-zone-allocator \
    --enable-prof --disable-initial-exec-tls
    make build_lib_shared
    sudo make install_lib_shared install_include
    sudo cp "${CURDIR}"/jemalloc/bin/jeprof /usr/local/bin/jeprof
    sudo chmod a+x /usr/local/bin/jeprof
    if [ -f /usr/lib64/libjemalloc.so.2 ]; then
      sudo mv /usr/lib64/libjemalloc.so.2 ~/badlibjemalloc
    fi
  fi

  # ninja
  if [[ "${DISTRO}" == "rhel-7."* ]] && [ ! -f "/usr/bin/ninja" ]; then
    cd "${CURDIR}"
    printf -- 'Installing ninja\n'
    git clone https://github.com/ninja-build/ninja
    cd ninja
    git checkout v1.8.2
    ./configure.py --bootstrap
    sudo cp ninja /usr/bin
  fi

  # v8
  cd "${CURDIR}"
  if [ ! -f "/usr/local/lib/libv8.so" ]; then
    installV8
  fi

  # Boost
  sudo ldconfig /usr/local/lib64 /usr/local/lib
  cd "${CURDIR}"
  if [ ! -d "/usr/local/include/boost" ]; then
    printf -- 'Installing Boost\n'
    TOOLSET=gcc
    CENV=(PATH=$PATH LD_LIBRARY_PATH=$LD_LIBRARY_PATH LD_RUN_PATH=$LD_RUN_PATH CC=$CC CXX=$CXX)
    URL=https://boostorg.jfrog.io/artifactory/main/release/1.74.0/source/boost_1_74_0.tar.gz
    curl -sSL $URL | tar xzf -
    cd boost_1_74_0
    sed -i 's/array\.hpp/array_wrapper.hpp/g' boost/numeric/ublas/matrix.hpp
    sed -i 's/array\.hpp/array_wrapper.hpp/g' boost/numeric/ublas/storage.hpp
    ./bootstrap.sh --with-libraries=context,chrono,date_time,filesystem,program_options,regex,system,thread --with-icu=/usr/local/lib
    options=( toolset=$TOOLSET variant=release link=shared runtime-link=shared threading=multi --without-python )
    sudo ${CENV[@]} ./b2 -j 4 ${options[@]} install
  fi

  # double-conversion, glog, gflags
  if [[ "${ID}" != "ubuntu" ]]; then
    if [ ! -d "/usr/local/include/double-conversion" ]; then
      printf -- 'Installing double-conversion\n'
      cd "${CURDIR}"
      git clone https://github.com/google/double-conversion.git
      cd double-conversion
      git checkout v3.0.0
      cmake -D BUILD_SHARED_LIBS=OFF -D BUILD_TESTING=OFF .
      make
      sudo make install
    fi

    if [ ! -d "/usr/local/include/glog" ]; then
      printf -- 'Installing glog\n'
      cd "${CURDIR}"
      git clone https://github.com/google/glog.git
      cd glog
      git checkout v0.4.0
      cmake -S . -B build -G "Unix Makefiles" -D BUILD_SHARED_LIBS=OFF
      cmake --build build
      sudo cmake --build build --target install
    fi

    if [ ! -d "/usr/local/include/gflags" ]; then
      printf -- 'Installing gflags\n'
      cd "${CURDIR}"
      version=2.2.2
      wget https://github.com/gflags/gflags/archive/refs/tags/v$version.tar.gz
      tar xzf v$version.tar.gz
      cd gflags-$version
      mkdir build && cd build
      cmake ..
      make
      sudo make install
    fi
  fi

  # fmt
  cd "${CURDIR}"
  if [ ! -d "/usr/local/include/fmt" ]; then
    printf -- 'Installing fmt\n'
    git clone https://github.com/fmtlib/fmt.git
    cd fmt
    git checkout 6.2.1
    mkdir build
    cd build
    cmake ..
    make -j$(nproc)
    sudo make install
  fi

  # folly
  sudo ldconfig /usr/local/lib64 /usr/local/lib
  cd "${CURDIR}"
  if [ ! -d "/usr/local/include/folly" ]; then
    printf -- 'Installing folly\n'
    git clone https://github.com/facebook/folly
    cd folly
    git checkout v2020.08.24.00
    curl https://github.com/facebook/folly/commit/eedb340bd5fff6a4a44006ff641cb3ecc2b293fb.patch | git apply -
    wget "${PATCH_URL}"/folly.diff -P ${CURDIR}/patch
    git apply ${CURDIR}/patch/folly.diff
    mkdir _build
    cd _build
    cmake -DCMAKE_INCLUDE_PATH=/usr/local/include -DCMAKE_LIBRARY_PATH=/usr/local/lib .. -DBUILD_SHARED_LIBS=OFF
    make -j$(nproc)
    sudo make install
  fi

  # erlang
  cd "${CURDIR}"
  if [ ! -d "/usr/local/lib/erlang" ]; then
    printf -- 'Installing erlang\n'
    git clone https://github.com/couchbasedeps/erlang.git
    cd erlang && git checkout couchbase-cheshirecat
    ./otp_build autoconf
    touch lib/debugger/SKIP lib/megaco/SKIP lib/observer/SKIP lib/wx/SKIP lib/et/SKIP
    ./configure --prefix=/usr/local --enable-smp-support --disable-hipe --disable-fp-exceptions CFLAGS="-fno-strict-aliasing -O3 -ggdb3"
    make -j $(nproc)
    sudo make install
    hash -r
  fi

  # flatbuffers
  cd "${CURDIR}"
  if [ ! -d "/usr/local/include/flatbuffers" ]; then
    printf -- 'Installing Flatbuffers\n'
    git clone https://github.com/google/flatbuffers
    cd flatbuffers && git checkout v1.10.0
    wget "${PATCH_URL}"/flatbuffers.diff -P ${CURDIR}/patch
    git apply ${CURDIR}/patch/flatbuffers.diff
    curl https://github.com/google/flatbuffers/commit/2e865f4d4e67a9b628c137aab7da8140dd9339a4.patch | git apply -
    cmake -G "Unix Makefiles"
    make -j $(nproc)
    sudo make install
    sudo cp flatc flathash flattests flatsamplebinary flatsampletext /usr/local/bin
    hash -r
  fi

  # json hpp
  cd "${CURDIR}"
  if [ ! -d "/usr/local/include/nlohmann" ]; then
    printf -- 'Installing json\n'
    git clone https://github.com/nlohmann/json
    cd "${CURDIR}"/json
    git checkout v3.5.0
    cd "${CURDIR}"/json/include/nlohmann
    sudo mkdir /usr/local/include/nlohmann
    sudo cp -r * /usr/local/include/nlohmann
  fi

  # prometheus-cpp
  cd "${CURDIR}"
  if [ ! -d "/usr/local/include/prometheus" ]; then
    printf -- 'Installing prometheus-cpp\n'
    git clone https://github.com/jupp0r/prometheus-cpp.git
    cd prometheus-cpp
    git checkout v0.10.0
    git submodule init
    git submodule update
    mkdir _build
    cd _build
    cmake .. -DBUILD_SHARED_LIBS=OFF \
    -DENABLE_PUSH=OFF \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    make -j$(nproc)
    sudo make install
  fi

  # prometheus
  cd "${CURDIR}"
  export GOPATH=$(go env GOPATH)
  if [ ! -d "$GOPATH/src/github.com/prometheus" ]; then
    printf -- 'Installing prometheus\n'
    wget https://nodejs.org/dist/v16.14.2/node-v16.14.2-linux-s390x.tar.xz
    tar xf node-v16.14.2-linux-s390x.tar.xz
    export PATH="${CURDIR}"/node-v16.14.2-linux-s390x/bin:$PATH
    npm install -g yarn
    mkdir -p $GOPATH/src/github.com
    cd $GOPATH/src/github.com
    git clone https://github.com/couchbasedeps/prometheus.git
    cd prometheus
    git checkout couchbase-v2.22
    make build
    sudo cp prometheus /usr/local/bin/prometheus
  fi

  # numactl
  if [[ "${ID}" == "ubuntu" ]] || [[ "${DISTRO}" == "rhel-7."* ]] || [[ "${ID}" == "sles" ]]; then
    # numactl - needed to build for SLES as there are no headers in repo
    cd "${CURDIR}"
    if [ ! -f "/usr/local/lib/libnuma.a" ]; then
      printf -- 'Installing numactl\n'
      git clone https://github.com/numactl/numactl.git
      cd numactl
      if [[ "${DISTRO}" == "rhel-7."* ]]; then
        git checkout v2.0.14
      else
        git checkout v2.0.11
        curl https://github.com/numactl/numactl/commit/25691a084a2012a339395ade567dbae814e237e9.patch | git apply -
      fi
      ./autogen.sh
      ./configure
      make
      sudo make install
    fi
  fi

  # pcre
  cd "${CURDIR}"
  if [ ! -f "/usr/local/include/pcre.h" ]; then
    printf -- 'Installing PCRE\n'
    wget https://sourceforge.net/projects/pcre/files/pcre/8.43/pcre-8.43.tar.gz
    tar -xzf pcre-8.43.tar.gz
    cd pcre-8.43
    ./configure --prefix=/usr/local
    make
    sudo make install
  fi

  # protoc
  cd "${CURDIR}"
  if [ ! -f "/usr/local/lib/libprotobuf.a" ]; then
    printf -- 'Installing protoc\n'
    export GO111MODULE=on
    go get github.com/golang/protobuf/protoc-gen-go@v1.2.0
    sudo cp "${HOME}"/go/bin/protoc-gen-go /usr/local/bin
    git clone https://github.com/protocolbuffers/protobuf.git
    cd protobuf
    git checkout v3.11.2
    git submodule update --init --recursive
    ./autogen.sh
    ./configure --prefix=/usr/local
    make -j$(nproc)
    sudo make install
    sudo cp src/.libs/protoc /usr/local/bin
  fi

  # grpc
  sudo ldconfig /usr/local/lib64 /usr/local/lib
  cd "${CURDIR}"
  if [ ! -d "/usr/local/include/grpc" ]; then
    printf -- 'Installing GRPC\n'
    git clone -b v1.33.2 https://github.com/grpc/grpc
    cd grpc/
    git submodule update --init
    mkdir -p cmake/build
    cd cmake/build
    mv ../../third_party/boringssl-with-bazel ../../third_party/boringssl-with-bazel_ORIG
    cd ../../third_party/
    git clone https://github.com/linux-on-ibm-z/boringssl.git
    cd boringssl
    git checkout patch-s390x-Aug2019
    cd ..
    mv boringssl boringssl-with-bazel
    cd ../cmake/build/
    cmake -DgRPC_INSTALL=ON \
      -DgRPC_BUILD_TESTS=OFF \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      ../..
    make -j$(nproc)
    sudo make install
    cd "${CURDIR}"/grpc
    mkdir -p third_party/abseil-cpp/cmake/build
    cd third_party/abseil-cpp/cmake/build
    cmake -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DCMAKE_POSITION_INDEPENDENT_CODE=TRUE \
      ../..
    make -j$(nproc)
    sudo make install
  fi

  # cbpy
  cd "${CURDIR}"
  if [ ! -d "/usr/local/lib/python/runtime" ]; then
    printf -- 'Installing cbpy\n'
    wget https://repo.anaconda.com/miniconda/Miniconda3-py38_4.10.3-Linux-s390x.sh
    chmod a+x Miniconda3-py38_4.10.3-Linux-s390x.sh
    sudo ./Miniconda3-py38_4.10.3-Linux-s390x.sh -b -p /usr/local/lib/python/runtime
  fi

  # crc32
  cd "${CURDIR}"
  if [ ! -d "crc32-s390x" ]; then
    printf -- 'Installing crc32\n'
    git clone https://github.com/linux-on-ibm-z/crc32-s390x.git
    cd crc32-s390x
    wget "${PATCH_URL}"/crc32-s390x.diff -P ${CURDIR}/patch
    git apply ${CURDIR}/patch/crc32-s390x.diff
    make
    sudo cp crc32-s390x.h /usr/local/include/
    sudo cp libcrc32_s390x.a /usr/local/lib/
  fi

  # rocksdb
  cd "${CURDIR}"
  if [ ! -d "/usr/local/include/rocksdb" ]; then
    printf -- 'Installing RocksDB\n'
    git clone https://github.com/facebook/rocksdb.git
    cd rocksdb
    git checkout v5.18.3
    CXXFLAGS='-Wno-error=deprecated-copy -Wno-error=pessimizing-move -Wno-error=redundant-move' make -j$(nproc) shared_lib
    sudo make install-shared INSTALL_PATH=/usr/local
  fi

  #re2c
  if [[ "${ID}" == "rhel" ]] || [[ "${DISTRO}" == "sles-12.5" ]]; then
    if [ ! -f "/usr/local/bin/re2c" ]; then
      printf -- 'Installing re2c\n'
      cd "${CURDIR}"
      wget https://github.com/skvadrik/re2c/releases/download/3.0/re2c-3.0.tar.xz
      tar xf re2c-3.0.tar.xz
      cd re2c-3.0/
      ./configure
      make
      sudo make install
      sudo cp /usr/local/bin/re2c /usr/bin/re2c
    fi
  fi

  # clang 12
  cd "${CURDIR}"
  if [[ "${DISTRO}" != "ubuntu-20.04" ]] && [[ "${DISTRO}" != "sles-15.3" ]]; then
    if [ ! -f "/usr/local/bin/clang" ]; then
      installClang12
    fi
  fi
  clang -v

  # couchbase
  printf -- 'Installing Couchbase\n'
  cd "${CURDIR}"
  curl https://storage.googleapis.com/git-repo-downloads/repo > repo
  chmod a+x repo
  sudo mv repo /usr/bin
  mkdir -p "${CURDIR}"/couchbase
  cd "${CURDIR}"/couchbase

  set +e
  user_name=`git config user.name`
  user_email=`git config user.email`
  set -e
  if [ -z ${user_name} ] || [ -z ${user_email} ]; then
    printf -- 'Set up git user\n'
    git config --global user.email "tester@email"
    git config --global user.name "tester"
  fi

  repo init -u https://github.com/couchbase/manifest -m released/couchbase-server/7.0.2.xml
  repo sync
  cd "${CURDIR}"/couchbase/tlm
  if [[ "${DISTRO}" == "rhel-7."* ]]; then
    wget "${PATCH_URL}"/tlm-rhel7.diff -P ${CURDIR}/patch
    git apply ${CURDIR}/patch/tlm-rhel7.diff
  elif [[ "${DISTRO}" == "rhel-8."* ]]; then
    wget "${PATCH_URL}"/tlm-rhel8.diff -P ${CURDIR}/patch
    git apply ${CURDIR}/patch/tlm-rhel8.diff
  elif [[ "${ID}" == "sles" ]]; then
    wget "${PATCH_URL}"/tlm-sles.diff -P ${CURDIR}/patch
    git apply ${CURDIR}/patch/tlm-sles.diff
  elif [[ "${DISTRO}" == "ubuntu-20.04" ]]; then
    wget "${PATCH_URL}"/tlm-ub20.diff -P ${CURDIR}/patch
    git apply ${CURDIR}/patch/tlm-ub20.diff
  else
    wget "${PATCH_URL}"/tlm-ub18.diff -P ${CURDIR}/patch
    git apply ${CURDIR}/patch/tlm-ub18.diff
  fi
  cd "${CURDIR}"/couchbase/couchdb
  wget "${PATCH_URL}"/couchdb.diff -P ${CURDIR}/patch
  git apply ${CURDIR}/patch/couchdb.diff
  cd "${CURDIR}"/couchbase/couchstore
  wget "${PATCH_URL}"/couchstore.diff -P ${CURDIR}/patch
  git apply ${CURDIR}/patch/couchstore.diff
  cd "${CURDIR}"/couchbase/forestdb
  wget "${PATCH_URL}"/forestdb.diff -P ${CURDIR}/patch
  git apply ${CURDIR}/patch/forestdb.diff
  cd "${CURDIR}"/couchbase/kv_engine
  wget "${PATCH_URL}"/kv_engine.diff -P ${CURDIR}/patch
  git apply ${CURDIR}/patch/kv_engine.diff
  cd "${CURDIR}"/couchbase/platform
  wget "${PATCH_URL}"/platform.diff -P ${CURDIR}/patch
  git apply ${CURDIR}/patch/platform.diff
  cd "${CURDIR}"/couchbase/

  sudo ldconfig /usr/local/lib64 /usr/local/lib

  OPTIONS=""
  if [[ "${DISTRO}" != "ubuntu-20.04" ]] && [[ "${DISTRO}" != "sles-15.3" ]]; then
    OPTIONS+="-DCMAKE_C_COMPILER=/usr/local/bin/clang -DCMAKE_CXX_COMPILER=/usr/local/bin/clang++"
  else #Ubuntu 20.04 and #SLES 15.3
    OPTIONS+="-DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++"
  fi
  if [[ "$HAS_PREFIX" == "true" ]]; then
    OPTIONS+=" -DCMAKE_INSTALL_PREFIX=$CB_PREFIX"
  fi

  sudo make -j$(nproc) EXTRA_CMAKE_OPTIONS="$OPTIONS"

  printf -- 'Build process completed successfully\n'

  #Run tests
  runTest |& tee -a "$LOG_FILE"

  #Install deps to couchbase install directory
  cd $CURDIR
  wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Couchbase/7.0.2/installDeps.sh
  if [[ "$HAS_PREFIX" == "true" ]]; then
    source installDeps.sh $CB_PREFIX |& tee -a "$LOG_FILE"
  else
    source installDeps.sh |& tee -a "$LOG_FILE"
  fi

  printf -- 'Couchbase built succesfully\n'
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
  echo "bash build_couchdb.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests] [-p <install_prefix>]"
  echo
}

while getopts "h?dytp:" opt; do
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
    HAS_PREFIX="true"
    CB_PREFIX=${OPTARG}
    ;;
  esac
done

function printSummary() {
  printf -- '\n\nRun following command to run couchbase server.\n' |& tee -a "$LOG_FILE"
  if [[ "$HAS_PREFIX" == "true" ]]; then
    printf -- "\n\n  sudo $CB_PREFIX/bin/couchbase-server -- -noinput & \n" "${CURDIR}" |& tee -a "$LOG_FILE"
  else
    printf -- "\n\n  sudo %s/couchbase/install/bin/couchbase-server -- -noinput & \n" "${CURDIR}" |& tee -a "$LOG_FILE"
  fi
  printf -- '\nThe Couchbase UI can be viewed at http://hostname:8091\n' |& tee -a "$LOG_FILE"
  printf -- '\nFor more help visit https://docs.couchbase.com/home/server.html \n' |& tee -a "$LOG_FILE"
}

logDetails
prepare |& tee -a "$LOG_FILE"

DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
  "ubuntu-18.04")
  printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  printf -- '\nInstalling dependencies from repository \n' |& tee -a "$LOG_FILE"
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive TZ=America/Toronto apt-get install -y \
  autoconf automake autotools-dev \
  binutils-dev bison ccache clang cmake flex g++ gcc gcc-multilib g++-multilib \
  git gnome-keyring libatk1.0-dev libcups2-dev libdouble-conversion-dev libev-dev \
  libevent-dev libgconf2-dev libglib2.0-dev libgoogle-glog-dev libgflags-dev \
  libgtk-3-dev libiberty-dev liblz4-dev liblz4-tool liblzma-dev libnss3-dev \
  libpango1.0-dev libsnappy-dev libssl-dev libtool libuv1 libuv1-dev locales locales-all make \
  ncurses-dev ninja-build python python3 python3-httplib2 python3-six \
  pkg-config re2c texinfo tzdata unzip wget zlib1g-dev
  sudo ln -sf /usr/bin/python2 /usr/bin/python
  export LANG=en_US.UTF-8
  configureAndInstall |& tee -a "$LOG_FILE"
  ;;
  "ubuntu-20.04")
  printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  printf -- '\nInstalling dependencies from repository \n' |& tee -a "$LOG_FILE"
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive TZ=America/Toronto apt-get install -y \
  autoconf automake autotools-dev \
  binutils-dev bison ccache clang-12 cmake curl flex g++-10 gcc-10 gcc-10-multilib g++-10-multilib \
  git gnome-keyring libatk1.0-dev libcups2-dev libdouble-conversion-dev libev-dev \
  libevent-dev libgconf2-dev libglib2.0-dev libgoogle-glog-dev libgflags-dev \
  libgtk-3-dev libiberty-dev liblz4-dev liblz4-tool liblzma-dev libnss3-dev \
  libpango1.0-dev libsnappy-dev libssl-dev libtool libuv1 libuv1-dev locales locales-all make \
  ncurses-dev ninja-build python python3 python3-httplib2 python3-six \
  pkg-config re2c texinfo tzdata unzip wget zlib1g-dev
  sudo ln -sf /usr/bin/python2 /usr/bin/python
  sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-9 9
  sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-9 9
  sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-10 10
  sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-10 10
  sudo update-alternatives --install /usr/bin/clang clang /usr/bin/clang-12 12
  sudo update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-12 12
  export LANG=en_US.UTF-8
  configureAndInstall |& tee -a "$LOG_FILE"
  ;;
  "rhel-7.8" | "rhel-7.9")
  printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  printf -- '\nInstalling dependencies from repository \n' |& tee -a "$LOG_FILE"
  sudo yum install -y atk-devel autoconf automake binutils-devel bison bzip2 \
    ca-certificates cmake cups-devel flex gcc gcc-c++ git gnome-keyring \
    libcurl-devel libtool make ncurses-devel \
    python2 python3 python3-devel tar texinfo \
    unzip wget which xmlto xz xz-devel zlib-devel
  sudo pip3 install six httplib2
  sudo ln -sf /usr/bin/python2 /usr/bin/python
  export LANG=en_US.UTF-8
  export LD_LIBRARY_PATH=/usr/local/lib64:/usr/local/lib/:/usr/lib64:/usr/lib/:$LD_LIBRARY_PATH
  configureAndInstall |&  tee -a "$LOG_FILE"
  ;;
  "rhel-8.4")
  printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  printf -- '\nInstalling dependencies from repository \n' |& tee -a "$LOG_FILE"
  sudo yum install -y atk-devel autoconf automake binutils-devel bison bzip2 \
    clang cmake cups-devel flex gcc gcc-c++ git gnome-keyring \
    libcurl-devel libev-devel libevent-devel libuv libuv-devel \
    libtool lz4-devel make ncurses-devel ninja-build numactl-devel openssl-devel openssl-perl\
    pcre-devel python2 python3 python3-devel python3-httplib2 snappy-devel tar texinfo \
    unzip wget which xz xz-devel zlib-devel
  sudo ln -sf /usr/bin/python2 /usr/bin/python
  export LANG=en_US.UTF-8
  configureAndInstall |&  tee -a "$LOG_FILE"
  ;;
  "sles-15.3")
  printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  printf -- '\nInstalling dependencies from repository \n' |& tee -a "$LOG_FILE"
  sudo sudo zypper install -y asciidoc autoconf automake clang12 cmake curl flex \
    gcc gcc-c++ gcc10-c++-10.3.0+git1587 gcc10-10.3.0+git1587 git-core glib2 glib2-devel glibc-locale go1.15 \
    libcurl-devel libevent-devel libopenssl-devel libncurses6 \
    libsnappy1 libtirpc-devel libtool libuv1 libuv-devel libxml2-tools libxslt-tools \
    liblz4-1 libz1 liblz4-devel make makedepend \
    ncurses-devel ninja patch pkg-config \
    python python-xml python3-httplib2 re2c ruby snappy-devel sqlite3 tar \
    unixODBC wget which xinetd xmlto zlib-devel python3-pip xz 
	pip3 install pyparsing
  sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-10 10
  sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-10 10
  sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-10 10
  sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-10 10
  sudo update-alternatives --install /usr/bin/clang clang /usr/bin/clang-12 12 \
  --slave /usr/bin/clang++ clang++ /usr/bin/clang++-12
  sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
  export LANG=en_US.UTF-8
  configureAndInstall |&  tee -a "$LOG_FILE"
  ;;
  "sles-12.5" )
  printf -- "\nInstalling %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  printf -- '\nInstalling dependencies from repository \n' |& tee -a "$LOG_FILE"
  sudo zypper install -y asciidoc autoconf automake binutils-devel bison cmake \
    cups-libs flex gcc gcc-c++ git-core glib2-devel libatk-1_0-0 \
    libgconfmm-2_6-1 libgtk-3-0 liblzma5 libncurses6 \
    libopenssl1_1 libopenssl-1_1-devel libpango-1_0-0 \
    libtirpc-devel libtool libxml2-tools libxslt-tools libz1 make makedepend \
    ncurses-devel ninja openssl-1_1 patch pkg-config python re2c ruby \
    snappy-devel sqlite3 tar texinfo unixODBC wget which xinetd xmlto zlib-devel xz glibc-locale
  export LANG=en_US.UTF-8
  export LD_LIBRARY_PATH=/usr/local/lib64:/usr/local/lib/:/usr/lib64:/usr/lib/:$LD_LIBRARY_PATH
  # Install Python 3
  if [ ! -f "/usr/local/bin/python3" ]; then
    wget -q https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Python3/3.8.6/build_python3.sh
    bash build_python3.sh -y
    # use system's openssl
    cd $CURDIR/openssl-1.1.1h
    sudo make uninstall
  fi
  pip3 install httplib2 --upgrade
  pip3 install six
  configureAndInstall |&  tee -a "$LOG_FILE"
  ;;
  *)
  printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
  exit 1
  ;;
esac

# Print Summary
printSummary |& tee -a "$LOG_FILE"
