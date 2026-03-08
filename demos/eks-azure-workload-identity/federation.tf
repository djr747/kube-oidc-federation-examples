# ── Automatic Entra Federated Identity Credential Configuration ──────────────

# This resource automatically configures the federated identity credential on
# the Entra Application Registration, enabling the EKS ServiceAccount to exchange
# its OIDC token for Entra access tokens. This completes the end-to-end setup.
#
# Prerequisites:
#   - Azure CLI must be installed and authenticated: az login
#   - The Entra Application Registration must already exist
#   - The Object ID of the Entra app (NOT the client ID) is required
#
# Usage:
#   export TF_VAR_azure_app_object_id=<your-app-object-id>
#   export TF_VAR_setup_federation=true
#   terraform apply

resource "null_resource" "configure_federation" {
  count = var.setup_federation && var.azure_app_object_id != "" ? 1 : 0

  provisioner "local-exec" {
    command = "${path.module}/scripts/configure-federation.sh --app-object-id ${var.azure_app_object_id} --issuer ${module.eks.cluster_oidc_issuer_url} --namespace ${var.app_namespace} --service-account ${var.app_service_account_name}"
  }

  # Ensure service account is created before attempting federation setup
  depends_on = [
    kubernetes_service_account_v1.app,
  ]
}

# Output for manual federation setup if automation was disabled
output "federation_setup_command" {
  description = "Command to manually configure the Entra federated identity credential if setup_federation is disabled."
  value       = var.setup_federation ? "Federation configured automatically." : "To manually configure federation, run: ./scripts/configure-federation.sh --app-object-id <OBJECT_ID> --issuer ${module.eks.cluster_oidc_issuer_url} --namespace ${var.app_namespace} --service-account ${var.app_service_account_name}"
}
