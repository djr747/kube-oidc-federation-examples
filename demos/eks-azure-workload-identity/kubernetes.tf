# ── Demo application namespace ───────────────────────────────────────────────

resource "kubernetes_namespace_v1" "app" {
  metadata {
    name = var.app_namespace

    labels = {
      "azure.workload.identity/use" = "true"
    }
  }

  # Wait for the cluster API to be fully operational, cert-manager and the
  # webhook to be ready. This ensures the Kubernetes provider can authenticate
  # and create resources without "Unauthorized" errors.
  depends_on = [
    null_resource.wait_for_cluster_api,
    helm_release.cert_manager,
    helm_release.azure_workload_identity_webhook,
  ]
}

# ── Demo application ServiceAccount ─────────────────────────────────────────
# The `azure.workload.identity/client-id` annotation binds this ServiceAccount
# to the Entra Application Registration.  Pods that reference this SA and carry
# the label `azure.workload.identity/use: "true"` will have their token volume
# and environment variables injected by the webhook.

resource "kubernetes_service_account_v1" "app" {
  metadata {
    name      = var.app_service_account_name
    namespace = kubernetes_namespace_v1.app.metadata[0].name

    annotations = {
      # Entra Application (client) ID – links this SA to the Entra App Registration.
      "azure.workload.identity/client-id" = var.azure_client_id

      # Optional: override the token audience (defaults to api://AzureADTokenExchange).
      # "azure.workload.identity/service-account-token-expiry" = "3600"

      # IRSA annotation – lets the pod also assume the AWS IAM role.
      "eks.amazonaws.com/role-arn" = aws_iam_role.app.arn
    }

    labels = {
      "azure.workload.identity/use" = "true"
    }
  }

  depends_on = [kubernetes_namespace_v1.app]
}

# ── msal-go demo Deployment ───────────────────────────────────────────────────
# Deploys the Azure Workload Identity sample application.
# Source: https://github.com/Azure/azure-workload-identity/tree/main/examples/msal-go
#
# The webhook automatically injects into every pod that carries the label
# `azure.workload.identity/use: "true"` and references this ServiceAccount:
#   AZURE_CLIENT_ID           – from the ServiceAccount annotation
#   AZURE_TENANT_ID           – from the webhook configuration
#   AZURE_FEDERATED_TOKEN_FILE – path to the projected service-account token
#   AZURE_AUTHORITY_HOST      – AAD endpoint
#
# The app uses those env vars to exchange the OIDC token for an Azure access
# token and then reads a secret from Key Vault in a loop every 60 seconds.

resource "kubernetes_deployment_v1" "msal_go" {
  metadata {
    name      = "msal-go"
    namespace = kubernetes_namespace_v1.app.metadata[0].name

    labels = {
      app = "msal-go"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "msal-go"
      }
    }

    template {
      metadata {
        labels = {
          app = "msal-go"
          # Required label – tells the webhook to inject Azure Workload Identity
          # environment variables and volume mounts into this pod.
          "azure.workload.identity/use" = "true"
        }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.app.metadata[0].name

        node_selector = {
          "kubernetes.io/os" = "linux"
        }

        container {
          name  = "msal-go"
          image = "ghcr.io/azure/azure-workload-identity/msal-go:latest"

          # The app reads KEYVAULT_URL and SECRET_NAME.  The four Azure env vars
          # (AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_FEDERATED_TOKEN_FILE,
          # AZURE_AUTHORITY_HOST) are injected automatically by the webhook.
          env {
            name  = "KEYVAULT_URL"
            value = var.keyvault_url
          }

          env {
            name  = "SECRET_NAME"
            value = var.keyvault_secret_name
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "64Mi"
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.azure_workload_identity_webhook,
    kubernetes_service_account_v1.app,
  ]
}
