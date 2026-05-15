output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.hub.id
}

output "log_analytics_workspace_id_guid" {
  description = "Workspace GUID - used in KQL queries and portal Log search"
  value       = azurerm_log_analytics_workspace.hub.workspace_id
}

output "storage_account_id" {
  description = "Resource ID of the flow log storage account"
  value       = azurerm_storage_account.flow_logs.id
}

output "private_endpoint_ip" {
  description = "Private IP allocated to the Log Analytics private endpoint in snet-management"
  value       = azurerm_private_endpoint.log_analytics.private_service_connection[0].private_ip_address
}
