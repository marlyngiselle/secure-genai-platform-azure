# Remote state lives in a storage account reached with Entra ID, never with an access key.
# Values are supplied at init time: terraform init -backend-config=backend.hcl
terraform {
  backend "azurerm" {
    use_azuread_auth = true
  }
}
