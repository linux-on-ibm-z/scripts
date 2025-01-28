#!/bin/bash -e

image_name=$IMAGE_NAME
build_docker=$BUILD_DOCKER

DOCKER_IMAGE="sankalppersi/trivy-db:latest"
docker pull "$DOCKER_IMAGE"
docker run -d --name trivy-container "$DOCKER_IMAGE"
sudo mkdir -p /root/.cache/trivy/db
sudo docker cp trivy-container:/trivy.db /root/.cache/trivy/db/trivy.db
docker rm -f trivy-container

if [ $build_docker == true ];then
	wget https://github.com/aquasecurity/trivy/releases/download/v0.45.0/trivy_0.45.0_Linux-S390X.tar.gz
	tar -xf trivy_0.45.0_Linux-S390X.tar.gz
        chmod +x trivy
        sudo mv trivy /usr/bin
	echo "Executing trivy scanner"
	sudo trivy -q image --timeout 30m -f json ${image_name} > trivy_image_vulnerabilities_results.json
	sudo trivy -q image --timeout 30m -f cyclonedx ${image_name} > trivy_image_sbom_results.cyclonedx
 fi