variable "subscription_id" {
  description = "Target Azure subscription ID. Supplied per environment, never committed."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.subscription_id))
    error_message = "subscription_id must be a GUID."
  }
}

variable "prefix" {
  description = "Short workload prefix used in every resource name."
  type        = string
  default     = "genai"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,9}$", var.prefix))
    error_message = "prefix must be 3 to 10 lowercase alphanumeric characters starting with a letter."
  }
}

variable "environment" {
  description = "Deployment environment. Drives naming and a few safety defaults."
  type        = string

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "environment must be one of dev, test or prod."
  }
}

variable "location" {
  description = "Primary region for the network, gateway, Key Vault and observability resources."
  type        = string
  default     = "westeurope"
}

variable "tags" {
  description = "Extra tags merged onto every resource."
  type        = map(string)
  default     = {}
}

# Network

variable "vnet_address_space" {
  description = "Address space of the platform virtual network."
  type        = string
  default     = "10.40.0.0/22"

  validation {
    condition     = can(cidrhost(var.vnet_address_space, 0))
    error_message = "vnet_address_space must be a valid CIDR block."
  }
}

variable "subnet_prefixes" {
  description = "CIDR of each subnet. The APIM subnet needs at least a /27."
  type = object({
    apim              = string
    private_endpoints = string
    workload          = string
  })
  default = {
    apim              = "10.40.0.0/27"
    private_endpoints = "10.40.0.64/26"
    workload          = "10.40.1.0/24"
  }

  validation {
    condition = alltrue([
      for cidr in values(var.subnet_prefixes) : can(cidrhost(cidr, 0))
    ])
    error_message = "Every subnet prefix must be a valid CIDR block."
  }

  validation {
    condition     = tonumber(split("/", var.subnet_prefixes.apim)[1]) <= 27
    error_message = "The APIM subnet must be a /27 or larger."
  }
}

# Azure OpenAI

variable "openai_instances" {
  description = "Azure OpenAI accounts placed behind the gateway backend pool. Two or more regions give failover and extra quota."
  type = map(object({
    location = string
    priority = optional(number, 1)
    weight   = optional(number, 50)
  }))
  default = {
    primary   = { location = "swedencentral" }
    secondary = { location = "francecentral" }
  }

  validation {
    condition     = length(var.openai_instances) >= 1 && length(var.openai_instances) <= 5
    error_message = "Declare between 1 and 5 Azure OpenAI instances."
  }

  validation {
    condition = alltrue([
      for k, v in var.openai_instances : can(regex("^[a-z][a-z0-9]{1,11}$", k)) && v.priority >= 1 && v.priority <= 100 && v.weight >= 1 && v.weight <= 1000
    ])
    error_message = "Instance keys must be short lowercase names, priority must be 1 to 100 and weight 1 to 1000."
  }
}

variable "model_deployments" {
  description = "Model deployments created on every Azure OpenAI instance. The map key is the deployment name callers use."
  type = map(object({
    model_name    = string
    model_version = string
    sku_name      = optional(string, "GlobalStandard")
    capacity      = optional(number, 10)
  }))
  default = {
    "gpt-4o-mini" = {
      model_name    = "gpt-4o-mini"
      model_version = "2024-07-18"
    }
  }

  validation {
    condition = alltrue([
      for d in values(var.model_deployments) : contains(["Standard", "GlobalStandard", "DataZoneStandard", "ProvisionedManaged"], d.sku_name)
    ])
    error_message = "sku_name must be Standard, GlobalStandard, DataZoneStandard or ProvisionedManaged."
  }

  validation {
    condition     = alltrue([for d in values(var.model_deployments) : d.capacity >= 1])
    error_message = "capacity is expressed in thousands of tokens per minute and must be at least 1."
  }
}

# API Management (AI gateway)

variable "apim_sku_name" {
  description = "APIM SKU. Developer_1 for non production, Premium_N for production with SLA and zones."
  type        = string
  default     = "Developer_1"

  validation {
    condition     = can(regex("^(Developer_1|Premium_[1-9][0-9]?)$", var.apim_sku_name))
    error_message = "apim_sku_name must be Developer_1 or Premium_N. Both support VNet injection."
  }
}

variable "apim_virtual_network_type" {
  description = "Internal keeps the gateway reachable only from the VNet. External exposes it publicly while backends stay private."
  type        = string
  default     = "Internal"

  validation {
    condition     = contains(["Internal", "External"], var.apim_virtual_network_type)
    error_message = "apim_virtual_network_type must be Internal or External."
  }
}

variable "apim_publisher_name" {
  description = "Publisher name shown on the APIM developer portal."
  type        = string
  default     = "Platform Engineering"
}

variable "apim_publisher_email" {
  description = "Publisher contact address for APIM notifications."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.apim_publisher_email))
    error_message = "apim_publisher_email must be a valid email address."
  }
}

variable "openai_api_version" {
  description = "Azure OpenAI data plane API version exposed through the gateway."
  type        = string
  default     = "2024-10-21"

  validation {
    condition     = can(regex("^\\d{4}-\\d{2}-\\d{2}(-preview)?$", var.openai_api_version))
    error_message = "openai_api_version must look like 2024-10-21 or 2025-01-01-preview."
  }
}

variable "gateway_audience" {
  description = "Entra ID audience (application ID URI) that callers request a token for. APIM validates it on every call."
  type        = string
  default     = "api://genai-gateway"

  validation {
    condition     = startswith(var.gateway_audience, "api://")
    error_message = "gateway_audience must be an application ID URI starting with api://."
  }
}

variable "teams" {
  description = "Consuming teams. Each one becomes an APIM product with its own tokens per minute and token quota."
  type = map(object({
    display_name       = string
    tokens_per_minute  = number
    token_quota        = number
    token_quota_period = optional(string, "Monthly")
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, t in var.teams : can(regex("^[a-z][a-z0-9-]{2,39}$", k)) && t.tokens_per_minute > 0 && t.token_quota >= t.tokens_per_minute
    ])
    error_message = "Team keys must be lowercase slugs, tokens_per_minute positive and token_quota at least tokens_per_minute."
  }

  validation {
    condition = alltrue([
      for t in values(var.teams) : contains(["Hourly", "Daily", "Weekly", "Monthly", "Yearly"], t.token_quota_period)
    ])
    error_message = "token_quota_period must be Hourly, Daily, Weekly, Monthly or Yearly."
  }
}

# Optional services and observability

variable "enable_content_safety" {
  description = "Deploy an Azure AI Content Safety account behind a private endpoint."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "Retention of the Log Analytics workspace."
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "log_retention_days must be between 30 and 730."
  }
}
