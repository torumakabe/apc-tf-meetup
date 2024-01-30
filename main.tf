terraform {
  required_version = "~> 1.7.1"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.89.0"
    }

    azapi = {
      source  = "Azure/azapi"
      version = "~> 1.12.0"
    }
  }
}

provider "azurerm" {
  skip_provider_registration = true
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider "azapi" {
  # Specify for your environment
  # https://github.com/Azure/terraform-provider-azapi/issues/203
  use_msi = false
}

resource "azurerm_resource_group" "apc_tf_meetup" {
  name     = var.rg_name
  location = var.location
}

module "subnet_addrs_default" {
  source  = "hashicorp/subnets/cidr"
  version = "~> 1.0.0"

  base_cidr_block = local.vnet_address_space.default
  networks = [
    {
      name     = "default"
      new_bits = 8
    },
    {
      name     = "agw"
      new_bits = 8
    },
    {
      name     = "cae"
      new_bits = 4
    },
    {
      name     = "aci"
      new_bits = 8
    },
  ]
}

resource "azurerm_virtual_network" "default" {
  name                = "vnet-default"
  resource_group_name = azurerm_resource_group.apc_tf_meetup.name
  location            = azurerm_resource_group.apc_tf_meetup.location
  address_space       = [local.vnet_address_space.default]
}

resource "azurerm_subnet" "default" {
  name                 = "snet-default"
  resource_group_name  = azurerm_resource_group.apc_tf_meetup.name
  virtual_network_name = azurerm_virtual_network.default.name
  address_prefixes     = [module.subnet_addrs_default.network_cidr_blocks["default"]]
}

resource "azurerm_subnet" "agw" {
  name                 = "snet-agw"
  resource_group_name  = azurerm_resource_group.apc_tf_meetup.name
  virtual_network_name = azurerm_virtual_network.default.name
  address_prefixes     = [module.subnet_addrs_default.network_cidr_blocks["agw"]]
}

locals {
  agw_fe_ip = cidrhost(azurerm_subnet.agw.address_prefixes[0], 10)
}

resource "azurerm_subnet" "cae" {
  name                 = "snet-cae"
  resource_group_name  = azurerm_resource_group.apc_tf_meetup.name
  virtual_network_name = azurerm_virtual_network.default.name
  address_prefixes     = [module.subnet_addrs_default.network_cidr_blocks["cae"]]
}

resource "azurerm_subnet" "aci" {
  name                 = "snet-aci"
  resource_group_name  = azurerm_resource_group.apc_tf_meetup.name
  virtual_network_name = azurerm_virtual_network.default.name
  address_prefixes     = [module.subnet_addrs_default.network_cidr_blocks["aci"]]

  delegation {
    name = "Microsoft.ContainerInstance.containerGroups"

    service_delegation {
      name    = "Microsoft.ContainerInstance/containerGroups"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_network_security_group" "aci" {
  name                = "nsg-aci"
  resource_group_name = azurerm_resource_group.apc_tf_meetup.name
  location            = azurerm_resource_group.apc_tf_meetup.location
}

resource "azurerm_subnet_network_security_group_association" "aci" {
  subnet_id                 = azurerm_subnet.aci.id
  network_security_group_id = azurerm_network_security_group.aci.id
}

resource "azurerm_container_app_environment" "default" {
  name                           = "cae-default"
  location                       = azurerm_resource_group.apc_tf_meetup.location
  resource_group_name            = azurerm_resource_group.apc_tf_meetup.name
  infrastructure_subnet_id       = azurerm_subnet.cae.id
  internal_load_balancer_enabled = true
}

resource "azurerm_private_dns_zone" "cae_default" {
  resource_group_name = azurerm_resource_group.apc_tf_meetup.name
  name                = azurerm_container_app_environment.default.default_domain
}

resource "azurerm_private_dns_a_record" "cae_default_wildcard" {
  resource_group_name = azurerm_resource_group.apc_tf_meetup.name
  name                = "*"
  zone_name           = azurerm_private_dns_zone.cae_default.name
  ttl                 = 300
  records             = [azurerm_container_app_environment.default.static_ip_address]
}

resource "azurerm_private_dns_zone_virtual_network_link" "cae_default_to_vnet_default" {
  name                  = "pdnsz-link-cae-default-to-vnet-default"
  resource_group_name   = azurerm_resource_group.apc_tf_meetup.name
  private_dns_zone_name = azurerm_private_dns_zone.cae_default.name
  virtual_network_id    = azurerm_virtual_network.default.id
}

resource "azurerm_container_app" "nginx" {
  name                         = "ca-nginx"
  container_app_environment_id = azurerm_container_app_environment.default.id
  resource_group_name          = azurerm_resource_group.apc_tf_meetup.name
  revision_mode                = "Single"

  ingress {
    allow_insecure_connections = true
    external_enabled           = true
    target_port                = 80
    transport                  = "auto"
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    container {
      name   = "nginx"
      image  = "nginx"
      cpu    = 0.25
      memory = "0.5Gi"
    }
    min_replicas = 1
  }
}

resource "azurerm_container_app" "hello" {
  name                         = "ca-hello"
  container_app_environment_id = azurerm_container_app_environment.default.id
  resource_group_name          = azurerm_resource_group.apc_tf_meetup.name
  revision_mode                = "Single"

  ingress {
    allow_insecure_connections = true
    external_enabled           = true
    target_port                = 80
    transport                  = "auto"
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    container {
      name   = "hello"
      image  = "mcr.microsoft.com/k8se/quickstart:latest"
      cpu    = 0.25
      memory = "0.5Gi"
    }
    min_replicas = 1
  }
}

# For outbound only (no bindings to listener)
resource "azurerm_public_ip" "agw" {
  name                = "pip-agw"
  resource_group_name = azurerm_resource_group.apc_tf_meetup.name
  location            = azurerm_resource_group.apc_tf_meetup.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_application_gateway" "default" {
  location            = azurerm_resource_group.apc_tf_meetup.location
  name                = "agw-default"
  resource_group_name = azurerm_resource_group.apc_tf_meetup.name

  sku {
    capacity = 2
    name     = "Standard_v2"
    tier     = "Standard_v2"
  }

  # No bindings to listener
  frontend_ip_configuration {
    name                 = local.agw_settings.frontend_pip_configuration_name
    public_ip_address_id = azurerm_public_ip.agw.id
  }

  frontend_ip_configuration {
    name                          = local.agw_settings.frontend_ip_configuration_name
    subnet_id                     = azurerm_subnet.agw.id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.agw_fe_ip
  }

  frontend_port {
    name = local.agw_settings.frontend_port_name
    port = 80
  }

  gateway_ip_configuration {
    name      = local.agw_settings.gateway_ip_configuration_name
    subnet_id = azurerm_subnet.agw.id
  }

  http_listener {
    frontend_ip_configuration_name = local.agw_settings.frontend_ip_configuration_name
    frontend_port_name             = local.agw_settings.frontend_port_name
    name                           = local.agw_settings.default_http_listener_name
    protocol                       = "Http"
  }

  backend_address_pool {
    fqdns = [azurerm_container_app.hello.ingress[0].fqdn]
    name  = local.ca_hello.agw_settings.backend_address_pool_name
  }

  backend_address_pool {
    fqdns = [azurerm_container_app.nginx.ingress[0].fqdn]
    name  = local.ca_nginx.agw_settings.backend_address_pool_name
  }

  backend_http_settings {
    cookie_based_affinity               = "Disabled"
    name                                = local.ca_hello.agw_settings.backend_http_settings_name
    path                                = "/"
    pick_host_name_from_backend_address = true
    port                                = 80
    protocol                            = "Http"
    request_timeout                     = 15
    connection_draining {
      drain_timeout_sec = 10
      enabled           = true
    }
  }

  backend_http_settings {
    cookie_based_affinity               = "Disabled"
    name                                = local.ca_nginx.agw_settings.backend_http_settings_name
    path                                = "/"
    pick_host_name_from_backend_address = true
    port                                = 80
    protocol                            = "Http"
    request_timeout                     = 15
    connection_draining {
      drain_timeout_sec = 10
      enabled           = true
    }
  }

  request_routing_rule {
    http_listener_name = local.agw_settings.default_http_listener_name
    name               = local.agw_settings.default_request_routing_rule_name
    priority           = 100
    rule_type          = "PathBasedRouting"
    url_path_map_name  = local.agw_settings.default_path_map_name
  }

  url_path_map {
    default_backend_address_pool_name  = local.ca_nginx.agw_settings.backend_address_pool_name
    default_backend_http_settings_name = local.ca_nginx.agw_settings.backend_http_settings_name
    name                               = local.agw_settings.default_path_map_name

    path_rule {
      backend_address_pool_name  = local.ca_nginx.agw_settings.backend_address_pool_name
      backend_http_settings_name = local.ca_nginx.agw_settings.backend_http_settings_name
      name                       = "nginx"
      paths                      = ["/nginx"]
    }

    path_rule {
      backend_address_pool_name  = local.ca_hello.agw_settings.backend_address_pool_name
      backend_http_settings_name = local.ca_hello.agw_settings.backend_http_settings_name
      name                       = "hello"
      paths                      = ["/hello"]
    }
  }
}
