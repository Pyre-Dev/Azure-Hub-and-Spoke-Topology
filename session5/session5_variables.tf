variable "resource_group_name" {
  description = "Resource group shared across all lab sessions"
  type        = string
  default     = "rg-hub-spoke-lab"
}

variable "location" {
  description = "Azure region - must match Sessions 1-4"
  type        = string
  default     = "eastus"
}

variable "log_analytics_workspace_name" {
  description = <<-EOT
    Log Analytics Workspace name. Must be unique within the resource group.
    3-63 characters, alphanumeric and hyphens only.
    Example: law-hub-spoke-lab
  EOT
  type        = string
  default     = "law-hub-spoke-lab"
}

variable "storage_account_name" {
  description = <<-EOT
    Storage account name for NSG flow log buffer. Must be globally unique across Azure.
    3-24 characters, lowercase alphanumeric only (no hyphens).
    Example: stflowlogs<your-initials>
  EOT
  type        = string
}
