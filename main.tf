provider "azurerm" {
  version = "=2.44.0"
  features {}
}

resource "azurerm_resource_group" "azfw" {
  name     = "${var.prefix}-azfw-apprule-poc"
  location = var.location
}

resource "azurerm_virtual_network" "azfw" {
  name                = "${var.prefix}-azfw-network"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.azfw.location
  resource_group_name = azurerm_resource_group.azfw.name
}

resource "azurerm_subnet" "azfw" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.azfw.name
  virtual_network_name = azurerm_virtual_network.azfw.name
  address_prefixes     = ["10.0.0.0/24"]
}

resource "azurerm_public_ip" "azfw" {
  name                = "${var.prefix}-azfw-pip"
  location            = azurerm_resource_group.azfw.location
  resource_group_name = azurerm_resource_group.azfw.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_firewall" "azfw" {
  name                = "${var.prefix}-azfw"
  location            = azurerm_resource_group.azfw.location
  resource_group_name = azurerm_resource_group.azfw.name

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.azfw.id
    public_ip_address_id = azurerm_public_ip.azfw.id
  }
}


resource "azurerm_firewall_nat_rule_collection" "azfw" {
  name                = "natrulecollection"
  azure_firewall_name = azurerm_firewall.azfw.name
  resource_group_name = azurerm_resource_group.azfw.name
  priority            = 100
  action              = "Dnat"

  rule {
    name = "sshnatrule"

    source_addresses = [
      "*",
    ]

    destination_ports = [
      "1022",
    ]

    destination_addresses = [
      azurerm_public_ip.azfw.ip_address
    ]

    translated_port = 22

    translated_address = "10.2.0.4"

    protocols = [
      "TCP",
      "UDP",
    ]
  }
}


resource "azurerm_firewall_application_rule_collection" "azfw" {
  name                = "apprulecollection"
  azure_firewall_name = azurerm_firewall.azfw.name
  resource_group_name = azurerm_resource_group.azfw.name
  priority            = 100
  action              = "Allow"

  rule {
    name = "webrule"

    source_addresses = [
      "10.2.0.0/16",
    ]

    target_fqdns = [
      "web.poc.local",
    ]

    protocol {
      port = "80"
      type = "Http"
    }
  }

  rule {
    name = "pkgupdaterule"

    source_addresses = [
      "10.1.0.0/16",
      "10.2.0.0/16",
    ]

    target_fqdns = [
      "*.ubuntu.com",
    ]

    protocol {
      port = "80"
      type = "Http"
    }
  }
}

resource "azurerm_firewall_network_rule_collection" "azfw" {
  name                = "netcollection"
  azure_firewall_name = azurerm_firewall.azfw.name
  resource_group_name = azurerm_resource_group.azfw.name
  priority            = 100
  action              = "Allow"

  rule {
    name = "sshrule"

    source_addresses = [
      "10.2.0.0/16",
    ]

    destination_ports = [
      "22",
    ]

    destination_addresses = [
      "10.1.0.4",
    ]

    protocols = [
      "TCP",
      "UDP",
    ]
  }
}


resource "azurerm_virtual_network" "nginx" {
  name                = "${var.prefix}-nginx-network"
  address_space       = ["10.1.0.0/16"]
  location            = azurerm_resource_group.azfw.location
  resource_group_name = azurerm_resource_group.azfw.name
}

resource "azurerm_subnet" "nginx" {
  name                 = "nginxsubnet"
  resource_group_name  = azurerm_resource_group.azfw.name
  virtual_network_name = azurerm_virtual_network.nginx.name
  address_prefixes     = ["10.1.0.0/24"]
}

resource "azurerm_virtual_network_peering" "azfwnginx" {
  name                      = "peerazfwnginx"
  resource_group_name       = azurerm_resource_group.azfw.name
  virtual_network_name      = azurerm_virtual_network.azfw.name
  remote_virtual_network_id = azurerm_virtual_network.nginx.id
  allow_forwarded_traffic   = true
}

resource "azurerm_virtual_network_peering" "azfwclient" {
  name                      = "peerazfwclient"
  resource_group_name       = azurerm_resource_group.azfw.name
  virtual_network_name      = azurerm_virtual_network.azfw.name
  remote_virtual_network_id = azurerm_virtual_network.client.id
  allow_forwarded_traffic   = true
}

resource "azurerm_network_interface" "nginx" {
  name                = "${var.prefix}-nginx-nic"
  location            = azurerm_resource_group.azfw.location
  resource_group_name = azurerm_resource_group.azfw.name

  ip_configuration {
    name                          = "testconfiguration1"
    subnet_id                     = azurerm_subnet.nginx.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_virtual_machine" "nginx" {
  name                          = "${var.prefix}-nginx-vm"
  location                      = azurerm_resource_group.azfw.location
  resource_group_name           = azurerm_resource_group.azfw.name
  network_interface_ids         = [azurerm_network_interface.nginx.id]
  vm_size                       = "Standard_DS1_v2"
  delete_os_disk_on_termination = true


  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
  storage_os_disk {
    name              = "${var.prefix}-nginx-osdisc"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  os_profile {
    computer_name  = "nginx"
    admin_username = var.admin_username
    admin_password = var.admin_password
  }
  os_profile_linux_config {
    disable_password_authentication = false
  }
  tags = {
    environment = "poc"
  }
}

resource "azurerm_virtual_machine_extension" "nginx" {
  name                 = "nginx"
  virtual_machine_id   = azurerm_virtual_machine.nginx.id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.0"

  settings = <<SETTINGS
    {
        "commandToExecute": "apt-get update && apt-get install -y nginx"
    }
SETTINGS

  depends_on = [
    azurerm_firewall_application_rule_collection.azfw
  ]
}



resource "azurerm_virtual_network_peering" "nginxazfw" {
  name                      = "peernginxazfw"
  resource_group_name       = azurerm_resource_group.azfw.name
  virtual_network_name      = azurerm_virtual_network.nginx.name
  remote_virtual_network_id = azurerm_virtual_network.azfw.id
  allow_forwarded_traffic   = true
}




resource "azurerm_virtual_network" "client" {
  name                = "${var.prefix}-client-network"
  address_space       = ["10.2.0.0/16"]
  location            = azurerm_resource_group.azfw.location
  resource_group_name = azurerm_resource_group.azfw.name
}

resource "azurerm_subnet" "client" {
  name                 = "clientsubnet"
  resource_group_name  = azurerm_resource_group.azfw.name
  virtual_network_name = azurerm_virtual_network.client.name
  address_prefixes     = ["10.2.0.0/24"]
}

resource "azurerm_network_interface" "client" {
  name                = "${var.prefix}-client-nic"
  location            = azurerm_resource_group.azfw.location
  resource_group_name = azurerm_resource_group.azfw.name

  ip_configuration {
    name                          = "testconfiguration1"
    subnet_id                     = azurerm_subnet.client.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_virtual_machine" "client" {
  name                          = "${var.prefix}-client-vm"
  location                      = azurerm_resource_group.azfw.location
  resource_group_name           = azurerm_resource_group.azfw.name
  network_interface_ids         = [azurerm_network_interface.client.id]
  vm_size                       = "Standard_DS1_v2"
  delete_os_disk_on_termination = true


  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
  storage_os_disk {
    name              = "${var.prefix}-client-osdisc"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  os_profile {
    computer_name  = "client"
    admin_username = var.admin_username
    admin_password = var.admin_password
  }
  os_profile_linux_config {
    disable_password_authentication = false
  }
  tags = {
    environment = "poc"
  }
}

resource "azurerm_virtual_network_peering" "clientazfw" {
  name                      = "peerclientazfw"
  resource_group_name       = azurerm_resource_group.azfw.name
  virtual_network_name      = azurerm_virtual_network.client.name
  remote_virtual_network_id = azurerm_virtual_network.azfw.id
  allow_forwarded_traffic   = true
}


resource "azurerm_route_table" "azfw" {
  name                          = "${var.prefix}-azfw-udr"
  location                      = azurerm_resource_group.azfw.location
  resource_group_name           = azurerm_resource_group.azfw.name
  disable_bgp_route_propagation = false

  route {
    name                   = "default-azfw"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = "10.0.0.4"
  }

}

resource "azurerm_subnet_route_table_association" "client" {
  subnet_id      = azurerm_subnet.client.id
  route_table_id = azurerm_route_table.azfw.id
}

resource "azurerm_subnet_route_table_association" "nginx" {
  subnet_id      = azurerm_subnet.nginx.id
  route_table_id = azurerm_route_table.azfw.id
}


resource "azurerm_private_dns_zone" "dns" {
  name                = "poc.local"
  resource_group_name = azurerm_resource_group.azfw.name
}

resource "azurerm_private_dns_a_record" "dns" {
  name                = "web"
  zone_name           = azurerm_private_dns_zone.dns.name
  resource_group_name = azurerm_resource_group.azfw.name
  ttl                 = 300
  records             = ["10.1.0.4"]
}

resource "azurerm_private_dns_zone_virtual_network_link" "azfw" {
  name                  = "azfw"
  resource_group_name   = azurerm_resource_group.azfw.name
  private_dns_zone_name = azurerm_private_dns_zone.dns.name
  virtual_network_id    = azurerm_virtual_network.azfw.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "nginx" {
  name                  = "nginx"
  resource_group_name   = azurerm_resource_group.azfw.name
  private_dns_zone_name = azurerm_private_dns_zone.dns.name
  virtual_network_id    = azurerm_virtual_network.nginx.id
}


resource "azurerm_private_dns_zone_virtual_network_link" "client" {
  name                  = "client"
  resource_group_name   = azurerm_resource_group.azfw.name
  private_dns_zone_name = azurerm_private_dns_zone.dns.name
  virtual_network_id    = azurerm_virtual_network.client.id
}
