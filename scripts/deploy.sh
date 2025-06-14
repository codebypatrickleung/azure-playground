#!/bin/bash

# Azure Playground Deployment Script
# This script installs required tools, validates Azure resources, builds and pushes a Docker image, and deploys to Kubernetes.

set -euo pipefail

# Function to print info messages
info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
# Function to print error messages
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

# Ensure Azure CLI is installed
if ! command -v az &> /dev/null; then
    info "Azure CLI not found. Installing Azure CLI..."
    echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/azure-cli.list
    sudo apt update
    sudo apt install -y azure-cli
else
    info "Azure CLI is already installed."
fi

# Ensure unzip is installed
if ! command -v unzip &> /dev/null; then
    info "unzip not found. Installing unzip..."
    sudo apt-get install -y unzip
else
    info "unzip is already installed."
fi

# Ensure yq v4+ is installed
if ! yq --version 2>/dev/null | grep -q 'version 4'; then
    info "yq v4+ not found. Installing yq..."
    sudo apt-get install -y snapd
    sudo snap install yq
else
    info "yq v4+ is already installed."
fi

# Ensure Helm is installed
if ! command -v helm &> /dev/null; then
    info "Helm not found. Installing Helm..."
    curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
    sudo apt-get install apt-transport-https --yes
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
    sudo apt-get update
    sudo apt-get install -y helm
else
    info "Helm is already installed."
fi 

# Ensure Notary is installed
if ! command -v notary &> /dev/null; then
    info "Notary not found. Installing Notary..."
    sudo apt-get install -y notary
else
    info "Notary is already installed."
fi

# Ensure Docker is installed
if ! command -v docker &> /dev/null; then
    info "Docker not found. Installing Docker..."
    sudo apt-get update
    sudo apt-get install -y docker.io
    sudo usermod -aG docker "$USER"
    newgrp docker
    sudo systemctl start docker
    sudo systemctl enable docker
else
    info "Docker is already installed."
fi

# Ensure kubectl is installed
if ! command -v kubectl &> /dev/null; then
    info "kubectl not found. Installing kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl
    kubectl version --client
else
    info "kubectl is already installed."
fi

# Ensure kubelogin is installed
if ! command -v kubelogin &> /dev/null; then
    info "kubelogin not found. Installing kubelogin..."
    curl -LO https://github.com/Azure/kubelogin/releases/latest/download/kubelogin-linux-amd64.zip
    unzip kubelogin-linux-amd64.zip
    sudo mv bin/linux_amd64/kubelogin /usr/local/bin/
    sudo chmod +x /usr/local/bin/kubelogin
    kubelogin --version
    rm kubelogin-linux-amd64.zip
    rm -rf bin
else
    info "kubelogin is already installed."
fi

# Azure login
info "Authenticating with Azure..."
az login --identity > /dev/null 2>&1

# Set up variables
IMAGE_NAME="arxiv-ai-agent"
TAG="v1"
TEMPERATURE=0.2
AZURE_OPENAI_MODEL="model-router"
AZURE_OPENAI_DEPLOYMENT="model-router"
CONFIGMAPTEMPLATE="configMap.yaml"
NAMESPACE="arxiv-ai-agent"

# Retrieve Azure resource group
AZURE_RG_NAME=$(az group list --tag project=arxiv-ai-agent --query "[0].name" -o tsv)
if [[ -z "$AZURE_RG_NAME" ]]; then
    error "Could not find Azure resource group with tag project=arxiv-ai-agent."
    exit 1
fi
info "Found Azure resource group: $AZURE_RG_NAME"

# Retrieve Azure Kubernetes Service (AKS) cluster
AKS_CLUSTER_NAME=$(az aks list --resource-group "${AZURE_RG_NAME}" --query "[0].name" -o tsv)
if [[ -z "$AKS_CLUSTER_NAME" ]]; then
    error "Could not find Azure Kubernetes Service (AKS) cluster in resource group $AZURE_RG_NAME."
    exit 1
fi

# Retrieve Azure Container Registry
ACR_NAME=$(az acr list --resource-group "${AZURE_RG_NAME}" --query "[0].name" -o tsv)
if [[ -z "$ACR_NAME" ]]; then
    error "Could not find Azure Container Registry in resource group $AZURE_RG_NAME."
    exit 1
fi
info "Found Azure Container Registry: $ACR_NAME"

# Retrieve Azure OpenAI resource
AZURE_OPENAI_NAME=$(az cognitiveservices account list --resource-group "${AZURE_RG_NAME}" --query "[0].name" -o tsv)
AZURE_OPENAI_ENDPOINT=$(az cognitiveservices account show --resource-group "${AZURE_RG_NAME}" --name "${AZURE_OPENAI_NAME}" --query "endpoint" -o tsv)
if [[ -z "$AZURE_OPENAI_NAME" || -z "$AZURE_OPENAI_ENDPOINT" ]]; then
    error "Could not find Azure OpenAI resource in resource group $AZURE_RG_NAME."
    exit 1
fi
info "Found Azure OpenAI resource: $AZURE_OPENAI_NAME (Endpoint: $AZURE_OPENAI_ENDPOINT)"

# Clone repository
info "Cloning Azure Playground repository..."
if ! git clone https://github.com/codebypatrickleung/azure-playground.git; then
    error "Failed to clone the repository."
    exit 1
fi

# Build and push Docker image
cd azure-playground/
az login --identity > /dev/null 2>&1
az acr login --name "${ACR_NAME}"

LOGIN_SERVER=$(az acr show --name "${ACR_NAME}" --query loginServer --output tsv)
IMAGE_FULL_NAME="${LOGIN_SERVER}/${IMAGE_NAME}:${TAG}"

info "Building Docker image ${IMAGE_FULL_NAME}..."
docker build -t "${IMAGE_FULL_NAME}" -f scripts/Dockerfile .

info "Pushing Docker image to ACR..."
docker push "${IMAGE_FULL_NAME}"

# Connect to AKS cluster
info "Connecting to Azure Kubernetes Service (AKS)..."
az aks get-credentials --resource-group $AZURE_RG_NAME --name "${AKS_CLUSTER_NAME}" --overwrite-existing
kubelogin convert-kubeconfig -l azurecli
az login --identity


