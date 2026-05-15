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
# Data sources - reads existing resources from Session 1
# -------------------------------------------------------
data "azurerm_resource_group" "lab" {
  name = var.resource_group_name
}

data "azurerm_subnet" "hub_firewall" {
  name                 = "AzureFirewallSubnet"
  virtual_network_name = "vnet-hub"
  resource_group_name  = data.azurerm_resource_group.lab.name
}

data "azurerm_subnet" "spoke1_workload" {
  name                 = "snet-workload"
  virtual_network_name = "vnet-spoke1"
  resource_group_name  = data.azurerm_resource_group.lab.name
}

data "azurerm_subnet" "spoke2_workload" {
  name                 = "snet-workload"
  virtual_network_name = "vnet-spoke2"
  resource_group_name  = data.azurerm_resource_group.lab.name
}

# -------------------------------------------------------
# Public IP for Azure Firewall
# Standard SKU required for Azure Firewall.
# Static allocation so the IP doesn't change across
# firewall stop/start cycles.
# -------------------------------------------------------
resource "azurerm_public_ip" "firewall" {
  name                = "pip-hub-firewall"
  location            = data.azurerm_resource_group.lab.location
  resource_group_name = data.azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# -------------------------------------------------------
# Azure Firewall
# Sits in AzureFirewallSubnet (/26 minimum).
# All spoke egress traffic is forced here via UDR.
# Note: takes 5-10 minutes to provision.
# -------------------------------------------------------
resource "azurerm_firewall" "hub" {
  name                = "afw-hub"
  location            = data.azurerm_resource_group.lab.location
  resource_group_name = data.azurerm_resource_group.lab.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"

  ip_configuration {
    name                 = "ipconfig-firewall"
    subnet_id            = data.azurerm_subnet.hub_firewall.id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }
}

# -------------------------------------------------------
# Route Tables for Spoke Workload Subnets
#
# disable_bgp_route_propagation = true prevents gateway
# routes from being injected into the route table, which
# would override the UDR and allow traffic to bypass the
# firewall. This is the most common misconfiguration in
# hub-and-spoke designs.
# -------------------------------------------------------
resource "azurerm_route_table" "spoke1" {
  name                          = "rt-spoke1"
  location                      = data.azurerm_resource_group.lab.location
  resource_group_name           = data.azurerm_resource_group.lab.name
  disable_bgp_route_propagation = true
}

resource "azurerm_route" "spoke1_default_to_firewall" {
  name                   = "udr-default-to-firewall"
  resource_group_name    = data.azurerm_resource_group.lab.name
  route_table_name       = azurerm_route_table.spoke1.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_firewall.hub.ip_configuration[0].private_ip_address
}

resource "azurerm_route_table" "spoke2" {
  name                          = "rt-spoke2"
  location                      = data.azurerm_resource_group.lab.location
  resource_group_name           = data.azurerm_resource_group.lab.name
  disable_bgp_route_propagation = true
}

resource "azurerm_route" "spoke2_default_to_firewall" {
  name                   = "udr-default-to-firewall"
  resource_group_name    = data.azurerm_resource_group.lab.name
  route_table_name       = azurerm_route_table.spoke2.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_firewall.hub.ip_configuration[0].private_ip_address
}

resource "azurerm_subnet_route_table_association" "spoke1" {
  subnet_id      = data.azurerm_subnet.spoke1_workload.id
  route_table_id = azurerm_route_table.spoke1.id
}

resource "azurerm_subnet_route_table_association" "spoke2" {
  subnet_id      = data.azurerm_subnet.spoke2_workload.id
  route_table_id = azurerm_route_table.spoke2.id
}
