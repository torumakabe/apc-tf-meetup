# for fail test only (usually not associated to NSG)
resource "azurerm_network_security_rule" "failtest" {
  count                       = var.mode_failtest ? 1 : 0
  name                        = "deny_to_agw_subnet"
  priority                    = 100
  direction                   = "Outbound"
  access                      = "Deny"
  protocol                    = "Tcp"
  source_port_range           = "*"
  source_address_prefix       = "*"
  destination_port_range      = "80"
  destination_address_prefix  = module.subnet_addrs_default.network_cidr_blocks["agw"]
  resource_group_name         = azurerm_resource_group.apc_tf_meetup.name
  network_security_group_name = azurerm_network_security_group.aci.name
}

resource "azurerm_container_group" "check_nginx" {
  depends_on = [
    azurerm_virtual_network.default,
    azurerm_subnet.default,
    azurerm_subnet.agw,
    azurerm_subnet.cae,
    azurerm_subnet.aci,
    azurerm_public_ip.agw,
    azurerm_application_gateway.default,
    azurerm_container_app_environment.default,
    azurerm_container_app.nginx,
    azurerm_container_app.hello,
    azurerm_private_dns_zone.cae_default,
    azurerm_private_dns_a_record.cae_default_wildcard,
    azurerm_private_dns_zone_virtual_network_link.cae_default_to_vnet_default,
    azurerm_network_security_group.aci,
    azurerm_subnet_network_security_group_association.aci,
  ]
  name                = "ci-check-nginx"
  resource_group_name = azurerm_resource_group.apc_tf_meetup.name
  location            = azurerm_resource_group.apc_tf_meetup.location
  ip_address_type     = "None"
  subnet_ids          = [azurerm_subnet.aci.id]
  os_type             = "Linux"
  restart_policy      = "Never"

  container {
    name   = "curl"
    image  = "curlimages/curl"
    cpu    = "1.0"
    memory = "1.0"

    commands = [
      "curl",
      "http://${local.agw_fe_ip}/nginx",
      "-sS",
      "-o",
      "/dev/null",
      "-m",
      "5",
      "--retry",
      "3",
      "--fail"
    ]
  }

  lifecycle {
    ignore_changes = [
      ip_address_type,
    ]
    replace_triggered_by = [
      azurerm_virtual_network.default,
      azurerm_subnet.default,
      azurerm_subnet.agw,
      azurerm_subnet.cae,
      azurerm_subnet.aci,
      azurerm_public_ip.agw,
      azurerm_application_gateway.default,
      azurerm_container_app_environment.default,
      azurerm_container_app.nginx,
      azurerm_container_app.hello,
      azurerm_private_dns_zone.cae_default,
      azurerm_private_dns_a_record.cae_default_wildcard,
      azurerm_private_dns_zone_virtual_network_link.cae_default_to_vnet_default,
      azurerm_network_security_group.aci,
      azurerm_subnet_network_security_group_association.aci,
    ]
  }

  # Wait for async container execution
  provisioner "local-exec" {
    command = "sleep 60"
  }
}

check "nginx" {
  data "azapi_resource" "ci_check_nginx" {
    depends_on = [azurerm_container_group.check_nginx]
    name       = "ci-check-nginx"
    parent_id  = azurerm_resource_group.apc_tf_meetup.id
    type       = "Microsoft.ContainerInstance/containerGroups@2023-05-01"

    response_export_values = ["properties.instanceView.state"]
  }

  assert {
    condition     = jsondecode(data.azapi_resource.ci_check_nginx.output).properties.instanceView.state == "Succeeded"
    error_message = "curl check failed: to nginx. if state is Running, it is possible that the test just did not finish in time, please re-run it!"
  }
}
