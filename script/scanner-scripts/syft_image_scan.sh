#!/bin/bash -e

image_name=$IMAGE_NAME
build_docker=$BUILD_DOCKER

if [ $build_docker == true ];then
        wget https://github.com/anchore/syft/releases/download/v0.90.0/syft_0.90.0_linux_s390x.tar.gz
        tar -xf syft_0.90.0_linux_s390x.tar.gz
        chmod +x syft
        sudo mv syft /usr/bin  
        echo "Executing syft scanner"
        sudo syft -q -s AllLayers -o cyclonedx-json ${image_name} > syft_image_sbom_results.json
fi
