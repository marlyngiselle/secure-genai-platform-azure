# Offline plan tests. Providers are mocked, so no Azure credentials are needed.
# Run from infra/terraform: terraform test

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000000"
    }
  }
}

mock_provider "azapi" {}
mock_provider "random" {}

variables {
  subscription_id      = "00000000-0000-0000-0000-000000000000"
  environment          = "dev"
  apim_publisher_email = "platform-team@example.com"
  teams = {
    alpha = { display_name = "Alpha", tokens_per_minute = 1000, token_quota = 100000 }
    beta  = { display_name = "Beta", tokens_per_minute = 2000, token_quota = 200000 }
  }
}

run "models_are_private_and_keyless" {
  command = plan

  assert {
    condition     = alltrue([for a in azurerm_cognitive_account.openai : a.public_network_access_enabled == false && a.local_auth_enabled == false])
    error_message = "Every Azure OpenAI account must disable public access and local (key) auth."
  }

  assert {
    condition     = length(azurerm_private_endpoint.openai) == length(var.openai_instances)
    error_message = "Every Azure OpenAI account needs a private endpoint."
  }
}

run "gateway_identity_has_data_plane_role_only" {
  command = plan

  assert {
    condition     = alltrue([for r in azurerm_role_assignment.apim_openai_user : r.role_definition_name == "Cognitive Services OpenAI User"])
    error_message = "The gateway identity must only hold Cognitive Services OpenAI User."
  }
}

run "key_vault_is_rbac_and_private" {
  command = plan

  assert {
    condition     = azurerm_key_vault.this.rbac_authorization_enabled && !azurerm_key_vault.this.public_network_access_enabled && azurerm_key_vault.this.purge_protection_enabled
    error_message = "Key Vault must use RBAC, have no public access and keep purge protection."
  }
}

run "one_product_and_token_policy_per_team" {
  command = plan

  assert {
    condition     = length(azurerm_api_management_product.team) == 2 && length(azurerm_api_management_product_policy.team) == 2
    error_message = "Each team must get a product and a token limit policy."
  }

  assert {
    condition     = strcontains(azurerm_api_management_product_policy.team["alpha"].xml_content, "tokens-per-minute=\"1000\"")
    error_message = "The rendered policy must carry the team's tokens per minute."
  }
}

run "deployments_fan_out_across_instances" {
  command = plan

  variables {
    model_deployments = {
      chat  = { model_name = "gpt-4o-mini", model_version = "2024-07-18" }
      embed = { model_name = "text-embedding-3-small", model_version = "1", sku_name = "Standard" }
    }
  }

  assert {
    condition     = length(azurerm_cognitive_deployment.this) == 4
    error_message = "Two models on two instances must give four deployments."
  }
}

run "internal_mode_gets_private_gateway_dns" {
  command = plan

  assert {
    condition     = length(azurerm_private_dns_a_record.apim_gateway) == 1 && length(azurerm_private_dns_zone.this) == 4
    error_message = "Internal mode needs the azure-api.net private zone and a gateway A record."
  }
}

run "external_mode_skips_gateway_dns" {
  command = plan

  variables {
    apim_virtual_network_type = "External"
  }

  assert {
    condition     = length(azurerm_private_dns_a_record.apim_gateway) == 0 && length(azurerm_private_dns_zone.this) == 3
    error_message = "External mode must not create the azure-api.net private zone."
  }
}

run "rejects_unsupported_apim_sku" {
  command = plan

  variables {
    apim_sku_name = "Basic_1"
  }

  expect_failures = [var.apim_sku_name]
}

run "rejects_small_apim_subnet" {
  command = plan

  variables {
    subnet_prefixes = {
      apim              = "10.40.0.0/28"
      private_endpoints = "10.40.0.64/26"
      workload          = "10.40.1.0/24"
    }
  }

  expect_failures = [var.subnet_prefixes]
}
