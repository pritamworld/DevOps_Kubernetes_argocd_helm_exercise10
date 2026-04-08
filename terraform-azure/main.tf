terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}

provider "azurerm" {
  features {}
}

# ----------------------------
# Resource Group
# ----------------------------
resource "azurerm_resource_group" "lab" {
  name     = var.resource_group_name
  location = var.location
}

# ----------------------------
# Networking
# ----------------------------
resource "azurerm_virtual_network" "lab_vnet" {
  name                = "ci-cd-lab-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
}

# Subnet
resource "azurerm_subnet" "lab_subnet" {
  name                 = "ci-cd-lab-subnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# ----------------------------
# Public IP
# ----------------------------
resource "azurerm_public_ip" "lab_ip" {
  name                = "ci-cd-lab-ip"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  allocation_method = "Static"
  sku               = "Standard"

  domain_name_label = "ci-cd-lab-unique123" # optional
}

# --------------------------------------------------------
# NSG (Network Security Group (like AWS Security Group))
# --------------------------------------------------------
resource "azurerm_network_security_group" "lab_nsg" {
  name                = "ci-cd-lab-nsg"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = var.allow_cidr
    destination_port_range     = "22"
    destination_address_prefix = "*"
    source_port_range          = "*"
  }

  security_rule {
    name                       = "HTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = var.allow_cidr
    destination_port_range     = "80"
    destination_address_prefix = "*"
    source_port_range          = "*"
  }

  security_rule {
    name                       = "Prometheus"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = var.allow_cidr
    destination_port_range     = "9090"
    destination_address_prefix = "*"
    source_port_range          = "*"
  }

  security_rule {
    name                       = "Grafana"
    priority                   = 1004
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = var.allow_cidr
    destination_port_range     = "3000"
    destination_address_prefix = "*"
    source_port_range          = "*"
  }
}


# ----------------------------
# NIC (Network Interface)
# ----------------------------
resource "azurerm_network_interface" "lab_nic" {
  name                = "ci-cd-lab-nic"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.lab_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.lab_ip.id
  }
}

# Associate NSG to NIC
resource "azurerm_network_interface_security_group_association" "lab_assoc" {
  network_interface_id      = azurerm_network_interface.lab_nic.id
  network_security_group_id = azurerm_network_security_group.lab_nsg.id
}


# ------------------------------------
# VM (Linux VM (Ubuntu 22.04 LTS))
# ------------------------------------
resource "azurerm_linux_virtual_machine" "lab_vm" {
  name                = "ci-cd-lab-vm"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  size                = var.instance_type
  admin_username      = var.admin_username

  network_interface_ids = [
    azurerm_network_interface.lab_nic.id
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  # Ubuntu 22.04 (equivalent to AWS AMI lookup)
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }


  # ----------------------------
  # Cloud-init bootstrap
  # ----------------------------
  custom_data = base64encode(file("${path.module}/cloud-init.yaml"))

  tags = {
    Name = "ci-cd-lab-vm"
  }
}