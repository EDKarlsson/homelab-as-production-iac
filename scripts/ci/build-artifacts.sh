#!/usr/bin/env bash
# Build CI/CD artifacts and provenance metadata.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${1:-${ROOT_DIR}/dist/ci-artifacts}"
PROJECT_NAME="${PROJECT_NAME:-homelab-iac}"
ARTIFACT_NAME="${ARTIFACT_NAME:-homelab-ci-bundle}"
ARTIFACT_VERSION="${ARTIFACT_VERSION:-dev}"

mkdir -p "${OUT_DIR}"

GIT_SHA="$(git -C "${ROOT_DIR}" rev-parse HEAD)"
GIT_SHA_SHORT="$(git -C "${ROOT_DIR}" rev-parse --short=7 HEAD)"
GIT_REF="${GIT_REF:-$(git -C "${ROOT_DIR}" symbolic-ref -q --short HEAD || git -C "${ROOT_DIR}" describe --tags --always)}"
BUILD_TS_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

BUNDLE_FILE="${ARTIFACT_NAME}_${ARTIFACT_VERSION}_${GIT_SHA_SHORT}.tar.gz"
PROVENANCE_FILE="${ARTIFACT_NAME}_${ARTIFACT_VERSION}_${GIT_SHA_SHORT}.provenance.json"

# Keep bundle deterministic and focused on CI pipeline inputs.
tar -czf "${OUT_DIR}/${BUNDLE_FILE}" \
  -C "${ROOT_DIR}" \
  scripts/ci \
  ci/allowlists \
  .github/workflows/ci-testing.yml

cat > "${OUT_DIR}/${PROVENANCE_FILE}" <<JSON
{
  "project": "${PROJECT_NAME}",
  "artifact_name": "${ARTIFACT_NAME}",
  "artifact_version": "${ARTIFACT_VERSION}",
  "git_sha": "${GIT_SHA}",
  "git_sha_short": "${GIT_SHA_SHORT}",
  "git_ref": "${GIT_REF}",
  "created_at_utc": "${BUILD_TS_UTC}",
  "source_paths": [
    "scripts/ci",
    "ci/allowlists",
    ".github/workflows/ci-testing.yml"
  ],
  "ci_context": {
    "github_workflow": "${GITHUB_WORKFLOW:-}",
    "github_run_id": "${GITHUB_RUN_ID:-}",
    "github_run_attempt": "${GITHUB_RUN_ATTEMPT:-}",
    "github_repository": "${GITHUB_REPOSITORY:-}",
    "github_actor": "${GITHUB_ACTOR:-}",
    "github_event_name": "${GITHUB_EVENT_NAME:-}"
  }
}
JSON

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "artifact_version=${ARTIFACT_VERSION}"
    echo "bundle_file=${BUNDLE_FILE}"
    echo "provenance_file=${PROVENANCE_FILE}"
    echo "out_dir=${OUT_DIR}"
  } >> "${GITHUB_OUTPUT}"
fi

echo "Built artifact bundle: ${OUT_DIR}/${BUNDLE_FILE}"
echo "Built provenance file: ${OUT_DIR}/${PROVENANCE_FILE}"
