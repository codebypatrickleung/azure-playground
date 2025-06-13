#!/bin/bash

## Tool installation and deployment script
### Check if Azure CLI is installed, If not install it in Ubuntu
if ! command -v az &> /dev/null; then
    echo "Azure CLI not found. Installing Azure CLI..."
       echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/azure-cli.list
       sudo apt update
       sudo apt install -y azure-cli
fi

### Ensure yq v4+ is installed
if ! yq --version | grep -q 'version 4'; then
    echo "yq v4+ not found. Installing yq..."
    sudo apt-get install -y snapd
    sudo snap install yq
fi

az login --identity > /dev/null 2>&1
 
# Set up variables
IMAGE_NAME="arxiv-ai-agent"
TAG="v1"
CONTAINER_NAME="arxiv-ai-agent-container"
AZURE_RG_NAME=$(az group list --tag project=arxiv-ai-agent --query "[0].name" -o tsv)
ACR_NAME=$(az acr list --resource-group ${AZURE_RG_NAME} --query "[0].name" -o tsv)
TEMPERATURE=0.2
AZURE_OPENAI_NAME=$(az cognitiveservices account list --resource-group ${AZURE_RG_NAME} --query "[0].name" -o tsv)
AZURE_OPENAI_ENDPOINT=$(az cognitiveservices account show --resource-group ${AZURE_RG_NAME} --name ${AZURE_OPENAI_NAME} --query "endpoint" -o tsv)
AZURE_OPENAI_MODEL="model-router"
AZURE_OPENAI_DEPLOYMENT="model-router"
CONFIGMAPTEMPLATE="configMap.yaml"
NAMESPACE="arxiv-ai-agent"

# Check required Azure resources
if [[ -z "$AZURE_RG_NAME" ]]; then
    echo "Error: Could not find Azure resource group with tag project=arxiv-ai-agent."
    exit 1
else
    echo "Found Azure resource group: $AZURE_RG_NAME"
fi

if [[ -z "$ACR_NAME" ]]; then
    echo "Error: Could not find Azure Container Registry in resource group $AZURE_RG_NAME."
    exit 1
else
    echo "Found Azure Container Registry: $ACR_NAME"
fi

if [[ -z "$AZURE_OPENAI_NAME" || -z "$AZURE_OPENAI_ENDPOINT" ]]; then
    echo "Error: Could not find Azure OpenAI resource in resource group $AZURE_RG_NAME."
    exit 1
else
    echo "Found Azure OpenAI resource: $AZURE_OPENAI_NAME with endpoint: $AZURE_OPENAI_ENDPOINT"
fi

# Check if configMap.yaml exists
if [ ! -f "$CONFIGMAPTEMPLATE" ]; then
    echo "Error: $CONFIGMAPTEMPLATE not found in the current directory."
    exit 1
fi

# Build the docker image
cd ..
docker build -t "${IMAGE_NAME}:${TAG}" -f scripts/Dockerfile .

# Run the docker container
docker run -it --rm \
    -p 5001:5001 \
    -e TEMPERATURE="${TEMPERATURE}" \
    -e AZURE_OPENAI_ENDPOINT="${AZURE_OPENAI_ENDPOINT}" \
    -e AZURE_OPENAI_MODEL="${AZURE_OPENAI_MODEL}" \
    -e AZURE_OPENAI_DEPLOYMENT="${AZURE_OPENAI_DEPLOYMENT}" \
    --name "${CONTAINER_NAME}" \
    "${IMAGE_NAME}:${TAG}"

# Login to ACR
az acr login --name "${ACR_NAME}"

# Retrieve ACR login server
LOGIN_SERVER=$(az acr show --name "${ACR_NAME}" --query loginServer --output tsv)

# Tag the local image with the LOGIN_SERVER of ACR
docker tag "${IMAGE_NAME,,}:${TAG}" "${LOGIN_SERVER}/${IMAGE_NAME,,}:${TAG}"

# Push latest container image to ACR
docker push "${LOGIN_SERVER}/${IMAGE_NAME,,}:${TAG}"

# Check if namespace exists in the cluster
result=$(kubectl get namespace -o jsonpath="{.items[?(@.metadata.name=='$NAMESPACE')].metadata.name}")

if [[ -n $result ]]; then
    echo "$NAMESPACE namespace already exists in the cluster"
else
    echo "$NAMESPACE namespace does not exist in the cluster"
    echo "creating $NAMESPACE namespace in the cluster..."
    kubectl create namespace $NAMESPACE
fi

# Create config map
cat $CONFIGMAPTEMPLATE |
        yq "(.data.TEMPERATURE)|="\""$TEMPERATURE"\"" |
        yq "(.data.AZURE_OPENAI_BASE)|="\""$AZURE_OPENAI_ENDPOINT"\"" |
        yq "(.data.AZURE_OPENAI_MODEL)|="\""$AZURE_OPENAI_MODEL"\"" |
        yq "(.data.AZURE_OPENAI_DEPLOYMENT)|="\""$AZURE_OPENAI_DEPLOYMENT"\"" |
        kubectl apply -n $NAMESPACE -f -
