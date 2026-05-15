variable "resource_group_name" {
  description = "Resource group shared across all lab sessions"
  type        = string
  default     = "rg-hub-spoke-lab"
}

variable "location" {
  description = "Azure region - must match Sessions 1 and 2"
  type        = string
  default     = "eastus"
}

variable "key_vault_name" {
  description = <<-EOT
    Key Vault name. Must be globally unique across all of Azure.
    3-24 characters, alphanumeric and hyphens only.
    Example: kv-hub-spoke-gc
  EOT
  type        = string
}

variable "allowed_ip" {
  description = "Your public IPv4 for temporary Key Vault access during apply"
  type        = string
  default     = ""
}
