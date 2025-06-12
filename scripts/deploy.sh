#!/bin/bash

IMAGE_NAME="arXiv-ai-agent"
TAG="v1"
CONTAINER_NAME="arxiv-ai-agent-container"
AZURE_RG_NAME="rg-p9g9"  
ACR_NAME=$(az acr list --resource-group ${AZURE_RG_NAME} --query "[0].name" -o tsv)
TEMPERATURE=0.2
AZURE_OPENAI_NAME=$(az cognitiveservices account list --resource-group ${AZURE_RG_NAME} --query "[0].name" -o tsv)
AZURE_OPENAI_BASE=$(az cognitiveservices account show --resource-group ${AZURE_RG_NAME} --query "properties.endpoint" -o tsv)
AZURE_OPENAI_MODEL="gpt-4.1"
AZURE_OPENAI_DEPLOYMENT="gpt-4.1-deployment"

# Build the docker image
docker build -t "${IMAGE_NAME}:${TAG}" -f Dockerfile .

# Run the docker container
docker run -it --rm \
    -p 5001:5001 \
    -e TEMPERATURE="${TEMPERATURE}" \
    -e AZURE_OPENAI_BASE="${AZURE_OPENAI_BASE}" \
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

