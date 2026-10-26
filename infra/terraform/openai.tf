resource "azurerm_cognitive_account" "openai" {
  for_each = var.openai_instances

  name                          = "oai-${local.name}-${each.key}-${local.suffix}"
  location                      = each.value.location
  resource_group_name           = azurerm_resource_group.this.name
  kind                          = "OpenAI"
  sku_name                      = "S0"
  custom_subdomain_name         = "oai-${local.name}-${each.key}-${local.suffix}"
  public_network_access_enabled = false
  local_auth_enabled            = false
  tags                          = local.tags

  identity {
    type = "SystemAssigned"
  }

  network_acls {
    default_action = "Deny"
  }
}

resource "azurerm_cognitive_deployment" "this" {
  for_each = local.deployments

  name                   = each.value.deployment
  cognitive_account_id   = azurerm_cognitive_account.openai[each.value.instance].id
  version_upgrade_option = "NoAutoUpgrade"

  model {
    format  = "OpenAI"
    name    = each.value.config.model_name
    version = each.value.config.model_version
  }

  sku {
    name     = each.value.config.sku_name
    capacity = each.value.config.capacity
  }
}

# The endpoint lives in the platform VNet even when the account sits in another region.
resource "azurerm_private_endpoint" "openai" {
  for_each = var.openai_instances

  name                          = "pe-${azurerm_cognitive_account.openai[each.key].name}"
  location                      = azurerm_resource_group.this.location
  resource_group_name           = azurerm_resource_group.this.name
  subnet_id                     = azurerm_subnet.private_endpoints.id
  custom_network_interface_name = "nic-pe-${azurerm_cognitive_account.openai[each.key].name}"
  tags                          = local.tags

  private_service_connection {
    name                           = "psc-${azurerm_cognitive_account.openai[each.key].name}"
    private_connection_resource_id = azurerm_cognitive_account.openai[each.key].id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "default"
    private_dns_zone_ids = [
      azurerm_private_dns_zone.this["openai"].id,
      azurerm_private_dns_zone.this["cognitive"].id,
    ]
  }
}
