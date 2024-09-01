provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  client_id       = var.client_id
  client_secret   = var.client_secret
  tenant_id       = var.tenant_id
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

resource "random_pet" "resource_name" {
  length    = 2
  separator = "-"
}

resource "azurerm_resource_group" "rg" {
  name     = "${random_pet.resource_name.id}-rg"
  location = "West US"
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${random_pet.resource_name.id}-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "${random_pet.resource_name.id}-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.0.0/24"]
}

resource "azurerm_public_ip" "pip" {
  name                = "${random_pet.resource_name.id}-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "nic" {
  name                = "${random_pet.resource_name.id}-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

resource "azurerm_network_security_group" "nsg" {
  name                = "${random_pet.resource_name.id}-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "allow"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface_security_group_association" "nic_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "${random_pet.resource_name.id}-aks"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "aks-cluster"

  default_node_pool {
    name            = "default"
    node_count      = 2
    vm_size         = "Standard_D2_v2"
    vnet_subnet_id  = azurerm_subnet.subnet.id
  }

  network_profile {
    network_plugin = "azure"
    service_cidr   = "10.1.0.0/16"
    dns_service_ip = "10.1.0.10"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    Environment = "Production"
  }

  depends_on = [
    azurerm_virtual_network.vnet,
    azurerm_subnet.subnet
  ]
}

resource "null_resource" "wait_for_dns" {
  provisioner "local-exec" {
    command = <<EOT
      while ! nslookup ${azurerm_kubernetes_cluster.aks.fqdn}; do
        echo "Waiting for DNS to propagate..."
        sleep 60
      done
      echo "DNS propagation complete."
    EOT
  }
  depends_on = [azurerm_kubernetes_cluster.aks]
}

resource "null_resource" "wait_for_aks" {
  provisioner "local-exec" {
    command = <<EOT
      while ! curl -k --silent --fail --output /dev/null ${azurerm_kubernetes_cluster.aks.fqdn}; do
        echo "Waiting for AKS to be available..."
        sleep 60
      done
      echo "AKS is available."
      sleep 180
    EOT
  }
  depends_on = [null_resource.wait_for_dns]
}

resource "kubernetes_secret" "tls_cert" {
  depends_on = [ null_resource.wait_for_aks ]
  metadata {
    name      = "tls-secret"
    namespace = "default"
  }

  data = {
    "tls.crt" = filebase64(var.tls_cert_file)
    "tls.key" = filebase64(var.tls_key_file)
  }
}

output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.aks.name
}