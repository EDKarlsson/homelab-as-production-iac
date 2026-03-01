#!/usr/bin/env bash
# CI policy checks for Kubernetes and infrastructure manifests.
# Enforces no new high-risk drift patterns while allowing existing baseline
# exceptions via allowlists. Any new exception fails CI.
#
# Current policy checks:
#   1) Floating container image tags (:latest / *-latest)
#   2) Wildcard Helm chart versions (*.x)
#   3) kubeconfig insecure-skip-tls-verify: true
#   4) StrictHostKeyChecking=no usage
#   5) write-kubeconfig-mode: 0644 (world-readable kubeconfig)
#   6) Terraform provider/resource insecure = true

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

LATEST_ALLOWLIST="${ROOT_DIR}/ci/allowlists/image-tag-latest.txt"
HELM_ALLOWLIST="${ROOT_DIR}/ci/allowlists/helm-wildcard-versions.txt"
INSECURE_TLS_SKIP_ALLOWLIST="${ROOT_DIR}/ci/allowlists/kube-insecure-skip-tls-verify.txt"
SSH_HOSTKEY_ALLOWLIST="${ROOT_DIR}/ci/allowlists/ssh-strict-hostkeychecking-no.txt"
KUBECONFIG_MODE_ALLOWLIST="${ROOT_DIR}/ci/allowlists/kubeconfig-mode-0644.txt"
TF_INSECURE_ALLOWLIST="${ROOT_DIR}/ci/allowlists/terraform-insecure-true.txt"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

cd "${ROOT_DIR}"

found_latest="${tmp_dir}/found-latest.txt"
found_helm="${tmp_dir}/found-helm.txt"
found_insecure_tls_skip="${tmp_dir}/found-insecure-tls-skip.txt"
found_ssh_hostkey="${tmp_dir}/found-ssh-hostkey.txt"
found_kubeconfig_mode="${tmp_dir}/found-kubeconfig-mode.txt"
found_tf_insecure="${tmp_dir}/found-tf-insecure.txt"

new_latest="${tmp_dir}/new-latest.txt"
new_helm="${tmp_dir}/new-helm.txt"
new_insecure_tls_skip="${tmp_dir}/new-insecure-tls-skip.txt"
new_ssh_hostkey="${tmp_dir}/new-ssh-hostkey.txt"
new_kubeconfig_mode="${tmp_dir}/new-kubeconfig-mode.txt"
new_tf_insecure="${tmp_dir}/new-tf-insecure.txt"

mkdir -p "${ROOT_DIR}/ci/allowlists"

echo "==> Scanning for floating image tags"
{ rg -n --no-heading \
    -g '*.yaml' \
    -g '*.yml' \
    -g '!**/_todo/**' \
    'image:\s*[^[:space:]#]+:(latest|[A-Za-z0-9._-]*-latest)\b' \
    kubernetes infrastructure/modules/op-connect/templates || true; } \
  | awk -F'image:[[:space:]]*' '
      {
        split($1, a, ":");
        image = $2;
        sub(/[[:space:]]*#.*/, "", image);
        gsub(/[[:space:]]+$/, "", image);
        print a[1] "|" image;
      }' \
  | sort -u > "${found_latest}"

echo "==> Scanning for wildcard Helm chart versions"
{ rg -n --no-heading \
    -g '*.yaml' \
    -g '*.yml' \
    'version:\s*"[0-9]+(\.[0-9]+)?\.x"' \
    kubernetes || true; } \
  | awk -F'version:[[:space:]]*' '
      {
        split($1, a, ":");
        version = $2;
        sub(/[[:space:]]*#.*/, "", version);
        gsub(/"/, "", version);
        gsub(/[[:space:]]+/, "", version);
        print a[1] "|" version;
      }' \
  | sort -u > "${found_helm}"

echo "==> Scanning for insecure kubeconfig TLS skip"
{ rg -n --no-heading \
    -g '*.yaml' \
    -g '*.yml' \
    -g '*.j2' \
    -g '*.tftpl' \
    'insecure-skip-tls-verify:\s*true' \
    ansible infrastructure kubernetes clusters || true; } \
  | sed -E 's#^([^:]+):[0-9]+:.*$#\1|insecure-skip-tls-verify: true#' \
  | sort -u > "${found_insecure_tls_skip}"

echo "==> Scanning for disabled SSH host key checking"
{ rg -n --no-heading \
    -g '*.yaml' \
    -g '*.yml' \
    -g '*.sh' \
    -g '!scripts/ci/policy-check.sh' \
    'StrictHostKeyChecking=no' \
    ansible infrastructure scripts || true; } \
  | sed -E 's#^([^:]+):[0-9]+:.*$#\1|StrictHostKeyChecking=no#' \
  | sort -u > "${found_ssh_hostkey}"

echo "==> Scanning for world-readable kubeconfig mode"
{ rg -n --no-heading \
    -g '*.yaml' \
    -g '*.yml' \
    -g '*.j2' \
    -g '*.tftpl' \
    'write-kubeconfig-mode:\s*"?0?644"?' \
    ansible infrastructure || true; } \
  | sed -E 's#^([^:]+):[0-9]+:.*$#\1|write-kubeconfig-mode: 0644#' \
  | sort -u > "${found_kubeconfig_mode}"

echo "==> Scanning for Terraform insecure=true"
{ rg -n --no-heading -g '*.tf' 'insecure\s*=\s*true' infrastructure || true; } \
  | sed -E 's#^([^:]+):[0-9]+:.*$#\1|insecure = true#' \
  | sort -u > "${found_tf_insecure}"

status=0

check_policy() {
  local label="$1"
  local found_file="$2"
  local allowlist_file="$3"
  local new_file="$4"

  touch "${allowlist_file}"
  sort -u -o "${allowlist_file}" "${allowlist_file}"
  comm -23 "${found_file}" "${allowlist_file}" > "${new_file}" || true

  local count
  count="$(wc -l < "${found_file}" | tr -d ' ')"
  echo "${label} found: ${count}"

  if [[ -s "${new_file}" ]]; then
    status=1
    echo ""
    echo "ERROR: New ${label} were introduced:"
    cat "${new_file}"
    echo ""
    echo "If intentional, add entries to ${allowlist_file}."
  fi
}

check_policy "floating image tags" "${found_latest}" "${LATEST_ALLOWLIST}" "${new_latest}"
check_policy "wildcard Helm chart versions" "${found_helm}" "${HELM_ALLOWLIST}" "${new_helm}"
check_policy "kubeconfig insecure-skip-tls-verify" "${found_insecure_tls_skip}" "${INSECURE_TLS_SKIP_ALLOWLIST}" "${new_insecure_tls_skip}"
check_policy "StrictHostKeyChecking=no occurrences" "${found_ssh_hostkey}" "${SSH_HOSTKEY_ALLOWLIST}" "${new_ssh_hostkey}"
check_policy "write-kubeconfig-mode 0644 occurrences" "${found_kubeconfig_mode}" "${KUBECONFIG_MODE_ALLOWLIST}" "${new_kubeconfig_mode}"
check_policy "Terraform insecure=true occurrences" "${found_tf_insecure}" "${TF_INSECURE_ALLOWLIST}" "${new_tf_insecure}"

if [[ "${status}" -eq 0 ]]; then
  echo "Policy checks passed."
else
  exit "${status}"
fi
