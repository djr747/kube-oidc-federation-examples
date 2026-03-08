module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  # In v21 the input variable is `name` (was `cluster_name` in v20).
  name               = var.cluster_name
  kubernetes_version = var.cluster_version

  # Expose the Kubernetes API server on the public internet so you can reach it
  # from a local workstation without a VPN.  For tighter security, set
  # endpoint_public_access_cidrs to your own IP range.
  endpoint_public_access = true

  vpc_id = module.vpc.vpc_id

  # Control-plane ENIs stay in private subnets (best practice).
  control_plane_subnet_ids = module.vpc.private_subnets

  # Worker nodes run in public subnets – they get public IPs via the Internet
  # Gateway, so no NAT Gateway is required.  This saves ~$0.045/hr.
  subnet_ids = module.vpc.public_subnets

  # Enable the IAM OIDC provider so IRSA and the Azure Workload Identity webhook
  # can work with pod identity.  Defaults to true in v21, kept explicit here for
  # clarity.
  enable_irsa = true

  # Install the standard EKS add-ons so the cluster is fully functional.
  # Required when bootstrap_self_managed_addons = false (the v21 module default).
  # Ensure networking addons are created before compute so nodes bootstrap
  # with the CNI present: `vpc-cni` and `kube-proxy` use `before_compute`.
  addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true, before_compute = true }
    vpc-cni    = { most_recent = true, before_compute = true }
  }

  # ── Managed node group ─────────────────────────────────────────────────────
  eks_managed_node_groups = {
    spot = {
      name = "${var.cluster_name}-spot"

      # t3.micro (1 vCPU / 1 GiB) is the smallest supported instance type.
      # Note: system DaemonSets consume a significant portion of this capacity;
      # the cluster is intentionally minimal for demo / cost-saving purposes.
      instance_types = ["t3a.small"]
      capacity_type  = "SPOT"

      desired_size = var.node_desired_size
      min_size     = var.node_min_size
      max_size     = var.node_max_size

      # Allow the webhook injector and MSAL workload pods to be scheduled.
      labels = {
        Environment  = "demo"
        SpotInstance = "true"
      }

      tags = var.tags
    }
  }

  # Grant the identity that runs Terraform admin access to the cluster so that
  # subsequent Helm and Kubernetes provider calls succeed without a separate
  # access-entry step.
  enable_cluster_creator_admin_permissions = true

  tags = var.tags
}
