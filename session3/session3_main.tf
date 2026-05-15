terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = false
    }
  }
}

# -------------------------------------------------------
# Data sources - reads existing resources from Sessions 1-2
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

# Resolves to your logged-in identity. Used for the Key Vault
# access policy so Terraform can create keys and Session 4
# can read them back without any additional auth.
data "azurerm_client_config" "current" {}

# -------------------------------------------------------
# Private DNS Zone for Key Vault
#
# Azure requires this exact zone name. Any variation breaks
# automatic DNS resolution through the private endpoint.
# -------------------------------------------------------
resource "azurerm_private_dns_zone" "keyvault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = data.azurerm_resource_group.lab.name
}

# -------------------------------------------------------
# Link DNS zone to all three VNets
#
# Without these links, VMs in the spokes resolve the vault
# FQDN to the public IP and bypass the private endpoint.
# registration_enabled = false - the private endpoint manages
# the A record automatically via the dns_zone_group block.
# -------------------------------------------------------
resource "azurerm_private_dns_zone_virtual_network_link" "keyvault_hub" {
  name                  = "link-keyvault-hub"
  resource_group_name   = data.azurerm_resource_group.lab.name
  private_dns_zone_name = azurerm_private_dns_zone.keyvault.name
  virtual_network_id    = data.azurerm_virtual_network.hub.id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "keyvault_spoke1" {
  name                  = "link-keyvault-spoke1"
  resource_group_name   = data.azurerm_resource_group.lab.name
  private_dns_zone_name = azurerm_private_dns_zone.keyvault.name
  virtual_network_id    = data.azurerm_virtual_network.spoke1.id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "keyvault_spoke2" {
  name                  = "link-keyvault-spoke2"
  resource_group_name   = data.azurerm_resource_group.lab.name
  private_dns_zone_name = azurerm_private_dns_zone.keyvault.name
  virtual_network_id    = data.azurerm_virtual_network.spoke2.id
  registration_enabled  = false
}

# -------------------------------------------------------
# Key Vault
#
# Central secrets store in the hub. Public network access
# disabled - all traffic must flow through the private
# endpoint. bypass = "AzureServices" allows trusted
# Microsoft services (Backup, Monitor, Defender) to reach
# the vault even with the network deny in place.
# -------------------------------------------------------
resource "azurerm_key_vault" "hub" {
  name                          = var.key_vault_name
  location                      = data.azurerm_resource_group.lab.location
  resource_group_name           = data.azurerm_resource_group.lab.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  purge_protection_enabled      = false
  public_network_access_enabled = true

  network_acls {
  default_action = "Deny"
  bypass         = "AzureServices"
  ip_rules       = var.allowed_ip != "" ? ["${var.allowed_ip}"] : []
}

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
  "Get", "List", "Create", "Delete", "Recover",
  "Backup", "Restore", "Purge", "Import",
  "GetRotationPolicy", "SetRotationPolicy"
    ]
    secret_permissions = [
      "Get", "List", "Set", "Delete", "Recover",
      "Backup", "Restore", "Purge"
    ]
    certificate_permissions = [
      "Get", "List", "Create", "Delete", "Recover",
      "Backup", "Restore", "Purge", "Import"
    ]
  }
}

# -------------------------------------------------------
# Private Endpoint for Key Vault
#
# Drops a NIC into snet-management (10.0.2.0/24).
# The private_dns_zone_group creates and manages the A
# record in the zone automatically - no manual DNS work.
# -------------------------------------------------------
resource "azurerm_private_endpoint" "keyvault" {
  name                = "pe-keyvault-hub"
  location            = data.azurerm_resource_group.lab.location
  resource_group_name = data.azurerm_resource_group.lab.name
  subnet_id           = data.azurerm_subnet.hub_management.id

  private_service_connection {
    name                           = "psc-keyvault"
    private_connection_resource_id = azurerm_key_vault.hub.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "pdns-group-keyvault"
    private_dns_zone_ids = [azurerm_private_dns_zone.keyvault.id]
  }
}

# -------------------------------------------------------
# SSH Key Pair - generated inside Key Vault
#
# Key Vault generates and stores the RSA private key.
# It never exists in Terraform state or on disk.
# Session 4 reads the public key back via data source.
# To SSH into the VM, export the private key once:
#
#   az keyvault key download \
#     --vault-name <vault-name> \
#     --name lab-ssh-key \
#     --encoding PEM \
#     --file ~/.ssh/lab_key.pem
#   chmod 600 ~/.ssh/lab_key.pem
#
# depends_on the private endpoint because Key Vault
# data-plane operations fail if the endpoint hasn't
# finished provisioning when the vault is network-locked.
# -------------------------------------------------------
resource "azurerm_key_vault_key" "ssh" {
  name         = "lab-ssh-key"
  key_vault_id = azurerm_key_vault.hub.id
  key_type     = "RSA"
  key_size     = 4096

  key_opts = [
    "decrypt", "encrypt", "sign",
    "unwrapKey", "verify", "wrapKey"
  ]

  depends_on = [azurerm_private_endpoint.keyvault]
}
