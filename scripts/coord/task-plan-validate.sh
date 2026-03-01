#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/coord/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") [--plan-file path] [--branch branch] [--quiet]

Validates branch/task-plan consistency and unstable service declaration quality.
USAGE
}

PLAN_FILE_INPUT=""
BRANCH_INPUT="$(coord_branch)"
QUIET=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan-file)
      PLAN_FILE_INPUT="${2:-}"
      shift 2
      ;;
    --branch)
      BRANCH_INPUT="${2:-}"
      shift 2
      ;;
    --quiet)
      QUIET=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      coord_die "Unknown argument: $1"
      ;;
  esac
done

coord_ensure_runtime_dirs

if [[ -n "$PLAN_FILE_INPUT" ]]; then
  coord_load_plan "$PLAN_FILE_INPUT"
else
  coord_load_plan "$(coord_plan_file_for_branch "$BRANCH_INPUT")"
fi

CURRENT_BRANCH="$(coord_branch)"
if [[ "$PLAN_BRANCH" != "$CURRENT_BRANCH" ]]; then
  coord_die "Plan branch mismatch. plan=$PLAN_BRANCH current=$CURRENT_BRANCH"
fi

BRANCH_SERVICES="$(coord_branch_services "$PLAN_BRANCH")"
if [[ -n "$BRANCH_SERVICES" ]]; then
  MISSING_FROM_SERVICES="$(coord_csv_missing_items "$BRANCH_SERVICES" "$PLAN_SERVICES_NORM")"
  if [[ -n "$MISSING_FROM_SERVICES" ]]; then
    coord_die "SERVICES is missing branch-detected service(s): $MISSING_FROM_SERVICES"
  fi
fi

REQUIRED_UNSTABLE="$(coord_required_unstable_for_plan)"
MISSING_FROM_UNSTABLE="$(coord_csv_missing_items "$REQUIRED_UNSTABLE" "$PLAN_UNSTABLE_NORM")"
if [[ -n "$MISSING_FROM_UNSTABLE" ]]; then
  coord_die "UNSTABLE_SERVICES is missing required item(s): $MISSING_FROM_UNSTABLE"
fi

if [[ "$QUIET" -eq 0 ]]; then
  coord_info "Plan file: $PLAN_FILE"
  coord_info "Branch: $PLAN_BRANCH"
  coord_info "Owner: $PLAN_OWNER"
  coord_info "Services: $PLAN_SERVICES_NORM"
  coord_info "Unstable services: $PLAN_UNSTABLE_NORM"
  coord_info "Required unstable coverage: $REQUIRED_UNSTABLE"
fi
