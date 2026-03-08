# ── AWS Configuration ─────────────────────────────────────────────────────────────
# All variables can be set via environment variables. See .env.example for a
# template that documents all available options.

variable "aws_region" {
  description = "AWS region to deploy resources into."
  type        = string
  default     = "us-east-1"
  # Set via environment variable: export TF_VAR_aws_region=<region>
}

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster."
  type        = string
  default     = "1.34"
}

variable "node_desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes."
  type        = number
  default     = 2
}

# ── Azure / Entra ──────────────────────────────────────────────────────────────

variable "azure_tenant_id" {
  description = "Entra (Azure AD) tenant ID used by the Azure Workload Identity webhook."
  type        = string
}

variable "azure_client_id" {
  description = <<-EOT
    Client ID of the Entra Application Registration for the demo workload.
    This value is injected as the `azure.workload.identity/client-id` annotation
    on the Kubernetes ServiceAccount and is required to establish the federated
    identity credential in Entra.

    Set via environment variable: export TF_VAR_azure_client_id=<value>
  EOT
  type        = string
}

variable "azure_app_object_id" {
  description = <<-EOT
    Object ID of the Entra Application Registration (NOT the client ID).
    This is required to automatically configure the federated identity credential
    that enables the EKS ServiceAccount to exchange OIDC tokens for Entra access tokens.
    Find this in the Azure Portal under your app registration's Overview page,
    or retrieve it with: az ad app show --id <client-id> --query id --output tsv

    Set via environment variable: export TF_VAR_azure_app_object_id=<value>
  EOT
  type        = string
}

variable "setup_federation" {
  description = <<-EOT
    Automatically configure the Entra federated identity credential during
    Terraform apply. Requires az CLI to be installed and authenticated.
    Set to false if you prefer to run the federation setup manually afterward.

    Set via environment variable: export TF_VAR_setup_federation=true
  EOT
  type        = bool
  default     = true
}

# ── Demo application ───────────────────────────────────────────────────────────

variable "app_namespace" {
  description = "Kubernetes namespace for the demo application."
  type        = string
  default     = "msal-go-demo"
}

variable "app_service_account_name" {
  description = "Kubernetes ServiceAccount name for the demo application."
  type        = string
  default     = "msal-go-sa"
}

# ── Azure Key Vault (msal-go demo app) ────────────────────────────────────────

variable "keyvault_url" {
  description = <<-EOT
    Full URI of the Azure Key Vault that the msal-go demo pod will read from.
    Example: https://my-kv.vault.azure.net/
    Create the vault with:
      az keyvault create -n <name> -g <rg> --location eastus
    then grant the App Registration GET permission:
      az keyvault set-policy -n <name> --secret-permissions get \
        --spn <application-client-id>

    Set via environment variable: export TF_VAR_keyvault_url=<url>
  EOT
  type        = string
}

variable "keyvault_secret_name" {
  description = <<-EOT
    Name of the secret inside the Azure Key Vault that the msal-go app will
    retrieve to prove end-to-end federated authentication is working.
    Create the secret with:
      az keyvault secret set -n <secret-name> --vault-name <vault-name> --value "Hello!"

    Set via environment variable: export TF_VAR_keyvault_secret_name=<name>
  EOT
  type        = string
}

# ── Tagging ────────────────────────────────────────────────────────────────────

variable "tags" {
  description = "Common tags applied to all AWS resources."
  type        = map(string)
  default = {
    Project     = "eks-azure-workload-identity-demo"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}
