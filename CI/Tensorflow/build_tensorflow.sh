#!/bin/bash
# © Copyright IBM Corporation 2026
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)

set -x

cat /etc/os-release
df -h
free -h

ls /tmp | wc -l

export work_dir=$(pwd)
sudo rm -rf $work_dir/build_bazel.sh* $work_dir/logs $work_dir/tensorflow_whl $work_dir/Tensorflow_tmp $work_dir/bazel/ $work_dir/netty-tcnative $work_dir/netty
sudo rm -rf .cache $work_dir/.cache /root/.cache
sudo rm -rf  $work_dir/bazel/bazel/rules_java $work_dir/io
sudo rm -rf $work_dir/.ccachetmp

ls

mkdir $work_dir/tensorflow_whl
mkdir $work_dir/Tensorflow_tmp
mkdir $work_dir/bazel

sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install wget git gcc g++ unzip zip openjdk-21-jdk pkg-config libhdf5-dev libssl-dev libblas-dev liblapack-dev gfortran curl patchelf libopenblas-dev vim-common -y
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-s390x/
export PATH=$JAVA_HOME/bin:/usr/local/lib:$PATH
sudo DEBIAN_FRONTEND=noninteractive apt-get install lsb-release wget software-properties-common gnupg -y

mkdir $work_dir/.ccachetmp
export CCACHE_DIR=$work_dir/.ccachetmp

export HOME=/home/alfred/jenkins/workspace/TensorFlow_IBMZ_CI_test
export XDG_CACHE_HOME=/home/alfred/jenkins/workspace/TensorFlow_IBMZ_CI_test

cd $work_dir/bazel
rm -rf *
wget https://github.com/bazelbuild/bazel/releases/download/7.4.1/bazel-7.4.1-dist.zip
unzip bazel-7.4.1-dist.zip
chmod -R +w .
env EXTRA_BAZEL_ARGS="--tool_java_runtime_version=local_jdk" bash ./compile.sh
export PATH=$work_dir/bazel/output/:$PATH
sudo ln -s $work_dir/bazel/output/bazel /usr/bin/bazel

cd $work_dir
wget -q https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Python3/3.11.4/build_python3.sh
sed -i 's/apt-get install/DEBIAN_FRONTEND=noninteractive apt-get install/g' build_python3.sh
bash build_python3.sh -y
sudo update-alternatives --install /usr/local/bin/python python /usr/local/bin/python3 60  
sudo update-alternatives --install /usr/local/bin/pip3 pip3 /usr/local/bin/pip3.11 60

gcc --version
python3 -V
python -V

cd $work_dir
wget https://apt.llvm.org/llvm.sh
sed -i 's,add-apt-repository "${REPO_NAME}",add-apt-repository "${REPO_NAME}" -y,g' llvm.sh
chmod +x llvm.sh
sudo ./llvm.sh 19
rm ./llvm.sh
sudo ln -sf /usr/bin/clang-19 /usr/bin/clang
sudo ln -sf /usr/bin/clang++-19 /usr/bin/clang++

export GRPC_PYTHON_BUILD_SYSTEM_OPENSSL=True
pip3 install wheel==0.41.3 setuptools==70.0.0 numpy==2.1.3 ml-dtypes==0.5.1 grpcio==1.71.0 h5py==3.13.0
pip3 install keras_preprocessing --no-deps

cd $work_dir
wget https://cmake.org/files/v3.27/cmake-3.27.4.tar.gz
tar -xzf cmake-3.27.4.tar.gz
cd cmake-3.27.4
./bootstrap --prefix=/usr
make -j$(nproc)
sudo make install
hash -r

cd $work_dir

git clone -b v0.37.1 --depth 1 https://github.com/tensorflow/io.git
cd io/
python3 setup.py -q bdist_wheel --project tensorflow_io_gcs_filesystem
cd dist
pip3 install ./tensorflow_io_gcs_filesystem-0.37.1-cp*-cp*-linux_s390x.whl

cd $work_dir/tensorflow/

sed -i '/name *= *"XNNPACK"/a\
        patch_file = ["//third_party:xnn.patch"],' tensorflow/workspace2.bzl

patch -p1 < $work_dir/scripts/OSUOSL-CI/TensorFlow/patch/patch_file1.txt
patch -p1 < $work_dir/scripts/OSUOSL-CI/TensorFlow/patch/patch_xnnpack.txt
patch -p1 < $work_dir/scripts/OSUOSL-CI/TensorFlow/patch/patch_file2.txt
patch -p1 < $work_dir/scripts/OSUOSL-CI/TensorFlow/patch/patch_BUILD_llvm.txt
patch -p1 < $work_dir/scripts/OSUOSL-CI/TensorFlow/patch/patch_builtin_fp16.txt
patch -p1 < $work_dir/scripts/OSUOSL-CI/TensorFlow/patch/patch_vector_ops.txt

export TEST_TMPDIR=$work_dir/Tensorflow_tmp
yes "" | ./configure
sleep 5s

unset CC
unset CXX

TF_SYSTEM_LIBS="boringssl" TMPDIR="$work_dir/Tensorflow_tmp" bazel build --copt=-Wno-gnu-offsetof-extensions   //tensorflow/tools/pip_package:wheel --repo_env=WHEEL_NAME=tensorflow_cpu --define=with_openssl_support=true --linkopt="-l:libssl.so.3" --linkopt="-l:libcrypto.so.3" --action_env=CC="/usr/bin/clang" --action_env=CXX="/usr/bin/clang++"
ls bazel-bin/tensorflow/tools/pip_package/wheel_house/

rm -rf $work_dir/tensorflow_wheel/*
cp bazel-bin/tensorflow/tools/pip_package/wheel_house/*.whl $work_dir/tensorflow_whl
rm -rf $work_dir/tensorflow

df -h 
ls /tmp | wc -l
ls $work_dir/Tensorflow_tmp
