#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/coord/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") --summary "..." [--services svc1,svc2] [--unstable svc1,svc2] [--owner name] [--branch branch]

Creates/updates .coord/task-plans/<sanitized-branch>.env
USAGE
}

SUMMARY=""
SERVICES_INPUT=""
UNSTABLE_INPUT=""
OWNER_INPUT="$(coord_owner)"
BRANCH_INPUT="$(coord_branch)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --summary)
      SUMMARY="${2:-}"
      shift 2
      ;;
    --services)
      SERVICES_INPUT="${2:-}"
      shift 2
      ;;
    --unstable)
      UNSTABLE_INPUT="${2:-}"
      shift 2
      ;;
    --owner)
      OWNER_INPUT="${2:-}"
      shift 2
      ;;
    --branch)
      BRANCH_INPUT="${2:-}"
      shift 2
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

[[ -n "$SUMMARY" ]] || coord_die "--summary is required"

coord_ensure_runtime_dirs

BRANCH_SERVICES="$(coord_branch_services "$BRANCH_INPUT")"

if [[ -n "$SERVICES_INPUT" ]]; then
  SERVICES_NORM="$(coord_normalize_csv "$SERVICES_INPUT")"
else
  SERVICES_NORM="$BRANCH_SERVICES"
fi

[[ -n "$SERVICES_NORM" ]] || coord_die "SERVICES resolved to empty. Pass --services explicitly."

REQUIRED_UNSTABLE="$(coord_csv_union "$SERVICES_NORM" "$(coord_dependency_services "$SERVICES_NORM")")"
REQUIRED_UNSTABLE="$(coord_csv_union "$REQUIRED_UNSTABLE" "$BRANCH_SERVICES")"

if [[ -n "$UNSTABLE_INPUT" ]]; then
  UNSTABLE_NORM="$(coord_normalize_csv "$UNSTABLE_INPUT")"
else
  UNSTABLE_NORM="$REQUIRED_UNSTABLE"
fi

[[ -n "$UNSTABLE_NORM" ]] || coord_die "UNSTABLE_SERVICES resolved to empty."

MISSING_UNSTABLE="$(coord_csv_missing_items "$REQUIRED_UNSTABLE" "$UNSTABLE_NORM")"
if [[ -n "$MISSING_UNSTABLE" ]]; then
  coord_die "UNSTABLE_SERVICES is missing required items: $MISSING_UNSTABLE"
fi

PLAN_FILE="$(coord_plan_file_for_branch "$BRANCH_INPUT")"
SUMMARY_ESCAPED="${SUMMARY//\\/\\\\}"
SUMMARY_ESCAPED="${SUMMARY_ESCAPED//\"/\\\"}"

cat > "$PLAN_FILE" <<PLAN
BRANCH="$BRANCH_INPUT"
OWNER="$OWNER_INPUT"
TASK_SUMMARY="$SUMMARY_ESCAPED"
SERVICES="$SERVICES_NORM"
UNSTABLE_SERVICES="$UNSTABLE_NORM"
TEST_PLAN=""
NOTES=""
LAST_UPDATED_UTC="$(coord_now_utc)"
PLAN

coord_info "Task plan written: $PLAN_FILE"
coord_info "Detected branch services: ${BRANCH_SERVICES:-<none>}"
coord_info "Services: $SERVICES_NORM"
coord_info "Unstable services: $UNSTABLE_NORM"
