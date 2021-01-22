output "azfw_pip_addr" {
  value       = azurerm_public_ip.azfw.ip_address
  description = "The public IP address of the Azure Firewall."
}

output "client_username" {
  value       = var.admin_username
  description = "The Username of the Client."
}

output "connect_cmd" {
  value       = "ssh -l ${var.admin_username} -p 1022 ${azurerm_public_ip.azfw.ip_address}"
  description = "SSH Connectionstring to the client"
}
