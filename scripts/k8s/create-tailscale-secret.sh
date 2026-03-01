#!/usr/bin/env bash
# Create the Tailscale operator OAuth secret in Kubernetes.
# Pulls credentials from 1Password (Homelab vault, item: tailscale-k8s-operator).
#
# Prerequisites:
#   - 1Password CLI (op) authenticated
#   - kubectl configured for the target cluster
#   - Tailscale OAuth client created in admin console with:
#     - Write scopes: Devices Core, Auth Keys, Services
#     - Tag: tag:k8s-operator
#
# Usage: ./scripts/k8s/create-tailscale-secret.sh

set -euo pipefail

NAMESPACE="tailscale"
SECRET_NAME="tailscale-operator-oauth"
OP_ITEM="tailscale-k8s-operator"
OP_VAULT="Homelab"

echo "==> Creating namespace '${NAMESPACE}' (if not exists)..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Fetching OAuth credentials from 1Password..."
# Unset Connect env vars so op CLI uses direct/desktop mode (not Connect server)
CLIENT_ID="$(env -u OP_CONNECT_HOST -u OP_CONNECT_TOKEN op item get "${OP_ITEM}" --vault "${OP_VAULT}" --field clientId --reveal)"
CLIENT_SECRET="$(env -u OP_CONNECT_HOST -u OP_CONNECT_TOKEN op item get "${OP_ITEM}" --vault "${OP_VAULT}" --field clientSecret --reveal)"

if [[ -z "${CLIENT_ID}" || -z "${CLIENT_SECRET}" ]]; then
  echo "ERROR: Failed to retrieve credentials from 1Password." >&2
  echo "Ensure item '${OP_ITEM}' exists in vault '${OP_VAULT}' with fields 'clientId' and 'clientSecret'." >&2
  exit 1
fi

echo "==> Creating secret '${SECRET_NAME}' in namespace '${NAMESPACE}'..."
kubectl create secret generic "${SECRET_NAME}" \
  --namespace="${NAMESPACE}" \
  --from-literal=clientId="${CLIENT_ID}" \
  --from-literal=clientSecret="${CLIENT_SECRET}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Done. Verify with: kubectl get secret ${SECRET_NAME} -n ${NAMESPACE}"
