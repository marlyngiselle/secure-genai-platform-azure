resource "azurerm_cognitive_account" "content_safety" {
  count = var.enable_content_safety ? 1 : 0

  name                          = "cs-${local.name}-${local.suffix}"
  location                      = azurerm_resource_group.this.location
  resource_group_name           = azurerm_resource_group.this.name
  kind                          = "ContentSafety"
  sku_name                      = "S0"
  custom_subdomain_name         = "cs-${local.name}-${local.suffix}"
  public_network_access_enabled = false
  local_auth_enabled            = false
  tags                          = local.tags

  network_acls {
    default_action = "Deny"
  }
}

resource "azurerm_private_endpoint" "content_safety" {
  count = var.enable_content_safety ? 1 : 0

  name                = "pe-${azurerm_cognitive_account.content_safety[0].name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = local.tags

  private_service_connection {
    name                           = "psc-${azurerm_cognitive_account.content_safety[0].name}"
    private_connection_resource_id = azurerm_cognitive_account.content_safety[0].id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.this["cognitive"].id]
  }
}
