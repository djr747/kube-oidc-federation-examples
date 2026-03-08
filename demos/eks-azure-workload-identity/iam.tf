locals {
  oidc_issuer = module.eks.cluster_oidc_issuer_url
  # Strip the https:// prefix – used in IAM trust policy conditions.
  oidc_issuer_host = replace(local.oidc_issuer, "https://", "")
}

# ── IRSA IAM role for the demo workload ──────────────────────────────────────
# This role is optional – it lets the msal-go pod call AWS APIs (e.g. STS) in
# addition to authenticating to Azure via workload identity federation.

data "aws_iam_policy_document" "app_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_host}:sub"
      values   = ["system:serviceaccount:${var.app_namespace}:${var.app_service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "${var.cluster_name}-msal-go-irsa"
  assume_role_policy = data.aws_iam_policy_document.app_assume_role.json
  description        = "IRSA role for the msal-go demo workload in ${var.cluster_name}"

  tags = var.tags
}

# Attach a minimal inline policy – expand this if the workload needs AWS access.
resource "aws_iam_role_policy" "app_inline" {
  name = "sts-get-caller-identity"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sts:GetCallerIdentity"]
        Resource = "*"
      }
    ]
  })
}
