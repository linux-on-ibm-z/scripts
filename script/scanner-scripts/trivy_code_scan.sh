#!/bin/bash -e

validate_build_script=$VALIDATE_BUILD_SCRIPT
cloned_package=$CLONED_PACKAGE
current_dir=$(pwd)
cd "$current_dir"
printer() {
    while :; do
        echo "Build is still in progress..."
        sleep 200
    done
}
if [ $validate_build_script == true ];then
    sudo yum install make wget -y
    git clone https://github.com/aquasecurity/trivy-db.git
    cd trivy-db
    git checkout 492b9fcc1279a323f1e6f97f316d109c00da4528
    wget -q https://raw.githubusercontent.com/linux-on-ibm-z/scripts/refs/heads/master/script/trivy.patch
    git apply trivy.patch

    GO_VERSION=1.23.1
    wget -q https://storage.googleapis.com/golang/go"${GO_VERSION}".linux-s390x.tar.gz
    chmod ugo+r go"${GO_VERSION}".linux-s390x.tar.gz
    sudo rm -rf /usr/local/go /usr/bin/go
    sudo tar -C /usr/local -xzf go"${GO_VERSION}".linux-s390x.tar.gz
    sudo ln -sf /usr/local/go/bin/go /usr/bin/
    sudo ln -sf /usr/local/go/bin/gofmt /usr/bin/
    sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc

    printer &
    printer_pid=$!

    make db-fetch-langs db-fetch-vuln-list
    make build
    make db-build
    kill $printer_pid

    export TRIVY_DB_FILE=./out/trivy.db

    wget https://github.com/aquasecurity/trivy/releases/download/v0.45.0/trivy_0.45.0_Linux-S390X.tar.gz
    tar -xf trivy_0.45.0_Linux-S390X.tar.gz
    chmod +x trivy
    sudo mv trivy /usr/bin

    echo "Executing Trivy scanner"
    cd "$current_dir/package-cache"

    printer &
    printer_pid=$!

    sudo trivy -q fs --timeout 30m -f json "${cloned_package}" > trivy_source_vulnerabilities_results.json || true
    sudo cp /$current_dir/trivy-db/out/trivy.db /root/.cache/trivy/db/trivy.db
    sudo chmod 644 /$current_dir/trivy-db/out/trivy.db
    sudo trivy -q fs --timeout 30m -f json "${cloned_package}" > trivy_source_vulnerabilities_results.json
    sudo trivy -q fs --timeout 30m -f cyclonedx "${cloned_package}" > trivy_source_sbom_results.cyclonedx

    kill $printer_pid
fi