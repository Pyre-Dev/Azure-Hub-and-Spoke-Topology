variable "resource_group_name" {
  description = "Name of the resource group for the lab"
  type        = string
  default     = "rg-hub-spoke-lab"
}

variable "location" {
  description = "Azure region to deploy resources"
  type        = string
  default     = "eastus"
}
