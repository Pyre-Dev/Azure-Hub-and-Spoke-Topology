output "vm_private_ip" {
  description = "Private IP of the test VM in Spoke 1 (10.1.0.x)"
  value       = azurerm_network_interface.test_vm.private_ip_address
}

output "vm_managed_identity_principal_id" {
  description = "Object ID of the VM's system-assigned managed identity - useful for additional RBAC assignments"
  value       = azurerm_linux_virtual_machine.test_vm.identity[0].principal_id
}

output "ssh_export_command" {
  description = "Run this from Cloud Shell to export the private key for SSH access"
  value       = "az keyvault key download --vault-name ${var.key_vault_name} --name lab-ssh-key --encoding PEM --file ~/.ssh/lab_key.pem && chmod 600 ~/.ssh/lab_key.pem"
}
