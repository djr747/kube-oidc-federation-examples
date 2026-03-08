# EKS – Azure Workload Identity Demo

This Terraform stack provisions a minimal, cost-optimised AWS EKS cluster and
installs the **Azure Workload Identity webhook** via Helm.  It demonstrates how
a Kubernetes workload running on EKS can authenticate to Azure services (e.g.
Key Vault, Microsoft Graph) **without managing any secrets** by using OIDC
federation between the EKS cluster and an Entra Application Registration.

```text
AWS EKS (OIDC provider)
  └── Pod with projected service-account token
        └── MSAL  ─── exchanges OIDC token ──▶  Entra ID  ──▶  Azure resource
```

---

## Architecture

| Component | Details |
| ----------- | --------- |
| **Region** | `us-east-1` (cheapest) |
| **EKS version** | 1.32 |
| **Node group** | `t3.micro` Spot instances (min 1 / desired 2 / max 3) in **public subnets** (no NAT GW) |
| **Networking** | New VPC, 3 private + 3 public subnets; control-plane ENIs in private, worker nodes in public |
| **State backend** | S3 bucket `drocx-s3-bucket` |
| **Azure WI webhook** | `workload-identity-webhook` Helm chart v1.5.1, `azure-workload-identity-system` namespace |
| **Demo workload** | `msal-go` Deployment (`ghcr.io/azure/azure-workload-identity/msal-go:latest`) in namespace `msal-go-demo` |

---

## Prerequisites

| Tool | Minimum version |
| ------ | ---------------- |
| Terraform | ≥ 1.5.0 |
| AWS CLI | ≥ 2.x (authenticated) – see login instructions below |
| Azure CLI (`az`) | ≥ 2.50 (authenticated) – **required before running Terraform** |
| kubectl | ≥ 1.28 |
| helm | ≥ 3.x |

### AWS Credential Configuration

Before running `terraform` you need valid AWS credentials.  There are a few common ways to obtain them:

* **AWS SSO / Entra** – if your organisation uses AWS SSO (often backed by Entra ID) you can authenticate with:

  ```bash
  aws sso login --profile terraform-profile
  ```

  The command opens a browser, you sign in with your email/password, and the CLI caches short‑lived credentials under `terraform-profile`.

* **IAM user / access keys** – if you just have an AWS account and an IAM user (email/password for the console) you must first create or retrieve an access key & secret key in the AWS Console.  Then run:

  ```bash
  aws configure --profile terraform-profile
  ```

  and enter the key pair when prompted; you may also specify a default region and output format.

* **Assume‑role or environment variables** – advanced users can export credentials directly or have their profile assume a role.

Once a profile is configured you can tell Terraform to use it:

```bash
export AWS_PROFILE=terraform-profile
```

AWS credentials must have permissions to create VPCs, EKS clusters, IAM roles, and EC2 instances.

### Azure CLI Authentication ⚠️ **Required**

Before running `terraform apply`, **you must authenticate with the Azure CLI**. This is essential because Terraform will automatically configure the Entra federated identity credential using the `az` CLI.

```bash
# Log in to Azure
az login

# Verify your login
az account show
```

**Note:** The `az` CLI authentication is required because Terraform will automatically configure the federation during the `terraform apply` command (step 5) when `TF_VAR_setup_federation=true` is set.

### State Backend Configuration

By default, Terraform uses **local state storage** (state file on your machine). This is fine for demos and development.

To use an **S3 backend** instead (for team collaboration):

1. Ensure an S3 bucket exists
2. Initialize Terraform with backend flags:

   ```bash
   terraform init \
     -backend-config="bucket=my-bucket" \
     -backend-config="key=eks-azure-workload-identity/terraform.tfstate" \
     -backend-config="region=us-east-1"
   ```

See [backend.tf](backend.tf) for more details.

---

## Quick Start

### 1 – Authenticate with Azure CLI

```bash
az login
az account show  # Verify successful login
```

This step must be completed before running Terraform (see *Prerequisites* above).

### 2 – Create an Entra Application Registration

In the Azure Portal (or via az CLI) create an **App Registration** for your demo workload and note down:

* **Application (client) ID** – you will use this as `TF_VAR_azure_client_id`
* **Object ID** – you will use this as `TF_VAR_azure_app_object_id`

**Get the Object ID:**

```bash
az ad app show --id <YOUR-CLIENT-ID> --query id --output tsv
```

### 3 – Create an Azure Key Vault and a secret

> Skip this step if you already have a Key Vault and a secret.

```bash
# Create a resource group (any region is fine – Key Vault is global)
az group create -n azwi-demo-rg -l eastus

# Create the Key Vault
az keyvault create -n <YOUR-KV-NAME> -g azwi-demo-rg -l eastus

# Store a test secret
az keyvault secret set -n test-secret --vault-name <YOUR-KV-NAME> --value "Hello from Key Vault!"

# Grant your Entra App Registration GET access to secrets
az keyvault set-policy -n <YOUR-KV-NAME> \
  --secret-permissions get \
  --spn <YOUR-ENTRA-APP-CLIENT-ID>
```

### 4 – Configure Terraform variables via environment variables

Instead of creating a `terraform.tfvars` file, export the required variables as environment variables:

```bash
# Copy the example file
cp .env.example .env

# Edit .env with your values (see comments for guidance)
# Required/important values:
#   - AWS_PROFILE                      (if you configured an AWS profile)
#   - TF_VAR_azure_client_id           (from step 2)
#   - TF_VAR_azure_app_object_id       (from step 2)
#   - TF_VAR_setup_federation=true     (to enable automatic federation setup)
#   - TF_VAR_keyvault_url              (from step 3)
#   - TF_VAR_keyvault_secret_name      (from step 3)

# Source the environment file to load all variables
source .env

# Verify the critical variables are set
echo $AWS_PROFILE
echo $TF_VAR_azure_client_id
echo $TF_VAR_azure_app_object_id
echo $TF_VAR_setup_federation
```

Alternatively, export variables directly without using `.env`:

```bash
export AWS_PROFILE="terraform-profile"  # only if using an AWS profile
export TF_VAR_azure_client_id="<YOUR-CLIENT-ID>"
export TF_VAR_azure_app_object_id="<YOUR-OBJECT-ID>"
export TF_VAR_setup_federation=true  # Enable automatic federation setup
export TF_VAR_keyvault_url="https://<YOUR-KEYVAULT-NAME>.vault.azure.net/"
export TF_VAR_keyvault_secret_name="my-secret"
```

### 5 – Initialize and apply (includes automatic federation setup)

```bash
cd demos/eks-azure-workload-identity

terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Provisioning takes approximately **15–20 minutes**.  `terraform apply` will:

1. Create the VPC, EKS cluster, and IAM roles.
2. Deploy the Azure Workload Identity webhook via Helm.
3. Create the `msal-go-demo` namespace and the `msal-go-sa` ServiceAccount.
4. Deploy the **msal-go** sample application (`ghcr.io/azure/azure-workload-identity/msal-go:latest`).
5. **Automatically configure the Entra federated identity credential** (because `TF_VAR_setup_federation=true`).

The federation setup is crucial – without it, the msal-go pod will crash because it won't be able to exchange its OIDC token for an Entra access token.

### 6 – Create a temporary kubeconfig

```bash
$(terraform output -raw kubeconfig_command_temp)
```

Then set the environment variable to use it:

```bash
export KUBECONFIG=/tmp/drocx_kubeconfig
```

(Or omit this step and update your regular kubeconfig with `$(terraform output -raw kubeconfig_command)` if you prefer.)

### 7 – Verify the cluster is accessible

Now that the cluster is fully deployed and federation is configured, verify that kubectl can access the cluster:

```bash
# Verify the temporary kubeconfig is set
echo $KUBECONFIG

# Test cluster access
kubectl cluster-info

# List the namespaces – you should see the azure-workload-identity-system and msal-go-demo namespaces
kubectl get namespaces

# Check the msal-go pod is running
kubectl get pods -n msal-go-demo
```

### 8 – Verify end-to-end authentication

With the federated credential in place, the msal-go pod can now exchange its OIDC token for an Azure access token and read the Key Vault secret.

**Make sure your temporary kubeconfig is in use:**

```bash
export KUBECONFIG=/tmp/drocx_kubeconfig
# Or if you're using your regular kubeconfig, that works too
```

**Inspect the pod and injected environment variables:**

```bash
# Inspect the env vars and volumes the webhook injected into the pod
$(terraform output -raw msal_go_describe_command)
```

Look for these injected environment variables under the container section:

| Variable | Description |
| ---------- | ------------- |
| `AZURE_CLIENT_ID` | From the ServiceAccount annotation |
| `AZURE_TENANT_ID` | From the webhook configuration |
| `AZURE_FEDERATED_TOKEN_FILE` | Path to the projected OIDC token |
| `AZURE_AUTHORITY_HOST` | AAD endpoint |

**Stream the pod logs to verify successful Key Vault access:**

```bash
# Stream the pod logs – a successful run prints the secret value every 60 s
$(terraform output -raw msal_go_logs_command)
```

Expected log output when the federated identity is working:

```text
I<timestamp> main.go] "successfully got secret" secret="Hello from Key Vault!"
```

This log message proves that the end-to-end scenario is working:

1. ✅ The pod retrieved its OIDC token from the projected volume
2. ✅ The token was successfully exchanged for an Entra access token  
3. ✅ The access token was used to authenticate to Azure Key Vault
4. ✅ The secret was retrieved from Key Vault

If you see an authentication or permission error, double-check that:

1. The federated credential issuer / subject / audience match the Terraform
   outputs exactly.
2. The App Registration has `get` permission on the Key Vault secrets.

---

## Terraform outputs

| Output | Description |
| -------- | ------------- |
| `cluster_name` | EKS cluster name |
| `cluster_endpoint` | Kubernetes API server URL |
| `cluster_oidc_issuer_url` | OIDC issuer (also `federation_issuer`) |
| `federation_subject` | Subject for the federated credential |
| `federation_audience` | Audience for the federated credential |
| `app_iam_role_arn` | IRSA IAM role ARN |
| `kubeconfig_command` | Command to configure kubectl |
| `msal_go_logs_command` | Command to stream msal-go pod logs |
| `msal_go_describe_command` | Command to inspect webhook-injected env vars |

---

## Troubleshooting

### Node group creation appears stuck

Managed node groups can take several minutes to provision. Terraform will
wait until the AWS service reports the node group as `ACTIVE` and this
process may look like "stuck" if the console is left idle. If progress
seems to halt:

1. **Check the AWS console** – navigate to **EKS → your cluster → Compute →
   Node groups** and inspect the status and any failure messages.
2. **Use the AWS CLI**:

   ```bash
   aws eks describe-nodegroup \
     --cluster-name $(terraform output -raw cluster_name) \
     --nodegroup-name ${var.cluster_name}-spot
   ```

   Look for `status` and `update`/`health` details.
3. **Spot capacity** – on the `t3.micro` Spot pool may be no capacity; the
   nodegroup will retry automatically but may remain `CREATE_PENDING` or
   `INSTANCE_UNAVAILABLE`. Consider switching to `capacity_type = "ON_DEMAND"`
   or a larger instance type for reliability.
4. **IAM / subnet issues** – ensure the IAM role created by the module has
   the required policies and that the selected subnets have free IPs and are
   in the same availability zones as the cluster control plane.
5. **AWS quotas** – verify your account has sufficient EC2 instance quotas in
   the region.

Once you identify and resolve the underlying issue, re-run
`terraform apply` to continue provisioning the node group.

## Tearing down

```bash
cd demos/eks-azure-workload-identity
terraform destroy
```

> **Note:** Spot instances are reclaimed by AWS and replaced automatically, so
> brief interruptions are expected.  This cluster is for demo purposes only.
>
> **Helm warnings during destroy:** You may see warnings like `Helm uninstall returned an information message` about cert-manager CRDs (Custom Resource Definitions) being retained. This is expected behavior and safe to ignore – cert-manager leaves these CRDs behind by design. All AWS resources will be properly cleaned up.

---

## Cost estimate (us-east-1)

Worker nodes are placed in **public subnets** so they receive public IPs directly
from the Internet Gateway.  This eliminates the need for a NAT Gateway and saves
approximately **$0.045/hr (~$1.08/day, ~$32/month)** compared to a
private-subnet design.

| Resource | Approx. cost |
| -------- | ------------- |
| EKS control plane | ~$0.10/hr |
| 2× t3.micro Spot | ~$0.003/hr each |
| **Total (running)** | **~$0.11/hr** |

> **Trade-off:** Running nodes in public subnets is less secure than private
> subnets because the node's public IP is reachable from the internet (though
> security groups still restrict traffic).  For a demo / dev environment this is
> acceptable.  If you need private nodes, set `enable_nat_gateway = true` and
> `single_nat_gateway = true` in `vpc.tf` and change the EKS module's
> `subnet_ids` back to `module.vpc.private_subnets`.

Destroy the stack when not in use to avoid charges.
