#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/coord/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") [--plan-file path] [--all] [--force]

Releases local runtime locks for the current plan (or all locks owned by plan owner+branch).
USAGE
}

PLAN_FILE_INPUT=""
RELEASE_ALL=0
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan-file)
      PLAN_FILE_INPUT="${2:-}"
      shift 2
      ;;
    --all)
      RELEASE_ALL=1
      shift
      ;;
    --force)
      FORCE=1
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
  coord_load_plan "$(coord_plan_file_for_branch "$(coord_branch)")"
fi

removed=0

if [[ "$RELEASE_ALL" -eq 1 ]]; then
  while IFS= read -r lock_dir; do
    [[ -d "$lock_dir" ]] || continue
    meta_file="$lock_dir/metadata.env"
    owner="$(coord_lock_meta_field "$meta_file" "owner" || true)"
    branch="$(coord_lock_meta_field "$meta_file" "branch" || true)"

    if [[ "$FORCE" -eq 1 || ( "$owner" == "$PLAN_OWNER" && "$branch" == "$PLAN_BRANCH" ) ]]; then
      rm -rf "$lock_dir"
      removed=$((removed + 1))
    fi
  done < <(find "$COORD_LOCK_DIR" -mindepth 1 -maxdepth 1 -type d | sort)
else
  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    lock_dir="$(coord_lock_dir_for_key "$key")"
    [[ -d "$lock_dir" ]] || continue

    meta_file="$lock_dir/metadata.env"
    owner="$(coord_lock_meta_field "$meta_file" "owner" || true)"
    branch="$(coord_lock_meta_field "$meta_file" "branch" || true)"

    if [[ "$FORCE" -eq 1 || ( "$owner" == "$PLAN_OWNER" && "$branch" == "$PLAN_BRANCH" ) ]]; then
      rm -rf "$lock_dir"
      removed=$((removed + 1))
    fi
  done < <(coord_lock_keys_from_unstable "$PLAN_UNSTABLE_NORM")
fi

coord_info "Released lock count: $removed"
