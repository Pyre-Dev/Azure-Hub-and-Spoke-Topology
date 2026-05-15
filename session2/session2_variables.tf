variable "resource_group_name" {
  description = "Resource group shared across all lab sessions"
  type        = string
  default     = "rg-hub-spoke-lab"
}

variable "location" {
  description = "Azure region - must match Session 1"
  type        = string
  default     = "eastus"
}
