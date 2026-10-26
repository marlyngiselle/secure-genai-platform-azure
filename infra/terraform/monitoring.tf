resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${local.name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.tags
}

resource "azurerm_application_insights" "this" {
  name                = "appi-${local.name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "web"
  disable_ip_masking  = false
  tags                = local.tags
}

locals {
  diagnostic_targets = merge(
    { for k, v in azurerm_cognitive_account.openai : "openai-${k}" => v.id },
    { for i, v in azurerm_cognitive_account.content_safety : "content-safety" => v.id },
    {
      apim      = azurerm_api_management.this.id
      key-vault = azurerm_key_vault.this.id
    },
  )
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  for_each = local.diagnostic_targets

  name                           = "diag-to-log-analytics"
  target_resource_id             = each.value
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.this.id
  log_analytics_destination_type = each.key == "apim" ? "Dedicated" : null

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
