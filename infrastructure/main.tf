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
  name                = var.private_dns_zone_name
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  name                  = "vnet-dns-link"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.this.name
  virtual_network_id    = module.avm_res_network_virtualnetwork.resource_id
  registration_enabled  = false
}

resource "azurerm_resource_group" "this" {
  location = var.location
  name     = module.naming.resource_group.name_unique
  tags     = var.tags
}

resource "azurerm_user_assigned_identity" "this" {
  location            = azurerm_resource_group.this.location
  name                = module.naming.user_assigned_identity.name_unique
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_public_ip" "this" {
  allocation_method   = "Static"
  location            = azurerm_resource_group.this.location
  name                = module.naming.public_ip.name_unique
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "Standard"
  tags                = var.tags
  zones               = [1, 2, 3]
}

resource "random_integer" "zone_index" {
  max = length(module.regions.regions_by_name[var.location].zones)
  min = 1
}

module "regions" {
  source  = "Azure/avm-utl-regions/azurerm"
  version = "0.5.0"

  availability_zones_filter = true
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
    node_subnet_id = module.avm_res_network_virtualnetwork.subnets["aks_subnet"].resource_id
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
  source           = "Azure/avm-res-network-virtualnetwork/azurerm"
  enable_telemetry = var.enable_telemetry
  version          = "0.7.1"

  address_space       = ["10.31.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  name                = module.naming.virtual_network.name_unique
  subnets = {
    "aks_subnet" = {
      name             = "aks_subnet"
      address_prefixes = ["10.31.0.0/17"]
      nat_gateway = {
        id = module.natgateway.resource_id
      }
    }
    "private_link_subnet" = {
      name             = "private_link_subnet"
      address_prefixes = ["10.31.129.0/24"]
      nat_gateway = {
        id = module.natgateway.resource_id
      }
    }
    "AzureBastionSubnet" = {
      name             = "AzureBastionSubnet"
      address_prefixes = ["10.31.130.0/24"]
    }
  }
}

module "avm_res_network_bastionhost" {
  source              = "Azure/avm-res-network-bastionhost/azurerm"
  enable_telemetry    = var.enable_telemetry
  name                = module.naming.bastion_host.name_unique
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  copy_paste_enabled  = true
  file_copy_enabled   = true
  sku                 = "Standard"
  ip_configuration = {
    name                 = "${module.naming.bastion_host.name_unique}-ipconfig1"
    subnet_id            = module.avm_res_network_virtualnetwork.subnets["AzureBastionSubnet"].resource_id
    public_ip_address_id = azurerm_public_ip.this.id
    create_public_ip     = false
  }
  ip_connect_enabled     = true
  scale_units            = 4
  shareable_link_enabled = true
  tunneling_enabled      = true
  kerberos_enabled       = true

  tags = var.tags
}

module "natgateway" {
  source  = "Azure/avm-res-network-natgateway/azurerm"
  version = "0.2.1"

  location            = var.location
  name                = module.naming.nat_gateway.name_unique
  resource_group_name = azurerm_resource_group.this.name
  enable_telemetry    = var.enable_telemetry
  public_ips = {
    public_ip_1 = {
      name = "${module.naming.nat_gateway.name_unique}-pip1"
    }
  }
}

module "vm_sku" {
  source  = "Azure/avm-utl-sku-finder/azapi"
  version = "0.3.0"

  location      = var.location
  cache_results = true
  vm_filters = {
    min_vcpus                      = 2
    max_vcpus                      = 2
    encryption_at_host_supported   = true
    accelerated_networking_enabled = true
    premium_io_supported           = true
    location_zone                  = random_integer.zone_index.result
  }

  depends_on = [random_integer.zone_index]
}

module "avm_res_keyvault_vault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "=0.10.0"

  location            = var.location
  name                = "${module.naming.key_vault.name_unique}-linux-default"
  resource_group_name = azurerm_resource_group.this.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  network_acls = {
    default_action = "Allow"
  }
  role_assignments = {
    deployment_user_secrets = {
      role_definition_id_or_name = "Key Vault Secrets Officer"
      principal_id               = data.azurerm_client_config.current.object_id
    }
  }
  tags = var.tags
  wait_for_rbac_before_secret_operations = {
    create = "60s"
  }
}

module "avm_res_compute_virtualmachine" {
  source  = "Azure/avm-res-compute-virtualmachine/azurerm"
  version = "0.19.3"

  location = var.location
  name     = module.naming.virtual_machine.name_unique
  network_interfaces = {
    network_interface_1 = {
      name = module.naming.network_interface.name_unique
      ip_configurations = {
        ip_configuration_1 = {
          name                          = "${module.naming.network_interface.name_unique}-ipconfig1"
          private_ip_subnet_resource_id = module.avm_res_network_virtualnetwork.subnets["private_link_subnet"].resource_id
        }
      }
    }
  }
  resource_group_name = azurerm_resource_group.this.name
  zone                = random_integer.zone_index.result
  account_credentials = {
    key_vault_configuration = {
      resource_id = module.avm_res_keyvault_vault.resource_id
    }
  }
  enable_telemetry = var.enable_telemetry
  managed_identities = {
    system_assigned = true
  }
  role_assignments = {
    role_assignment_1 = {
      principal_id               = data.azurerm_client_config.current.client_id
      role_definition_id_or_name = "Virtual Machine Contributor"
      description                = "Assign the Virtual Machine Contributor role to the deployment user on this virtual machine."
      principal_type             = "ServicePrincipal"
    }
  }
  role_assignments_system_managed_identity = {
    role_assignment_1 = {
      scope_resource_id          = azurerm_resource_group.this.id
      role_definition_id_or_name = "Contributor"
      description                = "Assign the Contributor role to the system managed identity on this virtual machine."
      principal_type             = "ServicePrincipal"
    },
    role_assignment_2 = {
      scope_resource_id          = azurerm_resource_group.this.id
      role_definition_id_or_name = "Container Registry Repository Writer"
      description                = "Assign the Container Registry Repository Writer role to the system managed identity on this virtual machine."
      principal_type             = "ServicePrincipal"
    },
    role_assignment_3 = {
      scope_resource_id          = azurerm_resource_group.this.id
      role_definition_id_or_name = "Azure Kubernetes Service Cluster Admin Role"
      description                = "Assign the Azure Kubernetes Service Cluster Admin Role role to the system managed identity on this virtual machine."
      principal_type             = "ServicePrincipal"
    },
    role_assignment_4 = {
      scope_resource_id          = azurerm_resource_group.this.id
      role_definition_id_or_name = "Cognitive Services Contributor"
      description                = "Assign the Cognitive Services Contributor Role role to the system managed identity on this virtual machine."
      principal_type             = "ServicePrincipal"
    }
  }
  os_type  = "Linux"
  sku_size = module.vm_sku.sku
  source_image_reference = {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }
  tags = var.tags

  depends_on = [
    module.avm_res_keyvault_vault
  ]
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
