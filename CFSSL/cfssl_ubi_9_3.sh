#!/bin/bash
# -----------------------------------------------------------------------------
#
# Package        : CFSSL
# Version        : v1.6.3
# Source repo    : https://github.com/cloudflare/cfssl
# Tested on      : UBI: 9.3
# Language       : go
# Travis-Check   : True
# Script License : Apache License, Version 2 or later
# Maintainer     : Aloc Jose <Aloc.Jose@ibm.com>
#
# Disclaimer: This script has been tested in root mode on given
# ==========  platform using the mentioned version of the package.
#             It may not work as expected with newer versions of the
#             package and/or distribution. In such case, please
#             contact "Maintainer" of this script.
#
# ----------------------------------------------------------------------------

set -ex

# Variables
PACKAGE_NAME=cfssl
PACKAGE_VERSION=${1:-v1.6.3}
PACKAGE_URL=https://github.com/cloudflare/cfssl

# Install dependencies
yum install -y git golang make wget tar gcc sudo
sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc

OS_NAME=$(cat /etc/os-release | grep ^PRETTY_NAME | cut -d= -f2)

export GOPATH=$HOME/go
export PATH=/usr/local/go/bin:$GOPATH/bin:$PATH

# Install Go
GO_VERSION="1.18.8"
wget https://golang.org/dl/go${GO_VERSION}.linux-s390x.tar.gz
sudo tar -C /usr/local -xvzf go${GO_VERSION}.linux-s390x.tar.gz

# Clone the repository
git clone $PACKAGE_URL
cd $PACKAGE_NAME
git checkout $PACKAGE_VERSION

# Build and test the package
if ! go install github.com/cloudflare/cfssl/cmd/cfssl@${PACKAGE_VERSION} ||
   ! go install github.com/cloudflare/cfssl/cmd/cfssljson@${PACKAGE_VERSION}; then
    echo "------------------$PACKAGE_NAME:build_fails-------------------------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | $OS_NAME | GitHub | Fail |  Build_Fails"
    exit 1
fi

if [[ "$TESTS" == "true" ]]; then
    mkdir -p $GOPATH/src/github.com/cloudflare
    mv $PACKAGE_NAME $GOPATH/src/github.com/cloudflare/
    cd $GOPATH/src/github.com/cloudflare/cfssl
    go install golang.org/x/lint/golint@latest
    go mod vendor
    export PATH=$PATH:$GOPATH/bin
    export GO111MODULE=on
    export GOFLAGS="-mod=vendor"
    export GODEBUG="x509sha1=1"
    if ! ./test.sh; then
        echo "------------------$PACKAGE_NAME:test_fails---------------------"
        echo "$PACKAGE_URL $PACKAGE_NAME"
        echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | $OS_NAME | GitHub | Fail |  Test_Fails"
        exit 2
    fi
fi

echo "------------------$PACKAGE_NAME:build_and_test_success-------------------------"
echo "$PACKAGE_URL $PACKAGE_NAME"
touch build.log
echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | $OS_NAME | GitHub | Pass |  Build_and_Test_Success"