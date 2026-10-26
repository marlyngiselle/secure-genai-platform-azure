prefix      = "genai"
environment = "dev"
location    = "westeurope"

apim_sku_name             = "Developer_1"
apim_virtual_network_type = "Internal"
apim_publisher_name       = "Platform Engineering"
apim_publisher_email      = "platform-team@example.com"

openai_instances = {
  primary   = { location = "swedencentral", priority = 1, weight = 50 }
  secondary = { location = "francecentral", priority = 1, weight = 50 }
}

model_deployments = {
  "gpt-4o-mini" = {
    model_name    = "gpt-4o-mini"
    model_version = "2024-07-18"
    sku_name      = "GlobalStandard"
    capacity      = 50
  }
  "text-embedding-3-small" = {
    model_name    = "text-embedding-3-small"
    model_version = "1"
    sku_name      = "Standard"
    capacity      = 30
  }
}

teams = {
  search-assistant = {
    display_name       = "Search Assistant"
    tokens_per_minute  = 20000
    token_quota        = 5000000
    token_quota_period = "Monthly"
  }
  customer-support = {
    display_name       = "Customer Support"
    tokens_per_minute  = 10000
    token_quota        = 2000000
    token_quota_period = "Monthly"
  }
}

enable_content_safety = true
