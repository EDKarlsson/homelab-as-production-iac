#!/usr/bin/env bash
# configure-proxy-repos.sh — Declaratively configure Nexus proxy repositories
#
# Creates (or updates) proxy repositories in Nexus Repository Manager via the
# REST API. Idempotent: safe to run repeatedly. Existing repos are updated in
# place; missing repos are created.
#
# Prerequisites:
#   1. Nexus admin credentials (ExternalSecret or manual)
#   2. Port-forward or direct access to Nexus API
#
# Usage:
#   # Port-forward first (if not on LAN):
#   kubectl port-forward -n nexus svc/nexus-nexus-repository-manager 8081:8081
#
#   # Set credentials:
#   export NEXUS_URL="http://localhost:8081"
#   export NEXUS_USER="admin"
#   export NEXUS_PASSWORD="<password>"
#
#   # Run:
#   ./configure-proxy-repos.sh              # Configure all repos
#   ./configure-proxy-repos.sh --dry-run    # Preview without changes
#   ./configure-proxy-repos.sh docker-hub   # Configure a single repo
#
# Supported formats: apt, docker, go, helm, npm, pypi, cargo, raw

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
: "${NEXUS_URL:?NEXUS_URL is required (e.g. http://localhost:8081)}"
: "${NEXUS_USER:?NEXUS_USER is required}"
: "${NEXUS_PASSWORD:?NEXUS_PASSWORD is required}"

DRY_RUN=0
SINGLE_REPO=""
BLOB_STORE="default"

# Parse CLI args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)  DRY_RUN=1; shift ;;
    --blob-store) BLOB_STORE="$2"; shift 2 ;;
    -*)         echo "Unknown flag: $1" >&2; exit 2 ;;
    *)          SINGLE_REPO="$1"; shift ;;
  esac
done

API_BASE="${NEXUS_URL%/}/service/rest/v1"

# Counters
CREATED=0
UPDATED=0
SKIPPED=0
FAILED=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log_info()  { echo "  INFO: $*"; }
log_ok()    { echo "  OK:   $*"; }
log_error() { echo "  FAIL: $*" >&2; }
log_skip()  { echo "  SKIP: $*"; }
log_dry()   { echo "  DRY:  $*"; }

# Generic Nexus API call. Returns HTTP status code only.
# Usage: nexus_api METHOD path [json_body]
nexus_api() {
  local method="$1" path="$2" body="${3:-}"
  local url="${API_BASE}${path}"
  local -a curl_args=(
    -s -o /dev/null -w "%{http_code}"
    -u "${NEXUS_USER}:${NEXUS_PASSWORD}"
    -X "${method}"
  )
  if [[ -n "$body" ]]; then
    curl_args+=(-H "Content-Type: application/json" -d "$body")
  fi
  curl "${curl_args[@]}" "$url"
}

# Check if a repository already exists. Returns 0 if exists, 1 if not.
repo_exists() {
  local name="$1"
  local status
  status=$(nexus_api GET "/repositories/${name}" 2>/dev/null)
  [[ "$status" == "200" ]]
}

# ---------------------------------------------------------------------------
# Common JSON builders
# ---------------------------------------------------------------------------

# Build the common payload fields shared by all proxy repos.
# Usage: build_common_payload name remoteUrl
build_common_payload() {
  local name="$1" remote_url="$2"
  cat <<EOF
  "name": "${name}",
  "online": true,
  "storage": {
    "blobStoreName": "${BLOB_STORE}",
    "strictContentTypeValidation": true
  },
  "proxy": {
    "remoteUrl": "${remote_url}",
    "contentMaxAge": 1440,
    "metadataMaxAge": 1440
  },
  "negativeCache": {
    "enabled": true,
    "timeToLive": 1440
  },
  "httpClient": {
    "blocked": false,
    "autoBlock": true,
    "connection": {
      "retries": 0,
      "userAgentSuffix": "",
      "timeout": 60,
      "enableCircularRedirects": false,
      "enableCookies": false,
      "useTrustStore": false
    }
  }
EOF
}

# ---------------------------------------------------------------------------
# Format-specific payload builders
# ---------------------------------------------------------------------------

# APT proxy — requires distribution field
# Docs: https://help.sonatype.com/en/apt-repositories.html
build_apt_payload() {
  local name="$1" remote_url="$2" distribution="$3" flat="${4:-false}"
  cat <<EOF
{
$(build_common_payload "$name" "$remote_url"),
  "apt": {
    "distribution": "${distribution}",
    "flat": ${flat}
  }
}
EOF
}

# Docker proxy — requires docker + dockerProxy sections
# indexType: HUB for Docker Hub, REGISTRY for all others
build_docker_payload() {
  local name="$1" remote_url="$2" index_type="$3"
  local index_url_field=""
  if [[ "$index_type" == "HUB" ]]; then
    index_url_field=',
      "indexUrl": "https://index.docker.io/"'
  fi
  cat <<EOF
{
$(build_common_payload "$name" "$remote_url"),
  "docker": {
    "v1Enabled": false,
    "forceBasicAuth": false
  },
  "dockerProxy": {
    "indexType": "${index_type}"${index_url_field}
  }
}
EOF
}

# Go proxy
build_go_payload() {
  local name="$1" remote_url="$2"
  cat <<EOF
{
$(build_common_payload "$name" "$remote_url")
}
EOF
}

# Helm proxy
build_helm_payload() {
  local name="$1" remote_url="$2"
  cat <<EOF
{
$(build_common_payload "$name" "$remote_url")
}
EOF
}

# npm proxy
build_npm_payload() {
  local name="$1" remote_url="$2"
  cat <<EOF
{
$(build_common_payload "$name" "$remote_url")
}
EOF
}

# PyPI proxy
build_pypi_payload() {
  local name="$1" remote_url="$2"
  cat <<EOF
{
$(build_common_payload "$name" "$remote_url")
}
EOF
}

# Cargo proxy
build_cargo_payload() {
  local name="$1" remote_url="$2"
  cat <<EOF
{
$(build_common_payload "$name" "$remote_url")
}
EOF
}

# Raw proxy (for Git LFS, Hugging Face, Terraform Registry, etc.)
build_raw_payload() {
  local name="$1" remote_url="$2"
  cat <<EOF
{
$(build_common_payload "$name" "$remote_url")
}
EOF
}

# ---------------------------------------------------------------------------
# Idempotent create-or-update
# ---------------------------------------------------------------------------

# ensure_repo FORMAT NAME PAYLOAD
#   FORMAT: the API path segment (e.g. "apt", "docker", "npm")
#   NAME:   repository name
#   PAYLOAD: full JSON body
ensure_repo() {
  local format="$1" name="$2" payload="$3"

  # Filter to single repo if requested
  if [[ -n "$SINGLE_REPO" && "$SINGLE_REPO" != "$name" ]]; then
    return 0
  fi

  echo ""
  echo "--- ${name} (${format}/proxy) ---"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log_dry "Would create/update ${name}"
    log_dry "  Format:  ${format}/proxy"
    log_dry "  Payload: $(echo "$payload" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(json.dumps(d, indent=2))' 2>/dev/null || echo "$payload")"
    SKIPPED=$((SKIPPED + 1))
    return 0
  fi

  local status
  if repo_exists "$name"; then
    # Update existing
    status=$(nexus_api PUT "/repositories/${format}/proxy/${name}" "$payload")
    if [[ "$status" == "204" || "$status" == "200" ]]; then
      log_ok "Updated ${name}"
      UPDATED=$((UPDATED + 1))
    else
      log_error "Update ${name} failed (HTTP ${status})"
      FAILED=$((FAILED + 1))
    fi
  else
    # Create new
    status=$(nexus_api POST "/repositories/${format}/proxy" "$payload")
    if [[ "$status" == "201" || "$status" == "200" ]]; then
      log_ok "Created ${name}"
      CREATED=$((CREATED + 1))
    else
      log_error "Create ${name} failed (HTTP ${status})"
      FAILED=$((FAILED + 1))
    fi
  fi
}

# ---------------------------------------------------------------------------
# Repository definitions
# ---------------------------------------------------------------------------
echo "=== Nexus Proxy Repository Configuration ==="
echo "  Target:   ${NEXUS_URL}"
echo "  Blob:     ${BLOB_STORE}"
[[ "$DRY_RUN" -eq 1 ]] && echo "  Mode:     DRY RUN"
echo ""

# -- APT --
ensure_repo apt apt-ubuntu \
  "$(build_apt_payload apt-ubuntu "http://archive.ubuntu.com/ubuntu" noble)"

ensure_repo apt apt-ubuntu-security \
  "$(build_apt_payload apt-ubuntu-security "http://security.ubuntu.com/ubuntu" noble)"

# -- Docker --
ensure_repo docker docker-hub \
  "$(build_docker_payload docker-hub "https://registry-1.docker.io" HUB)"

ensure_repo docker docker-ghcr \
  "$(build_docker_payload docker-ghcr "https://ghcr.io" REGISTRY)"

ensure_repo docker docker-quay \
  "$(build_docker_payload docker-quay "https://quay.io" REGISTRY)"

# -- Go --
ensure_repo go go-proxy \
  "$(build_go_payload go-proxy "https://proxy.golang.org")"

# -- Helm --
ensure_repo helm helm-stable \
  "$(build_helm_payload helm-stable "https://charts.helm.sh/stable")"

# Helm proxy repos for all upstream chart registries used by the cluster
ensure_repo helm helm-jetstack \
  "$(build_helm_payload helm-jetstack "https://charts.jetstack.io")"

ensure_repo helm helm-external-secrets \
  "$(build_helm_payload helm-external-secrets "https://charts.external-secrets.io")"

ensure_repo helm helm-ingress-nginx \
  "$(build_helm_payload helm-ingress-nginx "https://kubernetes.github.io/ingress-nginx")"

ensure_repo helm helm-metallb \
  "$(build_helm_payload helm-metallb "https://metallb.github.io/metallb")"

ensure_repo helm helm-codecentric \
  "$(build_helm_payload helm-codecentric "https://codecentric.github.io/helm-charts")"

ensure_repo helm helm-longhorn \
  "$(build_helm_payload helm-longhorn "https://charts.longhorn.io")"

ensure_repo helm helm-nfs-provisioner \
  "$(build_helm_payload helm-nfs-provisioner "https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/")"

ensure_repo helm helm-oauth2-proxy \
  "$(build_helm_payload helm-oauth2-proxy "https://oauth2-proxy.github.io/manifests")"

ensure_repo helm helm-portainer \
  "$(build_helm_payload helm-portainer "https://portainer.github.io/k8s/")"

ensure_repo helm helm-tailscale \
  "$(build_helm_payload helm-tailscale "https://pkgs.tailscale.com/helmcharts")"

ensure_repo helm helm-vmware-tanzu \
  "$(build_helm_payload helm-vmware-tanzu "https://vmware-tanzu.github.io/helm-charts")"

ensure_repo helm helm-minio \
  "$(build_helm_payload helm-minio "https://charts.min.io")"

ensure_repo helm helm-grafana \
  "$(build_helm_payload helm-grafana "https://grafana.github.io/helm-charts")"

ensure_repo helm helm-sonatype \
  "$(build_helm_payload helm-sonatype "https://sonatype.github.io/helm3-charts/")"

ensure_repo helm helm-podinfo \
  "$(build_helm_payload helm-podinfo "https://stefanprodan.github.io/podinfo")"

ensure_repo helm helm-gabe565 \
  "$(build_helm_payload helm-gabe565 "https://charts.gabe565.com")"

ensure_repo helm helm-coder \
  "$(build_helm_payload helm-coder "https://helm.coder.com/v2")"

ensure_repo helm helm-jameswynn \
  "$(build_helm_payload helm-jameswynn "https://jameswynn.github.io/helm-charts/")"

# Plex has no official Helm registry — this raw GitHub Pages URL is the only
# published chart source (community-maintained).
ensure_repo helm helm-plex \
  "$(build_helm_payload helm-plex "https://raw.githubusercontent.com/plexinc/pms-docker/gh-pages")"

ensure_repo helm helm-windmill \
  "$(build_helm_payload helm-windmill "https://windmill-labs.github.io/windmill-helm-charts/")"

# -- npm --
ensure_repo npm npm-proxy \
  "$(build_npm_payload npm-proxy "https://registry.npmjs.org")"

# -- PyPI --
ensure_repo pypi pypi-proxy \
  "$(build_pypi_payload pypi-proxy "https://pypi.org")"

# -- Cargo --
ensure_repo cargo cargo-proxy \
  "$(build_cargo_payload cargo-proxy "https://index.crates.io/")"

# -- Raw (Git LFS, Hugging Face, Terraform Registry) --
ensure_repo raw gitlfs-github \
  "$(build_raw_payload gitlfs-github "https://github.com")"

ensure_repo raw huggingface \
  "$(build_raw_payload huggingface "https://huggingface.co")"

ensure_repo raw terraform-registry \
  "$(build_raw_payload terraform-registry "https://registry.terraform.io")"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== Summary ==="
TOTAL=$((CREATED + UPDATED + SKIPPED + FAILED))
echo "  Total:   ${TOTAL}"
echo "  Created: ${CREATED}"
echo "  Updated: ${UPDATED}"
echo "  Skipped: ${SKIPPED}"
echo "  Failed:  ${FAILED}"

if [[ "$FAILED" -gt 0 ]]; then
  echo ""
  echo "Some repositories failed. Check the Nexus API response above."
  echo "Tip: verify payload schemas at ${NEXUS_URL}/#admin/system/api"
  exit 1
fi
