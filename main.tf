provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = "myResourceGroup"
  location = "West Europe"
}

resource "azurerm_virtual_network" "vnet" {
  name                = "myVNet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "mySubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "pip" {
  name                = "myPublicIP"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "nic" {
  name                = "myNIC"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

resource "azurerm_virtual_machine" "vm" {
  name                  = "myVM"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.nic.id]
  vm_size               = "Standard_B1s"

  storage_os_disk {
    name              = "myOSDisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  storage_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  os_profile {
    computer_name  = "hostname"
    admin_username = "adminuser"
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys {
      path     = "/home/adminuser/.ssh/authorized_keys"
      key_data = file("~/.ssh/id_rsa.pub")
    }
  }
}

data "azurerm_public_ip" "public_ip" {
  name                = azurerm_public_ip.pip.name
  resource_group_name = azurerm_resource_group.rg.name
}

resource "null_resource" "install_docker" {
  depends_on = [azurerm_virtual_machine.vm]

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "adminuser"
      private_key = file("~/.ssh/id_rsa")
      host        = data.azurerm_public_ip.public_ip.ip_address
    }

    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -",
      "sudo add-apt-repository 'deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable'",
      "sudo apt-get update",
      "sudo apt-get install -y docker-ce",
      "sudo usermod -aG docker adminuser",
      "sudo docker run -d -p 80:80 --name mynginx nginx"  # Pull and run the nginx Docker image
    ]
  }
}

resource "null_resource" "setup_github_runner" {
  depends_on = [azurerm_virtual_machine.vm]

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "adminuser"
      private_key = file("~/.ssh/id_rsa")
      host        = data.azurerm_public_ip.public_ip.ip_address
    }

    inline = [
      "mkdir actions-runner && cd actions-runner",
      "curl -o actions-runner-linux-x64-2.300.2.tar.gz -L https://github.com/actions/runner/releases/download/v2.300.2/actions-runner-linux-x64-2.300.2.tar.gz",
      "tar xzf ./actions-runner-linux-x64-2.300.2.tar.gz",
      "sudo ./bin/installdependencies.sh",
      "sudo usermod -aG docker adminuser",
      "sudo -u adminuser ./config.sh --url https://github.com/${var.RUNNER_REPO} --token ${var.GITHUB_TOKEN} --name ${var.RUNNER_NAME} --unattended",
      "sudo apt-get install -y supervisor",
      "echo '[program:actions-runner]' | sudo tee /etc/supervisor/conf.d/actions-runner.conf",
      "echo 'command=sudo -u adminuser /home/adminuser/actions-runner/run.sh' | sudo tee -a /etc/supervisor/conf.d/actions-runner.conf",
      "echo 'autostart=true' | sudo tee -a /etc/supervisor/conf.d/actions-runner.conf",
      "echo 'autorestart=true' | sudo tee -a /etc/supervisor/conf.d/actions-runner.conf",
      "echo 'stderr_logfile=/var/log/actions-runner.err.log' | sudo tee -a /etc/supervisor/conf.d/actions-runner.conf",
      "echo 'stdout_logfile=/var/log/actions-runner.out.log' | sudo tee -a /etc/supervisor/conf.d/actions-runner.conf",
      "sudo supervisorctl reread",
      "sudo supervisorctl update",
      "sudo supervisorctl start actions-runner"
    ]
  }
}

output "vm_ip" {
  value = data.azurerm_public_ip.public_ip.ip_address
}
