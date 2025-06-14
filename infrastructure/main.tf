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

data "azurerm_client_config" "current" {
}

resource "azurerm_resource_group" "this" {
  location = var.location
  name     = module.naming.resource_group.name_unique
  tags     = var.tags
}

module "naming" {
  source  = "Azure/naming/azurerm"
  version = "0.4.0"
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

module "avm-res-cognitiveservices-account" {
  source  = "Azure/avm-res-cognitiveservices-account/azurerm"
  version = "0.7.1"

  kind                = "OpenAI"
  location            = var.location
  name                = module.naming.cognitive_account.name_unique
  resource_group_name = azurerm_resource_group.this.name
  sku_name            = "S0"
  tags                = var.tags
  role_assignments = {
    "role_assignments_1" = {
      principal_id    = data.azurerm_client_config.current.client_id
      role_definition_id_or_name = "Cognitive Services OpenAI User"
      principal_type  = "ServicePrincipal"
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
