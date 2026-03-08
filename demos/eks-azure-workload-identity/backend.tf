terraform {
  # ── S3 backend (optional) ─────────────────────────────────────────────────
  # To enable remote state storage, uncomment the backend block below and update
  # the bucket name. You can also supply these values via command-line flags:
  #   terraform init \
  #     -backend-config="bucket=my-bucket" \
  #     -backend-config="key=demos/eks-azure-workload-identity/terraform.tfstate" \
  #     -backend-config="region=us-east-1"
  #
  # For local state only, simply leave this commented out and run terraform init
  # without the -backend-config flags.
  #
  # backend "s3" {
  #   bucket = "my-s3-bucket"
  #   key    = "demos/eks-azure-workload-identity/terraform.tfstate"
  #   region = "us-east-1"
  # }
}
