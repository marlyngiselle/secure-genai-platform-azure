# Gateway identity may call the models. Data plane only: it cannot manage deployments or read keys.
resource "azurerm_role_assignment" "apim_openai_user" {
  for_each = var.openai_instances

  scope                            = azurerm_cognitive_account.openai[each.key].id
  role_definition_name             = "Cognitive Services OpenAI User"
  principal_id                     = azurerm_user_assigned_identity.apim.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# Workload identity reads its gateway subscription key from Key Vault.
resource "azurerm_role_assignment" "workload_kv_secrets_user" {
  scope                            = azurerm_key_vault.this.id
  role_definition_name             = "Key Vault Secrets User"
  principal_id                     = azurerm_user_assigned_identity.workload.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# Workload identity screens prompts and completions with Content Safety.
resource "azurerm_role_assignment" "workload_content_safety_user" {
  count = var.enable_content_safety ? 1 : 0

  scope                            = azurerm_cognitive_account.content_safety[0].id
  role_definition_name             = "Cognitive Services User"
  principal_id                     = azurerm_user_assigned_identity.workload.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# Workload identity publishes telemetry with Entra ID instead of the instrumentation key.
resource "azurerm_role_assignment" "workload_metrics_publisher" {
  scope                            = azurerm_application_insights.this.id
  role_definition_name             = "Monitoring Metrics Publisher"
  principal_id                     = azurerm_user_assigned_identity.workload.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}
