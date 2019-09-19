variable "resource_group" { default = "terraform-wolfer-az-demo" } 
variable "location" { default = "southcentralus" }
variable "virtual_network_name" { default = "wolferaznet1" }
variable "virtual_network_address_space" { default = "10.0.0.0/24" }
variable "web01-hostname" { default = "wolfer-demo-web01" }
variable "web02-hostname" { default = "wolfer-demo-web02" }
variable "haproxy-hostname" { default = "wolfer-demo-haproxy" }

variable "admin_username" {} 
variable "admin_password" {}

# ========================================== 
#             Resource Group 
# ========================================== 

resource "azurerm_resource_group" "josh_demo" {
  name     = "${var.resource_group}"
  location = "${var.location}"
	
  tags = {
    environment = "Demonstration"
  }

}

# ========================================== 
#        Build Virtual Net / subnet 
# ========================================== 

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.virtual_network_name}"
  resource_group_name = "${azurerm_resource_group.josh_demo.name}"      # Inherit the Resource Group from "josh_demo" above.
  location            = "${azurerm_resource_group.josh_demo.location}"  # Inherit the Location from "josh_demo" above.
  address_space       = ["${var.virtual_network_address_space}"]        # Azure defaults to 10.0.0.0/24
}

resource "azurerm_subnet" "subnet" {
  name                 = "josh-demo-subnet"
  virtual_network_name = "${azurerm_virtual_network.vnet.name}"           # Tie this subnet definition into the virtual network above.
  resource_group_name  = "${azurerm_resource_group.josh_demo.name}"       # Inherit the Resource Group from "josh_demo" above.
  address_prefix       = "${var.virtual_network_address_space}"           # Use the same subnet as the address space.
}



# ========================================== 
#        Security group policy 
# ========================================== 

resource "azurerm_network_security_group" "josh_demo_secgroup" {
  name                = "josh_demo-sg"
  location            = "${azurerm_resource_group.josh_demo.location}"
  resource_group_name = "${azurerm_resource_group.josh_demo.name}"

  security_rule {
    name                       = "HTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "SSH"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}


# ========================================== 
#          Web01 Network Config
# ========================================== 

resource "azurerm_network_interface" "josh-demo-web01-vnic" {
  name                      = "josh-demo-web01-vnic"
  location                  = "${azurerm_resource_group.josh_demo.location}"
  resource_group_name       = "${azurerm_resource_group.josh_demo.name}"
  network_security_group_id = "${azurerm_network_security_group.josh_demo_secgroup.id}"   # Uses the security group above.

  ip_configuration {
    name                          = "josh-demo-web01-ipconfig"
    subnet_id                     = "${azurerm_subnet.subnet.id}"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = "${azurerm_public_ip.josh_demo-web01-public_ip.id}"    # Optional public IP. This will need to be the load balancer, when setup.
  }
}

resource "azurerm_public_ip" "josh_demo-web01-public_ip" {
  name                         = "josh_demo-web01-public_ip"
  location                     = "${azurerm_resource_group.josh_demo.location}"
  resource_group_name          = "${azurerm_resource_group.josh_demo.name}"
  allocation_method            = "Dynamic"
  domain_name_label            = "${var.web01-hostname}"                              
}

# ------------------------------------------ 
#             Web01 VM Config
# ------------------------------------------ 

resource "azurerm_virtual_machine" "web01" {
  name                = "${var.web01-hostname}"
  location            = "${azurerm_resource_group.josh_demo.location}"
  resource_group_name = "${azurerm_resource_group.josh_demo.name}"
  vm_size             = "Standard_A0"

  network_interface_ids         = ["${azurerm_network_interface.josh-demo-web01-vnic.id}"]
  delete_os_disk_on_termination = "true"

  #  "az vm image list" To determine the VM details:
  #
  #  "offer": "UbuntuServer",
  #  "publisher": "Canonical",
  #  "sku": "18.04-LTS",
  #  "urn": "Canonical:UbuntuServer:18.04-LTS:latest",
  #  "urnAlias": "UbuntuLTS",
  #  "version": "latest"

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "${var.web01-hostname}-osdisk"
    managed_disk_type = "Standard_LRS"
    caching           = "ReadWrite"
    create_option     = "FromImage"
  }

  os_profile {
    computer_name  = "${var.web01-hostname}"
    admin_username = "${var.admin_username}"
    admin_password = "${var.admin_password}"
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

# ------------------------------------------ 
#          Provisioning of Web01
# ------------------------------------------ 
  provisioner "file" {
    source      = "config/web01-setup.sh"
    destination = "/home/${var.admin_username}/setup.sh"

    connection {
      type     = "ssh"
      user     = "${var.admin_username}"
      password = "${var.admin_password}"
      host     = "${azurerm_public_ip.josh_demo-web01-public_ip.fqdn}"
    }
  }
  
  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/${var.admin_username}/setup.sh",
      "sudo /home/${var.admin_username}/setup.sh",
    ]

    connection {
      type     = "ssh"
      user     = "${var.admin_username}"
      password = "${var.admin_password}"
      host     = "${azurerm_public_ip.josh_demo-web01-public_ip.fqdn}"
    }
  }
}

output "Web01_URL" {
  value = "http://${azurerm_public_ip.josh_demo-web01-public_ip.fqdn}"
}
