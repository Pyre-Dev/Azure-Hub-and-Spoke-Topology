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
# Resource Group
# -------------------------------------------------------
resource "azurerm_resource_group" "lab" {
  name     = var.resource_group_name
  location = var.location
}

# -------------------------------------------------------
# NSG - Hub Management Subnet
#
# snet-management hosts private endpoints only. Nothing
# initiates outbound connections from here to the internet.
# Inbound is restricted to RFC 1918 address space so only
# resources inside the VNets can reach the private endpoints.
# -------------------------------------------------------
resource "azurerm_network_security_group" "hub_management" {
  name                = "nsg-hub-management"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  # Inbound
  security_rule {
    name                       = "Allow-VNet-Inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "Deny-Internet-Inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  # Outbound
  security_rule {
    name                       = "Allow-VNet-Outbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "Deny-Internet-Outbound"
    priority                   = 4000
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }
}

# -------------------------------------------------------
# NSG - Spoke 1 Workload Subnet
#
# Allows inbound from within the VNets (hub-to-spoke
# management), denies inbound from internet explicitly
# even though no public IP exists on the VM (documents
# intent and provides defense in depth).
#
# Outbound allows:
# - UDP 53 to Azure DNS for private zone resolution
# - TCP 443 to snet-management for Key Vault private endpoint
# - TCP 443/80 toward the firewall for internet-bound egress
# - VNet traffic for general RFC 1918 reachability
# Denies direct internet outbound (belt-and-suspenders with UDR).
# -------------------------------------------------------
resource "azurerm_network_security_group" "spoke1_workload" {
  name                = "nsg-spoke1-workload"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  # Inbound
  security_rule {
    name                       = "Allow-VNet-Inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "Deny-Internet-Inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  # Outbound
  security_rule {
    name                       = "Allow-DNS-Outbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "53"
    source_address_prefix      = "*"
    destination_address_prefix = "168.63.129.16/32"
  }

  security_rule {
    name                       = "Allow-KeyVault-PE-Outbound"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "10.0.2.0/24"
  }

  security_rule {
    name                       = "Allow-VNet-Outbound"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "Allow-Firewall-Egress"
    priority                   = 130
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
    source_address_prefix      = "*"
    destination_address_prefix = "10.0.0.0/26"
  }

  security_rule {
    name                       = "Deny-Internet-Outbound"
    priority                   = 4000
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }
}

# -------------------------------------------------------
# NSG - Spoke 2 Workload Subnet (mirrors Spoke 1)
# -------------------------------------------------------
resource "azurerm_network_security_group" "spoke2_workload" {
  name                = "nsg-spoke2-workload"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  security_rule {
    name                       = "Allow-VNet-Inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "Deny-Internet-Inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-DNS-Outbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "53"
    source_address_prefix      = "*"
    destination_address_prefix = "168.63.129.16/32"
  }

  security_rule {
    name                       = "Allow-KeyVault-PE-Outbound"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "10.0.2.0/24"
  }

  security_rule {
    name                       = "Allow-VNet-Outbound"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "Allow-Firewall-Egress"
    priority                   = 130
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
    source_address_prefix      = "*"
    destination_address_prefix = "10.0.0.0/26"
  }

  security_rule {
    name                       = "Deny-Internet-Outbound"
    priority                   = 4000
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }
}

# -------------------------------------------------------
# Hub VNet
# -------------------------------------------------------
resource "azurerm_virtual_network" "hub" {
  name                = "vnet-hub"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "hub_firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.0.0.0/26"]
  # NSGs are not supported on AzureFirewallSubnet - Azure will reject them
}

resource "azurerm_subnet" "hub_gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.0.1.0/27"]
  # NSGs are not supported on GatewaySubnet
}

resource "azurerm_subnet" "hub_management" {
  name                 = "snet-management"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_subnet_network_security_group_association" "hub_management" {
  subnet_id                 = azurerm_subnet.hub_management.id
  network_security_group_id = azurerm_network_security_group.hub_management.id
}

# -------------------------------------------------------
# Spoke 1 VNet
# -------------------------------------------------------
resource "azurerm_virtual_network" "spoke1" {
  name                = "vnet-spoke1"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.1.0.0/16"]
}

resource "azurerm_subnet" "spoke1_workload" {
  name                 = "snet-workload"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.spoke1.name
  address_prefixes     = ["10.1.0.0/24"]
}

resource "azurerm_subnet_network_security_group_association" "spoke1_workload" {
  subnet_id                 = azurerm_subnet.spoke1_workload.id
  network_security_group_id = azurerm_network_security_group.spoke1_workload.id
}

# -------------------------------------------------------
# Spoke 2 VNet
# -------------------------------------------------------
resource "azurerm_virtual_network" "spoke2" {
  name                = "vnet-spoke2"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.2.0.0/16"]
}

resource "azurerm_subnet" "spoke2_workload" {
  name                 = "snet-workload"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.spoke2.name
  address_prefixes     = ["10.2.0.0/24"]
}

resource "azurerm_subnet_network_security_group_association" "spoke2_workload" {
  subnet_id                 = azurerm_subnet.spoke2_workload.id
  network_security_group_id = azurerm_network_security_group.spoke2_workload.id
}

# -------------------------------------------------------
# VNet Peerings (Hub <-> Spoke1, Hub <-> Spoke2)
# Peering is not transitive. Spoke1 and Spoke2 cannot
# reach each other directly - all traffic flows through
# the hub. This is intentional.
# -------------------------------------------------------
resource "azurerm_virtual_network_peering" "hub_to_spoke1" {
  name                      = "peer-hub-to-spoke1"
  resource_group_name       = azurerm_resource_group.lab.name
  virtual_network_name      = azurerm_virtual_network.hub.name
  remote_virtual_network_id = azurerm_virtual_network.spoke1.id
  allow_forwarded_traffic   = true
  allow_gateway_transit     = true
  use_remote_gateways       = false
}

resource "azurerm_virtual_network_peering" "spoke1_to_hub" {
  name                      = "peer-spoke1-to-hub"
  resource_group_name       = azurerm_resource_group.lab.name
  virtual_network_name      = azurerm_virtual_network.spoke1.name
  remote_virtual_network_id = azurerm_virtual_network.hub.id
  allow_forwarded_traffic   = true
  allow_gateway_transit     = false
  use_remote_gateways       = false
}

resource "azurerm_virtual_network_peering" "hub_to_spoke2" {
  name                      = "peer-hub-to-spoke2"
  resource_group_name       = azurerm_resource_group.lab.name
  virtual_network_name      = azurerm_virtual_network.hub.name
  remote_virtual_network_id = azurerm_virtual_network.spoke2.id
  allow_forwarded_traffic   = true
  allow_gateway_transit     = true
  use_remote_gateways       = false
}

resource "azurerm_virtual_network_peering" "spoke2_to_hub" {
  name                      = "peer-spoke2-to-hub"
  resource_group_name       = azurerm_resource_group.lab.name
  virtual_network_name      = azurerm_virtual_network.spoke2.name
  remote_virtual_network_id = azurerm_virtual_network.hub.id
  allow_forwarded_traffic   = true
  allow_gateway_transit     = false
  use_remote_gateways       = false
}
