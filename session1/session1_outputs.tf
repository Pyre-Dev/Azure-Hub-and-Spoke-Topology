output "hub_vnet_id" {
  description = "Resource ID of the hub VNet"
  value       = azurerm_virtual_network.hub.id
}

output "spoke1_vnet_id" {
  description = "Resource ID of spoke 1 VNet"
  value       = azurerm_virtual_network.spoke1.id
}

output "spoke2_vnet_id" {
  description = "Resource ID of spoke 2 VNet"
  value       = azurerm_virtual_network.spoke2.id
}

output "hub_firewall_subnet_id" {
  description = "Subnet ID reserved for Azure Firewall (used in Session 2)"
  value       = azurerm_subnet.hub_firewall.id
}

output "hub_management_subnet_id" {
  description = "Subnet ID for hub management / private endpoints (used in Sessions 3 and 5)"
  value       = azurerm_subnet.hub_management.id
}

output "spoke1_workload_subnet_id" {
  description = "Subnet ID for spoke 1 workloads (UDR attached in Session 2)"
  value       = azurerm_subnet.spoke1_workload.id
}

output "spoke2_workload_subnet_id" {
  description = "Subnet ID for spoke 2 workloads (UDR attached in Session 2)"
  value       = azurerm_subnet.spoke2_workload.id
}

output "nsg_hub_management_id" {
  description = "NSG ID for hub management subnet (used for flow log config in Session 5)"
  value       = azurerm_network_security_group.hub_management.id
}

output "nsg_spoke1_workload_id" {
  description = "NSG ID for spoke 1 workload subnet (used for flow log config in Session 5)"
  value       = azurerm_network_security_group.spoke1_workload.id
}

output "nsg_spoke2_workload_id" {
  description = "NSG ID for spoke 2 workload subnet (used for flow log config in Session 5)"
  value       = azurerm_network_security_group.spoke2_workload.id
}
