#!/usr/bin/env bash
# configure-federation.sh
#
# Adds (or updates) a Federated Identity Credential on an Entra Application
# Registration so that the Kubernetes ServiceAccount in the EKS cluster can
# exchange its projected OIDC token for an Entra access token.
#
# Usage:
#   ./scripts/configure-federation.sh \
#       --app-object-id  <Entra App OBJECT ID>   \
#       --issuer         <EKS OIDC Issuer URL>    \
#       --namespace      <Kubernetes Namespace>   \
#       --service-account <Kubernetes SA Name>
#
# All values can be obtained from the Terraform outputs:
#   terraform -chdir=demos/eks-azure-workload-identity output
#
# Prerequisites:
#   - az CLI installed and signed in (az login)
#   - jq installed
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Defaults (override via flags) ─────────────────────────────────────────────
APP_OBJECT_ID=""
ISSUER=""
NAMESPACE=""
SERVICE_ACCOUNT=""
CREDENTIAL_NAME="eks-workload-identity"
AUDIENCES="api://AzureADTokenExchange"

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

# ── Parse arguments ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-object-id)    APP_OBJECT_ID="$2";    shift 2 ;;
    --issuer)           ISSUER="$2";           shift 2 ;;
    --namespace)        NAMESPACE="$2";        shift 2 ;;
    --service-account)  SERVICE_ACCOUNT="$2";  shift 2 ;;
    --credential-name)  CREDENTIAL_NAME="$2";  shift 2 ;;
    -h|--help)          usage ;;
    *)                  echo "Unknown flag: $1"; usage ;;
  esac
done

# ── Validate ──────────────────────────────────────────────────────────────────
missing=()
[[ -z "$APP_OBJECT_ID"   ]] && missing+=("--app-object-id")
[[ -z "$ISSUER"          ]] && missing+=("--issuer")
[[ -z "$NAMESPACE"       ]] && missing+=("--namespace")
[[ -z "$SERVICE_ACCOUNT" ]] && missing+=("--service-account")

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "ERROR: Missing required arguments: ${missing[*]}"
  usage
fi

SUBJECT="system:serviceaccount:${NAMESPACE}:${SERVICE_ACCOUNT}"

echo "──────────────────────────────────────────────────────────"
echo " Configuring Entra Federated Identity Credential"
echo "──────────────────────────────────────────────────────────"
echo "  App Object ID   : ${APP_OBJECT_ID}"
echo "  Credential name : ${CREDENTIAL_NAME}"
echo "  Issuer          : ${ISSUER}"
echo "  Subject         : ${SUBJECT}"
echo "  Audiences       : ${AUDIENCES}"
echo "──────────────────────────────────────────────────────────"

# ── Check whether the credential already exists ───────────────────────────────
EXISTING=$(az ad app federated-credential list \
  --id "${APP_OBJECT_ID}" \
  --query "[?name=='${CREDENTIAL_NAME}'].id" \
  --output tsv 2>/dev/null || true)

if [[ -n "$EXISTING" ]]; then
  echo "Federated credential '${CREDENTIAL_NAME}' already exists – updating..."
  az ad app federated-credential update \
    --id "${APP_OBJECT_ID}" \
    --federated-credential-id "${EXISTING}" \
    --parameters "{
      \"name\": \"${CREDENTIAL_NAME}\",
      \"issuer\": \"${ISSUER}\",
      \"subject\": \"${SUBJECT}\",
      \"audiences\": [\"${AUDIENCES}\"]
    }"
  echo "Updated federated credential '${CREDENTIAL_NAME}'."
else
  echo "Creating new federated credential '${CREDENTIAL_NAME}'..."
  az ad app federated-credential create \
    --id "${APP_OBJECT_ID}" \
    --parameters "{
      \"name\": \"${CREDENTIAL_NAME}\",
      \"issuer\": \"${ISSUER}\",
      \"subject\": \"${SUBJECT}\",
      \"audiences\": [\"${AUDIENCES}\"]
    }"
  echo "Created federated credential '${CREDENTIAL_NAME}'."
fi

echo ""
echo "Done.  The EKS ServiceAccount '${SERVICE_ACCOUNT}' in namespace"
echo "'${NAMESPACE}' can now exchange its OIDC token for Entra access tokens."
