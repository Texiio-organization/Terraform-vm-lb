resource "azurerm_resource_group" "main" {
  location = var.resource_group_location
  name     = "az-loadbalancer"
}

# Create virtual network
resource "azurerm_virtual_network" "az_vnet" {
  name                = "azvnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

#Create availability set
resource "azurerm_availability_set" "availset" {
    name = "aas01"
    resource_group_name = azurerm_resource_group.main.name
    location = azurerm_resource_group.main.location
    platform_fault_domain_count = 3
    platform_update_domain_count = 5
}


# Create subnet
resource "azurerm_subnet" "az_subnet" {
  name                 = "azsubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.az_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}


# Create public IPs
resource "azurerm_public_ip" "az_public_ip" {
  count = 4
  name                = "public-ip${count.index}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Dynamic"
}


# Create Network Security Group and rules
resource "azurerm_network_security_group" "az_nsg" {
  name                = "az_net_grp"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name


  security_rule {
    name                       = "RDP"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "web"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}


# Create network interface
resource "azurerm_network_interface" "az_nic" {
  count = 3
  name                = "az_net${count.index}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name


  ip_configuration {
    name                          = "az_nic_configuration"
    subnet_id                     = azurerm_subnet.az_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id           = azurerm_public_ip.az_public_ip[count.index].id
  }
}


# Connect the security group to the network interface
resource "azurerm_network_interface_security_group_association" "az_nsg_security" {
  count = 3
  network_interface_id      = azurerm_network_interface.az_nic[count.index].id
  network_security_group_id = azurerm_network_security_group.az_nsg.id
}


# Create virtual machine
resource "azurerm_windows_virtual_machine" "az_virtual_machine" {
  count = 3
  name                  = "vm0${count.index}"
  admin_username        = "azureuser"
  admin_password        = "Sysadmin@123"
  location              = azurerm_resource_group.main.location
  availability_set_id   = azurerm_availability_set.availset.id
  resource_group_name   = azurerm_resource_group.main.name
  network_interface_ids = [azurerm_network_interface.az_nic[count.index].id]
  size                  = "Standard_DS1_v2"


  os_disk {
    name                 = "myOsDisk${count.index}"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }


  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }
}


# Install IIS web server to the virtual machine
resource "azurerm_virtual_machine_extension" "web_server_install" {
  count = 3
  name                       = "texiio-${count.index}"
  virtual_machine_id         = azurerm_windows_virtual_machine.az_virtual_machine[count.index].id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.8"
  auto_upgrade_minor_version = true


  settings = <<SETTINGS
    {
      "commandToExecute": "powershell -ExecutionPolicy Unrestricted Install-WindowsFeature -Name Web-Server -IncludeAllSubFeature -IncludeManagementTools"
    }
  SETTINGS
}


resource "azurerm_lb" "az_lb" {
  name ="az_lb_01"
  resource_group_name = azurerm_resource_group.main.name
  location = azurerm_resource_group.main.location
  frontend_ip_configuration {
    name = "az_nic_configuration"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.az_public_ip[3].id
  }
}

resource "azurerm_lb_backend_address_pool" "az_backend" {
    
  name = "az_backend_01"
  loadbalancer_id = azurerm_lb.az_lb.id  
}

resource "azurerm_lb_probe" "az_probe" {
  name = "az_probe_01"
  loadbalancer_id = azurerm_lb.az_lb.id
  port =  80
}

resource "azurerm_network_interface_backend_address_pool_association" "az_pool_association" {
    count = 3
    backend_address_pool_id = azurerm_lb_backend_address_pool.az_backend.id
    network_interface_id = azurerm_network_interface.az_nic[count.index].id
    ip_configuration_name = "az_nic_configuration"
}

resource "azurerm_lb_rule" "az_lb_rule" {
  name = "az_rule"
  loadbalancer_id = azurerm_lb.az_lb.id
  backend_address_pool_ids = ["${azurerm_lb_backend_address_pool.az_backend.id}"]
  frontend_ip_configuration_name = azurerm_lb.az_lb.frontend_ip_configuration[0].name
  probe_id = azurerm_lb_probe.az_probe.id
  protocol = "Tcp"
  frontend_port = "80"
  backend_port =  "80"
}

