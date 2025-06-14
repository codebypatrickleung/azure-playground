#!/bin/bash

# Azure Playground Deployment Script (macOS)
set -euo pipefail

# Logging functions
info()    { echo -e "\033[1;34m[INFO]\033[0m $*"; }
warn()    { echo -e "\033[1;33m[WARN]\033[0m $*"; }
error()   { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

# Prerequisite check function
require_cmd() {
    if ! command -v "$1" &>/dev/null; then
        if [[ -n "${2:-}" ]]; then
            info "$1 not found. Installing $1..."
            brew install "$2"
        else
            error "$1 not found. $3"
            exit 1
        fi
    else
        info "$1 is already installed."
    fi
}

# Check prerequisites
require_cmd brew "" "Please install Homebrew first: https://brew.sh/"
require_cmd az azure-cli
require_cmd unzip unzip
require_cmd helm helm
require_cmd docker "" "Please install Docker Desktop for Mac: https://www.docker.com/products/docker-desktop/"
require_cmd kubectl kubectl

# Azure authentication
info "Authenticating with Azure..."
az login

# Configuration variables
PROJECT_TAG="azure-playground"
IMAGE_NAME="arxiv-ai-agent"
TAG="v1"
TEMPERATURE=0.2
AZURE_OPENAI_MODEL="model-router"
AZURE_OPENAI_DEPLOYMENT="model-router"
CONFIGMAPTEMPLATE="script/configMap.yaml"
NAMESPACE="default"

# Retrieve Azure resource group
info "Retrieving Azure resource group with tag: ${PROJECT_TAG}..."
AZURE_RG_NAME=$(az group list --tag project="${PROJECT_TAG}" --query "[0].name" -o tsv)
if [[ -z "$AZURE_RG_NAME" ]]; then
    error "Azure resource group with tag \"${PROJECT_TAG}\" not found."
    exit 1
fi
info "Resource group found: $AZURE_RG_NAME"

# Retrieve Azure OpenAI resource
AZURE_OPENAI_NAME=$(az cognitiveservices account list --resource-group "${AZURE_RG_NAME}" --query "[0].name" -o tsv)
AZURE_OPENAI_ENDPOINT=$(az cognitiveservices account show --resource-group "${AZURE_RG_NAME}" --name "${AZURE_OPENAI_NAME}" --query "properties.endpoint" -o tsv)
if [[ -z "$AZURE_OPENAI_NAME" || -z "$AZURE_OPENAI_ENDPOINT" ]]; then
    error "Could not find Azure OpenAI resource in resource group $AZURE_RG_NAME."
    exit 1
fi
info "Found Azure OpenAI resource: $AZURE_OPENAI_NAME (Endpoint: $AZURE_OPENAI_ENDPOINT)"

# Retrieve AKS cluster
info "Retrieving AKS cluster in resource group: $AZURE_RG_NAME..."
AKS_CLUSTER_NAME=$(az aks list --resource-group "${AZURE_RG_NAME}" --query "[0].name" -o tsv)
if [[ -z "$AKS_CLUSTER_NAME" ]]; then
    error "AKS cluster not found in resource group $AZURE_RG_NAME."
    exit 1
fi
info "AKS cluster found: $AKS_CLUSTER_NAME"

# Retrieve Azure Container Registry
info "Retrieving Azure Container Registry in resource group: $AZURE_RG_NAME..."
ACR_NAME=$(az acr list --resource-group "${AZURE_RG_NAME}" --query "[0].name" -o tsv)
if [[ -z "$ACR_NAME" ]]; then
    error "Azure Container Registry not found in resource group $AZURE_RG_NAME."
    exit 1
fi
info "Container Registry found: $ACR_NAME"

# Build and push Docker image
info "Logging in to Azure Container Registry..."
az acr login --name "${ACR_NAME}"

LOGIN_SERVER=$(az acr show --name "${ACR_NAME}" --query loginServer --output tsv)
IMAGE_FULL_NAME="${LOGIN_SERVER}/${IMAGE_NAME}:${TAG}"

info "Building Docker image: ${IMAGE_FULL_NAME}..."
docker build -t "${IMAGE_FULL_NAME}" -f scripts/Dockerfile .

info "Pushing Docker image to Azure Container Registry..."
docker push "${IMAGE_FULL_NAME}"

# Connect to AKS cluster
info "Connecting to AKS cluster..."
az aks get-credentials --resource-group "$AZURE_RG_NAME" --name "${AKS_CLUSTER_NAME}" --overwrite-existing

info "Verifying Kubernetes nodes..."
kubectl get nodes

# Ensure Kubernetes namespace exists
if kubectl get namespace "${NAMESPACE}" &> /dev/null; then
    info "Namespace '${NAMESPACE}' already exists."
else
    info "Creating namespace '${NAMESPACE}'..."
    kubectl create namespace "${NAMESPACE}"
fi

# Create or update ConfigMap
info "Applying ConfigMap to namespace '${NAMESPACE}'..."
yq ".data.AZURE_OPENAI_ENDPOINT |= \"${AZURE_OPENAI_ENDPOINT}\" |
    "${CONFIGMAPTEMPLATE}" | kubectl apply -n "${NAMESPACE}" -f -

info "Deployment script completed successfully."
