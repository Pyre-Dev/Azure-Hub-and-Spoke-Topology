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
# Data sources - reads existing resources from Sessions 1-3
# -------------------------------------------------------
data "azurerm_resource_group" "lab" {
  name = var.resource_group_name
}

data "azurerm_subnet" "spoke1_workload" {
  name                 = "snet-workload"
  virtual_network_name = "vnet-spoke1"
  resource_group_name  = data.azurerm_resource_group.lab.name
}

data "azurerm_firewall" "hub" {
  name                = "afw-hub"
  resource_group_name = data.azurerm_resource_group.lab.name
}

data "azurerm_key_vault" "hub" {
  name                = var.key_vault_name
  resource_group_name = data.azurerm_resource_group.lab.name
}

# Reads the public key from Key Vault.
# public_key_openssh is automatically converted from JWK
# to OpenSSH format by the provider - no scripting needed.
# The private key never appears in state or the repo.
data "azurerm_key_vault_key" "ssh" {
  name         = "lab-ssh-key"
  key_vault_id = data.azurerm_key_vault.hub.id
}

# -------------------------------------------------------
# Firewall Application Rule Collection
#
# FQDN-based HTTPS filtering. Only explicitly listed
# destinations are reachable from the spokes. All other
# traffic hits the implicit deny and is logged.
# -------------------------------------------------------
resource "azurerm_firewall_application_rule_collection" "allow_microsoft" {
  name                = "arc-allow-microsoft"
  azure_firewall_name = data.azurerm_firewall.hub.name
  resource_group_name = data.azurerm_resource_group.lab.name
  priority            = 100
  action              = "Allow"

  rule {
    name             = "allow-microsoft-fqdns"
    source_addresses = ["10.1.0.0/24", "10.2.0.0/24"]

    target_fqdns = [
      "*.microsoft.com",
      "*.azure.com",
      "*.azure.net",         # Covers vault.azure.net for Key Vault data-plane
      "*.ubuntu.com",        # Allows apt updates from the test VM
      "security.ubuntu.com",
    ]

    protocol {
      port = "443"
      type = "Https"
    }
  }
}

# -------------------------------------------------------
# Firewall Network Rule Collection - DNS
#
# Allows spokes to reach Azure DNS (168.63.129.16) on
# UDP 53. Required for private DNS zone resolution.
# Without this, DNS queries are dropped at the firewall
# before they reach the Azure resolver.
# -------------------------------------------------------
resource "azurerm_firewall_network_rule_collection" "allow_dns" {
  name                = "nrc-allow-dns"
  azure_firewall_name = data.azurerm_firewall.hub.name
  resource_group_name = data.azurerm_resource_group.lab.name
  priority            = 100
  action              = "Allow"

  rule {
    name                  = "allow-azure-dns"
    source_addresses      = ["10.1.0.0/24", "10.2.0.0/24"]
    destination_addresses = ["168.63.129.16"]
    destination_ports     = ["53"]
    protocols             = ["UDP"]
  }
}

# -------------------------------------------------------
# Network Interface for test VM
# -------------------------------------------------------
resource "azurerm_network_interface" "test_vm" {
  name                = "nic-test-vm-spoke1"
  location            = data.azurerm_resource_group.lab.location
  resource_group_name = data.azurerm_resource_group.lab.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = data.azurerm_subnet.spoke1_workload.id
    private_ip_address_allocation = "Dynamic"
    # No public IP - connect via Azure Serial Console or Bastion
  }
}

# -------------------------------------------------------
# Test VM in Spoke 1
#
# SSH public key sourced from Key Vault via data source.
# No plaintext key in variables, CLI flags, or state.
# System-assigned managed identity allows the VM to
# authenticate to Key Vault at runtime via IMDS with
# no stored credentials anywhere.
# -------------------------------------------------------
resource "azurerm_linux_virtual_machine" "test_vm" {
  name                  = "vm-test-spoke1"
  location              = data.azurerm_resource_group.lab.location
  resource_group_name   = data.azurerm_resource_group.lab.name
  size                  = "Standard_B1s"
  admin_username        = "azureuser"
  network_interface_ids = [azurerm_network_interface.test_vm.id]

  admin_ssh_key {
    username   = "azureuser"
    public_key = data.azurerm_key_vault_key.ssh.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }
}

# -------------------------------------------------------
# Key Vault access policy for the VM's managed identity
#
# Grants the VM read access to secrets so it can retrieve
# them at runtime via IMDS token without any stored creds.
# -------------------------------------------------------
resource "azurerm_key_vault_access_policy" "vm_identity" {
  key_vault_id = data.azurerm_key_vault.hub.id
  tenant_id    = azurerm_linux_virtual_machine.test_vm.identity[0].tenant_id
  object_id    = azurerm_linux_virtual_machine.test_vm.identity[0].principal_id

  secret_permissions = ["Get", "List"]
}
