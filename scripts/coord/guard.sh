#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/coord/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") [--plan-file path] [--check-only] -- <command> [args...]
  $(basename "$0") [--plan-file path] [--check-only] <command> [args...]

Checks task plan + local locks every invocation before running the command.
Mutating commands are blocked unless required locks are held by the current branch owner.
USAGE
}

PLAN_FILE_INPUT=""
CHECK_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan-file)
      PLAN_FILE_INPUT="${2:-}"
      shift 2
      ;;
    --check-only)
      CHECK_ONLY=1
      shift
      ;;
    --)
      shift
      break
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      break
      ;;
  esac
done

(( $# > 0 )) || coord_die "No command provided"

command_is_mutating() {
  local cmd arg
  cmd="$1"
  shift

  case "$cmd" in
    terraform)
      for arg in "$@"; do
        case "$arg" in
          apply|destroy|import|taint|untaint|state|workspace)
            return 0
            ;;
        esac
      done
      ;;
    kubectl)
      for arg in "$@"; do
        case "$arg" in
          apply|create|delete|patch|replace|scale|annotate|label|set|rollout|drain|cordon|uncordon|taint|edit)
            return 0
            ;;
        esac
      done
      ;;
    flux)
      for arg in "$@"; do
        case "$arg" in
          reconcile|suspend|resume|create|delete|bootstrap|install|uninstall)
            return 0
            ;;
        esac
      done
      ;;
    ansible-playbook)
      return 0
      ;;
    helm)
      for arg in "$@"; do
        case "$arg" in
          install|upgrade|uninstall|rollback)
            return 0
            ;;
        esac
      done
      ;;
  esac

  return 1
}

coord_ensure_runtime_dirs

if [[ -n "$PLAN_FILE_INPUT" ]]; then
  "$SCRIPT_DIR/task-plan-validate.sh" --plan-file "$PLAN_FILE_INPUT" --quiet
  coord_load_plan "$PLAN_FILE_INPUT"
else
  "$SCRIPT_DIR/task-plan-validate.sh" --quiet
  coord_load_plan "$(coord_plan_file_for_branch "$(coord_branch)")"
fi

CMD=("$@")
MUTATING=0
if command_is_mutating "${CMD[@]}"; then
  MUTATING=1
fi

conflicts=()
missing=()

while IFS= read -r key; do
  [[ -z "$key" ]] && continue

  lock_dir="$(coord_lock_dir_for_key "$key")"
  meta_file="$lock_dir/metadata.env"

  if [[ ! -d "$lock_dir" ]]; then
    missing+=("$key")
    continue
  fi

  owner="$(coord_lock_meta_field "$meta_file" "owner" || true)"
  branch="$(coord_lock_meta_field "$meta_file" "branch" || true)"

  if [[ "$owner" != "$PLAN_OWNER" || "$branch" != "$PLAN_BRANCH" ]]; then
    conflicts+=("$key:${owner:-unknown}:${branch:-unknown}")
  fi
done < <(coord_lock_keys_from_unstable "$PLAN_UNSTABLE_NORM")

if (( ${#conflicts[@]} > 0 )); then
  coord_die "Lock conflict(s): ${conflicts[*]}"
fi

if (( ${#missing[@]} > 0 )); then
  if [[ "$MUTATING" -eq 1 ]]; then
    coord_die "Missing required lock(s): ${missing[*]}. Run scripts/coord/lock-acquire.sh first."
  fi

  coord_warn "Missing lock(s) for non-mutating command: ${missing[*]}"
fi

if [[ "$CHECK_ONLY" -eq 1 ]]; then
  coord_info "Preflight check passed for: ${CMD[*]}"
  exit 0
fi

exec "${CMD[@]}"
