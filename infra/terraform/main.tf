data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "this" {
  name     = "rg-${local.name}"
  location = var.location
  tags     = local.tags
}

# Identity used by the gateway to call Azure OpenAI. No API keys exist anywhere in the chain.
resource "azurerm_user_assigned_identity" "apim" {
  name                = "id-${local.name}-apim"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

# Identity attached to the consuming workload (container app, AKS pod, function).
resource "azurerm_user_assigned_identity" "workload" {
  name                = "id-${local.name}-workload"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}
