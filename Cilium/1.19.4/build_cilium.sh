#!/bin/bash
# © Copyright IBM Corporation 2026
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Cilium/1.19.4/build_cilium.sh
# Execute build script: bash build_cilium.sh    (provide -h for help)

# Package: Cilium
# Version: 1.19.4
# Source repo: https://github.com/cilium/cilium
# Maintainer :   LoZ Open Source Ecosystem (https://www.ibm.com/community/z/open-source)
# Language: Go, C++, Bazel

USER_IN_GROUP_DOCKER=$(id -nGz "$USER" | tr '\0' '\n' | grep -c '^docker$' || true)
set -e -o pipefail

PACKAGE_NAME="cilium"
PACKAGE_VERSION="v1.19.4"
SOURCE_ROOT="$(pwd)"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Cilium/1.19.4/patch"

# For local testing, use local patch directory if it exists
if [ -d "$SCRIPT_DIR/patch" ]; then
    PATCH_DIR="$SCRIPT_DIR/patch"
    msglog() { echo "$@"; }  # Define msglog early for this check
    msglog "Using local patch directory: $PATCH_DIR"
else
    PATCH_DIR=""
fi

FORCE="false"
TESTS="false"
DEBUG="false"

# Component versions
GO_VERSION="1.26.2"
CNI_VERSION="1.9.1"
KIND_VERSION="v0.32.0"
KIND_PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Kind/0.32.0/patch"
K8S_VERSION="v1.36.1"
KUBE_CROSS_TAG="v1.36.0-go1.26.2-trixie.0"
KIND_BASE_TAG="v20260601-995e8fa5"
KINDNETD_TAG="v20260528-9350166c"
LOCAL_PATH_PROV_TAG="v20260521-9fb22683"
LOCAL_PATH_HELPER_TAG="v20260131-7181c60a"
RELEASE_VERSION="v0.19.0"
CILIUM_CLI_VERSION="v0.18.5"
CLUSTER_NAME="cilium-test"
CMAKE_VERSION="3.28.3"

source "/etc/os-release"
DISTRO="$ID-$VERSION_ID"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$DISTRO-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
    mkdir -p "$SOURCE_ROOT/logs/"
fi

error() {
    echo "Error: ${*}"
    exit 1
}

msg() {
    echo "${*}"
}

log() {
    echo "${*}" >>"$LOG_FILE"
}

msglog() {
    echo "${*}" |& tee -a "$LOG_FILE"
}

cleanup() {
    # Remove temporary artifacts
    rm -rf "$SOURCE_ROOT"/go"${GO_VERSION}".linux-s390x.tar.gz
    rm -rf "$SOURCE_ROOT"/aws-lc/build-fips-s390x
    msglog "Cleaned up temporary artifacts"
}

printHelp() {
    echo "bash build_cilium.sh [-d debug] [-y install-without-confirmation] [-t run-test-cases]"
    echo "  default: Builds Cilium ${PACKAGE_VERSION} for s390x"
}

logDetails() {
    msglog "**************************** SYSTEM DETAILS ****************************"
    cat /etc/os-release |& tee -a "$LOG_FILE"
    msglog "detected distribution: $DISTRO"
    msglog "*************************** END SYSTEM DETAILS *************************"
}

prepare() {
    if command -v "sudo" >/dev/null; then
        msglog "sudo : Yes"
    else
        msglog "sudo : No"
        error "sudo is required. Install sudo from repository using apt, yum or zypper based on your distro."
    fi

    # Ensure swap is usable — some distros default to swappiness=0 which causes
    # the OOM killer to fire instead of swapping during memory-heavy builds (Bazel bootstrap)
    local current_swappiness
    current_swappiness=$(cat /proc/sys/vm/swappiness)
    if [[ "$current_swappiness" -lt 10 ]]; then
        msglog "Adjusting vm.swappiness from $current_swappiness to 60"
        sudo sysctl -w vm.swappiness=60 |& tee -a "$LOG_FILE"
    fi

    if command -v "docker" >/dev/null; then
        msglog "Docker : Yes"
        docker --version |& tee -a "$LOG_FILE"

        # Configure BuildKit to use host networking for RUN instructions.
        # The default BuildKit network sandbox can break on s390x hosts.
        if [ ! -f /etc/buildkit/buildkitd.toml ]; then
            sudo mkdir -p /etc/buildkit
            sudo tee /etc/buildkit/buildkitd.toml > /dev/null <<'BKEOF'
[worker.oci]
  networkMode = "host"
BKEOF
            msglog "Created BuildKit config for host networking"
            sudo systemctl restart docker |& tee -a "$LOG_FILE" || true
        fi
    else
        msglog "Docker : No"
        error "Docker is required. Please install Docker or Podman (with podman-docker) based on your distro."
    fi

    if [[ "$USER_IN_GROUP_DOCKER" == "1" ]]; then
        msglog "User $USER belongs to group docker"
    else
        msglog "Warning: User $USER does not belong to group docker. You may need to run 'sudo usermod -aG docker $USER' and log out/in."
    fi

    if [[ "$FORCE" == "true" ]]; then
        msglog "Force attribute provided. Continuing with install without confirmation."
    else
        # Ask user for prerequisite installation
        msg "\nAs part of the installation, dependencies would be installed/upgraded."
        msg "This build process will:"
        msg "  - Install Go ${GO_VERSION}"
        msg "  - Clone and build multiple components (image-tools, AWS-LC, proxy, cilium)"
        msg "  - Build Docker images locally (several GB of disk space required)"
        msg "\nPrerequisites:"
        msg "  - Docker with buildx support"

        while true; do
            read -r -p "Do you want to continue (y/n)? : " yn
            case $yn in
            [Yy]*)
                msglog "User responded with Yes."
                break
                ;;
            [Nn]*) exit ;;
            *) echo "Please provide confirmation to proceed." ;;
            esac
        done
    fi
}


installGo() {
    msglog "Installing Go ${GO_VERSION}"

    cd "$SOURCE_ROOT"
    wget -q https://go.dev/dl/go"${GO_VERSION}".linux-s390x.tar.gz
    chmod ugo+r go"${GO_VERSION}".linux-s390x.tar.gz
    sudo mkdir -p /usr/local/go-${GO_VERSION}
    sudo tar -C /usr/local/go-${GO_VERSION} --strip-components=1 -xzf go${GO_VERSION}.linux-s390x.tar.gz |& tee -a "$LOG_FILE"

    export GOROOT="/usr/local/go-${GO_VERSION}"
    export PATH="$GOROOT/bin:$PATH"
    export GOPATH=$SOURCE_ROOT/go

    go version |& tee -a "$LOG_FILE"
    msglog "Go installation completed"
}

buildImageTools() {
    msglog "Building Cilium image-tools"

    cd "$SOURCE_ROOT"

    # Clone image-tools if it doesn't exist
    # Using commit from around Cilium v1.19.4 release date (May 13, 2026)
    if [ ! -d "image-tools" ]; then
        msglog "Cloning image-tools repository (pinned to e8fd5656)"
        git clone https://github.com/cilium/image-tools.git |& tee -a "$LOG_FILE"
        cd image-tools
        git checkout e8fd56563d1738f3cf72190c6ed54080d8215fc4 |& tee -a "$LOG_FILE"
        cd ..
    else
        msglog "image-tools directory already exists, skipping clone"
    fi

    cd image-tools

    # Apply s390x patch
    if [ -n "$PATCH_DIR" ]; then
        if cat "$PATCH_DIR/image-tools-s390x.patch" | git apply - |& tee -a "$LOG_FILE"; then
            msglog "Applied image-tools s390x patch successfully"
        else
            if grep -q "linux/s390x" Makefile; then
                msglog "s390x support already present, patch may have been previously applied"
            else
                msglog "Warning: Failed to apply image-tools patch, attempting to continue anyway"
            fi
        fi
    else
        if curl -sSL "$PATCH_URL/image-tools-s390x.patch" | git apply - |& tee -a "$LOG_FILE"; then
            msglog "Applied image-tools s390x patch successfully"
        else
            if grep -q "linux/s390x" Makefile; then
                msglog "s390x support already present, patch may have been previously applied"
            else
                msglog "Warning: Failed to apply image-tools patch, attempting to continue anyway"
            fi
        fi
    fi

    # Remove container-based buildx builders and use default docker builder
    # Container-based builders cannot access locally-built images
    msglog "Configuring buildx to use default docker builder"
    for builder in $(docker buildx ls | grep docker-container | awk '{print $1}' | grep -v NAME); do
        msglog "Removing container-based builder: $builder"
        docker buildx rm "$builder" 2>&1 | tee -a "$LOG_FILE" || true
    done
    
    # Set buildx to use default builder
    docker buildx use default |& tee -a "$LOG_FILE"
    
    # Create .buildx_builder file pointing to default
    echo "default" > .buildx_builder
    
    export MAKER_IMAGE=local/image-maker:$(scripts/make-image-tag.sh images/maker)
    export TESTER_IMAGE=local/image-tester:$(scripts/make-image-tag.sh images/tester)
    export COMPILERS_IMAGE=local/image-compilers:$(scripts/make-image-tag.sh images/compilers)
    export CILIUM_LLVM_IMAGE=local/cilium-llvm:$(scripts/make-image-tag.sh images/llvm)
    export CILIUM_BPFTOOL_IMAGE=local/cilium-bpftool:$(scripts/make-image-tag.sh images/bpftool)
    export CILIUM_IPTABLES_IMAGE=local/iptables:$(scripts/make-image-tag.sh images/iptables)

    export REGISTRIES=local
    export PLATFORMS=linux/s390x
    export PUSH=false

    msglog "Building maker-image"
    if ! make maker-image |& tee -a "$LOG_FILE"; then
        error "maker-image build failed"
    fi
    
    msglog "Building tester-image"
    if ! make tester-image |& tee -a "$LOG_FILE"; then
        error "tester-image build failed"
    fi
    
    msglog "Building iptables-image"
    if ! make iptables-image |& tee -a "$LOG_FILE"; then
        error "iptables-image build failed"
    fi
    
    msglog "Building compilers-image (requires maker and tester)"
    if ! make compilers-image |& tee -a "$LOG_FILE"; then
        error "compilers-image build failed"
    fi
    
    msglog "Building bpftool-image (requires compilers and tester)"
    if ! make bpftool-image |& tee -a "$LOG_FILE"; then
        error "bpftool-image build failed"
    fi
    
    msglog "Building llvm-image (requires compilers and tester)"
    if ! make llvm-image |& tee -a "$LOG_FILE"; then
        error "llvm-image build failed"
    fi

    # Verify all images were built
    msglog "Verifying all image-tools images were built"
    for img in "$MAKER_IMAGE" "$TESTER_IMAGE" "$COMPILERS_IMAGE" "$CILIUM_LLVM_IMAGE" "$CILIUM_BPFTOOL_IMAGE" "$CILIUM_IPTABLES_IMAGE"; do
        if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${img}$"; then
            error "Image $img was not built successfully"
        fi
    done
    msglog "All image-tools images verified successfully"

    # Export image names for use by Cilium build
    echo "export MAKER_IMAGE=$MAKER_IMAGE" >> "$SOURCE_ROOT/cilium_env.sh"
    echo "export TESTER_IMAGE=$TESTER_IMAGE" >> "$SOURCE_ROOT/cilium_env.sh"
    echo "export COMPILERS_IMAGE=$COMPILERS_IMAGE" >> "$SOURCE_ROOT/cilium_env.sh"
    echo "export CILIUM_LLVM_IMAGE=$CILIUM_LLVM_IMAGE" >> "$SOURCE_ROOT/cilium_env.sh"
    echo "export CILIUM_BPFTOOL_IMAGE=$CILIUM_BPFTOOL_IMAGE" >> "$SOURCE_ROOT/cilium_env.sh"
    echo "export CILIUM_IPTABLES_IMAGE=$CILIUM_IPTABLES_IMAGE" >> "$SOURCE_ROOT/cilium_env.sh"

    msglog "Image-tools build completed"
}

buildAWSLC() {
    msglog "Building AWS-LC cryptographic library with FIPS support"

    cd "$SOURCE_ROOT"
    rm -rf aws-lc
    # Clone official AWS-LC repo
    msglog "Cloning AWS-LC from official repo"
    git clone https://github.com/aws/aws-lc.git |& tee -a "$LOG_FILE"
    cd aws-lc

    # Checkout commit that patches were created against
    git checkout ec37c27edb7b5002955b68a5c834164a43ddcb14 |& tee -a "$LOG_FILE"
    msglog "Using AWS-LC commit ec37c27e (base for s390x patches)"

    # Apply s390x FIPS delocate patch
    if [ -n "$PATCH_DIR" ]; then
        if cat "$PATCH_DIR/aws-lc-s390x.patch" | git apply - |& tee -a "$LOG_FILE"; then
            msglog "Applied AWS-LC s390x FIPS delocate patch successfully"
            git add -A
            git -c user.name="Build Script" -c user.email="build@localhost" commit -m "Apply s390x patches" |& tee -a "$LOG_FILE"
        else
            msglog "Warning: AWS-LC s390x patch failed to apply, build may fail"
        fi
    else
        if curl -sSL "$PATCH_URL/aws-lc-s390x.patch" | git apply - |& tee -a "$LOG_FILE"; then
            msglog "Applied AWS-LC s390x FIPS delocate patch successfully"
            git add -A
            git -c user.name="Build Script" -c user.email="build@localhost" commit -m "Apply s390x patches" |& tee -a "$LOG_FILE"
        else
            msglog "Warning: AWS-LC s390x patch failed to apply, build may fail"
        fi
    fi

    export AWS_LC_LOCAL_COMMIT="$(git rev-parse --short=9 HEAD)"
    export AWS_LC_LOCAL_SRC="$PWD"

    # Host verification build - non-fatal since the actual FIPS build happens inside Bazel/envoy
    if CC=${CC:-gcc} CXX=${CXX:-g++} cmake -S . -B build-fips-s390x \
        -DFIPS=1 \
        -DBUILD_TESTING=OFF \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS='-fPIC -Wno-error=cast-align -Wno-cast-align' \
        -DCMAKE_CXX_FLAGS='-fPIC -Wno-error=cast-align -Wno-cast-align' |& tee -a "$LOG_FILE"; then
        cmake --build build-fips-s390x -j$(nproc) |& tee -a "$LOG_FILE" || \
            msglog "Warning: AWS-LC host verification build failed (non-fatal - FIPS build happens inside envoy)"
    else
        msglog "Warning: AWS-LC cmake configuration failed (non-fatal - FIPS build happens inside envoy)"
    fi

    echo "export AWS_LC_LOCAL_COMMIT=$AWS_LC_LOCAL_COMMIT" >> "$SOURCE_ROOT/cilium_env.sh"
    echo "export AWS_LC_LOCAL_SRC=$AWS_LC_LOCAL_SRC" >> "$SOURCE_ROOT/cilium_env.sh"

    msglog "AWS-LC build completed"
}

buildProxy() {
    msglog "Building cilium-envoy (Envoy proxy with Cilium extensions)"

    cd "$SOURCE_ROOT"
    rm -rf proxy
    git clone https://github.com/cilium/proxy.git |& tee -a "$LOG_FILE"
    cd proxy

    # Checkout specific commit that uses apt.llvm.org (compatible with s390x)
    # Later commits switched to LLVM binaries which don't support s390x
    git checkout b87d1e32 |& tee -a "$LOG_FILE"

    # Apply s390x AWS-LC patch
    if [ -n "$PATCH_DIR" ]; then
        if cat "$PATCH_DIR/proxy-s390x-aws-lc.patch" | git apply - |& tee -a "$LOG_FILE"; then
            msglog "Applied proxy s390x patch successfully"
        else
            msglog "Warning: Proxy s390x patch failed to apply, build may fail"
        fi
    else
        if curl -sSL "$PATCH_URL/proxy-s390x-aws-lc.patch" | git apply - |& tee -a "$LOG_FILE"; then
            msglog "Applied proxy s390x patch successfully"
        else
            msglog "Warning: Proxy s390x patch failed to apply, build may fail"
        fi
    fi

    # Source environment from AWS-LC build
    source "$SOURCE_ROOT/cilium_env.sh"

    # Do NOT manually copy AWS-LC - let the Makefile's prepare-aws-lc-local target handle it
    # Remove any stale .aws-lc-local directory to ensure clean staging
    rm -rf "$SOURCE_ROOT/proxy/.aws-lc-local"

    export CILIUM_ENVOY_IMAGE="local/cilium-envoy-dev:$(git rev-parse HEAD)-s390x"
    export DOCKER_DEV_ACCOUNT=local
    export ARCH=s390x
    export AWS_LC_FIPS=1

    # Remove container-based buildx builders and use default docker builder.
    # The default builder uses the Docker daemon's embedded BuildKit which
    # respects /etc/buildkit/buildkitd.toml (configured for host networking).
    for builder in $(docker buildx ls | grep docker-container | awk '{print $1}' | grep -v NAME); do
        docker buildx rm "$builder" 2>/dev/null || true
    done
    docker buildx use default |& tee -a "$LOG_FILE"
    sed -i 's/docker buildx create/echo skip-buildx-create #/' Makefile.docker

    export DOCKER_BUILD_OPTS="--load"

    msglog "Building docker-image-builder for proxy"
    make docker-image-builder |& tee -a "$LOG_FILE"

    export IMAGE_PUSH=false
    export CARGO_BAZEL_REPIN=true
    export ENVOY_IP_TEST_VERSIONS=v4only

    msglog "Building docker-image-envoy with local AWS-LC source (commit: $AWS_LC_LOCAL_COMMIT)"
    msglog "Using 3 parallel jobs with 8GB RAM and 3 CPUs (reduced for stability)"

    # Pass AWS-LC and Bazel options to make
    # Note: EXTRA_BAZEL_BUILD_OPTS must be quoted to preserve spaces
    # Reduced parallelism to avoid Bazel server crashes
    make \
        AWS_LC_LOCAL_SRC="${AWS_LC_LOCAL_SRC}" \
        AWS_LC_LOCAL_COMMIT="${AWS_LC_LOCAL_COMMIT}" \
        EXTRA_BAZEL_BUILD_OPTS="--config=aws-lc-fips-http3-exp --jobs=3 --local_ram_resources=8192 --local_cpu_resources=3 --action_env=AWS_LC_FIPS=1 --verbose_failures --sandbox_debug" \
        docker-image-envoy |& tee -a "$LOG_FILE"

    echo "export CILIUM_ENVOY_IMAGE=$CILIUM_ENVOY_IMAGE" >> "$SOURCE_ROOT/cilium_env.sh"

    msglog "Cilium-envoy proxy build completed"
    msglog "Cilium-envoy proxy build completed"
    msglog "Cilium-envoy proxy build completed"
}

buildCilium() {
    msglog "Building Cilium core components"

    cd "$SOURCE_ROOT"
    rm -rf cilium
    git clone --depth 1 --branch "$PACKAGE_VERSION" https://github.com/cilium/cilium.git |& tee -a "$LOG_FILE"
    cd cilium

    # Apply s390x patch
    if [ -n "$PATCH_DIR" ]; then
        if cat "$PATCH_DIR/cilium-s390x.patch" | git apply - |& tee -a "$LOG_FILE"; then
            msglog "Applied Cilium s390x patch successfully"
            sed -i "s/docker buildx create/echo default #/" images/Makefile
        else
            msglog "Warning: Cilium s390x patch failed to apply, build may fail"
        fi
    else
        if curl -sSL "$PATCH_URL/cilium-s390x.patch" | git apply - |& tee -a "$LOG_FILE"; then
            msglog "Applied Cilium s390x patch successfully"
            sed -i "s/docker buildx create/echo default #/" images/Makefile
        else
            msglog "Warning: Cilium s390x patch failed to apply, build may fail"
        fi
    fi

    # Update CNI version
    images/scripts/update-cni-version.sh "$CNI_VERSION" |& tee -a "$LOG_FILE"

    # Commit all changes so git tree is clean — prevents the build system from appending "-wip" to image tags
    git add -A
    git -c user.name="Build Script" -c user.email="build@localhost" commit -m "Apply s390x patches" |& tee -a "$LOG_FILE"

    # Source environment variables
    source "$SOURCE_ROOT/cilium_env.sh"

    export CILIUM_RUNTIME_IMAGE="local/cilium-runtime-dev:$(images/scripts/make-image-tag.sh images/runtime)"
    export CILIUM_BUILDER_IMAGE="local/cilium-builder-dev:$(images/scripts/make-image-tag.sh images/builder)"

    export PUSH=false
    export REGISTRIES=local
    export OUTPUT=--load
    export PLATFORMS=linux/s390x
    export UBUNTU_IMAGE=public.ecr.aws/ubuntu/ubuntu:24.04@sha256:8307fed669bda8e552b5716194d81544760741347dbf3333e7dcd33680a2b986

    msglog "Building Cilium runtime image"
    make -C images runtime-image |& tee -a "$LOG_FILE"

    msglog "Building Cilium builder image"
    make -C images builder-image |& tee -a "$LOG_FILE"

    msglog "Building Cilium main image"
    make -C images cilium-image |& tee -a "$LOG_FILE"

    msglog "Building Cilium operator image"
    OPERATOR_VARIANT=operator-generic make -C images operator-image |& tee -a "$LOG_FILE"

    msglog "Building Hubble relay image"
    make -C images hubble-relay-image |& tee -a "$LOG_FILE"

    msglog "Cilium core components build completed"
}

buildAncillaryServices() {
    msglog "Building ancillary services (certgen, hubble-ui, alpine-curl, json-mock)"

    cd "$SOURCE_ROOT"

    # Build certgen
    msglog "Building certgen"
    rm -rf certgen
    git clone -b v0.4.3 https://github.com/cilium/certgen.git |& tee -a "$LOG_FILE"
    cd certgen
    DOCKER_IMAGE=local/certgen:latest DOCKER_IMAGE_TAG=latest make docker-image |& tee -a "$LOG_FILE"

    # Build hubble-ui
    msglog "Building hubble-ui"
    cd "$SOURCE_ROOT"
    rm -rf hubble-ui
    git clone -b v0.13.5 https://github.com/cilium/hubble-ui.git |& tee -a "$LOG_FILE"
    cd hubble-ui
    
    # Fix s390x support in byteorder file
    sed -i "s/armbe || arm64be || mips || mips64 || ppc64/armbe || arm64be || mips || mips64 || ppc64 || s390x/" backend/vendor/github.com/cilium/cilium/pkg/byteorder/byteorder_bigendian.go
    
    # Build frontend
    docker buildx build --platform linux/s390x --load -t local/hubble-ui:latest . |& tee -a "$LOG_FILE"
    
    # Build backend
    docker buildx build --platform linux/s390x --load -f backend/Dockerfile -t local/hubble-ui-backend:latest ./backend |& tee -a "$LOG_FILE"

    # Build alpine-curl
    msglog "Building alpine-curl"
    cd "$SOURCE_ROOT"
    rm -rf alpine-curl
    git clone -b v1.10.0 https://github.com/cilium/alpine-curl.git |& tee -a "$LOG_FILE"
    cd alpine-curl
    docker buildx build --platform linux/s390x --load -t local/alpine-curl:v1.10.0 . |& tee -a "$LOG_FILE"

    # Build json-mock
    msglog "Building json-mock"
    cd "$SOURCE_ROOT"
    rm -rf json-mock
    git clone -b v1.3.8 https://github.com/cilium/json-mock.git |& tee -a "$LOG_FILE"
    cd json-mock
    docker buildx build --platform linux/s390x --load -t local/json-mock:v1.3.8 . |& tee -a "$LOG_FILE"

    msglog "Ancillary services build completed"
}

buildKind() {
    msglog "Building Kind ${KIND_VERSION} for s390x"

    cd "$SOURCE_ROOT"
    if [ ! -f "$SOURCE_ROOT/kind/bin/kind" ]; then
        rm -rf kind
        git clone -b "$KIND_VERSION" https://github.com/kubernetes-sigs/kind.git |& tee -a "$LOG_FILE"
        cd kind
        curl -sSL "$KIND_PATCH_URL/kind.patch" | git apply --ignore-whitespace - |& tee -a "$LOG_FILE"
        make build |& tee -a "$LOG_FILE"
        sudo cp bin/kind /usr/local/bin/kind
    else
        msglog "Kind binary already built, skipping"
        cd kind
    fi

    make -C images/base quick REGISTRY=kindest TAG="$KIND_BASE_TAG" |& tee -a "$LOG_FILE"
    make -C images/kindnetd REGISTRY=kindest TAG="$KINDNETD_TAG" quick |& tee -a "$LOG_FILE"
    make -C images/local-path-provisioner REGISTRY=kindest TAG="$LOCAL_PATH_PROV_TAG" quick |& tee -a "$LOG_FILE"
    make -C images/local-path-helper REGISTRY=kindest TAG="$LOCAL_PATH_HELPER_TAG" quick |& tee -a "$LOG_FILE"

    kind version |& tee -a "$LOG_FILE"
}

buildKubeCross() {
    msglog "Building kube-cross image for s390x"

    cd "$SOURCE_ROOT"
    if docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "local/kube-cross-s390x"; then
        msglog "kube-cross image already exists, skipping"
        return
    fi

    rm -rf release
    git clone -b "$RELEASE_VERSION" https://github.com/kubernetes/release.git |& tee -a "$LOG_FILE"
    cd release
    curl -sSL "$KIND_PATCH_URL/release.patch" | { cat; echo; } | git apply --ignore-whitespace - |& tee -a "$LOG_FILE"
    cd images/build/cross
    REGISTRY=local TARGETPLATFORM=s390x make container |& tee -a "$LOG_FILE"
}

buildNodeImage() {
    msglog "Building kindest/node image"

    cd "$SOURCE_ROOT"
    if docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "kindest/node:${K8S_VERSION}"; then
        msglog "kindest/node image already exists, skipping"
        return
    fi

    rm -rf kubernetes
    git clone --depth 1 -b "$K8S_VERSION" https://github.com/kubernetes/kubernetes.git |& tee -a "$LOG_FILE"
    cd kubernetes

    sed -i "s,v1.36.0-go1.26.2-bullseye.0,${KUBE_CROSS_TAG},g" build/build-image/cross/VERSION

    KUBE_CROSS_IMAGE=local/kube-cross-s390x \
        kind build node-image --image "kindest/node:${K8S_VERSION}" |& tee -a "$LOG_FILE"
}

installKubectl() {
    msglog "Installing kubectl"

    if command -v kubectl &>/dev/null; then
        msglog "kubectl already installed: $(kubectl version --client 2>&1 | head -1)"
        return
    fi

    cd "$SOURCE_ROOT"
    local k8s_minor
    k8s_minor=$(echo "$K8S_VERSION" | sed 's/^v//' | cut -d. -f1,2)
    wget -q "https://dl.k8s.io/release/$(wget -qO- https://dl.k8s.io/release/stable-${k8s_minor}.txt)/bin/linux/s390x/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/kubectl
    kubectl version --client |& tee -a "$LOG_FILE"
}

installHelm() {
    msglog "Installing Helm"

    if command -v helm &>/dev/null; then
        msglog "helm already installed: $(helm version --short 2>/dev/null)"
        return
    fi

    cd "$SOURCE_ROOT"
    wget -q https://get.helm.sh/helm-v3.18.4-linux-s390x.tar.gz
    tar -xzf helm-v3.18.4-linux-s390x.tar.gz
    sudo mv linux-s390x/helm /usr/local/bin/helm
    rm -rf linux-s390x helm-v3.18.4-linux-s390x.tar.gz
    helm version |& tee -a "$LOG_FILE"
}

buildCiliumCLI() {
    msglog "Building Cilium CLI ${CILIUM_CLI_VERSION} from source"
    cd "$SOURCE_ROOT"
    if [ ! -d cilium-cli ]; then
        git clone -b "$CILIUM_CLI_VERSION" https://github.com/cilium/cilium-cli.git
    fi
    cd cilium-cli
    sed -i 's/armbe || arm64be || mips || mips64 || ppc64/armbe || arm64be || mips || mips64 || ppc64 || s390x/' \
        vendor/github.com/cilium/cilium/pkg/byteorder/byteorder_bigendian.go
    go build -o cilium ./cmd/cilium
    sudo cp cilium /usr/local/bin/cilium
    cilium version --client |& tee -a "$LOG_FILE"
}

createCluster() {
    msglog "Creating Kind cluster"

    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        msglog "Cluster '${CLUSTER_NAME}' already exists, deleting..."
        kind delete cluster --name "$CLUSTER_NAME" |& tee -a "$LOG_FILE"
    fi

    cat <<EOF | kind create cluster --name "$CLUSTER_NAME" --image "kindest/node:${K8S_VERSION}" --config=- |& tee -a "$LOG_FILE"
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true
  podSubnet: "10.244.0.0/16"
nodes:
  - role: control-plane
  - role: worker
EOF

    kubectl cluster-info --context "kind-${CLUSTER_NAME}" |& tee -a "$LOG_FILE"
}

loadImages() {
    msglog "Loading Cilium images into Kind cluster"

    local cilium_tag
    cilium_tag=$(docker images --format '{{.Tag}}' --filter "reference=local/cilium-dev" | head -1)

    local envoy_tag
    envoy_tag=$(docker images --format '{{.Tag}}' --filter "reference=local/cilium-envoy-dev" | grep -v HEAD | head -1)

    docker tag "local/operator-dev:${cilium_tag}" "local/operator-dev-generic:${cilium_tag}"

    docker pull --platform linux/s390x docker.io/coredns/coredns:1.12.0 |& tee -a "$LOG_FILE"

    local images=(
        "local/cilium-dev:${cilium_tag}"
        "local/operator-dev-generic:${cilium_tag}"
        "local/hubble-relay-dev:${cilium_tag}"
        "local/cilium-envoy-dev:${envoy_tag}"
        "local/certgen:latest"
        "local/alpine-curl:v1.10.0"
        "local/json-mock:v1.3.8"
        "docker.io/coredns/coredns:1.12.0"
    )

    # Use ctr import directly — kind load uses --all-platforms which fails
    # when Docker's containerd store preserves multi-arch manifest indexes
    local nodes
    nodes=$(kind get nodes --name "$CLUSTER_NAME")

    for img in "${images[@]}"; do
        msglog "Loading $img"
        for node in $nodes; do
            docker save "$img" | docker exec -i "$node" \
                ctr --namespace=k8s.io images import --digests --snapshotter=overlayfs - \
                |& tee -a "$LOG_FILE"
        done
    done
}

installCilium() {
    msglog "Installing Cilium via Helm"

    local cilium_tag
    cilium_tag=$(docker images --format '{{.Tag}}' --filter "reference=local/cilium-dev" | head -1)
    local envoy_tag
    envoy_tag=$(docker images --format '{{.Tag}}' --filter "reference=local/cilium-envoy-dev" | grep -v HEAD | head -1)

    helm repo add cilium https://helm.cilium.io/ 2>/dev/null || true
    helm repo update |& tee -a "$LOG_FILE"

    helm install cilium cilium/cilium --version "1.19.4" \
        --namespace kube-system \
        --set image.repository="local/cilium-dev" \
        --set image.tag="${cilium_tag}" \
        --set image.useDigest=false \
        --set image.pullPolicy=Never \
        --set operator.image.repository="local/operator-dev" \
        --set operator.image.tag="${cilium_tag}" \
        --set operator.image.useDigest=false \
        --set operator.image.pullPolicy=Never \
        --set hubble.relay.image.repository="local/hubble-relay-dev" \
        --set hubble.relay.image.tag="${cilium_tag}" \
        --set hubble.relay.image.useDigest=false \
        --set hubble.relay.image.pullPolicy=Never \
        --set envoy.image.repository="local/cilium-envoy-dev" \
        --set envoy.image.tag="${envoy_tag}" \
        --set envoy.image.useDigest=false \
        --set envoy.image.pullPolicy=Never \
        --set certgen.image.repository="local/certgen" \
        --set certgen.image.tag="latest" \
        --set certgen.image.useDigest=false \
        --set certgen.image.pullPolicy=Never \
        --set hubble.enabled=true \
        --set hubble.relay.enabled=true \
        --set hubble.ui.enabled=false \
        --set ipam.operator.clusterPoolIPv4PodCIDRList="{10.244.0.0/16}" \
        |& tee -a "$LOG_FILE"

    msglog "Waiting for Cilium to be ready..."
    kubectl -n kube-system rollout status deployment/cilium-operator --timeout=300s |& tee -a "$LOG_FILE"
    kubectl -n kube-system rollout status daemonset/cilium --timeout=300s |& tee -a "$LOG_FILE"
}

runConnectivityTest() {
    msglog "Running Cilium connectivity test suite"

    kubectl wait --for=condition=Ready nodes --all --timeout=120s |& tee -a "$LOG_FILE"
    cilium status --wait |& tee -a "$LOG_FILE"

    cilium connectivity test --test-concurrency=1 \
        --external-target www.ibm.com. \
        --external-other-target k8s.io. \
        --curl-image "local/alpine-curl:v1.10.0" \
        --json-mock-image "local/json-mock:v1.3.8" \
        --dns-test-server-image "docker.io/coredns/coredns:1.12.0" \
        |& tee -a "$LOG_FILE"

    msglog "Connectivity test suite PASSED"
}

runTests() {
    if [[ "$TESTS" != "true" ]]; then
        return 0
    fi

    msglog "Starting Kind-based Cilium verification tests"

    buildKind
    buildKubeCross
    buildNodeImage
    installKubectl
    installHelm
    buildCiliumCLI
    createCluster
    loadImages
    installCilium
    runConnectivityTest

    msglog "Cleaning up test cluster..."
    kind delete cluster --name "$CLUSTER_NAME" |& tee -a "$LOG_FILE"

    msglog "All tests PASSED"
}

gettingStarted() {
    msglog "\n**********************************************************************************************************"
    msglog "\n* Cilium ${PACKAGE_VERSION} has been successfully built for s390x architecture"
    msglog "* Built Docker images:"
    msglog "*   - local/cilium-runtime-dev"
    msglog "*   - local/cilium-builder-dev"
    msglog "*   - local/cilium-dev"
    msglog "*   - local/operator-dev"
    msglog "*   - local/hubble-relay-dev"
    msglog "*   - local/cilium-envoy-dev"
    msglog "*   - local/hubble-ui"
    msglog "*   - local/hubble-ui-backend"
    msglog "*   - local/certgen"
    msglog "*   - And supporting images (image-tools, alpine-curl, json-mock)"
    msglog "*"
    msglog "* To view built images: docker images | grep local/"
    msglog "*"
    msglog "* To deploy Cilium:"
    msglog "*   1. Set up a Kubernetes cluster (Kind, k3s, or full cluster)"
    msglog "*   2. Use Helm to install Cilium with the local images"
    msglog "*   3. See cilium.sh for a full deployment example with all configuration options"
    msglog "*"
    msglog "* Log file: $LOG_FILE"
    msglog "*"
    msglog "**********************************************************************************************************"
}

configureAndInstall() {
    msglog "Configuration and Installation started"

    installGo

    buildImageTools
    buildAWSLC

    # Build Envoy proxy with FIPS-enabled AWS-LC
    buildProxy

    buildCilium
    buildAncillaryServices

    runTests

    msglog "Build completed successfully"
}

logDetails

#Parse command line options.
while getopts "h?ytd" opt; do
    case "$opt" in
    h | \?)
        printHelp
        exit 0
        ;;
    y) FORCE="true" ;;
    t) TESTS="true" ;;
    d) DEBUG="true" ; set -x ;;
    esac
done

prepare

case "$DISTRO" in
#----------------------------------------------------------
"rhel-9.6" | "rhel-9.8" | "rhel-10.0" | "rhel-10.2")
    msglog "\nInstalling $PACKAGE_NAME $PACKAGE_VERSION for $DISTRO"

    sudo dnf install -y --allowerasing wget curl git cmake clang make rsync file \
        ca-certificates gnupg yum-utils device-mapper-persistent-data lvm2 |& tee -a "${LOG_FILE}"

    configureAndInstall
    ;;

#----------------------------------------------------------
"sles-15.7" | "sles-16.0")
    msglog "\nInstalling $PACKAGE_NAME $PACKAGE_VERSION for $DISTRO"

    sudo zypper install -y wget curl git cmake gcc gcc-c++ make rsync file patch \
        ca-certificates |& tee -a "${LOG_FILE}"

    configureAndInstall
    ;;

#----------------------------------------------------------
"ubuntu-22.04" | "ubuntu-24.04")
    msglog "\nInstalling $PACKAGE_NAME $PACKAGE_VERSION for $DISTRO"

    # Ensure universe repo is enabled (clang requires it)
    if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then
        sudo sed -i 's/Components: main$/Components: main universe/' /etc/apt/sources.list.d/ubuntu.sources
    elif [ -f /etc/apt/sources.list ]; then
        sudo sed -i 's/^\(deb .* main\)$/\1 universe/' /etc/apt/sources.list
    fi

    sudo apt-get update |& tee -a "${LOG_FILE}"
    sudo apt-get install -y wget curl git cmake clang make rsync file \
        ca-certificates gnupg lsb-release apt-transport-https |& tee -a "${LOG_FILE}"

    configureAndInstall
    ;;

#----------------------------------------------------------
*)
    error "$DISTRO not supported. Supported distributions: rhel-9.6, rhel-9.8, rhel-10.0, rhel-10.2, sles-15.7, sles-16.0, ubuntu-22.04, ubuntu-24.04"
    ;;
esac

gettingStarted
