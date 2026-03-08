locals {
  azs = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${var.cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = local.azs
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  # No NAT Gateway – worker nodes run in public subnets and receive public IPs
  # directly from the Internet Gateway, eliminating the ~$0.045/hr NAT Gateway
  # charge.  The EKS control-plane ENIs remain in the private subnets and
  # communicate internally; they do not need a NAT Gateway.
  enable_nat_gateway = false

  # Assign public IPs to instances launched in the public subnets so that the
  # EKS worker nodes can reach ECR and the Kubernetes API server without NAT.
  map_public_ip_on_launch = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags required for the EKS cluster and Kubernetes cloud-controller-manager
  # to discover subnets automatically.
  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  }

  tags = var.tags
}
