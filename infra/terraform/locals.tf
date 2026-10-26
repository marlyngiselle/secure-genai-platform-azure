locals {
  name = "${var.prefix}-${var.environment}"

  # Globally unique names (custom subdomains, Key Vault) get a short stable suffix.
  suffix = random_string.suffix.result

  tags = merge(
    {
      workload    = "secure-genai-platform"
      environment = var.environment
      managed-by  = "terraform"
    },
    var.tags,
  )

  # One deployment per (instance, model) pair.
  deployments = {
    for pair in setproduct(keys(var.openai_instances), keys(var.model_deployments)) :
    "${pair[0]}-${pair[1]}" => {
      instance   = pair[0]
      deployment = pair[1]
      config     = var.model_deployments[pair[1]]
    }
  }

  private_dns_zones = {
    openai         = "privatelink.openai.azure.com"
    cognitive      = "privatelink.cognitiveservices.azure.com"
    key_vault      = "privatelink.vaultcore.azure.net"
    apim_azure_api = "azure-api.net"
  }

  policy_dir = "${path.module}/../../apim-policies"
}

resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}
