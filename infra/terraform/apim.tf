resource "azurerm_api_management" "this" {
  name                 = "apim-${local.name}-${local.suffix}"
  location             = azurerm_resource_group.this.location
  resource_group_name  = azurerm_resource_group.this.name
  publisher_name       = var.apim_publisher_name
  publisher_email      = var.apim_publisher_email
  sku_name             = var.apim_sku_name
  virtual_network_type = var.apim_virtual_network_type
  min_api_version      = "2021-08-01"
  tags                 = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.apim.id]
  }

  virtual_network_configuration {
    subnet_id = azurerm_subnet.apim.id
  }

  protocols {
    http2_enabled = true
  }

  depends_on = [
    azurerm_subnet_network_security_group_association.apim,
  ]
}

# In Internal mode the gateway has no public DNS. Resolve it inside the VNet instead.
resource "azurerm_private_dns_a_record" "apim_gateway" {
  count = var.apim_virtual_network_type == "Internal" ? 1 : 0

  name                = azurerm_api_management.this.name
  zone_name           = azurerm_private_dns_zone.this["apim_azure_api"].name
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 300
  records             = azurerm_api_management.this.private_ip_addresses
  tags                = local.tags
}

# Named values referenced by the policy files. None of them is a secret.
resource "azurerm_api_management_named_value" "this" {
  for_each = {
    entra-tenant-id         = data.azurerm_client_config.current.tenant_id
    gateway-audience        = var.gateway_audience
    apim-identity-client-id = azurerm_user_assigned_identity.apim.client_id
  }

  name                = each.key
  display_name        = each.key
  value               = each.value
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name
}

# Observability: request logs and the custom token metrics land in Application Insights.
resource "azurerm_api_management_logger" "appinsights" {
  name                = "appinsights"
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name
  resource_id         = azurerm_application_insights.this.id

  application_insights {
    connection_string = azurerm_application_insights.this.connection_string
  }
}

# azurerm does not expose the "metrics" switch that azure-openai-emit-token-metric needs.
resource "azapi_resource" "apim_diagnostic" {
  type      = "Microsoft.ApiManagement/service/diagnostics@2024-05-01"
  name      = "applicationinsights"
  parent_id = azurerm_api_management.this.id

  body = {
    properties = {
      loggerId    = azurerm_api_management_logger.appinsights.id
      alwaysLog   = "allErrors"
      verbosity   = "information"
      logClientIp = false
      metrics     = true
      sampling = {
        samplingType = "fixed"
        percentage   = 100
      }
      frontend = {
        request  = { headers = ["x-request-id"], body = { bytes = 0 } }
        response = { headers = ["x-request-id"], body = { bytes = 0 } }
      }
      backend = {
        request  = { headers = [], body = { bytes = 0 } }
        response = { headers = ["x-ratelimit-remaining-tokens"], body = { bytes = 0 } }
      }
    }
  }
}

resource "azurerm_api_management_policy" "global" {
  api_management_id = azurerm_api_management.this.id
  xml_content       = file("${local.policy_dir}/global.xml")
}

# One backend per Azure OpenAI instance, each with its own circuit breaker.
resource "azurerm_api_management_backend" "openai" {
  for_each = var.openai_instances

  name                = "openai-${each.key}"
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name
  protocol            = "http"
  url                 = "${trimsuffix(azurerm_cognitive_account.openai[each.key].endpoint, "/")}/openai"
  description         = "Azure OpenAI ${each.key} (${each.value.location})"

  tls {
    validate_certificate_chain = true
    validate_certificate_name  = true
  }

  circuit_breaker_rule {
    name                       = "openai-throttling"
    trip_duration              = "PT1M"
    accept_retry_after_enabled = true

    failure_condition {
      count             = 3
      interval_duration = "PT1M"
      error_reasons     = ["Server errors"]

      status_code_range {
        min = 429
        max = 429
      }

      status_code_range {
        min = 500
        max = 599
      }
    }
  }

  depends_on = [azurerm_private_endpoint.openai]
}

# Load balanced pool. azurerm has no pool backend type yet, so azapi fills the gap.
resource "azapi_resource" "openai_pool" {
  type      = "Microsoft.ApiManagement/service/backends@2024-05-01"
  name      = "openai-backend-pool"
  parent_id = azurerm_api_management.this.id

  body = {
    properties = {
      description = "Azure OpenAI pool, weighted and prioritised across regions"
      type        = "Pool"
      pool = {
        services = [
          for k, v in var.openai_instances : {
            id       = azurerm_api_management_backend.openai[k].id
            priority = v.priority
            weight   = v.weight
          }
        ]
      }
    }
  }
}

resource "azurerm_api_management_api" "openai" {
  name                  = "azure-openai"
  display_name          = "Azure OpenAI"
  description           = "Governed facade over the Azure OpenAI data plane (api-version ${var.openai_api_version})."
  api_management_name   = azurerm_api_management.this.name
  resource_group_name   = azurerm_resource_group.this.name
  revision              = "1"
  path                  = "openai"
  protocols             = ["https"]
  subscription_required = true

  subscription_key_parameter_names {
    header = "Ocp-Apim-Subscription-Key"
    query  = "subscription-key"
  }
}

resource "azurerm_api_management_api_operation" "openai" {
  for_each = {
    chat-completions = { display_name = "Chat completions", url = "/deployments/{deployment-id}/chat/completions" }
    embeddings       = { display_name = "Embeddings", url = "/deployments/{deployment-id}/embeddings" }
  }

  operation_id        = each.key
  api_name            = azurerm_api_management_api.openai.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name
  display_name        = each.value.display_name
  method              = "POST"
  url_template        = each.value.url

  template_parameter {
    name     = "deployment-id"
    type     = "string"
    required = true
  }
}

resource "azurerm_api_management_api_policy" "openai" {
  api_name            = azurerm_api_management_api.openai.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name
  xml_content         = file("${local.policy_dir}/api-azure-openai.xml")

  depends_on = [
    azurerm_api_management_named_value.this,
    azapi_resource.openai_pool,
  ]
}

# One product per team: the unit of quota, showback and access approval.
resource "azurerm_api_management_product" "team" {
  for_each = var.teams

  product_id            = each.key
  display_name          = each.value.display_name
  description           = "${each.value.tokens_per_minute} tokens per minute, ${each.value.token_quota} tokens per ${lower(each.value.token_quota_period)} period."
  api_management_name   = azurerm_api_management.this.name
  resource_group_name   = azurerm_resource_group.this.name
  subscription_required = true
  approval_required     = true
  subscriptions_limit   = 2
  published             = true
}

resource "azurerm_api_management_product_api" "team" {
  for_each = var.teams

  api_name            = azurerm_api_management_api.openai.name
  product_id          = azurerm_api_management_product.team[each.key].product_id
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_api_management_product_policy" "team" {
  for_each = var.teams

  product_id          = azurerm_api_management_product.team[each.key].product_id
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name
  xml_content = templatefile("${local.policy_dir}/product-team-token-limit.xml.tftpl", {
    tokens_per_minute  = each.value.tokens_per_minute
    token_quota        = each.value.token_quota
    token_quota_period = each.value.token_quota_period
  })
}

resource "azurerm_api_management_subscription" "team" {
  for_each = var.teams

  display_name        = "${each.value.display_name} (${var.environment})"
  product_id          = azurerm_api_management_product.team[each.key].id
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name
  state               = "active"
  allow_tracing       = false
}
