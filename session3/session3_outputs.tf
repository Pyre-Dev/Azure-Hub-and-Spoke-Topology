output "key_vault_id" {
  description = "Resource ID of the Key Vault - referenced by Session 4 data source"
  value       = azurerm_key_vault.hub.id
}

output "key_vault_uri" {
  description = "Vault URI - use this to verify private DNS resolution from spoke VMs"
  value       = azurerm_key_vault.hub.vault_uri
}

output "key_vault_name" {
  description = "Vault name - pass as a variable into Sessions 4 and 5"
  value       = azurerm_key_vault.hub.name
}

output "private_endpoint_ip" {
  description = "Private IP allocated to the Key Vault endpoint in snet-management (10.0.2.x)"
  value       = azurerm_private_endpoint.keyvault.private_service_connection[0].private_ip_address
}

output "private_dns_zone_id" {
  description = "Resource ID of the privatelink.vaultcore.azure.net zone"
  value       = azurerm_private_dns_zone.keyvault.id
}

output "ssh_key_name" {
  description = "Name of the SSH key object in Key Vault - referenced by Session 4"
  value       = azurerm_key_vault_key.ssh.name
}
