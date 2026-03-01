#!/usr/bin/env bash
# Publish files to a Nexus raw repository.

set -euo pipefail

if [[ "$#" -lt 2 ]]; then
  echo "Usage: $0 <repo-path-prefix> <file1> [file2 ...]" >&2
  exit 2
fi

REPO_PATH_PREFIX="$1"
shift

: "${NEXUS_URL:?NEXUS_URL is required}"
: "${NEXUS_CI_USERNAME:?NEXUS_CI_USERNAME is required}"
: "${NEXUS_CI_PASSWORD:?NEXUS_CI_PASSWORD is required}"

NEXUS_RAW_REPO="${NEXUS_RAW_REPO:-raw-ci-hosted}"
NEXUS_DRY_RUN="${NEXUS_DRY_RUN:-0}"

BASE_URL="${NEXUS_URL%/}/repository/${NEXUS_RAW_REPO}/${REPO_PATH_PREFIX#/}"

for file in "$@"; do
  if [[ ! -f "${file}" ]]; then
    echo "ERROR: File not found: ${file}" >&2
    exit 1
  fi

  filename="$(basename "${file}")"
  target_url="${BASE_URL%/}/${filename}"

  echo "Publishing ${file} -> ${target_url}"

  if [[ "${NEXUS_DRY_RUN}" == "1" ]]; then
    continue
  fi

  curl -fsS \
    -u "${NEXUS_CI_USERNAME}:${NEXUS_CI_PASSWORD}" \
    --upload-file "${file}" \
    "${target_url}"
done

echo "Nexus raw publish complete."
