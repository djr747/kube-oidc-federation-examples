# Kubernetes OIDC Federation Examples

Example deployments demonstrating Kubernetes OIDC federation to external identity providers — enabling **zero-secret, cross-cloud workload authentication**.

---

## Why OIDC Federation Matters for Kubernetes

Modern Kubernetes workloads frequently need to access resources in external cloud providers (Azure, AWS, GCP) or third-party services. Historically this meant storing long-lived credentials (client secrets, access keys, certificates) as Kubernetes Secrets — creating a large attack surface, rotation burden, and secret sprawl.

**OIDC federation eliminates all of that.** Instead of secrets, workloads prove their identity using cryptographically signed tokens issued by the Kubernetes API server itself. External identity providers validate these tokens and exchange them for short-lived access tokens — no static credentials ever leave the cluster.

### The Core Problem

```text
Traditional approach (insecure):
  Pod → reads static credential from K8s Secret → authenticates to external cloud

OIDC federation approach (secure):
  Pod → presents signed OIDC token → IDP validates token → issues short-lived access token
```

Static credentials are:

- **Risky** — if leaked, an attacker has persistent access until revoked
- **Operationally expensive** — must be rotated, audited, and distributed securely
- **Hard to scope** — often over-provisioned to avoid breakage during rotation

OIDC federation tokens are:

- **Ephemeral** — short-lived (minutes), automatically refreshed
- **Cryptographically bound** — tied to a specific ServiceAccount in a specific namespace on a specific cluster
- **Zero-touch** — no rotation, no distribution, no secrets to manage

---

## Kubernetes Service Account Token Volume Projection (SIG Auth)

This capability is built on the **Service Account Token Volume Projection** feature, developed under [Kubernetes SIG Auth](https://github.com/kubernetes/community/tree/master/sig-auth) and graduating to stable in Kubernetes v1.20 ([KEP-2799](https://github.com/kubernetes/enhancements/tree/master/keps/sig-auth/2799-reduction-of-secret-based-service-account-token)).

### How It Works

Every Kubernetes cluster runs an OIDC-compliant identity provider as part of the API server. When a ServiceAccount token is projected into a pod, the API server issues a signed JWT containing:

| Claim | Value |
| ------- | ------- |
| `iss` | The cluster's OIDC issuer URL (e.g. `https://oidc.eks.us-east-1.amazonaws.com/id/...`) |
| `sub` | `system:serviceaccount:<namespace>:<service-account-name>` |
| `aud` | Configurable audience (e.g. `api://AzureADTokenExchange`, `sts.amazonaws.com`) |
| `exp` | Short expiration (typically 1 hour) |

The cluster publishes its OIDC discovery document (`/.well-known/openid-configuration`) and JWKS (public signing keys) at the issuer URL. Any external identity provider can validate tokens by fetching these public keys — **no shared secret required**.

### SIG Auth References

- [Service Account Signing Key Retrieval (KEP-3107)](https://github.com/kubernetes/enhancements/tree/master/keps/sig-auth/3107-service-account-signing-key-retrieval) — added API server endpoints for OIDC discovery and JWKS
- [Reduction of Secret-based Service Account Tokens (KEP-2799)](https://github.com/kubernetes/enhancements/tree/master/keps/sig-auth/2799-reduction-of-secret-based-service-account-token) — drives the move from static to projected tokens
- [Bound Service Account Token Volume (KEP-1205)](https://github.com/kubernetes/enhancements/tree/master/keps/sig-auth/1205-bound-service-account-tokens) — the underlying projection mechanism
- [Service Account Token Volume Projection docs](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/#serviceaccount-token-volume-projection) — official Kubernetes documentation

---

## General Architecture

The following diagram shows the universal pattern for Kubernetes OIDC federation, regardless of which external identity provider is involved:

```mermaid
flowchart TB
    subgraph K8s["Kubernetes Cluster"]
        API["API Server<br/>(OIDC Issuer)"]
        SA["ServiceAccount"]
        POD["Pod"]
        TV["Projected Token Volume<br/>(signed JWT)"]
        
        SA -->|"bound to"| POD
        API -->|"issues signed token"| TV
        TV -->|"mounted into"| POD
    end

    subgraph OIDC["OIDC Discovery (Public Endpoint)"]
        DISC["/.well-known/openid-configuration"]
        JWKS["JWKS (public signing keys)"]
    end

    subgraph IDP["External Identity Provider"]
        VAL["Token Validation"]
        EXCHANGE["Token Exchange"]
        ACCESS["Short-lived Access Token"]
        
        VAL --> EXCHANGE --> ACCESS
    end

    subgraph TARGET["Target Cloud Resource"]
        RES["Cloud Service<br/>(Key Vault, S3, etc.)"]
    end

    API -->|"publishes"| DISC
    API -->|"publishes"| JWKS
    POD -->|"1. Presents OIDC token"| VAL
    IDP -->|"2. Fetches JWKS to verify signature"| JWKS
    ACCESS -->|"3. Pod uses access token"| RES

    style K8s fill:#326CE5,color:#fff
    style IDP fill:#FF9900,color:#000
    style TARGET fill:#00A4EF,color:#fff
    style OIDC fill:#2ECC71,color:#fff
```

### Trust Establishment

Before any token exchange can happen, a **federated identity credential** (or trust relationship) must be registered with the external identity provider. This one-time configuration says:

> *"I trust tokens from issuer X, for subject Y, with audience Z."*

| Field | Example |
| ------- | --------- |
| **Issuer** | `https://oidc.eks.us-east-1.amazonaws.com/id/ABCDEF123456` |
| **Subject** | `system:serviceaccount:my-namespace:my-service-account` |
| **Audience** | `api://AzureADTokenExchange` |

This is the **only configuration needed** — no secrets, no certificates, no key distribution.

---

## Token Exchange Flow

```mermaid
sequenceDiagram
    participant Pod as Pod (Workload)
    participant KAS as K8s API Server
    participant IDP as External IDP<br/>(e.g. Entra ID)
    participant Res as Cloud Resource<br/>(e.g. Key Vault)

    Note over Pod,KAS: Startup: token projected into pod volume
    KAS->>Pod: Signed OIDC JWT (short-lived)

    Pod->>IDP: Token exchange request<br/>(OIDC token + client_id + audience)
    
    Note over IDP: Validates token:
    Note over IDP: 1. Fetch JWKS from issuer
    Note over IDP: 2. Verify JWT signature
    Note over IDP: 3. Check issuer, subject, audience<br/>   match federated credential
    Note over IDP: 4. Check token not expired

    IDP->>Pod: Access token (short-lived)

    Pod->>Res: API call with access token
    Res->>Pod: Response (e.g. secret value)

    Note over Pod: Token auto-refreshed<br/>before expiry by kubelet
```

---

## Demo Catalogue

The table below lists the available use-case demonstrations. Each demo is a self-contained deployment in the `demos/` directory with its own README, Terraform configuration, and step-by-step instructions.

| # | Demo | Source → Target | Description | Status |
| --- | ------ | ----------------- | ------------- | -------- |
| 1 | [EKS → Azure Workload Identity](demos/eks-azure-workload-identity/) | AWS EKS → Azure (Entra ID) | Pod on EKS authenticates to Azure Key Vault using OIDC federation and the Azure Workload Identity webhook — zero secrets | ✅ Available |
| 2 | K3s → AWS (IRSA) | K3s (on-prem) → AWS | *Planned* | 🔜 Coming soon |
| 3 | AKS → AWS (IRSA) | Azure AKS → AWS | *Planned* | 🔜 Coming soon |
| 4 | OCP → Azure (Entra ID) | OpenShift (on-prem) → Azure (Entra ID) | *Planned* | 🔜 Coming soon |

---

## Demo 1: EKS → Azure Workload Identity

**Directory:** [`demos/eks-azure-workload-identity/`](demos/eks-azure-workload-identity/)

This demo provisions a minimal, cost-optimised AWS EKS cluster and installs the [Azure Workload Identity](https://azure.github.io/azure-workload-identity/) webhook. A sample `msal-go` application running on EKS authenticates to Azure Key Vault **without any static credentials** by exchanging its Kubernetes OIDC token for an Entra ID access token.

### Demo Architecture

```mermaid
flowchart LR
    subgraph AWS["AWS (EKS Cluster)"]
        direction TB
        VPC["VPC 10.0.0.0/16"]
        EKS["EKS Control Plane<br/>OIDC Issuer enabled"]
        NG["Node Group<br/>Spot instances (public subnets)"]
        
        subgraph PODS["Kubernetes Resources"]
            CM["cert-manager"]
            WH["Azure WI Webhook<br/>(mutating admission)"]
            NS["Namespace: msal-go-demo"]
            SA["ServiceAccount: msal-go-sa<br/>annotated with azure client-id"]
            APP["msal-go Pod<br/>label: azure.workload.identity/use"]
        end

        VPC --- EKS --- NG
        NG --- PODS
        WH -->|"injects env vars +<br/>projected token volume"| APP
        CM -->|"TLS certs"| WH
    end

    subgraph AZURE["Azure (Entra ID)"]
        ENT["Entra App Registration"]
        FIC["Federated Identity Credential<br/>issuer: EKS OIDC URL<br/>subject: system:serviceaccount:msal-go-demo:msal-go-sa<br/>audience: api://AzureADTokenExchange"]
        KV["Azure Key Vault<br/>Secret: 'Hello from Key Vault!'"]
        
        ENT --- FIC
        ENT -->|"get secret permission"| KV
    end

    APP -->|"1. Present OIDC token"| ENT
    ENT -->|"2. Validate via JWKS"| EKS
    ENT -->|"3. Return access token"| APP
    APP -->|"4. GET secret"| KV

    style AWS fill:#FF9900,color:#000
    style AZURE fill:#0078D4,color:#fff
    style PODS fill:#326CE5,color:#fff
```

### Demo Token Exchange Flow

```mermaid
sequenceDiagram
    participant Kubelet
    participant Pod as msal-go Pod
    participant Webhook as Azure WI Webhook
    participant EKS as EKS OIDC Issuer
    participant Entra as Entra ID
    participant KV as Azure Key Vault

    Note over Kubelet,Webhook: Pod Creation
    Kubelet->>Webhook: Pod admission request
    Webhook->>Webhook: Detects label<br/>azure.workload.identity/use: true
    Webhook->>Kubelet: Mutated pod spec:<br/>+ env vars (CLIENT_ID, TENANT_ID, etc.)<br/>+ projected token volume

    Note over Kubelet,Pod: Pod Starts
    Kubelet->>Pod: Mounts projected OIDC token<br/>at /var/run/secrets/azure/tokens/

    loop Every 60 seconds
        Pod->>Pod: MSAL reads AZURE_FEDERATED_TOKEN_FILE
        Pod->>Entra: POST /oauth2/v2.0/token<br/>(grant_type=client_credentials<br/>+ client_assertion=OIDC token)
        Entra->>EKS: GET /.well-known/openid-configuration<br/>+ JWKS keys
        EKS->>Entra: Public signing keys
        Entra->>Entra: Verify JWT signature,<br/>issuer, subject, audience
        Entra->>Pod: Access token
        Pod->>KV: GET /secrets/test-secret
        KV->>Pod: "Hello from Key Vault!"
    end
```

### What Gets Deployed

| Layer | Resources |
| ------- | ----------- |
| **AWS Networking** | VPC, 3 public + 3 private subnets, Internet Gateway (no NAT GW for cost savings) |
| **AWS Compute** | EKS v1.34 control plane, Spot node group (`t3a.small`) in public subnets |
| **AWS IAM** | OIDC provider, IRSA role for the demo pod |
| **Kubernetes** | cert-manager, Azure Workload Identity webhook, `msal-go-demo` namespace + ServiceAccount |
| **Azure** | Federated identity credential on pre-existing Entra App Registration |
| **Demo App** | `msal-go` container that reads a Key Vault secret every 60s |

### Quick Start

See the full [EKS → Azure Workload Identity README](demos/eks-azure-workload-identity/README.md) for prerequisites, step-by-step instructions, and troubleshooting.

---

## Repository Structure

```text
kube-oidc-federation-examples/
├── README.md                              ← You are here
├── LICENSE
└── demos/
    └── eks-azure-workload-identity/       ← Demo 1
        ├── README.md                      ← Full walkthrough
        ├── main.tf                        ← Provider config + cluster readiness
        ├── vpc.tf                         ← VPC, subnets, IGW
        ├── eks.tf                         ← EKS cluster + node group
        ├── iam.tf                         ← IRSA role for demo pod
        ├── helm.tf                        ← cert-manager + WI webhook Helm charts
        ├── kubernetes.tf                  ← Namespace, ServiceAccount, msal-go Deployment
        ├── federation.tf                  ← Automatic federated credential setup
        ├── variables.tf                   ← Input variables
        ├── outputs.tf                     ← Useful outputs (kubeconfig, logs, etc.)
        ├── versions.tf                    ← Provider version constraints
        ├── backend.tf                     ← State backend config
        └── scripts/
            └── configure-federation.sh    ← az CLI script for federation
```

---

## Contributing

To add a new demo:

1. Create a directory under `demos/` with a descriptive name (e.g. `gke-aws-irsa`)
2. Include a self-contained Terraform (or equivalent) configuration
3. Write a comprehensive `README.md` with prerequisites, architecture, quick-start steps, and teardown instructions
4. Update the **Demo Catalogue** table in this root README

---

## License

See [LICENSE](LICENSE).
