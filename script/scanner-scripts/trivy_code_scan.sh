#!/bin/bash -e

validate_build_script=$VALIDATE_BUILD_SCRIPT
cloned_package=$CLONED_PACKAGE
cd package-cache

DOCKER_IMAGE="sankalppersi/trivy-db:latest"
docker pull "$DOCKER_IMAGE"

if [ $validate_build_script == true ];then
    wget https://github.com/aquasecurity/trivy/releases/download/v0.45.0/trivy_0.45.0_Linux-S390X.tar.gz
    tar -xf trivy_0.45.0_Linux-S390X.tar.gz
    chmod +x trivy
    sudo mv trivy /usr/bin
    sudo trivy -q fs --timeout 30m -f json "${cloned_package}" > trivy_source_vulnerabilities_results.json || true
    echo "trivy.db not found, copying again.."
    find / -name "trivy.db" 2>/dev/null
    docker run -d --name trivy-container "$DOCKER_IMAGE"
    docker cp trivy-container:/trivy.db $HOME/.cache/trivy/db/trivy.db
    docker rm -f trivy-container

    sudo trivy -q fs --timeout 30m -f json "${cloned_package}" > trivy_source_vulnerabilities_results.json
    sudo trivy -q fs --timeout 30m -f cyclonedx "${cloned_package}" > trivy_source_sbom_results.cyclonedx
    
fi