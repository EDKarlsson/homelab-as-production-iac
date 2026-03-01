#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/coord/common.sh
source "$SCRIPT_DIR/common.sh"

coord_ensure_runtime_dirs
NOW_EPOCH="$(coord_now_epoch)"

printf '%-40s %-16s %-44s %-10s %-8s\n' "LOCK_KEY" "OWNER" "BRANCH" "STATE" "EXPIRES"
printf '%-40s %-16s %-44s %-10s %-8s\n' "--------" "-----" "------" "-----" "-------"

while IFS= read -r lock_dir; do
  [[ -d "$lock_dir" ]] || continue
  meta_file="$lock_dir/metadata.env"

  key="$(coord_lock_meta_field "$meta_file" "lock_key" || basename "$lock_dir" .lock)"
  owner="$(coord_lock_meta_field "$meta_file" "owner" || echo unknown)"
  branch="$(coord_lock_meta_field "$meta_file" "branch" || echo unknown)"
  expires_epoch="$(coord_lock_meta_field "$meta_file" "expires_epoch" || echo 0)"

  state="active"
  expires_in="n/a"
  if [[ "$expires_epoch" =~ ^[0-9]+$ ]]; then
    if (( expires_epoch < NOW_EPOCH )); then
      state="expired"
      expires_in="-"
    else
      expires_in="$((expires_epoch - NOW_EPOCH))s"
    fi
  fi

  printf '%-40s %-16s %-44s %-10s %-8s\n' "$key" "$owner" "$branch" "$state" "$expires_in"
done < <(find "$COORD_LOCK_DIR" -mindepth 1 -maxdepth 1 -type d | sort)
