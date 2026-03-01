#!/usr/bin/env bash
# Optional self-hosted smoke checks against the live homelab cluster.
# Intended for workflow_dispatch on self-hosted runners inside the homelab.

set -euo pipefail

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: Required command not found: ${cmd}" >&2
    exit 1
  fi
}

require_cmd kubectl
require_cmd curl

echo "==> Kubernetes context"
kubectl config current-context

echo "==> Cluster node readiness"
not_ready="$(kubectl get nodes --no-headers | awk '$2 != "Ready" {count++} END {print count+0}')"
if [[ "${not_ready}" -gt 0 ]]; then
  echo "ERROR: ${not_ready} nodes are not Ready"
  kubectl get nodes -o wide
  exit 1
fi
kubectl get nodes -o wide

echo "==> Namespace sanity"
required_namespaces=(
  flux-system
  ingress-nginx
  cert-manager
  external-secrets
  monitoring
  keycloak
  oauth2-proxy
)

for ns in "${required_namespaces[@]}"; do
  kubectl get namespace "${ns}" >/dev/null
done
echo "Required namespaces are present."

echo "==> Workload readiness by namespace"
check_namespace_workloads() {
  local ns="$1"
  local not_ready_workloads=0

  mapfile -t deploy_lines < <(kubectl get deploy -n "${ns}" --no-headers 2>/dev/null || true)
  mapfile -t sts_lines < <(kubectl get sts -n "${ns}" --no-headers 2>/dev/null || true)

  for line in "${deploy_lines[@]}"; do
    [[ -z "${line}" ]] && continue
    ready="$(awk '{print $2}' <<< "${line}")"
    if [[ "${ready}" != */* ]]; then
      continue
    fi
    current="${ready%/*}"
    desired="${ready#*/}"
    if [[ "${current}" != "${desired}" ]]; then
      echo "ERROR: Deployment not ready in ${ns}: ${line}"
      not_ready_workloads=$((not_ready_workloads + 1))
    fi
  done

  for line in "${sts_lines[@]}"; do
    [[ -z "${line}" ]] && continue
    ready="$(awk '{print $2}' <<< "${line}")"
    if [[ "${ready}" != */* ]]; then
      continue
    fi
    current="${ready%/*}"
    desired="${ready#*/}"
    if [[ "${current}" != "${desired}" ]]; then
      echo "ERROR: StatefulSet not ready in ${ns}: ${line}"
      not_ready_workloads=$((not_ready_workloads + 1))
    fi
  done

  return "${not_ready_workloads}"
}

workload_errors=0
for ns in "${required_namespaces[@]}"; do
  if ! check_namespace_workloads "${ns}"; then
    workload_errors=$((workload_errors + 1))
  fi
done

if [[ "${workload_errors}" -gt 0 ]]; then
  echo "ERROR: One or more namespaces have non-ready workloads."
  exit 1
fi
echo "Namespace workloads are healthy."

if command -v flux >/dev/null 2>&1; then
  echo "==> Flux health"
  flux get kustomizations -A
  flux get helmreleases -A
else
  echo "WARN: flux CLI not found on runner; skipping flux checks."
fi

echo "==> Ingress endpoint smoke checks (first 12 hosts)"
mapfile -t ingress_hosts < <(kubectl get ingress -A -o jsonpath='{range .items[*]}{range .spec.rules[*]}{.host}{"\n"}{end}{end}' \
  | sed '/^$/d' \
  | sort -u \
  | head -n 12)

for host in "${ingress_hosts[@]}"; do
  url="https://${host}"
  code="$(curl -k -sS -o /dev/null -m 8 -w '%{http_code}' "${url}" || true)"
  if [[ -z "${code}" || "${code}" == "000" ]]; then
    echo "ERROR: ${url} unreachable"
    exit 1
  fi
  echo "OK: ${url} -> HTTP ${code}"
done

echo "Homelab smoke checks passed."
