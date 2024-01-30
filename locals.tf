locals {
  vnet_address_space = {
    default = "10.0.0.0/16"
  }

  agw_settings = {
    gateway_ip_configuration_name     = "gw-ip"
    frontend_port_name                = "fe-port"
    frontend_ip_configuration_name    = "fe-ip"
    frontend_pip_configuration_name   = "fe-pip"
    default_http_listener_name        = "default-listener"
    default_request_routing_rule_name = "default-req-routing-rule"
    default_path_map_name             = "default-pathmap"
  }

  ca_nginx = {
    agw_settings = {
      backend_address_pool_name  = "nginx-be-pool"
      backend_http_settings_name = "nginx-http-settings"
    }
  }

  ca_hello = {
    agw_settings = {
      backend_address_pool_name  = "hello-be-pool"
      backend_http_settings_name = "hello-http-settings"
    }
  }
}
