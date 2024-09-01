provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  client_id       = var.client_id
  client_secret   = var.client_secret
  tenant_id       = var.tenant_id
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

resource "kubernetes_namespace" "ingress_nginx" {
  metadata {
    name = "ingress-nginx"
  }
}

resource "kubernetes_deployment" "nginx_ingress" {
  metadata {
    name      = "nginx-ingress-controller"
    namespace = kubernetes_namespace.ingress_nginx.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "nginx-ingress"
      }
    }

    template {
      metadata {
        labels = {
          app = "nginx-ingress"
        }
      }

      spec {
        container {
          name  = "nginx-ingress-controller"
          image = "k8s.gcr.io/ingress-nginx/controller:v1.2.1"

          args = [
            "/nginx-ingress-controller",
            "--configmap=$(POD_NAMESPACE)/nginx-configuration",
            "--tcp-services-configmap=$(POD_NAMESPACE)/tcp-services",
            "--udp-services-configmap=$(POD_NAMESPACE)/udp-services",
            "--publish-service=$(POD_NAMESPACE)/nginx-ingress",
          ]

          env {
            name = "POD_NAMESPACE"
            value_from {
              field_ref {
                field_path = "metadata.namespace"
              }
            }
          }

          port {
            name           = "http"
            container_port = 80
          }

          port {
            name           = "https"
            container_port = 443
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "nginx_ingress" {
  metadata {
    name      = "nginx-ingress"
    namespace = kubernetes_namespace.ingress_nginx.metadata[0].name
  }

  spec {
    selector = {
      app = "nginx-ingress"
    }

    type = "LoadBalancer"

    port {
      port        = 80
      target_port = 80
    }

    port {
      port        = 443
      target_port = 443
    }
  }
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
      while ! curl -k --silent --fail --output /dev/null https://${azurerm_kubernetes_cluster.aks.fqdn}; do
        echo "Waiting for AKS to be available..."
        sleep 60
      done
      echo "AKS is available."
      sleep 180
    EOT
  }
  depends_on = [null_resource.wait_for_dns]
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
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
