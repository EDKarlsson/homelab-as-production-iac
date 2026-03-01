#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/coord/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") [--plan-file path] [--ttl-minutes 240]

Acquires local runtime locks for all unstable services + lock domains in the task plan.
USAGE
}

PLAN_FILE_INPUT=""
TTL_MINUTES=240

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan-file)
      PLAN_FILE_INPUT="${2:-}"
      shift 2
      ;;
    --ttl-minutes)
      TTL_MINUTES="${2:-}"
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

[[ "$TTL_MINUTES" =~ ^[0-9]+$ ]] || coord_die "--ttl-minutes must be an integer"

coord_ensure_runtime_dirs

if [[ -n "$PLAN_FILE_INPUT" ]]; then
  "$SCRIPT_DIR/task-plan-validate.sh" --plan-file "$PLAN_FILE_INPUT" --quiet
  coord_load_plan "$PLAN_FILE_INPUT"
else
  "$SCRIPT_DIR/task-plan-validate.sh" --quiet
  coord_load_plan "$(coord_plan_file_for_branch "$(coord_branch)")"
fi

NOW_EPOCH="$(coord_now_epoch)"
EXPIRES_EPOCH="$((NOW_EPOCH + TTL_MINUTES * 60))"
HOST_SHORT="$(hostname -s 2>/dev/null || hostname || echo unknown-host)"

acquired_keys=()
conflicts=()

write_metadata() {
  local key="$1"
  local lock_dir meta_file
  lock_dir="$(coord_lock_dir_for_key "$key")"
  meta_file="$lock_dir/metadata.env"

  cat > "$meta_file" <<META
lock_key=$key
owner=$PLAN_OWNER
branch=$PLAN_BRANCH
pid=$$
host=$HOST_SHORT
created_epoch=$NOW_EPOCH
created_utc=$(coord_now_utc)
expires_epoch=$EXPIRES_EPOCH
plan_file=$PLAN_FILE
services=$PLAN_SERVICES_NORM
unstable_services=$PLAN_UNSTABLE_NORM
META
}

while IFS= read -r key; do
  [[ -z "$key" ]] && continue

  lock_dir="$(coord_lock_dir_for_key "$key")"
  meta_file="$lock_dir/metadata.env"

  if [[ -d "$lock_dir" ]]; then
    existing_expires="$(coord_lock_meta_field "$meta_file" "expires_epoch" || true)"
    if [[ -n "$existing_expires" ]] && [[ "$existing_expires" =~ ^[0-9]+$ ]] && (( existing_expires < NOW_EPOCH )); then
      coord_warn "Removing expired lock: $key"
      rm -rf "$lock_dir"
    fi
  fi

  if mkdir "$lock_dir" 2>/dev/null; then
    write_metadata "$key"
    acquired_keys+=("$key")
    continue
  fi

  existing_owner="$(coord_lock_meta_field "$meta_file" "owner" || true)"
  existing_branch="$(coord_lock_meta_field "$meta_file" "branch" || true)"

  if [[ "$existing_owner" == "$PLAN_OWNER" && "$existing_branch" == "$PLAN_BRANCH" ]]; then
    write_metadata "$key"
    continue
  fi

  conflicts+=("$key:${existing_owner:-unknown}:${existing_branch:-unknown}")
done < <(coord_lock_keys_from_unstable "$PLAN_UNSTABLE_NORM")

if (( ${#conflicts[@]} > 0 )); then
  for key in "${acquired_keys[@]}"; do
    rm -rf "$(coord_lock_dir_for_key "$key")"
  done

  coord_die "Lock conflict(s): ${conflicts[*]}"
fi

coord_info "Locks acquired/refreshed for branch=$PLAN_BRANCH owner=$PLAN_OWNER"
