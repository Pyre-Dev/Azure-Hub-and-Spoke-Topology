variable "resource_group_name" {
  description = "Resource group shared across all lab sessions"
  type        = string
  default     = "rg-hub-spoke-lab"
}

variable "location" {
  description = "Azure region - must match Sessions 1-3"
  type        = string
  default     = "eastus"
}

variable "key_vault_name" {
  description = "Name of the Key Vault deployed in Session 3 - used to read the SSH key via data source"
  type        = string
}
