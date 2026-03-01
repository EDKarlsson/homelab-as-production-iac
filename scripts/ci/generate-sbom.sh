#!/usr/bin/env bash
# generate-sbom.sh — Generate CycloneDX 1.4 SBOM from Kubernetes manifests
#                    and upload to OWASP Dependency-Track.
#
# Scans all Deployment/StatefulSet/DaemonSet manifests under kubernetes/ and
# clusters/ for container image references, builds a CycloneDX 1.4 JSON document,
# and uploads it to Dependency-Track via PUT /api/v1/bom.
#
# Usage (local — generate only):
#   SBOM_ONLY=1 bash scripts/ci/generate-sbom.sh
#
# Usage (local — upload):
#   DT_API_KEY=<key> bash scripts/ci/generate-sbom.sh
#
# Usage (CI): set DT_API_KEY as a masked CI/CD variable; other vars have defaults.
#
# Required env vars (for upload):
#   DT_API_KEY         — DT API key (BOM_UPLOAD + PROJECT_CREATION permissions)
#
# Optional env vars:
#   DT_URL             — DT base URL (default: https://dependency-track.homelab.ts.net)
#   DT_PROJECT_NAME    — DT project name (default: homelab-iac)
#   DT_PROJECT_VERSION — DT project version (default: current git branch)
#   SBOM_ONLY          — Set to 1 to skip upload and only write SBOM file
#
# Dependencies: yq >=4.x, jq >=1.6, curl, python3

set -euo pipefail

# Temp file vars initialised empty so the cleanup trap is safe to reference
# them even before the mktemp calls that populate them.
IMAGES_TMP=""
CURL_CONFIG=""
REQUEST_BODY=""
DT_RESPONSE=""

cleanup() {
  rm -f \
    ${IMAGES_TMP:+"${IMAGES_TMP}"} \
    ${CURL_CONFIG:+"${CURL_CONFIG}"} \
    ${REQUEST_BODY:+"${REQUEST_BODY}"} \
    ${DT_RESPONSE:+"${DT_RESPONSE}"}
}
trap cleanup EXIT

DT_URL="${DT_URL:-https://dependency-track.homelab.ts.net}"
DT_PROJECT_NAME="${DT_PROJECT_NAME:-homelab-iac}"
DT_PROJECT_VERSION="${DT_PROJECT_VERSION:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')}"
SBOM_ONLY="${SBOM_ONLY:-0}"
OUTPUT_DIR="${1:-dist/sbom}"

mkdir -p "${OUTPUT_DIR}"
SBOM_FILE="${OUTPUT_DIR}/homelab-iac-sbom.json"

# ── 1. Extract container image references ─────────────────────────────────────
echo "==> Extracting container images from Kubernetes manifests..."

# Pull image fields from container/initContainer specs across all YAML files.
# Targets the four container list paths that cover Deployments, StatefulSets,
# DaemonSets, and bare Pod specs.  Processing files individually allows yq to
# skip unparseable docs (HelmRelease values, etc.) without aborting.
mapfile -t IMAGES < <(
  find kubernetes clusters -name '*.yaml' -o -name '*.yml' 2>/dev/null | sort |
  while read -r f; do
    # Pipe via stdin — avoids snap/confinement restrictions on /tmp paths.
    # Run four separate selectors to cover all container list locations.
    for selector in \
      '.spec.template.spec.containers[].image' \
      '.spec.template.spec.initContainers[].image' \
      '.spec.containers[].image' \
      '.spec.initContainers[].image'; do
      yq eval "${selector}" - < "${f}" 2>/dev/null || true
    done
  done |
  grep -v '^null$' | grep -v '^---$' | grep -v '^\s*$' |
  sort -u
)

if [[ ${#IMAGES[@]} -eq 0 ]]; then
  echo "ERROR: No container images found in manifests" >&2
  exit 1
fi

echo "==> Found ${#IMAGES[@]} unique container images"

# ── 2. Build CycloneDX 1.4 JSON ───────────────────────────────────────────────
echo "==> Building CycloneDX SBOM..."

if command -v uuidgen >/dev/null 2>&1; then
  SERIAL_UUID=$(uuidgen | tr '[:upper:]' '[:lower:]')
else
  SERIAL_UUID=$(cat /proc/sys/kernel/random/uuid)
fi
SERIAL="urn:uuid:${SERIAL_UUID}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GIT_SHA="${CI_COMMIT_SHA:-$(git rev-parse HEAD 2>/dev/null || echo 'unknown')}"

# Write image list to a temp file so the Python script can read it cleanly.
IMAGES_TMP=$(mktemp)
printf '%s\n' "${IMAGES[@]}" > "${IMAGES_TMP}"

# Use Python3 to parse each image reference into a CycloneDX component with
# a pkg:oci PURL.  Shell string manipulation for registry/org/name splitting
# is fragile; Python's urllib handles percent-encoding correctly.
COMPONENTS_JSON=$(python3 - "${IMAGES_TMP}" << 'PYEOF'
import sys, json
from urllib.parse import quote

images_file = sys.argv[1]
with open(images_file) as f:
    images = [line.strip() for line in f if line.strip()]

components = []
for image in images:
    # Split off the tag (part after last colon in the final path segment).
    # Avoid splitting on colons that are part of a registry port (e.g., localhost:5000).
    last_slash_idx = image.rfind('/')
    segment_after_last_slash = image[last_slash_idx + 1:]
    if ':' in segment_after_last_slash:
        tag = segment_after_last_slash.split(':')[-1]
        path_part = image[:image.rfind(':')]
    else:
        tag = 'latest'
        path_part = image

    parts = path_part.split('/')

    # Detect explicit registry: first component contains a dot, colon, or is 'localhost'.
    if parts and ('.' in parts[0] or ':' in parts[0] or parts[0] == 'localhost'):
        registry = parts[0]
        remaining = '/'.join(parts[1:])
    else:
        registry = 'docker.io'
        remaining = path_part

    # Name is the final path segment; repository_url is everything before it.
    remaining_parts = remaining.split('/')
    name = remaining_parts[-1]
    repo_prefix_parts = remaining_parts[:-1]
    repository_url = f"{registry}/{'/'.join(repo_prefix_parts)}" if repo_prefix_parts else registry

    # pkg:oci PURL format per the PURL spec (OCI type).
    purl = f"pkg:oci/{name}@{quote(tag, safe='')}?repository_url={quote(repository_url, safe='')}"

    components.append({
        "type": "container",
        "name": name,
        "version": tag,
        "description": f"Container image: {image}",
        "purl": purl
    })

print(json.dumps(components))
PYEOF
)

# Assemble the complete BOM document.
jq -n \
  --arg serial    "${SERIAL}" \
  --arg ts        "${TIMESTAMP}" \
  --arg project   "${DT_PROJECT_NAME}" \
  --arg version   "${DT_PROJECT_VERSION}" \
  --arg sha       "${GIT_SHA}" \
  --argjson components "${COMPONENTS_JSON}" \
  '{
    "bomFormat": "CycloneDX",
    "specVersion": "1.4",
    "serialNumber": $serial,
    "version": 1,
    "metadata": {
      "timestamp": $ts,
      "tools": [{"vendor": "homelab-iac", "name": "generate-sbom.sh", "version": "1.0"}],
      "component": {
        "type": "application",
        "name": $project,
        "version": $version,
        "properties": [{"name": "git:sha", "value": $sha}]
      }
    },
    "components": $components
  }' > "${SBOM_FILE}"

COMPONENT_COUNT=$(jq '.components | length' "${SBOM_FILE}")
echo "==> SBOM written: ${SBOM_FILE} (${COMPONENT_COUNT} components)"

if [[ "${SBOM_ONLY}" == "1" ]]; then
  echo "==> SBOM_ONLY=1 — skipping upload"
  exit 0
fi

# ── 3. Upload to Dependency-Track ─────────────────────────────────────────────
if [[ -z "${DT_API_KEY:-}" ]]; then
  echo "WARNING: DT_API_KEY not set — skipping upload"
  exit 0
fi

echo "==> Uploading to Dependency-Track at ${DT_URL} ..."
echo "    Project: ${DT_PROJECT_NAME}  Version: ${DT_PROJECT_VERSION}"

BOM_B64=$(base64 -w 0 < "${SBOM_FILE}")

# Write the API key to a curl config file so it does not appear in the process
# list (argv is visible to other users via /proc/<pid>/cmdline and `ps aux`).
CURL_CONFIG=$(mktemp)
REQUEST_BODY=$(mktemp)
DT_RESPONSE=$(mktemp)

printf 'header = "X-Api-Key: %s"\n' "${DT_API_KEY}"  > "${CURL_CONFIG}"
printf 'header = "Content-Type: application/json"\n' >> "${CURL_CONFIG}"

jq -n \
  --arg name "${DT_PROJECT_NAME}" \
  --arg ver  "${DT_PROJECT_VERSION}" \
  --arg bom  "${BOM_B64}" \
  '{projectName: $name, projectVersion: $ver, autoCreate: true, bom: $bom}' \
  > "${REQUEST_BODY}"

HTTP_CODE=$(curl -s \
  --retry 3 --retry-delay 5 \
  --config "${CURL_CONFIG}" \
  -o "${DT_RESPONSE}" \
  -w "%{http_code}" \
  -X PUT \
  --data-binary @"${REQUEST_BODY}" \
  "${DT_URL}/api/v1/bom")

echo "==> HTTP ${HTTP_CODE}"
cat "${DT_RESPONSE}" && echo

if [[ "${HTTP_CODE}" == "200" ]]; then
  echo "==> SBOM uploaded successfully"
else
  echo "ERROR: Upload failed (HTTP ${HTTP_CODE})" >&2
  exit 1
fi
