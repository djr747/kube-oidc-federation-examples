# ── cert-manager ──────────────────────────────────────────────────────────────
# cert-manager is required by the Azure Workload Identity webhook to manage
# the webhook's TLS certificates and ValidatingWebhookConfiguration.
# Install it first and wait for it to be ready before deploying the webhook.

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true

  # Pin to a stable release; update as new versions are published.
  version = "v1.19.4"

  set = [
    {
      name  = "installCRDs"
      value = "true"
    },
  ]

  # Ensure the EKS cluster and its node group exist before trying to deploy.
  depends_on = [module.eks]
}

# ── Azure Workload Identity webhook ──────────────────────────────────────────
# The webhook (mutating admission controller) injects the necessary environment
# variables and volume mounts into pods that are labelled with
#   azure.workload.identity/use: "true"
# so that MSAL and other Azure SDKs can obtain tokens via federated credentials.
#
# REQUIRES: cert-manager must be deployed first to manage TLS certificates.

resource "helm_release" "azure_workload_identity_webhook" {
  name             = "azure-workload-identity-webhook"
  repository       = "https://azure.github.io/azure-workload-identity/charts"
  chart            = "workload-identity-webhook"
  namespace        = "azure-workload-identity-system"
  create_namespace = true

  # Pin to the latest stable release; update as new versions are published.
  version = "1.5.1"

  set = [
    {
      name  = "azureTenantID"
      value = var.azure_tenant_id
    },
  ]

  # Ensure cert-manager is deployed and ready before deploying the webhook.
  depends_on = [helm_release.cert_manager]
}
