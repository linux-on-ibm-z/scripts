#!/bin/bash
# © Copyright IBM Corporation 2018.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)

################################################################################################################################################################
#Script Name:   BuildCalico_v3.2.3.sh 
#Description:   The script specify the commands to build Calico version v3.2.3 on Linux on IBM Z.
#Maintainer :   LoZ Open Source Ecosystem (https://www.ibm.com/developerworks/community/groups/community/lozopensource) 
#Info/Notes :   Please refer to the instructions first for Building Calico mentioned in wiki( https://github.com/linux-on-ibm-z/docs/wiki/Building-Calico-3.x ). 
#               Build logs can be found in $GOPATH/buildLogs/
#               By Default, system tests are turned off. To run system tests for Calico, pass argument "-tests" to shell script as : ./BuildCalico_v3.2.3.sh -t
#               Test logs can be found at $GOPATH/buildLogs/testlogN.
#               Script is in sync with Building Calico wiki from Step 2.
################################################################################################################################################################

### 1. Determine if Calico system tests are to be run
set -e
set -v
export runTests=$1

if [ "$runTests" = "-t" ]
then
	echo "System tests will also run after Calico node build is complete."
else
	echo "System tests won't run for Calico by default"
fi

### 2. Install the system dependencies
. /etc/os-release
if [ $ID == "rhel" ]; then
	sudo yum install -y curl git wget tar gcc glibc-static.s390x make which patch
	export CC=gcc
	if [ -x "$(command -v docker)" ]; then
		docker --version | grep "Docker version"
		echo "Docker already exists !! Skipping Docker Installation."
		sudo chmod ugo+rw /var/run/docker.sock
	else
		echo "Installing Docker !!"
		rm -rf docker-18.06.1-ce.tgz docker
		wget https://download.docker.com/linux/static/stable/s390x/docker-18.06.1-ce.tgz
		tar xvf docker-18.06.1-ce.tgz
		sudo cp docker/* /usr/local/bin/
cat << 'EOF' > docker.service
[Unit]
Description=Docker Application Container Engine
Documentation=http://docs.docker.com
After=network.target docker.socket
Requires=docker.socket

[Service]
# the default is not to use systemd for cgroups because the delegate issues still
# exists and systemd currently does not support the cgroup feature set required
# for containers run by docker
#EnvironmentFile=/etc/sysconfig/docker
PIDFile=/var/run/docker.pid
ExecStart=/usr/local/bin/dockerd -H fd:// -H tcp://0.0.0.0:2375 -G docker
MountFlags=slave
LimitNOFILE=1048576
LimitNPROC=1048576
LimitCORE=infinity
# set delegate yes so that systemd does not reset the cgroups of docker containers
Delegate=yes

[Install]
WantedBy=multi-user.target
EOF
cat << 'EOF' > docker.socket
[Unit]
Description=Docker Socket for the API
PartOf=docker.service

[Socket]
ListenStream=/var/run/docker.sock
SocketMode=0660
# A Socket(User|Group) replacement workaround for systemd <= 214
#ExecStartPost=/usr/bin/chown root:docker /var/run/docker.sock

[Install]
WantedBy=sockets.target
EOF
		sudo mv docker.service /etc/systemd/system/
		sudo mv docker.socket /etc/systemd/system/
		sudo systemctl daemon-reload
		sudo systemctl enable docker
		sudo systemctl start docker
		sleep 120s
		sudo chmod ugo+rw /var/run/docker.sock
		sudo systemctl status docker
		docker ps
	fi
elif [ $ID == "sles" ]; then
	sudo zypper install -y curl git wget tar gcc glibc-static.s390x make which patch
	export CC=gcc
	if [ -x "$(command -v docker)" ]; then
		docker --version | grep "Docker version"
		echo "Docker already exists !! Skipping Docker Installation."
		sudo chmod ugo+rw /var/run/docker.sock
	else
		echo "Installing Docker !!"
		rm -rf docker-18.06.1-ce.tgz docker
		wget https://download.docker.com/linux/static/stable/s390x/docker-18.06.1-ce.tgz
		tar xvf docker-18.06.1-ce.tgz
		sudo cp docker/* /usr/local/bin/
cat << 'EOF' > docker.service
[Unit]
Description=Docker Application Container Engine
Documentation=http://docs.docker.com
After=network.target docker.socket
Requires=docker.socket

[Service]
# the default is not to use systemd for cgroups because the delegate issues still
# exists and systemd currently does not support the cgroup feature set required
# for containers run by docker
#EnvironmentFile=/etc/sysconfig/docker
PIDFile=/var/run/docker.pid
ExecStart=/usr/local/bin/dockerd -H fd:// -H tcp://0.0.0.0:2375 -G docker
MountFlags=slave
LimitNOFILE=1048576
LimitNPROC=1048576
LimitCORE=infinity
# set delegate yes so that systemd does not reset the cgroups of docker containers
Delegate=yes

[Install]
WantedBy=multi-user.target
EOF
cat << 'EOF' > docker.socket
[Unit]
Description=Docker Socket for the API
PartOf=docker.service

[Socket]
ListenStream=/var/run/docker.sock
SocketMode=0660
# A Socket(User|Group) replacement workaround for systemd <= 214
#ExecStartPost=/usr/bin/chown root:docker /var/run/docker.sock

[Install]
WantedBy=sockets.target
EOF
		sudo mv docker.service /etc/systemd/system/
		sudo mv docker.socket /etc/systemd/system/
		sudo systemctl daemon-reload
		sudo systemctl enable docker
		sudo systemctl start docker
		sleep 120s
		sudo chmod ugo+rw /var/run/docker.sock
		sudo systemctl status docker
		docker ps
	fi
elif [ $ID == "ubuntu" ]; then
	sudo apt-get update && sudo apt-get install -y git curl tar gcc wget make patch apt-transport-https  ca-certificates  curl software-properties-common
	if [ -x "$(command -v docker)" ]; then
		docker --version | grep "Docker version"
		echo "Docker already exists !! Skipping Docker Installation."
		sudo chmod ugo+rw /var/run/docker.sock
	else
		echo "Installing Docker !!"
		curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
		sudo add-apt-repository "deb [arch=s390x] https://download.docker.com/linux/ubuntu artful stable"
		sudo apt-get update
		sudo apt-get install -y docker-ce
		sudo systemctl enable docker
		sudo systemctl start docker
		sleep 120s
		sudo chmod ugo+rw /var/run/docker.sock
		sudo systemctl status docker
		docker ps
	fi
fi


#### 3. Install `Go` and  `etcd` as prerequisites

### 3.1 Install `Go 1.10.1`
#Change the directory to your /<source_root>/ as mentioned in Building Calico wiki, this will also be your GOPATH and WORKDIR. And then execute below commands.
mkdir -p Calico_v3.2.3
cd Calico_v3.2.3
export WORKDIR=$PWD
wget https://storage.googleapis.com/golang/go1.10.1.linux-s390x.tar.gz
tar xf go1.10.1.linux-s390x.tar.gz
export GOPATH=$PWD
export GOROOT=$PWD/go
export PATH=$GOROOT/bin:$PATH
export PATH=$PATH:$GOPATH/bin
#Create directories for module wise logs
rm -rf $GOPATH/buildLogs
mkdir -p $GOPATH/buildLogs

### 3.2 Install `etcd v3.3.7`.
cd $WORKDIR 
mkdir -p $WORKDIR/src/github.com/coreos
mkdir -p $WORKDIR/etcd_temp
cd $WORKDIR/src/github.com/coreos
git clone git://github.com/coreos/etcd
cd etcd
git checkout v3.3.7
export ETCD_DATA_DIR=$WORKDIR/etcd_temp
export ETCD_UNSUPPORTED_ARCH=s390x
./build


#### 4. Build `calicoctl` and  `calico/node` image

### 4.1 Build `go-build`
##This builds a docker image calico/go-build that is used to build other components
git clone https://github.com/projectcalico/go-build $GOPATH/src/github.com/projectcalico/go-build
cd $GOPATH/src/github.com/projectcalico/go-build
git checkout v0.17

## Then  build `calico/go-build-s390x` image
ARCH=s390x make build 2>&1 | tee $GOPATH/buildLogs/go-build.log
if grep -Fxq "Successfully tagged calico/go-build:latest-s390x" $GOPATH/buildLogs/go-build.log
then
    echo "Successfully built calico/go-build"
else
    echo "go-build FAILED, Stopping further build !!! Check logs at $GOPATH/buildLogs/go-build.log"
	exit 1
fi

docker tag calico/go-build:latest-s390x calico/go-build-s390x:latest
docker tag calico/go-build:latest-s390x calico/go-build:latest
docker tag calico/go-build:latest-s390x calico/go-build:v0.17

### 4.2 Build `calicoctl` binary and `calico/ctl` image
## Download the source code
git clone https://github.com/projectcalico/calicoctl $GOPATH/src/github.com/projectcalico/calicoctl
cd $GOPATH/src/github.com/projectcalico/calicoctl
git checkout v3.2.3

## Build the `calicoctl` binary and `calico/ctl` image
ARCH=s390x make calico/ctl 2>&1 | tee $GOPATH/buildLogs/calicoctl.log

if grep -Fxq "Successfully tagged calico/ctl:latest-s390x" $GOPATH/buildLogs/calicoctl.log
then
    echo "Successfully built calico/ctl"
else
    echo "calico/ctl Build FAILED, Stopping further build !!! Check logs at $GOPATH/buildLogs/calicoctl.log"
	exit 1
fi


### 4.3 Build `bird`
## Download the source code
git clone https://github.com/projectcalico/bird $GOPATH/src/github.com/projectcalico/bird
cd $GOPATH/src/github.com/projectcalico/bird
git checkout v0.3.2

## Create `Dockerfile-s390x`
cat << 'EOF' > Dockerfile-s390x
FROM s390x/alpine:3.8
MAINTAINER LoZ Open Source Ecosystem (https://www.ibm.com/developerworks/community/groups/community/lozopensource)

RUN apk update
RUN apk add alpine-sdk linux-headers autoconf flex bison ncurses-dev readline-dev

WORKDIR /code
EOF

## Modify `build.sh`
#Create and apply patch for build.sh for modifying the same
cat << 'EOF' > build.sh.patch
diff --git a/build.sh b/build.sh
index cca3381..b939d0d 100755
--- a/build.sh
+++ b/build.sh
@@ -14,6 +14,10 @@ if [ $ARCH = ppc64le ]; then
        ARCHTAG=-ppc64le
 fi

+if [ $ARCH = s390x ]; then
+        ARCHTAG=-s390x
+fi
+
 DIST=dist/$ARCH

 docker build -t birdbuild$ARCHTAG -f Dockerfile$ARCHTAG .
EOF

patch < build.sh.patch

## Run `build.sh` to build 3 executable files (in `dist/s390x/`)
ARCH=s390x ./build.sh 2>&1 | tee $GOPATH/buildLogs/bird.log
if [[ "$(docker images -q birdbuild-s390x:latest 2> /dev/null)" == "" ]]; then
  echo "Bird build FAILED, Stopping further build !!! Check logs at $GOPATH/buildLogs/bird.log"
  exit 1
else
  echo "Successfully built bird module."
fi
## Tag calico/bird image
docker tag birdbuild-s390x:latest calico/bird:v0.3.2-s390x
docker tag birdbuild-s390x:latest calico/bird:latest

                   
### 4.4 Build `Typha`
## Download the source code
git clone https://github.com/projectcalico/typha $GOPATH/src/github.com/projectcalico/typha
cd $GOPATH/src/github.com/projectcalico/typha
git checkout v3.2.3

## Modify `Makefile`
#This removes `pull` argument to stop docker from pulling x86 image forcibly
sed -i '254s/--pull//' Makefile

## Modify `docker-image/Dockerfile.s390x`
cd docker-image
cat << 'EOF' > Dockerfile.s390x.patch
diff --git a/docker-image/Dockerfile.s390x b/docker-image/Dockerfile.s390x
index f3dd5da..fe8ebe1 100644
--- a/docker-image/Dockerfile.s390x
+++ b/docker-image/Dockerfile.s390x
@@ -1,7 +1,7 @@
 ARG QEMU_IMAGE=calico/go-build:latest
 FROM ${QEMU_IMAGE} as qemu

-FROM s390x/alpine:3.8
+FROM s390x/alpine:3.8 as base
 MAINTAINER LoZ Open Source Ecosystem (https://www.ibm.com/developerworks/community/groups/community/lozopensource)

 # Enable non-native builds of this image on an amd64 hosts.
@@ -12,15 +12,19 @@ COPY --from=qemu /usr/bin/qemu-s390x-static /usr/bin/

 # Since our binary isn't designed to run as PID 1, run it via the tini init daemon.
 RUN apk add --update tini
-ENTRYPOINT ["/sbin/tini", "--"]

-ADD typha.cfg /etc/calico/typha.cfg
+FROM scratch
+COPY --from=base /sbin/tini /sbin/tini
+COPY --from=base /lib/ld-musl-s390x.so.1 /lib/libc.musl-s390x.so.1  /lib/

 # Put out binary in /code rather than directly in /usr/bin.  This allows the downstream builds
 # to more easily extract the build artefacts from the container.
-RUN mkdir /code
 ADD bin/calico-typha-s390x /code/calico-typha
+ADD typha.cfg /etc/calico/typha.cfg
+
 WORKDIR /code
+ENV PATH="$PATH:/code"

 # Run Typha by default
+ENTRYPOINT ["/sbin/tini", "--"]
 CMD ["calico-typha"]
EOF

patch < Dockerfile.s390x.patch

## Build the binaries and docker image for typha
cd $GOPATH/src/github.com/projectcalico/typha
ARCH=s390x make calico/typha 2>&1 | tee $GOPATH/buildLogs/typha.log

if grep -Fxq "Successfully tagged calico/typha:latest-s390x" $GOPATH/buildLogs/typha.log
then
    echo "Successfully built calico/typha"
else
    echo "calico/typha Build FAILED, Stopping further build !!! Check logs at $GOPATH/buildLogs/typha.log"
	exit 1
fi

### 4.5 Build `felix`
## To build `felix` it  needs `felixbackend.pb.go` that is generated by a docker image `calico/protoc`. Let's first built this image.
git clone https://github.com/tigera/docker-protobuf $GOPATH/src/github.com/projectcalico/docker-protobuf
cd  $GOPATH/src/github.com/projectcalico/docker-protobuf

## Modify `Dockerfile-s390x`
#Remove existing Dockerfile and create a new one to include golang generators.
rm -rf Dockerfile-s390x
cat << 'EOF' > Dockerfile-s390x
FROM s390x/golang:1.9.2

MAINTAINER LoZ Open Source Ecosystem (https://www.ibm.com/developerworks/community/groups/community/lozopensource)

RUN apt-get update && apt-get install -y git make autoconf automake libtool unzip

# Clone the initial protobuf library down
RUN mkdir -p /src
WORKDIR /src
ENV PROTOBUF_TAG v3.5.1
RUN git clone https://github.com/google/protobuf

# Switch to protobuf folder and carry out build
WORKDIR /src/protobuf
RUN git checkout ${PROTOBUF_TAG}
# Cherry pick specific for big endian systems, see https://github.com/google/protobuf/pull/3955
RUN git cherry-pick -n 642e1ac635f2563b4a14c255374f02645ae85dac
RUN ./autogen.sh && ./configure --prefix=/usr
RUN make -j 3
RUN make check install

# Cleanup protobuf after installation
WORKDIR /src
RUN rm -rf protobuf

# TODO: Lock this down to specific versions
# Install gogo, an optimised fork of the Golang generators
RUN rm -vrf /go/src/github.com/gogo/protobuf/*
RUN go get -d github.com/gogo/protobuf/proto
WORKDIR /go/src/github.com/gogo/protobuf
RUN git checkout v1.0.0
WORKDIR /src
RUN go get github.com/gogo/protobuf/proto \
       github.com/gogo/protobuf/protoc-gen-gogo \
       github.com/gogo/protobuf/gogoproto \
       github.com/gogo/protobuf/protoc-gen-gogofast \
       github.com/gogo/protobuf/protoc-gen-gogofaster \
       github.com/gogo/protobuf/protoc-gen-gogoslick
RUN apt-get purge -y git make autoconf automake libtool unzip && apt-get clean -y

ENTRYPOINT ["protoc"]

EOF

## Build and tag docker image `calico/protoc-s390x`
docker build -t calico/protoc-s390x -f Dockerfile-s390x . 2>&1 | tee $GOPATH/buildLogs/docker-protobuf.log
if grep -Fxq "Successfully tagged calico/protoc-s390x:latest" $GOPATH/buildLogs/docker-protobuf.log
then
    echo "Successfully built calico/protoc-s390x"
else
    echo "calico/protoc Build FAILED, Stopping further build !!! Check logs at $GOPATH/buildLogs/docker-protobuf.log"
	exit 1
fi

docker tag calico/protoc-s390x:latest calico/protoc:latest-s390x


### Build `felix`
git clone https://github.com/projectcalico/felix $GOPATH/src/github.com/projectcalico/felix
cd $GOPATH/src/github.com/projectcalico/felix
git checkout v3.2.3

## Modify Makefile
#Change version to latest instead of v0.1
sed -i '146s/v0.1/latest/' Makefile
#Remove `pull` argument to stop docker from pulling x86 image forcibly
sed -i '338s/--pull//' Makefile

## Modify `docker-image/Dockerfile.s390x`
cd docker-image/

cat << 'EOF' > Dockerfile-s390x.patch
diff --git a/docker-image/Dockerfile.s390x b/docker-image/Dockerfile.s390x
index 07c7b1d..0e81060 100644
--- a/docker-image/Dockerfile.s390x
+++ b/docker-image/Dockerfile.s390x
@@ -1,7 +1,7 @@
 ARG QEMU_IMAGE=calico/go-build:latest
 FROM ${QEMU_IMAGE} as qemu

-FROM s390x/alpine:3.6
+FROM s390x/alpine:3.8 as base
 MAINTAINER LoZ Open Source Ecosystem (https://www.ibm.com/developerworks/community/groups/community/lozopensource)

 # Enable non-native builds of this image on an amd64 hosts.
@@ -10,13 +10,10 @@ MAINTAINER LoZ Open Source Ecosystem (https://www.ibm.com/developerworks/communi
 # when running on a kernel >= 4.8, this will become less relevant
 COPY --from=qemu /usr/bin/qemu-s390x-static /usr/bin/

-
-# Since our binary isn't designed to run as PID 1, run it via the tini init daemon.
 RUN apk --no-cache add --update tini
-ENTRYPOINT ["/sbin/tini", "--"]

 # Install Felix's dependencies.
-RUN apk --no-cache add ip6tables ipset iputils iproute2 conntrack-tools
+RUN apk --no-cache add ip6tables ipset iputils iproute2 conntrack-tools file

 ADD felix.cfg /etc/calico/felix.cfg
 ADD calico-felix-wrapper usr/bin
@@ -24,9 +21,19 @@ ADD calico-felix-wrapper usr/bin
 # Put out binary in /code rather than directly in /usr/bin.  This allows the downstream builds
 # to more easily extract the Felix build artefacts from the container.
 RUN mkdir /code
-ADD bin/calico-felix /code
-WORKDIR /code
+ADD bin/calico-felix-s390x /code/calico-felix
 RUN ln -s /code/calico-felix /usr/bin

+# final image just copies everything over
+# do NOT do any RUN commands in the final image
+FROM scratch
+
+COPY --from=base / /
+
+WORKDIR /code
+
+# Since our binary isn't designed to run as PID 1, run it via the tini init daemon.
+ENTRYPOINT ["/sbin/tini", "--"]
+
 # Run felix by default
 CMD ["calico-felix-wrapper"]
EOF

patch < Dockerfile-s390x.patch

## Build the felix binaries
cd $GOPATH/src/github.com/projectcalico/felix
ARCH=s390x make image 2>&1 | tee $GOPATH/buildLogs/felix.log

if grep -Fxq "Successfully tagged calico/felix:latest-s390x" $GOPATH/buildLogs/felix.log
then
    echo "Successfully built calico/felix"
else
    echo "calico/typha Build FAILED, Stopping further build !!! Check logs at $GOPATH/buildLogs/felix.log"
	exit 1
fi


### 4.6 Build `cni-plugin` binaries and image
## Download the source code
sudo mkdir -p /opt/cni/bin
git clone https://github.com/projectcalico/cni-plugin.git $GOPATH/src/github.com/projectcalico/cni-plugin
cd $GOPATH/src/github.com/projectcalico/cni-plugin
git checkout v3.2.3

## Build binaries and image
ARCH=s390x make image 2>&1 | tee $GOPATH/buildLogs/cni-plugin.log

if grep -Fxq "Successfully tagged calico/cni:latest-s390x" $GOPATH/buildLogs/cni-plugin.log
then
    echo "Successfully built calico/cni-plugin"
else
    echo "calico/cni-plugin Build FAILED, Stopping further build !!! Check logs at $GOPATH/buildLogs/cni-plugin.log"
	exit 1
fi

sudo cp bin/s390x/* /opt/cni/bin
docker tag calico/cni:latest-s390x calico/cni:latest
docker tag calico/cni:latest quay.io/calico/cni-s390x:v3.2.3


### 4.7 Build image `calico/node`
## Download the source
git clone https://github.com/projectcalico/node $GOPATH/src/github.com/projectcalico/node
cd $GOPATH/src/github.com/projectcalico/node
git checkout v3.2.3

## Modify `Makefile`
#Change bird tag to v0.3.2
sed -i '96s/v0.3.2-13-g17d14e60/v0.3.2/' Makefile
#Change tags from master to latest for routereflector, calicoctl etc.
sed -i '100s/master/latest/' Makefile
sed -i '101s/master/latest/' Makefile
sed -i '102s/master/latest/' Makefile
#Change etcd image tag and version
sed -i '111s/$(ETCD_IMAGE)/quay.io\/coreos\/etcd:v3.3.7/' Makefile
#Remove `pull` argument to stop docker from pulling x86 image forcibly
sed -i '238s/--pull//' Makefile
#Delete docker pull commands to stop docker from pulling x86 image forcibly
sed -i '380d' Makefile
sed -i '388d' Makefile
sed -i '403d' Makefile

## Modify `Dockerfile.s390x`
sed -i '38d' Dockerfile.s390x

## Get the yaml binary if not installed, needed for building `calico/node`
go get gopkg.in/mikefarah/yq.v1
cd $GOPATH/bin
ln -s yq.v1 yaml
export PATH=$PATH:$GOPATH/bin

### Build `calico/node`
cd $GOPATH/src/github.com/projectcalico/node
mkdir -p filesystem/bin
mkdir -p dist
cp $GOPATH/src/github.com/projectcalico/bird/dist/s390x/* $GOPATH/src/github.com/projectcalico/node/filesystem/bin
cp $GOPATH/src/github.com/projectcalico/felix/bin/calico-felix-s390x $GOPATH/src/github.com/projectcalico/node/filesystem/bin/calico-felix
cp $GOPATH/src/github.com/projectcalico/calicoctl/bin/calicoctl-linux-s390x $GOPATH/src/github.com/projectcalico/node/dist/calicoctl
ARCH=s390x make calico/node 2>&1 | tee $GOPATH/buildLogs/node.log

if grep -Fxq "Successfully tagged calico/node:latest-s390x" $GOPATH/buildLogs/node.log
then
    echo "Successfully built calico/node"
else
    echo "calico/node Build FAILED, Stopping further build !!! Check logs at $GOPATH/buildLogs/node.log"
	exit 1
fi

docker tag calico/node:latest-s390x quay.io/calico/node-s390x:v3.2.3
docker tag calico/node:latest-s390x calico/node

#### 5. Calico testcases


### 5.1 Build `etcd`
cd $GOPATH/src/github.com/projectcalico/
git clone https://github.com/coreos/etcd
cd etcd
git checkout v3.3.7

## Modify `Dockerfile-release` for s390x
cat << 'EOF' > Dockerfile-release.patch
diff --git a/Dockerfile-release b/Dockerfile-release
index 736445f..ab0df2a 100644
--- a/Dockerfile-release
+++ b/Dockerfile-release
@@ -1,7 +1,8 @@
-FROM alpine:latest
+FROM s390x/alpine:3.8

-ADD etcd /usr/local/bin/
-ADD etcdctl /usr/local/bin/
+ADD bin/etcd /usr/local/bin/
+ADD bin/etcdctl /usr/local/bin/
+ENV ETCD_UNSUPPORTED_ARCH=s390x
 RUN mkdir -p /var/etcd/
 RUN mkdir -p /var/lib/etcd/

EOF

patch < Dockerfile-release.patch

## Then build etcd and image
./build
docker build -f Dockerfile-release  -t quay.io/coreos/etcd . 2>&1 | tee $GOPATH/buildLogs/etcd.log

if grep -Fxq "Successfully tagged quay.io/coreos/etcd:latest" $GOPATH/buildLogs/etcd.log
then
    echo "Successfully built etcd image"
else
    echo "etcd image Build FAILED, Stopping further build !!! Check logs at $GOPATH/buildLogs/etcd.log"
	exit 1
fi

cd bin
tar cvf etcd-v3.3.7-linux-s390x.tar etcd etcdctl
gzip etcd-v3.3.7-linux-s390x.tar
docker tag quay.io/coreos/etcd:latest quay.io/coreos/etcd:v3.3.7-s390x


### 5.2 Build `Confd` Image
git clone https://github.com/projectcalico/confd $GOPATH/src/github.com/projectcalico/confd-v3.1.3
cd $GOPATH/src/github.com/projectcalico/confd-v3.1.3
git checkout v3.1.3

## Create `Dockerfile-s390x`
cat << 'EOF' > Dockerfile-s390x
FROM s390x/alpine:3.6
MAINTAINER LoZ Open Source Ecosystem (https://www.ibm.com/developerworks/community/groups/community/lozopensource)

# Copy in the binary.
ADD bin/confd /bin/confd
EOF

## Build confd image
cd $GOPATH/src/github.com/projectcalico/confd-v3.1.3
ARCH=s390x make container 2>&1 | tee $GOPATH/buildLogs/confd.log

if grep -Fxq "Successfully tagged calico/confd-s390x:latest" $GOPATH/buildLogs/confd.log
then
    echo "Successfully built calico/confd"
else
    echo "calico/confd Build FAILED, Stopping further build !!! Check logs at $GOPATH/buildLogs/confd.log"
	exit 1
fi

docker tag calico/confd-s390x:latest calico/confd:v3.1.1-s390x


### 5.3 Build `calico/routereflector`
git clone https://github.com/projectcalico/routereflector.git $GOPATH/src/github.com/projectcalico/routereflector
cd $GOPATH/src/github.com/projectcalico/routereflector
git checkout v0.6.3
cp $GOPATH/src/github.com/projectcalico/bird/dist/s390x/* image/

## Modify `Makefile`
sed -i '38s/v0.16/v0.17/' Makefile
sed -i '103d' Makefile

## Build the routereflector 
cd $GOPATH/src/github.com/projectcalico/routereflector
ARCH=s390x make image 2>&1 | tee $GOPATH/buildLogs/routereflector.log

if grep -Fxq "Successfully tagged calico/routereflector:latest-s390x" $GOPATH/buildLogs/routereflector.log
then
    echo "Successfully built calico/routereflector"
else
    echo "calico/routereflector Build FAILED, Stopping further build !!! Check logs at $GOPATH/buildLogs/routereflector.log"
	exit 1
fi

docker tag calico/routereflector:latest-s390x calico/routereflector:latest


### 5.4 Build `calico/dind`
git clone https://github.com/projectcalico/dind $GOPATH/src/github.com/projectcalico/dind
cd $GOPATH/src/github.com/projectcalico/dind
## Build the dind
docker build -t calico/dind -f Dockerfile-s390x . 2>&1 | tee $GOPATH/buildLogs/dind.log

if grep -Fxq "Successfully tagged calico/dind:latest" $GOPATH/buildLogs/dind.log
then
    echo "Successfully built calico/dind"
else
    echo "calico/dind Build FAILED, Stopping further build !!! Check logs at $GOPATH/buildLogs/dind.log"
	exit 1
fi


### 5.5 Build `calico/test`
cd $GOPATH/src/github.com/projectcalico/node/calico_test/
mkdir pkg
cp $GOPATH/src/github.com/projectcalico/etcd/bin/etcd-v3.3.7-linux-s390x.tar.gz pkg

## Create `Dockerfile.s390x.calico_test`
cat << 'EOF' > Dockerfile.s390x.calico_test
FROM s390x/docker:18.03.0
MAINTAINER LoZ Open Source Ecosystem (https://www.ibm.com/developerworks/community/groups/community/lozopensource)

RUN apk add --update python python-dev py2-pip py-setuptools openssl-dev libffi-dev tshark \
        netcat-openbsd iptables ip6tables iproute2 iputils ipset curl && \
        echo 'hosts: files mdns4_minimal [NOTFOUND=return] dns mdns4' >> /etc/nsswitch.conf && \
        rm -rf /var/cache/apk/*

COPY requirements.txt /requirements.txt
RUN pip install -r /requirements.txt

RUN apk update \
&&   apk add ca-certificates wget \
&&   update-ca-certificates

# Install etcdctl
COPY pkg /pkg/
RUN tar -xzf pkg/etcd-v3.3.7-linux-s390x.tar.gz -C /usr/local/bin/

# The container is used by mounting the code-under-test to /code
WORKDIR /code/
EOF


### 5.6 Run the test cases
#Pull s390x images for creating workload
docker pull s390x/busybox
docker tag s390x/busybox busybox
docker pull s390x/nginx
docker tag s390x/nginx nginx
docker tag quay.io/coreos/etcd quay.io/coreos/etcd:v3.3.7

## Create `Dockerfile.s390x`
cd $GOPATH/src/github.com/projectcalico/node/workload
cat << 'EOF' > Dockerfile.s390x
FROM s390x/alpine:3.8
RUN apk add --no-cache \
    python \
    netcat-openbsd
COPY udpping.sh tcpping.sh responder.py /code/
WORKDIR /code/
RUN chmod +x udpping.sh && chmod +x tcpping.sh
CMD ["python", "responder.py"]
EOF


#Verifying if all images are built/tagged
cd $GOPATH
cat << 'EOF' > docker_images_expected.txt
calico/dind:latest
calico/routereflector:latest
calico/routereflector:latest-s390x
calico/confd-s390x:latest
calico/confd:v3.1.1-s390x
quay.io/coreos/etcd:latest
quay.io/coreos/etcd:v3.3.7
quay.io/coreos/etcd:v3.3.7-s390x
calico/node:latest
calico/node:latest-s390x
quay.io/calico/node-s390x:v3.2.3
quay.io/calico/cni-s390x:v3.2.3
calico/cni:latest
calico/cni:latest-s390x
calico/felix:latest-s390x
calico/protoc-s390x:latest
calico/protoc:latest-s390x
calico/typha:latest-s390x
calico/bird:latest
calico/bird:v0.3.2-s390x
birdbuild-s390x:latest
calico/ctl:latest-s390x
calico/go-build:latest
calico/go-build:latest-s390x
calico/go-build:v0.17
calico/go-build-s390x:latest
EOF

docker images --format "{{.Repository}}:{{.Tag}}" > docker_images.txt

count=0
while read image; do
  if ! grep -q $image docker_images.txt; then
  echo ""
  echo "$image"
  count=`expr $count + 1`
  fi
done < docker_images_expected.txt
if [ "$count" != "0" ]; then
	echo ""
	echo ""
	echo "Above $count images need to be present. Check the logs of above images/modules in $GOPATH/buildLogs/"
	echo "CALICO NODE & TESTS BUILD FAILED !!"
	exit 1
else
	echo ""
	echo ""
	echo ""
	echo "###################-----------------------------------------------------------------------------------------------###################"
	echo "                                      All docker images are created as expected."
	echo ""
	echo "                                  CALICO NODE & TESTS BUILD COMPLETED SUCCESSFULLY !!"
	echo "###################-----------------------------------------------------------------------------------------------###################"
fi

##########################################################################################################################################################
##########################################################################################################################################################
#                                              CALICO NODE & TESTS BUILD COMPLETED SUCCESSFULLY                                                          #
##########################################################################################################################################################
##########################################################################################################################################################

## 4.6.2 Execute test cases(Optional)
#Will only run if arg "-t" is passed to shell script
if [ "$runTests" = "-t" ]
then
	echo ""
	echo ""
	echo "###################-----------------------------------------------------------------------------------------------###################"
	echo "                            Running system tests now. Testlogs are saved in $GOPATH/buildLogs/testlogN"
	echo "###################-----------------------------------------------------------------------------------------------###################"
	cd $GOPATH/src/github.com/projectcalico/node
	ARCH=s390x make st 2>&1 | tee $GOPATH/buildLogs/testlog1
else
	cd $GOPATH
	echo ""
	echo ""
	echo ""
	echo "-------------------------------------------------------------------------------------------------------------------"
	echo "      System tests won't run for Calico by default as \"-t\" was not passed to this script in beginning."
	echo "-------------------------------------------------------------------------------------------------------------------"
	echo ""
	echo ""
	echo "                             To run Calico system tests, run the following commands now:"
	echo "-------------------------------------------------------------------------------------------------------------------"
	echo "                               ##   You should be in directory .../Calico_v3.2.3   ##"
	echo "                                    export WORKDIR=\$PWD"
	echo "                                    export GOPATH=\$PWD"
	echo "                                    export GOROOT=\$PWD/go"
	echo "                                    export PATH=\$GOROOT/bin:\$PATH"
	echo "                                    export PATH=\$PATH:\$GOPATH/bin"
	echo "                                    export ETCD_DATA_DIR=\$WORKDIR/etcd_temp"
	echo "                                    export ETCD_UNSUPPORTED_ARCH=s390x"
	echo ""
	echo ""
	echo "                               ##  Running system tests now. Testlogs are saved in $GOPATH/buildLogs/testlogN  ##"
	echo "                                    cd \$GOPATH/src/github.com/projectcalico/node"
	echo "                                    ARCH=s390x make st 2>&1 | tee \$GOPATH/buildLogs/testlog1"
fi
