#!/usr/bin/env bash
# Bootstrap FluxCD into the homelab-iac repository.
#
# Prerequisites:
#   1. Flux CLI installed: curl -s https://fluxcd.io/install.sh | sudo bash
#   2. kubectl configured to access the K3s cluster
#   3. GITHUB_TOKEN env var set to a GitHub PAT with repo scope
#
# Usage:
#   export GITHUB_TOKEN=<your-pat>
#   ./bootstrap-flux.sh
#
# See: docs/guides/fluxcd-bootstrap.md

set -euo pipefail

if ! command -v flux &>/dev/null; then
  echo "ERROR: flux CLI not found. Install with: curl -s https://fluxcd.io/install.sh | sudo bash"
  exit 1
fi

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "ERROR: GITHUB_TOKEN environment variable not set."
  echo "Create a GitHub PAT at https://github.com/settings/tokens with 'repo' scope."
  exit 1
fi

echo "Running Flux pre-flight checks..."
flux check --pre

echo ""
echo "Bootstrapping FluxCD..."
flux bootstrap github \
  --token-auth \
  --owner=homelab-admin \
  --repository=homelab-iac \
  --branch=main \
  --path=clusters/homelab \
  --personal

echo ""
echo "Verifying Flux installation..."
flux check
flux get kustomizations
