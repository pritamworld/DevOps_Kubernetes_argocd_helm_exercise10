output "public_ip" {
  description = "Public IP address of the VM"
  value       = azurerm_public_ip.lab_ip.ip_address
}

output "public_dns" {
  description = "Public DNS name of the VM"
  value       = azurerm_public_ip.lab_ip.fqdn
}

output "ssh_command" {
  description = "ssh command to login to vm"
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.lab_ip.ip_address}"
}