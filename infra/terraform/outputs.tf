output "resource_group_name" {
  description = "Resource group that holds the platform."
  value       = azurerm_resource_group.this.name
}

output "gateway_base_url" {
  description = "Base URL that workloads call instead of Azure OpenAI. Append /deployments/{name}/chat/completions."
  value       = "${azurerm_api_management.this.gateway_url}/${azurerm_api_management_api.openai.path}"
}

output "gateway_audience" {
  description = "Entra ID audience callers request a token for. The scope is this value followed by /.default."
  value       = var.gateway_audience
}

output "apim_private_ip_addresses" {
  description = "Private IP addresses of the gateway inside the VNet."
  value       = azurerm_api_management.this.private_ip_addresses
}

output "openai_endpoints" {
  description = "Private endpoints of the Azure OpenAI instances, by instance key. Reachable only from the VNet."
  value       = { for k, v in azurerm_cognitive_account.openai : k => v.endpoint }
}

output "model_deployments" {
  description = "Deployment names available on every instance behind the gateway."
  value       = keys(var.model_deployments)
}

output "team_products" {
  description = "APIM product ID per team, used for quota and showback queries."
  value       = { for k, v in azurerm_api_management_product.team : k => v.product_id }
}

output "key_vault_uri" {
  description = "URI of the Key Vault (RBAC mode, private endpoint only)."
  value       = azurerm_key_vault.this.vault_uri
}

output "workload_identity_client_id" {
  description = "Client ID to set as AZURE_CLIENT_ID on the consuming workload."
  value       = azurerm_user_assigned_identity.workload.client_id
}

output "workload_identity_id" {
  description = "Resource ID of the workload identity, to attach to a container app or pod."
  value       = azurerm_user_assigned_identity.workload.id
}

output "apim_identity_principal_id" {
  description = "Principal ID of the gateway identity that holds Cognitive Services OpenAI User."
  value       = azurerm_user_assigned_identity.apim.principal_id
}

output "content_safety_endpoint" {
  description = "Content Safety endpoint, or null when disabled."
  value       = one(azurerm_cognitive_account.content_safety[*].endpoint)
}

output "log_analytics_workspace_id" {
  description = "Workspace that receives diagnostic settings from every resource."
  value       = azurerm_log_analytics_workspace.this.id
}

output "application_insights_connection_string" {
  description = "Connection string for the sample service telemetry exporter."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}
