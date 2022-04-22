#!/bin/bash

set -e -o pipefail

if [ -f "/etc/os-release" ]; then
  source "/etc/os-release"
else
  printf -- "%s Package with version %s is currently not supported for %s .\n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
fi

DISTRO="$ID-$VERSION_ID"
CURDIR="$(pwd)"
CB_PATH=$CURDIR/couchbase/install

if ! [ -z "$1" ]; then
  CB_PATH=$1
fi

function installDeps() {
  printf -- "Installing libraries and binaries to Couchbase installation: $CB_PATH\n"

  sudo mkdir -p $CB_PATH/lib/pkgconfig
  sudo mkdir -p $CB_PATH/bin

  case "$DISTRO" in
    "ubuntu-18.04")
    #libevent
    sudo cp -a /usr/lib/s390x-linux-gnu/libevent*.so* $CB_PATH/lib
    #libsnappy
    sudo cp -a /usr/lib/s390x-linux-gnu/libsnappy.so* $CB_PATH/lib
    # libuv
    sudo cp -a /usr/lib/s390x-linux-gnu/libuv.so* $CB_PATH/lib
    #numactl
    sudo cp -a /usr/local/lib/libnuma.la $CB_PATH/lib
    sudo cp -a /usr/local/lib/libnuma.so* $CB_PATH/lib
    #zlib
    sudo cp -a /usr/local/lib/libz.so* $CB_PATH/lib
    #cURL
    sudo cp -a /usr/local/lib/libcurl.so* $CB_PATH/lib
    sudo cp -a /usr/local/bin/curl $CB_PATH/bin
    #LZ4
    sudo cp -a /usr/lib/s390x-linux-gnu/liblz4.so* $CB_PATH/lib
    #gcc
    sudo cp -a /usr/local/lib64/libstdc++.so* $CB_PATH/lib
    sudo cp -a /usr/local/lib64/libgcc_s.so* $CB_PATH/lib
    #OpenSSL
    sudo cp -a /usr/local/bin/openssl $CB_PATH/bin
    sudo cp -a /usr/local/bin/c_rehash $CB_PATH/bin
    sudo cp -a -r /usr/local/lib64/engines-1.1 $CB_PATH/lib
    sudo cp -a /usr/local/lib64/libcrypto.so* $CB_PATH/lib
    sudo cp -a /usr/local/lib64/libssl.so* $CB_PATH/lib
    sudo cp -a /usr/local/lib64/pkgconfig/libcrypto.pc $CB_PATH/lib/pkgconfig
    sudo cp -a /usr/local/lib64/pkgconfig/libssl.pc $CB_PATH/lib/pkgconfig
    sudo cp -a /usr/local/lib64/pkgconfig/openssl.pc $CB_PATH/lib/pkgconfig
    ;;
    "ubuntu-20.04")
    #libevent
    sudo cp -a /usr/lib/s390x-linux-gnu/libevent*.so* $CB_PATH/lib
    #libsnappy
    sudo cp -a /usr/lib/s390x-linux-gnu/libsnappy.so* $CB_PATH/lib
    # libuv
    sudo cp -a /usr/lib/s390x-linux-gnu/libuv.so* $CB_PATH/lib
    #numactl
    sudo cp -a /usr/local/lib/libnuma.la $CB_PATH/lib
    sudo cp -a /usr/local/lib/libnuma.so* $CB_PATH/lib
    #zlib
    sudo cp -a /usr/local/lib/libz.so* $CB_PATH/lib
    #cURL
    sudo cp -a /usr/local/lib/libcurl.so* $CB_PATH/lib
    sudo cp -a /usr/local/bin/curl $CB_PATH/bin
    #LZ4
    sudo cp -a /usr/lib/s390x-linux-gnu/liblz4.so* $CB_PATH/lib
    #gcc
    sudo cp -a /usr/lib/s390x-linux-gnu/libstdc++.so* $CB_PATH/lib
    sudo cp -a /usr/lib/s390x-linux-gnu/libgcc_s.so* $CB_PATH/lib
    #OpenSSL
    sudo cp -a -r /usr/lib/s390x-linux-gnu/engines-1.1 $CB_PATH/lib
    sudo cp -a /usr/lib/s390x-linux-gnu/libcrypto.so* $CB_PATH/lib
    sudo cp -a /usr/lib/s390x-linux-gnu/libssl.so* $CB_PATH/lib
    sudo cp -a /usr/lib/s390x-linux-gnu/pkgconfig/libcrypto.pc $CB_PATH/lib/pkgconfig
    sudo cp -a /usr/lib/s390x-linux-gnu/pkgconfig/libssl.pc $CB_PATH/lib/pkgconfig
    sudo cp -a /usr/lib/s390x-linux-gnu/pkgconfig/openssl.pc $CB_PATH/lib/pkgconfig
    sudo cp -a /usr/bin/openssl $CB_PATH/bin
    sudo cp -a /usr/bin/c_rehash $CB_PATH/bin
    ;;
    "rhel-7."*)
    #libevent
    sudo cp -a /usr/local/lib/libevent*.so* $CB_PATH/lib
    #snappy
    sudo cp -a /usr/local/lib/libsnappy.so* $CB_PATH/lib
    #libuv
    sudo cp -a /usr/local/lib/libuv.so* $CB_PATH/lib
    #numactl
    sudo cp -a /usr/local/lib/libnuma.la $CB_PATH/lib
    sudo cp -a /usr/local/lib/libnuma.so* $CB_PATH/lib
    #zlib
    sudo cp -a /usr/local/lib/libz.so* $CB_PATH/lib
    #cURL
    sudo cp -a /usr/local/lib64/libcurl.so* $CB_PATH/lib
    sudo cp -a /usr/local/bin/curl $CB_PATH/bin
    #LZ4
    sudo cp -a /usr/local/lib/liblz4.so* $CB_PATH/lib
    #gcc
    sudo cp -a /usr/local/lib64/libstdc++.so* $CB_PATH/lib
    sudo cp -a /usr/local/lib64/libgcc_s.so* $CB_PATH/lib
    #OpenSSL
    sudo cp -a /usr/local/bin/openssl $CB_PATH/bin
    sudo cp -a /usr/local/bin/c_rehash $CB_PATH/bin
    sudo cp -a -r /usr/local/lib64/engines-1.1 $CB_PATH/lib
    sudo cp -a /usr/local/lib64/libcrypto.so* $CB_PATH/lib
    sudo cp -a /usr/local/lib64/libssl.so* $CB_PATH/lib
    sudo cp -a /usr/local/lib64/pkgconfig/libcrypto.pc $CB_PATH/lib/pkgconfig
    sudo cp -a /usr/local/lib64/pkgconfig/libssl.pc $CB_PATH/lib/pkgconfig
    sudo cp -a /usr/local/lib64/pkgconfig/openssl.pc $CB_PATH/lib/pkgconfig
    ;;
    "rhel-8."*)
    #libevent
    sudo cp -a /usr/lib64/libevent*.so* $CB_PATH/lib
    #snappy
    sudo cp -a /usr/lib64/libsnappy*.so* $CB_PATH/lib
    #libuv
    sudo cp -a /usr/lib64/libuv*.so* $CB_PATH/lib
    #numactl
    sudo cp -a /usr/lib64/libnuma.so* $CB_PATH/lib
    #zlib
    sudo cp -a /usr/local/lib/libz.so* $CB_PATH/lib
    #cURL
    sudo cp -a /usr/lib64/libcurl.so* $CB_PATH/lib
    sudo cp -a /usr/bin/curl $CB_PATH/bin
    #LZ4
    sudo cp -a /usr/lib64/liblz4.so* $CB_PATH/lib
    #gcc
    sudo cp -a /usr/local/lib64/libstdc++.so* $CB_PATH/lib
    sudo cp -a /usr/local/lib64/libgcc_s.so* $CB_PATH/lib
    #OpenSSL
    sudo cp -a -r /usr/lib64/engines-1.1 $CB_PATH/lib
    sudo cp -a /usr/lib64/libcrypto.so* $CB_PATH/lib
    sudo cp -a /usr/lib64/libssl.so* $CB_PATH/lib
    sudo cp -a /usr/lib64/pkgconfig/libcrypto.pc $CB_PATH/lib/pkgconfig
    sudo cp -a /usr/lib64/pkgconfig/libssl.pc $CB_PATH/lib/pkgconfig
    sudo cp -a /usr/lib64/pkgconfig/openssl.pc $CB_PATH/lib/pkgconfig
    sudo cp -a /usr/bin/openssl $CB_PATH/bin
    sudo cp -a /usr/bin/c_rehash $CB_PATH/bin
    ;;
    "sles-12.5")
    #libevent
    sudo cp -a /usr/local/lib/libevent*.so* $CB_PATH/lib
    #snappy
    sudo cp -a /usr/local/lib/libsnappy.so* $CB_PATH/lib
    #libuv
    sudo cp -a /usr/local/lib/libuv.so* $CB_PATH/lib
    #numactl
    sudo cp -a /usr/local/lib/libnuma.la $CB_PATH/lib
    sudo cp -a /usr/local/lib/libnuma.so* $CB_PATH/lib
    #zlib
    sudo cp -a /usr/local/lib/libz.so* $CB_PATH/lib
    #cURL
    sudo cp -a /usr/local/lib64/libcurl.so* $CB_PATH/lib
    sudo cp -a /usr/local/bin/curl $CB_PATH/bin
    #LZ4
    sudo cp -a /usr/local/lib/liblz4.so* $CB_PATH/lib
    #gcc
    sudo cp -a /usr/local/lib64/libstdc++.so* $CB_PATH/lib
    sudo cp -a /usr/local/lib64/libgcc_s.so* $CB_PATH/lib
    #OpenSSL
    sudo cp -a -r /usr/lib64/engines-1.1 $CB_PATH/lib
    sudo cp -a /usr/lib64/libcrypto.so* $CB_PATH/lib
    sudo cp -a /usr/lib64/libssl.so* $CB_PATH/lib
    sudo cp -a /usr/lib64/pkgconfig/libcrypto.pc $CB_PATH/lib/pkgconfig
    sudo cp -a /usr/lib64/pkgconfig/libssl.pc $CB_PATH/lib/pkgconfig
    sudo cp -a /usr/lib64/pkgconfig/openssl.pc $CB_PATH/lib/pkgconfig
    sudo cp -a /usr/bin/openssl $CB_PATH/bin
    sudo cp -a /usr/bin/c_rehash $CB_PATH/bin
    ;;
    "sles-15.3")
    #libevent
    sudo cp -a /usr/lib64/libevent*.so* $CB_PATH/lib
    #snappy
    sudo cp -a /usr/lib64/libsnappy*.so* $CB_PATH/lib
    #libuv
    sudo cp -a /usr/lib64/libuv*.so* $CB_PATH/lib
    #numactl
    sudo cp -a /usr/local/lib/libnuma.la $CB_PATH/lib
    sudo cp -a /usr/local/lib/libnuma.so* $CB_PATH/lib
    #zlib
    sudo cp -a /usr/local/lib/libz.so* $CB_PATH/lib
    #cURL
    sudo cp -a /usr/lib64/libcurl.so* $CB_PATH/lib
    sudo cp -a /usr/bin/curl $CB_PATH/bin
    #LZ4
    sudo cp -a /usr/lib64/liblz4.so* $CB_PATH/lib
    #gcc
    sudo cp -a /usr/lib64/libstdc++.so* $CB_PATH/lib
    sudo cp -a /lib64/libgcc_s.so* $CB_PATH/lib
    #OpenSSL
    sudo cp -a -r /usr/lib64/engines-1.1 $CB_PATH/lib
    sudo cp -a /usr/lib64/libcrypto.so* $CB_PATH/lib
    sudo cp -a /usr/lib64/libssl.so* $CB_PATH/lib
    sudo cp -a /usr/lib64/pkgconfig/libcrypto.pc $CB_PATH/lib/pkgconfig
    sudo cp -a /usr/lib64/pkgconfig/libssl.pc $CB_PATH/lib/pkgconfig
    sudo cp -a /usr/lib64/pkgconfig/openssl.pc $CB_PATH/lib/pkgconfig
    sudo cp -a /usr/bin/openssl $CB_PATH/bin
    sudo cp -a /usr/bin/c_rehash $CB_PATH/bin
    ;;
    *)
    ;;
  esac

  #jemalloc - all
  sudo cp -a /usr/local/lib/libjemalloc*.so* $CB_PATH/lib
  sudo cp -a /usr/local/bin/jeprof $CB_PATH/bin

  # v8 - all
  sudo cp -a /usr/local/lib/libv8_libbase.so $CB_PATH/lib
  sudo cp -a /usr/local/lib/libv8_libplatform.so $CB_PATH/lib
  sudo cp -a /usr/local/lib/libv8.so $CB_PATH/lib
  sudo cp -a /usr/local/lib/libchrome*.so $CB_PATH/lib
  sudo cp -a /usr/local/lib/libicu*.so* $CB_PATH/lib
  sudo cp -a /usr/local/lib/icu*.dat $CB_PATH/lib
  sudo cp -a /usr/local/lib/icu*.dat $CB_PATH/bin

  # erlang - all
  sudo chmod -R a+rx $CB_PATH
  cd $CB_PATH/bin
  sudo cp -a -r /usr/local/lib/erlang $CB_PATH/lib
  for BIN in ct_run epmd erl escript dialyzer erlc run_erl to_erl typer
  do
    sudo ln -sf ../lib/erlang/bin/$BIN $BIN
  done

  #need to run this to update the erlang ROOTDIR
  sudo $CB_PATH/lib/erlang/Install -minimal $CB_PATH/lib/erlang

  #PCRE
  sudo cp -a /usr/local/lib/libpcre.la $CB_PATH/lib
  sudo cp -a /usr/local/lib/libpcre.so* $CB_PATH/lib
  sudo cp -a /usr/local/lib/libpcrecpp.la $CB_PATH/lib
  sudo cp -a /usr/local/lib/libpcrecpp.so* $CB_PATH/lib
  sudo cp -a /usr/local/lib/libpcreposix.la $CB_PATH/lib
  sudo cp -a /usr/local/lib/libpcreposix.so* $CB_PATH/lib
  sudo cp -a /usr/local/lib/pkgconfig/libpcre* $CB_PATH/lib/pkgconfig
  sudo cp -a /usr/local/bin/pcre* $CB_PATH/bin

  #prometheus
  sudo cp -a /usr/local/bin/prometheus $CB_PATH/bin
}

installDeps
