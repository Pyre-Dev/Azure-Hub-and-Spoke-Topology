output "firewall_private_ip" {
  description = "Private IP of Azure Firewall in AzureFirewallSubnet - used as next hop in spoke UDRs"
  value       = azurerm_firewall.hub.ip_configuration[0].private_ip_address
}

output "firewall_public_ip" {
  description = "Public IP of Azure Firewall - source IP for all spoke egress to the internet"
  value       = azurerm_public_ip.firewall.ip_address
}

output "firewall_id" {
  description = "Resource ID of the firewall - referenced by Sessions 4 and 5"
  value       = azurerm_firewall.hub.id
}
