#!/usr/bin/env bash

# This script downloads the Flux OpenAPI schemas, then it validates the
# Flux custom resources and the kustomize overlays using kubeconform.
# This script is meant to be run locally and in CI before the changes
# are merged on the main branch that's synced by Flux.

# Copyright 2023 The Flux authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Prerequisites
# - yq v4.34
# - kustomize v5.0
# - kubeconform v0.6

set -o errexit
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# mirror kustomize-controller build options
kustomize_flags=("--load-restrictor=LoadRestrictionsNone")
kustomize_config="kustomization.yaml"

# skip Kubernetes Secrets due to SOPS fields failing validation
kubeconform_flags=("-skip=Secret")

get_default_flux_schema_version() {
  local gotk_components="${REPO_ROOT}/clusters/homelab/flux-system/gotk-components.yaml"
  local detected=""

  if [[ -f "${gotk_components}" ]]; then
    detected="$(sed -n 's/^# Flux Version: \(v[^ ]*\)$/\1/p' "${gotk_components}" | head -n1)"
  fi

  # Fallback if the Flux comment header is unavailable.
  echo "${detected:-v2.7.5}"
}

DEFAULT_FLUX_SCHEMA_VERSION="$(get_default_flux_schema_version)"
FLUX_SCHEMA_VERSION="${FLUX_SCHEMA_VERSION:-${DEFAULT_FLUX_SCHEMA_VERSION}}"
FLUX_SCHEMA_VARIANT="${FLUX_SCHEMA_VARIANT:-master-standalone-strict}"
FLUX_SCHEMA_CACHE_DIR="${FLUX_SCHEMA_CACHE_DIR:-${XDG_CACHE_HOME:-${HOME}/.cache}/flux-crd-schemas}"
FLUX_SCHEMA_ROOT="${FLUX_SCHEMA_CACHE_DIR}/${FLUX_SCHEMA_VERSION}"
FLUX_SCHEMA_PATH="${FLUX_SCHEMA_ROOT}/${FLUX_SCHEMA_VARIANT}"
FLUX_SCHEMA_URL="${FLUX_SCHEMA_URL:-https://github.com/fluxcd/flux2/releases/download/${FLUX_SCHEMA_VERSION}/crd-schemas.tar.gz}"

kubeconform_config=(
  "-strict"
  "-ignore-missing-schemas"
  "-schema-location"
  "default"
  "-schema-location"
  "${FLUX_SCHEMA_ROOT}"
  "-verbose"
)

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${cmd}" >&2
    exit 1
  fi
}

ensure_secure_cache_dir() {
  local old_umask

  if [[ -L "${FLUX_SCHEMA_CACHE_DIR}" ]]; then
    echo "ERROR: schema cache directory must not be a symlink: ${FLUX_SCHEMA_CACHE_DIR}" >&2
    exit 1
  fi

  old_umask="$(umask)"
  umask 077
  mkdir -p "${FLUX_SCHEMA_CACHE_DIR}"
  umask "${old_umask}"

  if [[ ! -O "${FLUX_SCHEMA_CACHE_DIR}" ]]; then
    echo "ERROR: schema cache directory is not owned by current user: ${FLUX_SCHEMA_CACHE_DIR}" >&2
    exit 1
  fi

  chmod 700 "${FLUX_SCHEMA_CACHE_DIR}" || true
}

has_cached_flux_schemas() {
  if [[ ! -d "${FLUX_SCHEMA_PATH}" ]]; then
    return 1
  fi
  find "${FLUX_SCHEMA_PATH}" -type f -name '*.json' -print -quit | grep -q . || return 1
  return 0
}

download_flux_schemas() {
  (
    tmp_archive="$(mktemp)"
    tmp_extract="$(mktemp -d)"
    trap 'rm -f "${tmp_archive}"; rm -rf "${tmp_extract}"' EXIT

    curl -fsSL --retry 3 --retry-delay 1 --connect-timeout 10 "${FLUX_SCHEMA_URL}" -o "${tmp_archive}"

    mkdir -p "${tmp_extract}/${FLUX_SCHEMA_VARIANT}"
    tar -xzf "${tmp_archive}" -C "${tmp_extract}/${FLUX_SCHEMA_VARIANT}"

    find "${tmp_extract}/${FLUX_SCHEMA_VARIANT}" -type f -name '*.json' -print -quit | grep -q .

    if [[ -L "${FLUX_SCHEMA_ROOT}" || -L "${FLUX_SCHEMA_PATH}" ]]; then
      echo "ERROR: schema cache paths must not be symlinks: ${FLUX_SCHEMA_ROOT} / ${FLUX_SCHEMA_PATH}" >&2
      exit 1
    fi

    mkdir -p "${FLUX_SCHEMA_ROOT}"
    chmod 700 "${FLUX_SCHEMA_ROOT}" || true
    rm -rf "${FLUX_SCHEMA_PATH}"
    mv "${tmp_extract}/${FLUX_SCHEMA_VARIANT}" "${FLUX_SCHEMA_PATH}"
  )
}

prepare_flux_schemas() {
  local refresh="${FLUX_SCHEMA_REFRESH:-false}"

  if [[ "${refresh}" != "true" ]] && has_cached_flux_schemas; then
    echo "INFO - Using cached Flux OpenAPI schemas: ${FLUX_SCHEMA_PATH}"
    return 0
  fi

  echo "INFO - Downloading Flux OpenAPI schemas (${FLUX_SCHEMA_VERSION})"
  echo "INFO - Schema source: ${FLUX_SCHEMA_URL}"
  if download_flux_schemas; then
    echo "INFO - Flux schemas cached at ${FLUX_SCHEMA_PATH}"
    return 0
  fi

  if has_cached_flux_schemas; then
    echo "WARN - Schema download failed; falling back to cached schemas at ${FLUX_SCHEMA_PATH}" >&2
    return 0
  fi

  echo "ERROR: failed to download Flux schemas and no cache exists at ${FLUX_SCHEMA_PATH}" >&2
  echo "ERROR: re-run with connectivity or pre-seed FLUX_SCHEMA_CACHE_DIR" >&2
  exit 1
}

validate_prereqs() {
  require_cmd yq
  require_cmd kustomize
  require_cmd kubeconform
  require_cmd tar

  ensure_secure_cache_dir

  if ! has_cached_flux_schemas; then
    require_cmd curl
  fi
}

cd "${REPO_ROOT}"

validate_prereqs
prepare_flux_schemas

find . -type f -name '*.yaml' -print0 | while IFS= read -r -d $'\0' file;
  do
    echo "INFO - Validating $file"
    yq e 'true' "$file" > /dev/null
done

echo "INFO - Validating clusters"
find ./clusters -maxdepth 2 -type f -name '*.yaml' -print0 | while IFS= read -r -d $'\0' file;
  do
    if ! kubeconform "${kubeconform_flags[@]}" "${kubeconform_config[@]}" "${file}"; then
      exit 1
    fi
done

echo "INFO - Validating kustomize overlays"
find . -type f -name $kustomize_config -print0 | while IFS= read -r -d $'\0' file;
  do
    echo "INFO - Validating kustomization ${file/%$kustomize_config}"
    if ! kustomize build "${file/%$kustomize_config}" "${kustomize_flags[@]}" | \
      kubeconform "${kubeconform_flags[@]}" "${kubeconform_config[@]}"; then
      exit 1
    fi
done
