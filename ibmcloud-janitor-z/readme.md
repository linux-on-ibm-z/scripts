# Deploying Boskos with Custom Configurations

## Overview
This script (`deploy_boskos.sh`) automates the deployment of Boskos on a Kubernetes cluster. It ensures that the **test-pods namespace exists**, deletes any existing Boskos resources, updates the `boskos-configmap.yaml` file with a specified configuration name, applies the new configuration, and finally retrieves deployed resources.

## Prerequisites
Before running the script, ensure the following:
- You have a running **Kubernetes cluster**.
- You have **kubectl** installed and configured to interact with the cluster.
- The **Boskos configuration files** exist inside a `boskos/` directory.

## Installation
Clone or copy the script into your working directory:
```sh
chmod +x deploy_boskos.sh
```

## Usage
To deploy Boskos with a custom configuration name, run:
```sh
./deploy_boskos.sh <config-name>
```
Where `<config-name>` is the new name you want to set under the `vpc-service` in the `boskos-configmap.yaml` file.

### Example:
```sh
./deploy_boskos.sh new-conformance
```
This will update `boskos-configmap.yaml` so it contains:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: resources
  namespace: test-pods
data:
  boskos-resources.yaml: |
    resources:
      - type: "vpc-service"
        state: free
        names:
          - "new-conformance"
```

## How It Works
1. **Ensures namespace exists:** If `test-pods` does not exist, it creates it.
2. **Deletes old Boskos resources:** Ensures a clean slate before redeployment.
3. **Updates boskos-configmap.yaml:** Modifies the `names:` field under `vpc-service`.
4. **Deploys the updated Boskos resources.**
5. **Fetches deployed resources:** Lists Pods, ClusterSecretStore, and ExternalSecrets in `test-pods` namespace.

## Output
After successful execution, the script prints details of deployed resources, including:
- Running **Boskos Pods**
- Status of **ClusterSecretStore**
- Status of **ExternalSecrets**

## Troubleshooting
- If the `boskos` pod is in **Error** state, check logs using:
  ```sh
  kubectl logs -n test-pods <boskos-pod-name>
  ```
- If `names:` field is missing in `boskos-configmap.yaml`, verify the script execution and manually check the YAML formatting.

## Cleanup
To remove Boskos resources manually, run:
```sh
kubectl delete -f boskos/
```
