#!/bin/bash

set -e  # Exit on error

CONFIG_NAME=$1
NAMESPACE="test-pods"
CONFIGMAP_FILE="boskos/boskos-configmap.yaml"
MAX_WAIT=300  # Max wait time in seconds
INTERVAL=0.5    # Check every 5 seconds

# Colors
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m'  # No color

if [ -z "$CONFIG_NAME" ]; then
    echo -e "${RED}❌ Error: Config name is required.${NC}"
    echo -e "   Usage: ./deploy_boskos.sh <config-name>"
    exit 1
fi

echo -e "\n🔹 ${BLUE}Checking if namespace '$NAMESPACE' exists...${NC}"
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
    echo -e "🛠️  Namespace '$NAMESPACE' does not exist. Creating..."
    kubectl create namespace "$NAMESPACE"
else
    echo -e "✅ Namespace '$NAMESPACE' already exists."
fi

echo -e "\n🔹 ${BLUE}Deleting existing Boskos resources...${NC}"
kubectl delete -f boskos/ --ignore-not-found=true

echo -e "\n🔹 ${BLUE}Updating $CONFIGMAP_FILE with new config name: $CONFIG_NAME${NC}"
cat <<EOF > "$CONFIGMAP_FILE"
apiVersion: v1
kind: ConfigMap
metadata:
  name: resources
  namespace: $NAMESPACE
data:
  boskos-resources.yaml: |
    resources:
      - type: "vpc-service"
        state: free
        names:
          - "$CONFIG_NAME"
EOF

echo -e "\n🔹 ${BLUE}Applying Boskos configuration...${NC}"
kubectl apply -f boskos/

# Wait for resources to initialize with an animation
echo -e "\n⏳ ${YELLOW}Waiting for resources to become ready...${NC}"

spin=("█▒▒▒▒▒▒▒▒▒" "███▒▒▒▒▒▒▒" "█████▒▒▒▒▒" "██████████") 
i=0
start_time=$(date +%s)
while true; do
    # Fetch statuses
    PODS=$(kubectl get pods -n "$NAMESPACE" --no-headers || true)
    CLUSTER_SECRET=$(kubectl get clustersecretstore -n "$NAMESPACE" --no-headers || true)
    EXTERNAL_SECRET=$(kubectl get externalsecrets -n "$NAMESPACE" --no-headers || true)

    # Parse statuses
    PODS_READY=$(echo "$PODS" | grep -E 'Running' | wc -l)
    PODS_TOTAL=$(echo "$PODS" | wc -l)
    CLUSTER_SECRET_READY=$(echo "$CLUSTER_SECRET" | awk '{print $5}')
    CLUSTER_SECRET_STATUS=$(echo "$CLUSTER_SECRET" | awk '{print $3}')
    EXTERNAL_SECRET_READY=$(echo "$EXTERNAL_SECRET" | awk '{print $5}')
    EXTERNAL_SECRET_STATUS=$(echo "$EXTERNAL_SECRET" | awk '{print $4}')

    # Set default stickers
    PODS_STICKER="⏳"
    CLUSTER_SECRET_STICKER="⏳"
    EXTERNAL_SECRET_STICKER="⏳"

    # Update stickers based on readiness
    if [ "$PODS_READY" -eq "$PODS_TOTAL" ] && [ "$PODS_TOTAL" -gt 0 ]; then
        PODS_STICKER="✅"
    elif [ "$PODS_TOTAL" -gt 0 ]; then
        PODS_STICKER="⚠️"
    fi

    if [ "$CLUSTER_SECRET_READY" == "True" ] && [ "$CLUSTER_SECRET_STATUS" == "Valid" ]; then
        CLUSTER_SECRET_STICKER="✅"
    elif [ -n "$CLUSTER_SECRET_READY" ]; then
        CLUSTER_SECRET_STICKER="⚠️"
    fi

    if [ "$EXTERNAL_SECRET_READY" == "True" ] && [ "$EXTERNAL_SECRET_STATUS" == "SecretSynced" ]; then
        EXTERNAL_SECRET_STICKER="✅"
    elif [ -n "$EXTERNAL_SECRET_READY" ]; then
        EXTERNAL_SECRET_STICKER="⚠️"
    fi

    # Clear the screen to give the illusion of animation
    clear

    # Display real-time status
    echo -e "\n🔹 ${BLUE}Current Resource Status:${NC}"
    echo -e "+------------------------+-------------------+"
    echo -e "| ${BLUE}Resource${NC}                | ${BLUE}Status${NC}          |"
    echo -e "+------------------------+-------------------+"
    printf "| %-22s | ${YELLOW}%-15s${NC} |\n" "Pods ($PODS_READY/$PODS_TOTAL)" "$PODS_STICKER"
    printf "| %-22s | ${YELLOW}%-15s${NC} |\n" "ClusterSecretStore" "$CLUSTER_SECRET_STICKER"
    printf "| %-22s | ${YELLOW}%-15s${NC} |\n" "ExternalSecrets" "$EXTERNAL_SECRET_STICKER"
    echo -e "+------------------------+-------------------+"

    # Exit loop when all resources are ready
    if [[ "$PODS_READY" -eq "$PODS_TOTAL" && "$CLUSTER_SECRET_READY" == "True" && "$CLUSTER_SECRET_STATUS" == "Valid" && "$EXTERNAL_SECRET_READY" == "True" && "$EXTERNAL_SECRET_STATUS" == "SecretSynced" ]]; then
        echo -e "\n✅ ${GREEN}All resources are successfully initialized!${NC}"
        break
    fi

    # Check timeout
    current_time=$(date +%s)
    elapsed_time=$((current_time - start_time))
    if [ "$elapsed_time" -ge "$MAX_WAIT" ]; then
        echo -e "\n❌ ${RED}Timeout: Resources did not become ready within $MAX_WAIT seconds.${NC}"
        break
    fi

    # Spinner animation
    # Update spinner symbol and print it
    echo -ne "${spin[$i]}"

    # Increment and loop the spinner symbols
    i=$(( (i+1) %4 ))  # Loop through the spinner array
    sleep "$INTERVAL"   # Set the interval for updates
done


echo ""
echo "🔹 Final Resource Status:"
# Function to print table header
print_header() {
    printf "\n🔹 %s:\n" "$1"
    printf "%s\n" "$2"
}

# Function to print table footer
print_footer() {
    printf "%s\n" "$1"
}

# Pods
print_header "Pods" "+--------------------------------------------------+--------+----------+----------+------+
| NAME                                         | READY  | STATUS   | RESTARTS | AGE  |
+--------------------------------------------------+--------+----------+----------+------+"
kubectl get pods -n "$NAMESPACE" --no-headers | awk '{ printf "| %-46s | %-6s | %-8s | %-8s | %-4s |\n", $1, $2, $3, $4, $5 }'
print_footer "+--------------------------------------------------+--------+----------+----------+------+"

# Deployments
print_header "Deployments" "+----------------------------------------+--------+------------+-----------+------+
| NAME                                   | READY  | UP-TO-DATE | AVAILABLE | AGE  |
+----------------------------------------+--------+------------+-----------+------+"
kubectl get deployments -n "$NAMESPACE" --no-headers | awk '{ printf "| %-38s | %-6s | %-10s | %-9s | %-4s |\n", $1, $2, $3, $4, $5 }'
print_footer "+----------------------------------------+--------+------------+-----------+------+"

# Services
print_header "Services" "+------------------+-----------+---------------+-------------+--------+
| NAME             | TYPE      | CLUSTER-IP    | EXTERNAL-IP | PORTS  |
+------------------+-----------+---------------+-------------+--------+"
kubectl get services -n "$NAMESPACE" --no-headers | awk '{ printf "| %-16s | %-9s | %-13s | %-11s | %-6s |\n", $1, $2, $3, $4, $5 }'
print_footer "+------------------+-----------+---------------+-------------+--------+"

# ClusterSecretStore
print_header "ClusterSecretStore" "+----------------------------------------------+------+--------+-------------+------+
| NAME                                         | AGE  | STATUS | CAPABILITIES | READY|
+----------------------------------------------+------+--------+-------------+------+"
kubectl get clustersecretstore -n "$NAMESPACE" --no-headers | awk '{ printf "| %-44s | %-4s | %-6s | %-11s | %-5s |\n", $1, $2, $3, $4, $5 }'
print_footer "+----------------------------------------------+------+--------+-------------+------+"

# ExternalSecrets
print_header "ExternalSecrets" "+----------------------------------------------+----------------+-----------------+--------------+------+
| NAME                                         | STORE          | REFRESH INTERVAL | STATUS       | READY|
+----------------------------------------------+----------------+-----------------+--------------+------+"
kubectl get externalsecrets -n "$NAMESPACE" --no-headers | awk '{ printf "| %-44s | %-14s | %-15s | %-12s | %-5s |\n", $1, $2, $3, $4, $5 }'
print_footer "+----------------------------------------------+----------------+-----------------+--------------+------+"
