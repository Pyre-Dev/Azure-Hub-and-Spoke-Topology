terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# -------------------------------------------------------
# Data sources - reads existing resources from Sessions 1-4
# -------------------------------------------------------
data "azurerm_resource_group" "lab" {
  name = var.resource_group_name
}

data "azurerm_virtual_network" "hub" {
  name                = "vnet-hub"
  resource_group_name = data.azurerm_resource_group.lab.name
}

data "azurerm_virtual_network" "spoke1" {
  name                = "vnet-spoke1"
  resource_group_name = data.azurerm_resource_group.lab.name
}

data "azurerm_virtual_network" "spoke2" {
  name                = "vnet-spoke2"
  resource_group_name = data.azurerm_resource_group.lab.name
}

data "azurerm_subnet" "hub_management" {
  name                 = "snet-management"
  virtual_network_name = "vnet-hub"
  resource_group_name  = data.azurerm_resource_group.lab.name
}

data "azurerm_firewall" "hub" {
  name                = "afw-hub"
  resource_group_name = data.azurerm_resource_group.lab.name
}

# Use the existing Network Watcher Azure provisioned automatically.
# Azure blocks creation of new Network Watchers if one already exists
# in the region, so we read the existing one via data source.
data "azurerm_network_watcher" "lab" {
  name                = "NetworkWatcher_eastus"
  resource_group_name = "NetworkWatcherRG"
}

# -------------------------------------------------------
# Log Analytics Workspace
#
# Global PaaS resource - no VNet placement. Lives in the
# resource group and region. All access from within the
# VNets flows through the private endpoints below.
# 30-day retention is sufficient for a lab. Production
# designs typically use 90+ days.
# -------------------------------------------------------
resource "azurerm_log_analytics_workspace" "hub" {
  name                = var.log_analytics_workspace_name
  location            = data.azurerm_resource_group.lab.location
  resource_group_name = data.azurerm_resource_group.lab.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# -------------------------------------------------------
# Private DNS Zones for Log Analytics
#
# Log Analytics requires two private DNS zones:
# - privatelink.ods.opinsights.azure.com  (data ingestion)
# - privatelink.oms.opinsights.azure.com  (agent management)
#
# Both must be linked to all VNets for agents in the spokes
# to resolve the workspace endpoints to private IPs.
# -------------------------------------------------------
resource "azurerm_private_dns_zone" "ods" {
  name                = "privatelink.ods.opinsights.azure.com"
  resource_group_name = data.azurerm_resource_group.lab.name
}

resource "azurerm_private_dns_zone" "oms" {
  name                = "privatelink.oms.opinsights.azure.com"
  resource_group_name = data.azurerm_resource_group.lab.name
}

# ODS zone links
resource "azurerm_private_dns_zone_virtual_network_link" "ods_hub" {
  name                  = "link-ods-hub"
  resource_group_name   = data.azurerm_resource_group.lab.name
  private_dns_zone_name = azurerm_private_dns_zone.ods.name
  virtual_network_id    = data.azurerm_virtual_network.hub.id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "ods_spoke1" {
  name                  = "link-ods-spoke1"
  resource_group_name   = data.azurerm_resource_group.lab.name
  private_dns_zone_name = azurerm_private_dns_zone.ods.name
  virtual_network_id    = data.azurerm_virtual_network.spoke1.id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "ods_spoke2" {
  name                  = "link-ods-spoke2"
  resource_group_name   = data.azurerm_resource_group.lab.name
  private_dns_zone_name = azurerm_private_dns_zone.ods.name
  virtual_network_id    = data.azurerm_virtual_network.spoke2.id
  registration_enabled  = false
}

# OMS zone links
resource "azurerm_private_dns_zone_virtual_network_link" "oms_hub" {
  name                  = "link-oms-hub"
  resource_group_name   = data.azurerm_resource_group.lab.name
  private_dns_zone_name = azurerm_private_dns_zone.oms.name
  virtual_network_id    = data.azurerm_virtual_network.hub.id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "oms_spoke1" {
  name                  = "link-oms-spoke1"
  resource_group_name   = data.azurerm_resource_group.lab.name
  private_dns_zone_name = azurerm_private_dns_zone.oms.name
  virtual_network_id    = data.azurerm_virtual_network.spoke1.id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "oms_spoke2" {
  name                  = "link-oms-spoke2"
  resource_group_name   = data.azurerm_resource_group.lab.name
  private_dns_zone_name = azurerm_private_dns_zone.oms.name
  virtual_network_id    = data.azurerm_virtual_network.spoke2.id
  registration_enabled  = false
}

# -------------------------------------------------------
# Private Endpoint for Log Analytics
#
# A single private endpoint covers both ODS and OMS
# subresources. Both DNS zones are registered in the
# dns_zone_group so A records are created automatically.
# -------------------------------------------------------
resource "azurerm_private_endpoint" "log_analytics" {
  name                = "pe-law-hub"
  location            = data.azurerm_resource_group.lab.location
  resource_group_name = data.azurerm_resource_group.lab.name
  subnet_id           = data.azurerm_subnet.hub_management.id

  private_service_connection {
    name                           = "psc-law"
    private_connection_resource_id = azurerm_log_analytics_workspace.hub.id
    subresource_names              = ["azuremonitor"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "pdns-group-law"
    private_dns_zone_ids = [
      azurerm_private_dns_zone.ods.id,
      azurerm_private_dns_zone.oms.id,
    ]
  }
}

# -------------------------------------------------------
# Azure Firewall Diagnostic Settings
#
# Sends application rule and network rule logs to the
# Log Analytics workspace. Scoped to the two categories
# that reflect actual VM traffic in this lab:
#
# AZFWApplicationRule: captures allow/deny decisions on
# FQDN-based rules (microsoft.com allowed, snapcraft.io
# denied).
#
# AZFWNetworkRule: captures DNS traffic (UDP 53 to
# 168.63.129.16) the VM generates when resolving the
# Key Vault FQDN. Lets you correlate DNS lookups with
# Key Vault connections in a single workspace query.
# -------------------------------------------------------
resource "azurerm_monitor_diagnostic_setting" "firewall" {
  name                       = "diag-afw-hub"
  target_resource_id         = data.azurerm_firewall.hub.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.hub.id

  enabled_log {
    category = "AZFWApplicationRule"
  }

  enabled_log {
    category = "AZFWNetworkRule"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# -------------------------------------------------------
# Storage Account for VNet Flow Logs
#
# VNet flow logs (the replacement for retired NSG flow logs)
# still use a storage account as an intermediate buffer.
# Traffic Analytics reads from here and sends processed
# data to Log Analytics on the interval below.
# -------------------------------------------------------
resource "azurerm_storage_account" "flow_logs" {
  name                     = var.storage_account_name
  resource_group_name      = data.azurerm_resource_group.lab.name
  location                 = data.azurerm_resource_group.lab.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# -------------------------------------------------------
# VNet Flow Logs
#
# Replaces NSG flow logs, which were retired June 30 2025.
# VNet flow logs capture traffic at the VNet level rather
# than per-NSG, which gives broader coverage and avoids
# the per-subnet configuration overhead.
#
# One flow log per VNet. Hub captures management subnet
# traffic (private endpoint connections). Spoke logs
# capture VM egress and any inbound attempts.
# -------------------------------------------------------
resource "azurerm_virtual_network_flow_log" "hub" {
  name                      = "fl-vnet-hub"
  resource_group_name       = data.azurerm_resource_group.lab.name
  network_watcher_name      = data.azurerm_network_watcher.lab.name
  network_watcher_id        = data.azurerm_network_watcher.lab.id
  virtual_network_id        = data.azurerm_virtual_network.hub.id
  storage_account_id        = azurerm_storage_account.flow_logs.id
  enabled                   = true
  location                  = data.azurerm_resource_group.lab.location

  retention_policy {
    enabled = true
    days    = 7
  }

  traffic_analytics {
    enabled               = true
    workspace_id          = azurerm_log_analytics_workspace.hub.workspace_id
    workspace_region      = azurerm_log_analytics_workspace.hub.location
    workspace_resource_id = azurerm_log_analytics_workspace.hub.id
    interval_in_minutes   = 10
  }
}

resource "azurerm_virtual_network_flow_log" "spoke1" {
  name                      = "fl-vnet-spoke1"
  resource_group_name       = data.azurerm_resource_group.lab.name
  network_watcher_name      = data.azurerm_network_watcher.lab.name
  network_watcher_id        = data.azurerm_network_watcher.lab.id
  virtual_network_id        = data.azurerm_virtual_network.spoke1.id
  storage_account_id        = azurerm_storage_account.flow_logs.id
  enabled                   = true
  location                  = data.azurerm_resource_group.lab.location

  retention_policy {
    enabled = true
    days    = 7
  }

  traffic_analytics {
    enabled               = true
    workspace_id          = azurerm_log_analytics_workspace.hub.workspace_id
    workspace_region      = azurerm_log_analytics_workspace.hub.location
    workspace_resource_id = azurerm_log_analytics_workspace.hub.id
    interval_in_minutes   = 10
  }
}

resource "azurerm_virtual_network_flow_log" "spoke2" {
  name                      = "fl-vnet-spoke2"
  resource_group_name       = data.azurerm_resource_group.lab.name
  network_watcher_name      = data.azurerm_network_watcher.lab.name
  network_watcher_id        = data.azurerm_network_watcher.lab.id
  virtual_network_id        = data.azurerm_virtual_network.spoke2.id
  storage_account_id        = azurerm_storage_account.flow_logs.id
  enabled                   = true
  location                  = data.azurerm_resource_group.lab.location

  retention_policy {
    enabled = true
    days    = 7
  }

  traffic_analytics {
    enabled               = true
    workspace_id          = azurerm_log_analytics_workspace.hub.workspace_id
    workspace_region      = azurerm_log_analytics_workspace.hub.location
    workspace_resource_id = azurerm_log_analytics_workspace.hub.id
    interval_in_minutes   = 10
  }
}
