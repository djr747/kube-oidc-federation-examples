# ── Cluster ────────────────────────────────────────────────────────────────────

output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data for the cluster."
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL of the EKS cluster (used as the identity-provider URI when configuring Entra federated credentials)."
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider associated with the EKS cluster."
  value       = module.eks.oidc_provider_arn
}

# ── Convenience: kubeconfig update command ────────────────────────────────────

output "kubeconfig_command" {
  description = "Run this command to update your local kubeconfig for the new cluster."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "kubeconfig_command_temp" {
  description = "Run this command to save the kubeconfig to a temporary file instead of ~/.kube/config."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name} --kubeconfig /tmp/demo_kubeconfig"
}

# ── Azure Workload Identity federation ────────────────────────────────────────
# Use the values below when adding a Federated Identity Credential to your
# Entra Application Registration (via the Azure Portal, az CLI, or the
# scripts/configure-federation.sh helper included in this repo).

output "federation_issuer" {
  description = "Issuer URI to supply when creating the Entra Federated Identity Credential."
  value       = module.eks.cluster_oidc_issuer_url
}

output "federation_subject" {
  description = "Subject identifier to supply when creating the Entra Federated Identity Credential."
  value       = "system:serviceaccount:${var.app_namespace}:${var.app_service_account_name}"
}

output "federation_audience" {
  description = "Audience to supply when creating the Entra Federated Identity Credential (use the default unless you have a specific reason to change it)."
  value       = "api://AzureADTokenExchange"
}

# ── IRSA role ──────────────────────────────────────────────────────────────────

output "app_iam_role_arn" {
  description = "ARN of the IRSA IAM role attached to the demo ServiceAccount."
  value       = aws_iam_role.app.arn
}

# ── msal-go verification ──────────────────────────────────────────────────────

output "msal_go_logs_command" {
  description = "Run this command to stream the msal-go pod logs and verify end-to-end Azure Workload Identity authentication."
  value       = "kubectl logs -n ${var.app_namespace} -l app=msal-go --follow"
}

output "msal_go_describe_command" {
  description = "Run this command to inspect the env vars and volumes injected by the Azure Workload Identity webhook."
  value       = "kubectl describe pod -n ${var.app_namespace} -l app=msal-go"
}
