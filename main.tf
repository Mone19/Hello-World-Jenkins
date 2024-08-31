# Provider-Konfiguration
provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
  client_id       = var.client_id
  client_secret   = var.client_secret
  tenant_id       = var.tenant_id
}

# Random Pet für dynamische Namen
resource "random_pet" "name" {
  length = 2
}

# Ressourcen-Gruppe
resource "azurerm_resource_group" "rg" {
  name     = "rg-${random_pet.name.id}"
  location = "West US"
}

# Virtuelles Netzwerk
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${random_pet.name.id}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Subnetz
resource "azurerm_subnet" "subnet" {
  name                 = "subnet-${random_pet.name.id}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.0.0/24"]
}

# Öffentliche IP-Adresse
resource "azurerm_public_ip" "pip" {
  name                = "pip-${random_pet.name.id}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
}

# Netzwerkschnittstelle
resource "azurerm_network_interface" "nic" {
  name                = "nic-${random_pet.name.id}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

# Netzwerk-Sicherheitsgruppe
resource "azurerm_network_security_group" "nsg" {
  name                = "nsg-${random_pet.name.id}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "allow"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = 8080
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Verknüpfung der NSG mit der Netzwerkschnittstelle
resource "azurerm_network_interface_security_group_association" "nic_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-${random_pet.name.id}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "aks-cluster-${random_pet.name.id}"

  default_node_pool {
    name       = "default"
    node_count = 2
    vm_size    = "Standard_D2_v2"
    vnet_subnet_id = azurerm_subnet.subnet.id
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

# AKS Cluster Admin Kubeconfig
data "azurerm_kubernetes_cluster" "aks" {
  name                = azurerm_kubernetes_cluster.aks.name
  resource_group_name = azurerm_resource_group.rg.name
}