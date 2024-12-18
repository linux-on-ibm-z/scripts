#!/bin/bash -e

image_name=$IMAGE_NAME
build_docker=$BUILD_DOCKER

if [ $build_docker == true ];then
	wget https://github.com/aquasecurity/trivy/releases/download/v0.45.0/trivy_0.45.0_Linux-S390X.tar.gz
	tar -xf trivy_0.45.0_Linux-S390X.tar.gz
        chmod +x trivy
        sudo mv trivy /usr/bin
	echo "Executing trivy scanner"
	sudo trivy -q image --timeout 30m -f json ${image_name} > trivy_image_vulnerabilities_results.json
	sudo trivy -q image --timeout 30m -f cyclonedx ${image_name} > trivy_image_sbom_results.cyclonedx
 fi
