#!/bin/bash

set -euo pipefail

#---------------------------------------------#
# Constants and Global Variables
#---------------------------------------------#
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Image and deployment settings
readonly PROJECT_TAG="azure-playground"
readonly FRONTEND_IMAGE_NAME="azure-playground-frontend"
readonly LLM_SERVICE_IMAGE_NAME="azure-playground-llm-service"
readonly TAG="latest"
readonly NAMESPACE="default"
readonly AZURE_OPENAI_MODEL="model-router"
readonly AZURE_OPENAI_DEPLOYMENT="model-router"

# Helm chart
readonly CHART_DIR="${ROOT_DIR}/charts/azure-playground"

#---------------------------------------------#
# Logging Functions
#---------------------------------------------#
info()  { echo -e "\033[1;34m[INFO]\033[0m $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

#---------------------------------------------#
# Usage Function
#---------------------------------------------#
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
    --run <section>   Run only the specified section: prereq, config, build, deploy, run
    --all             Run all sections in order
    -h, --help        Show this help message

EXAMPLES:
    $0 --all                    # Run complete deployment
    $0 --run prereq             # Check prerequisites only
    $0 --run build              # Build and push images only

EOF
    exit 1
}

#---------------------------------------------#
# Utility Functions
#---------------------------------------------#
require_cmd() {
    local cmd="$1"
    local brew_package="${2:-}"
    local error_msg="${3:-}"
    
    if ! command -v "$cmd" &>/dev/null; then
        if [[ -n "$brew_package" ]]; then
            info "$cmd not found. Installing $cmd..."
            brew install "$brew_package"
        else
            error "$cmd not found. $error_msg"
            exit 1
        fi
    else
        info "$cmd is already installed."
    fi
}

check_macos() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        error "This script is intended to run on macOS only."
        exit 1
    fi
}

#---------------------------------------------#
# SECTION: Prerequisites
#---------------------------------------------#
prereq_section() {
    info "Checking prerequisites..."
    
    check_macos
    
    require_cmd brew "" "Please install Homebrew first: https://brew.sh/"
    require_cmd az azure-cli
    require_cmd unzip unzip
    require_cmd helm helm
    require_cmd docker "" "Please install Docker Desktop for Mac: https://www.docker.com/products/docker-desktop/"
    require_cmd kubectl kubectl
    require_cmd npm npm
    
    info "All prerequisites satisfied."
}

#---------------------------------------------#
# SECTION: Configuration
#---------------------------------------------#
config_section() {
    info "Starting configuration..."
    
    # Azure authentication
    info "Authenticating with Azure..."
    az login
    
    # Retrieve resource groups
    info "Retrieving Azure resource group with tag: ${PROJECT_TAG}..."
    AZURE_RG_NAME=$(az group list --tag project="${PROJECT_TAG}" --query "[0].name" -o tsv)
    [[ -z "$AZURE_RG_NAME" ]] && { error "Azure resource group with tag \"${PROJECT_TAG}\" not found."; exit 1; }
    info "Resource group found: $AZURE_RG_NAME"
    
    AKS_RG_NAME=$(az group list --tag aks-managed-cluster-rg="${AZURE_RG_NAME}" --query "[0].name" -o tsv)
    [[ -z "$AKS_RG_NAME" ]] && { error "AKS resource group not found."; exit 1; }
    info "AKS resource group found: $AKS_RG_NAME"
    
    # Derive unique ID
    UNIQUE_ID=$(echo "$AZURE_RG_NAME" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]' | tail -c 4)
    [[ -z "$UNIQUE_ID" ]] && { error "Failed to derive UNIQUE_ID."; exit 1; }
    info "Derived UNIQUE_ID: $UNIQUE_ID"
    
    # Azure OpenAI configuration
    AZURE_OPENAI_NAME=$(az cognitiveservices account list --resource-group "${AZURE_RG_NAME}" --query "[0].name" -o tsv)
    AZURE_OPENAI_ENDPOINT=$(az cognitiveservices account show --resource-group "${AZURE_RG_NAME}" --name "${AZURE_OPENAI_NAME}" --query "properties.endpoint" -o tsv)
    [[ -z "$AZURE_OPENAI_NAME" || -z "$AZURE_OPENAI_ENDPOINT" ]] && { error "Azure OpenAI resource not found."; exit 1; }
    info "Azure OpenAI: $AZURE_OPENAI_NAME (Endpoint: $AZURE_OPENAI_ENDPOINT)"
    
    # AKS cluster
    AKS_CLUSTER_NAME=$(az aks list --resource-group "${AZURE_RG_NAME}" --query "[0].name" -o tsv)
    [[ -z "$AKS_CLUSTER_NAME" ]] && { error "AKS cluster not found."; exit 1; }
    info "AKS cluster: $AKS_CLUSTER_NAME"
    
    # Container registry
    ACR_NAME=$(az acr list --resource-group "${AZURE_RG_NAME}" --query "[0].name" -o tsv)
    [[ -z "$ACR_NAME" ]] && { error "Azure Container Registry not found."; exit 1; }
    info "Container Registry: $ACR_NAME"
    
    # Export variables for subsequent sections
    export AZURE_RG_NAME AKS_RG_NAME UNIQUE_ID AZURE_OPENAI_NAME AZURE_OPENAI_ENDPOINT AKS_CLUSTER_NAME ACR_NAME
    
    info "Configuration completed successfully."
}

#---------------------------------------------#
# SECTION: Build
#---------------------------------------------#
build_section() {
    info "Starting build process..."
    
    # Get ACR login server
    LOGIN_SERVER=$(az acr show --name "${ACR_NAME}" --query loginServer --output tsv)
    FRONTEND_IMAGE_FULL_NAME="${LOGIN_SERVER}/${FRONTEND_IMAGE_NAME}:${TAG}"
    LLM_SERVICE_IMAGE_FULL_NAME="${LOGIN_SERVER}/${LLM_SERVICE_IMAGE_NAME}:${TAG}"
    
    # ACR login
    info "Logging in to Azure Container Registry..."
    az acr login --name "${ACR_NAME}"
    
    # Build frontend
    info "Building frontend Docker image..."
    cd "${ROOT_DIR}/app/frontend" || exit 1
    unset VITE_LLM_SERVICE_URL
    npm ci || { error "npm install failed"; exit 1; }
    npm run build || { error "npm build failed"; exit 1; }
    docker buildx build -t "${FRONTEND_IMAGE_FULL_NAME}" --platform linux/amd64,linux/arm64 -f Dockerfile .
    
    # Build LLM service
    info "Building LLM service Docker image..."
    cd "${ROOT_DIR}/app/llm-service" || exit 1
    docker buildx build -t "${LLM_SERVICE_IMAGE_FULL_NAME}" --platform linux/amd64,linux/arm64 -f Dockerfile .
    
    # Push images
    info "Pushing images to Azure Container Registry..."
    docker push "${FRONTEND_IMAGE_FULL_NAME}"
    docker push "${LLM_SERVICE_IMAGE_FULL_NAME}"
    
    export FRONTEND_IMAGE_FULL_NAME LLM_SERVICE_IMAGE_FULL_NAME LOGIN_SERVER
    info "Build and push completed successfully."
}

#---------------------------------------------#
# SECTION: Deploy
#---------------------------------------------#
deploy_section() {
    info "Starting deployment setup..."
    
    # AKS credentials
    info "Connecting to AKS cluster..."
    az aks get-credentials --resource-group "$AZURE_RG_NAME" --name "${AKS_CLUSTER_NAME}" --overwrite-existing
    
    # Verify connection
    info "Verifying Kubernetes nodes..."
    kubectl get nodes
    
    # Attach ACR to AKS
    info "Attaching Azure Container Registry to AKS cluster..."
    az aks update --name "${AKS_CLUSTER_NAME}" --resource-group "${AZURE_RG_NAME}" --attach-acr "${ACR_NAME}" &>/dev/null || true
    
    # Setup namespace
    info "Setting up Kubernetes namespace..."
    kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
    
    # Setup RBAC
    info "Setting up Kubernetes RBAC for Azure OpenAI..."
    USER_ASSIGNED_IDENTITY="aks-aks-${UNIQUE_ID}-agentpool"
    
    if ! az identity show --name "${USER_ASSIGNED_IDENTITY}" --resource-group "${AKS_RG_NAME}" &>/dev/null; then
        error "User-assigned managed identity '${USER_ASSIGNED_IDENTITY}' not found."
        exit 1
    fi
    
    # Get identity principal ID
    USER_ASSIGNED_IDENTITY_PID=$(az identity show --name "$USER_ASSIGNED_IDENTITY" --resource-group "$AKS_RG_NAME" --query principalId --output tsv)
    [[ -z "$USER_ASSIGNED_IDENTITY_PID" ]] && { error "Failed to retrieve principal ID."; exit 1; }
    info "User-assigned managed identity principal ID: $USER_ASSIGNED_IDENTITY_PID"
    
    # Get Azure OpenAI resource ID
    AZURE_OPENAI_ID=$(az cognitiveservices account show --resource-group "$AZURE_RG_NAME" --name "$AZURE_OPENAI_NAME" --query id -o tsv)
    [[ -z "$AZURE_OPENAI_ID" ]] && { error "Failed to retrieve Azure OpenAI resource ID."; exit 1; }
    info "Azure OpenAI resource ID: $AZURE_OPENAI_ID"
    
    # Assign role
    info "Assigning 'Cognitive Services User' role..."
    az role assignment create --assignee "$USER_ASSIGNED_IDENTITY_PID" --role "Cognitive Services User" --scope "$AZURE_OPENAI_ID"
    
    info "Deployment setup completed."
}

#---------------------------------------------#
# SECTION: Run
#---------------------------------------------#
run_section() {
    info "Deploying application to AKS cluster via Helm..."

    cd "${ROOT_DIR}" || exit 1

    helm upgrade --install azure-playground "${CHART_DIR}" \
        --namespace "${NAMESPACE}" \
        --set frontend.image.repository="${LOGIN_SERVER}/${FRONTEND_IMAGE_NAME}" \
        --set frontend.image.tag="${TAG}" \
        --set llmService.image.repository="${LOGIN_SERVER}/${LLM_SERVICE_IMAGE_NAME}" \
        --set llmService.image.tag="${TAG}" \
        --set llmService.azureOpenAI.endpoint="${AZURE_OPENAI_ENDPOINT}" \
        --wait \
        --timeout 300s

    info "Helm release deployed successfully."

    # Get external IP
    info "Retrieving external IP..."
    local external_ip=""
    local max_attempts=60
    local attempt=0

    while [[ -z "$external_ip" && $attempt -lt $max_attempts ]]; do
        external_ip=$(kubectl get svc -n "${NAMESPACE}" azure-playground-frontend -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
        if [[ -z "$external_ip" ]]; then
            info "Waiting for external IP... (attempt $((++attempt))/$max_attempts)"
            sleep 5
        fi
    done

    if [[ -z "$external_ip" ]]; then
        error "Failed to retrieve external IP after $max_attempts attempts."
        exit 1
    fi

    info "Service is available at: http://$external_ip:80"
    info "Deployment completed successfully!"
}

#---------------------------------------------#
# Main Execution
#---------------------------------------------#
main() {
    local run_section=""
    local run_all=0
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --run)
                shift
                [[ $# -eq 0 ]] && usage
                run_section="$1"
                shift
                ;;
            --all)
                run_all=1
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                usage
                ;;
        esac
    done
    
    # Validate arguments
    if [[ -z "$run_section" && "$run_all" -ne 1 ]]; then
        usage
    fi
    
    info "Starting Azure Playground Deployment Script..."
    
    # Execute sections
    if [[ "$run_all" -eq 1 ]]; then
        prereq_section
        config_section
        build_section
        deploy_section
        run_section
    else
        case "$run_section" in
            prereq)
                prereq_section
                ;;
            config)
                config_section
                ;;
            build)
                config_section
                build_section
                ;;
            deploy)
                config_section
                deploy_section
                ;;
            run)
                config_section
                build_section
                deploy_section
                run_section
                ;;
            *)
                usage
                ;;
        esac
    fi
}

# Run main function
main "$@"
