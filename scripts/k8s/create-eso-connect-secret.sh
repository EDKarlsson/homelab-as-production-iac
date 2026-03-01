#!/usr/bin/env bash
# Create the bootstrap secret for External Secrets Operator (ESO).
# Contains the 1Password Connect token that ESO uses to authenticate
# with the Connect server and sync secrets into Kubernetes.
#
# This is the ONE manual secret required — once ESO is running,
# all other secrets are managed via ExternalSecret resources.
#
# Prerequisites:
#   - kubectl configured for the target cluster
#   - One of these env vars set (from sourcing .env.d/terraform.env):
#     - OP_CONNECT_TOKEN
#     - TF_VAR_op_connect_token
#
# Usage: ./scripts/k8s/create-eso-connect-secret.sh

set -euo pipefail

NAMESPACE="external-secrets"
SECRET_NAME="onepassword-connect-token"

echo "==> Creating namespace '${NAMESPACE}' (if not exists)..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Reading 1Password Connect token from environment..."
TOKEN="${OP_CONNECT_TOKEN:-${TF_VAR_op_connect_token:-}}"

if [[ -z "${TOKEN}" ]]; then
  echo "ERROR: No Connect token found in environment." >&2
  echo "Set OP_CONNECT_TOKEN or TF_VAR_op_connect_token." >&2
  echo "Typically: source .env.d/terraform.env" >&2
  exit 1
fi

echo "==> Creating secret '${SECRET_NAME}' in namespace '${NAMESPACE}'..."
kubectl create secret generic "${SECRET_NAME}" \
  --namespace="${NAMESPACE}" \
  --from-literal=token="${TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Done. Verify with: kubectl get secret ${SECRET_NAME} -n ${NAMESPACE}"
