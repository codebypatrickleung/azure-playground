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

resource "azurerm_private_dns_zone" "this" {
  name                = "privatelink.azurecr.io"
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_resource_group" "this" {
  location = var.location
  name     = module.naming.resource_group.name_unique
}

resource "azurerm_user_assigned_identity" "this" {
  location            = azurerm_resource_group.this.location
  name                = module.naming.user_assigned_identity.name_unique
  resource_group_name = azurerm_resource_group.this.name
}

module "naming" {
  source  = "Azure/naming/azurerm"
  version = "0.4.0"
}

module "avm-ptn-aks-production" {
  source              = "Azure/avm-ptn-aks-production/azurerm"
  version             = "0.5.0"
  name                = module.naming.kubernetes_cluster.name_unique
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  network = {
    node_subnet_id = module.avm_res_network_virtualnetwork.subnets["subnet"].resource_id
    pod_cidr       = "20.0.0.0/16"
  }
  acr = {
    name                          = module.naming.container_registry.name_unique
    subnet_resource_id            = module.avm_res_network_virtualnetwork.subnets["private_link_subnet"].resource_id
    private_dns_zone_resource_ids = [azurerm_private_dns_zone.this.id]
    zone_redundancy_enabled       = var.acr_zone_redundancy_enabled
  }
  enable_telemetry   = var.enable_telemetry
  kubernetes_version = "1.30"
  managed_identities = {
    user_assigned_resource_ids = [
      azurerm_user_assigned_identity.this.id
    ]
  }
  node_pools = {
    workload = {
      name                 = "workload"
      vm_size              = "Standard_D2d_v5"
      orchestrator_version = "1.30.12"
      max_count            = 2
      min_count            = 1
      os_sku               = "AzureLinux"
      mode                 = "User"
      os_disk_size_gb      = 32
    },
    ingress = {
      name                 = "ingress"
      vm_size              = "Standard_D2d_v5"
      orchestrator_version = "1.30.12"
      max_count            = 2
      min_count            = 1
      os_sku               = "AzureLinux"
      mode                 = "User"
      os_disk_size_gb      = 32
      labels = {
        "ingress" = "true"
      }
    }
  }
  os_disk_type       = "Ephemeral"
  rbac_aad_tenant_id = data.azurerm_client_config.current.tenant_id
}

module "avm_res_network_virtualnetwork" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.7.1"

  address_space       = ["10.31.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  name                = module.naming.virtual_network.name_unique
  subnets = {
    "subnet" = {
      name             = "nodecidr"
      address_prefixes = ["10.31.0.0/17"]
    }
    "private_link_subnet" = {
      name             = "private_link_subnet"
      address_prefixes = ["10.31.129.0/24"]
    }
  }
}

module "avm-res-cognitiveservices-account" {
  source  = "Azure/avm-res-cognitiveservices-account/azurerm"
  version = "0.7.1"

  kind                = "OpenAI"
  location            = var.location
  name                = module.naming.cognitive_account.name_unique
  resource_group_name = azurerm_resource_group.this.name
  sku_name            = "S0"

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

