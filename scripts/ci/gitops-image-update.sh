#!/usr/bin/env bash
# Update a Flux-managed manifest image reference in-place.
# Supports:
#   - Deployment/StatefulSet/DaemonSet container images
#   - HelmRelease values.image.repository/tag

set -euo pipefail

if [[ "$#" -lt 2 || "$#" -gt 3 ]]; then
  echo "Usage: $0 <manifest-file> <image-reference> [container-name]" >&2
  exit 2
fi

MANIFEST_FILE="$1"
IMAGE_REF="$2"
CONTAINER_NAME="${3:-}"

if [[ ! -f "${MANIFEST_FILE}" ]]; then
  echo "ERROR: Manifest file not found: ${MANIFEST_FILE}" >&2
  exit 1
fi

if ! command -v yq >/dev/null 2>&1; then
  echo "ERROR: yq is required in PATH" >&2
  exit 1
fi

extract_repo_and_tag() {
  local image="$1"
  local no_digest="${image%@*}"
  local last_segment="${no_digest##*/}"
  local repo="${no_digest}"
  local tag=""

  if [[ "${last_segment}" == *:* ]]; then
    repo="${no_digest%:*}"
    tag="${no_digest##*:}"
  fi

  echo "${repo}|${tag}"
}

has_helm_release="$(yq e 'select(.kind == "HelmRelease") | .kind' "${MANIFEST_FILE}" | head -n1 || true)"
has_workload="$(yq e 'select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet") | .kind' "${MANIFEST_FILE}" | head -n1 || true)"

if [[ -n "${has_helm_release}" ]]; then
  parsed="$(extract_repo_and_tag "${IMAGE_REF}")"
  IMAGE_REPO="${parsed%%|*}"
  IMAGE_TAG="${parsed##*|}"

  if [[ -z "${IMAGE_TAG}" ]]; then
    echo "ERROR: HelmRelease updates require an image tag in <repo>:<tag> format." >&2
    exit 1
  fi

  has_repo_field="$(yq e 'select(.kind == "HelmRelease") | has("spec") and .spec.values.image.repository != null' "${MANIFEST_FILE}" | head -n1 || true)"
  has_tag_field="$(yq e 'select(.kind == "HelmRelease") | has("spec") and .spec.values.image.tag != null' "${MANIFEST_FILE}" | head -n1 || true)"

  if [[ "${has_tag_field}" != "true" ]]; then
    echo "ERROR: HelmRelease missing .spec.values.image.tag: ${MANIFEST_FILE}" >&2
    exit 1
  fi

  if [[ "${has_repo_field}" == "true" ]]; then
    IMAGE_REPO="${IMAGE_REPO}" yq e -i 'select(.kind == "HelmRelease").spec.values.image.repository = strenv(IMAGE_REPO)' "${MANIFEST_FILE}"
  fi

  IMAGE_TAG="${IMAGE_TAG}" yq e -i 'select(.kind == "HelmRelease").spec.values.image.tag = strenv(IMAGE_TAG)' "${MANIFEST_FILE}"
  echo "Updated HelmRelease image values in ${MANIFEST_FILE} to ${IMAGE_REF}"
  exit 0
fi

if [[ -n "${has_workload}" ]]; then
  if [[ -n "${CONTAINER_NAME}" ]]; then
    match="$(CONTAINER_NAME="${CONTAINER_NAME}" yq e 'select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet") | .spec.template.spec.containers[] | select(.name == strenv(CONTAINER_NAME)) | .name' "${MANIFEST_FILE}" | head -n1 || true)"
    if [[ -z "${match}" ]]; then
      echo "ERROR: Container '${CONTAINER_NAME}' not found in ${MANIFEST_FILE}" >&2
      exit 1
    fi

    IMAGE_REF="${IMAGE_REF}" CONTAINER_NAME="${CONTAINER_NAME}" yq e -i 'select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet").spec.template.spec.containers[] |= (select(.name == strenv(CONTAINER_NAME)).image = strenv(IMAGE_REF))' "${MANIFEST_FILE}"
    echo "Updated container '${CONTAINER_NAME}' image in ${MANIFEST_FILE} to ${IMAGE_REF}"
  else
    IMAGE_REF="${IMAGE_REF}" yq e -i 'select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet").spec.template.spec.containers[0].image = strenv(IMAGE_REF)' "${MANIFEST_FILE}"
    echo "Updated first workload container image in ${MANIFEST_FILE} to ${IMAGE_REF}"
  fi
  exit 0
fi

echo "ERROR: No supported workload kind found in ${MANIFEST_FILE}" >&2
echo "Supported: Deployment, StatefulSet, DaemonSet, HelmRelease" >&2
exit 1
