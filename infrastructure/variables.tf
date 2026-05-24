variable "subscription_id" {
  description = "The Azure subscription ID where the resources will be created"
  type        = string
}

variable "enable_telemetry" {
  description = "Enable or disable telemetry for the module"
  default     = true
  type        = bool
}

variable "location" {
  description = "Specifies the location for the resource group and all the resources"
  default     = "swedencentral"
  type        = string
}

variable "github_username" {
  description = "GitHub username that owns the azure-playground repository"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name for Flux GitOps"
  type        = string
  default     = "azure-playground"
}

variable "tags" {
  description = "(Optional) Specifies tags for all the resources"
  default = {
    createdWith = "Terraform"
    project     = "azure-playground"
  }
}
