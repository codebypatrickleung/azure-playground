terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  subscription_id = var.subscription_id
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "this" {
  location = var.location
  name     = module.naming.resource_group.name_unique
  tags     = var.tags
}

module "naming" {
  source  = "Azure/naming/azurerm"
  version = "0.4.3"
}

module "avm-ptn-aks-dev" {
  source                  = "Azure/avm-ptn-aks-dev/azurerm"
  version                 = "0.2.0"
  name                    = module.naming.kubernetes_cluster.name_unique
  container_registry_name = module.naming.container_registry.name_unique
  location                = var.location
  resource_group_name     = azurerm_resource_group.this.name
  enable_telemetry        = var.enable_telemetry
  tags                    = var.tags
}

# ─────────────────────────────────────────────
# Azure Key Vault
# ─────────────────────────────────────────────

resource "azurerm_key_vault" "this" {
  name                       = module.naming.key_vault.name_unique
  location                   = var.location
  resource_group_name        = azurerm_resource_group.this.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  tags                       = var.tags
}

data "azurerm_kubernetes_cluster" "this" {
  name                = "aks-${module.naming.kubernetes_cluster.name_unique}"
  resource_group_name = azurerm_resource_group.this.name
  depends_on          = [module.avm-ptn-aks-dev]
}

resource "azurerm_role_assignment" "kv_admin" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "kv_secrets_user" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = data.azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}

# ─────────────────────────────────────────────
# Outputs (used by deploy.sh)
# ─────────────────────────────────────────────

output "key_vault_name" {
  description = "Name of the Azure Key Vault"
  value       = azurerm_key_vault.this.name
}

output "key_vault_uri" {
  description = "URI of the Azure Key Vault"
  value       = azurerm_key_vault.this.vault_uri
}

# ─────────────────────────────────────────────
# Flux GitOps (Azure-native AKS extension)
# ─────────────────────────────────────────────

resource "azurerm_kubernetes_cluster_extension" "flux" {
  name           = "flux"
  cluster_id     = data.azurerm_kubernetes_cluster.this.id
  extension_type = "microsoft.flux"

  depends_on = [
    data.azurerm_kubernetes_cluster.this
  ]
}

resource "azurerm_kubernetes_flux_configuration" "this" {
  name       = "azure-playground"
  cluster_id = data.azurerm_kubernetes_cluster.this.id
  namespace  = "flux-system"
  scope      = "cluster"

  git_repository {
    url             = "https://github.com/${var.github_username}/${var.github_repo}.git"
    reference_type  = "branch"
    reference_value = "main"
  }

  kustomizations {
    name                       = "flux-system"
    path                       = "./clusters/dev"
    sync_interval_in_seconds   = 600
    retry_interval_in_seconds  = 60
    garbage_collection_enabled = false
  }

  depends_on = [azurerm_kubernetes_cluster_extension.flux]
}

# ─────────────────────────────────────────────
# Azure OpenAI
# ─────────────────────────────────────────────

module "avm-res-cognitiveservices-account" {
  source  = "Azure/avm-res-cognitiveservices-account/azurerm"
  version = "0.11.0"

  kind      = "OpenAI"
  location  = var.location
  name      = module.naming.cognitive_account.name_unique
  parent_id = azurerm_resource_group.this.id
  enable_telemetry    = var.enable_telemetry
  sku_name            = "S0"
  tags                = var.tags
  role_assignments = {
    "role_assignments_1" = {
      principal_id               = data.azurerm_client_config.current.object_id
      role_definition_id_or_name = "Cognitive Services OpenAI User"
    }
  }

  cognitive_deployments = {
    "model-router" = {
      name = "model-router"
      model = {
        format  = "OpenAI"
        name    = "model-router"
        version = "2025-05-19"
      }
      scale = {
        type = "GlobalStandard"
      }
    }
  }
}
