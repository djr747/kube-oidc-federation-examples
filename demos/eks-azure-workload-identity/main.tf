# ── AWS provider ──────────────────────────────────────────────────────────────

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}

# ── Wait for the EKS cluster API to be fully operational ──────────────────────
# The API takes time to initialize after the cluster is created.  Use `aws eks wait`
# to block until the cluster is ready before fetching auth tokens or creating
# Kubernetes resources. This prevents "Unauthorized" errors in the providers.

resource "null_resource" "wait_for_cluster_api" {
  provisioner "local-exec" {
    command = "aws eks wait cluster-active --name ${module.eks.cluster_name} --region ${var.aws_region}"
  }

  depends_on = [module.eks]
}

# ── Data sources needed to bootstrap the Helm / Kubernetes providers ──────────

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name

  depends_on = [null_resource.wait_for_cluster_api]
}

# ── Helm provider ──────────────────────────────────────────────────────────────

provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

# ── Kubernetes provider ────────────────────────────────────────────────────────

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}
