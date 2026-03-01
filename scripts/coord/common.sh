#!/usr/bin/env bash
set -euo pipefail

COORD_REPO_ROOT="${COORD_REPO_ROOT:-$(git rev-parse --show-toplevel)}"
COORD_DIR="${COORD_DIR:-$COORD_REPO_ROOT/.coord}"
COORD_PLAN_DIR="${COORD_PLAN_DIR:-$COORD_DIR/task-plans}"
COORD_LOCK_DIR="${COORD_LOCK_DIR:-$COORD_DIR/locks}"
COORD_SERVICE_MAP="${COORD_SERVICE_MAP:-$COORD_REPO_ROOT/configs/coordination/service-map.csv}"
COORD_SERVICE_DEPS="${COORD_SERVICE_DEPS:-$COORD_REPO_ROOT/configs/coordination/service-deps.csv}"

coord_die() {
  echo "ERROR: $*" >&2
  exit 1
}

coord_warn() {
  echo "WARN: $*" >&2
}

coord_info() {
  echo "INFO: $*" >&2
}

coord_now_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

coord_now_epoch() {
  date -u +"%s"
}

coord_branch() {
  git -C "$COORD_REPO_ROOT" rev-parse --abbrev-ref HEAD
}

coord_owner() {
  printf '%s\n' "${COORD_OWNER:-${USER:-unknown}}"
}

coord_sanitize_branch() {
  local value="${1:-}"
  value="${value//\//_}"
  value="${value// /_}"
  printf '%s\n' "$value" | tr -cd '[:alnum:]_.-'
}

coord_plan_file_for_branch() {
  local branch="${1:-}"
  [[ -n "$branch" ]] || coord_die "coord_plan_file_for_branch requires a branch name"
  printf '%s/%s.env\n' "$COORD_PLAN_DIR" "$(coord_sanitize_branch "$branch")"
}

coord_current_plan_file() {
  coord_plan_file_for_branch "$(coord_branch)"
}

coord_ensure_runtime_dirs() {
  mkdir -p "$COORD_PLAN_DIR" "$COORD_LOCK_DIR"
}

coord_normalize_csv() {
  local input="${1:-}"
  if [[ -z "${input//[[:space:],]/}" ]]; then
    echo ""
    return 0
  fi

  printf '%s\n' "$input" \
    | tr ',' '\n' \
    | sed 's/#.*$//' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
    | awk 'NF {print tolower($0)}' \
    | awk '!seen[$0]++' \
    | paste -sd, -
}

coord_csv_to_lines() {
  local csv
  csv="$(coord_normalize_csv "${1:-}")"
  if [[ -z "$csv" ]]; then
    return 0
  fi
  printf '%s\n' "$csv" | tr ',' '\n'
}

coord_csv_contains() {
  local haystack needle
  haystack="$(coord_normalize_csv "${1:-}")"
  needle="$(coord_normalize_csv "${2:-}")"
  [[ -z "$needle" ]] && return 1
  while IFS= read -r entry; do
    [[ "$entry" == "$needle" ]] && return 0
  done < <(coord_csv_to_lines "$haystack")
  return 1
}

coord_csv_union() {
  local merged
  merged="$(coord_normalize_csv "${1:-},${2:-}")"
  printf '%s\n' "$merged"
}

coord_csv_missing_items() {
  local required actual
  required="$(coord_normalize_csv "${1:-}")"
  actual="$(coord_normalize_csv "${2:-}")"

  local missing=""
  while IFS= read -r item; do
    [[ -z "$item" ]] && continue
    if ! coord_csv_contains "$actual" "$item"; then
      missing="$(coord_csv_union "$missing" "$item")"
    fi
  done < <(coord_csv_to_lines "$required")

  printf '%s\n' "$missing"
}

coord_domain_for_service() {
  local target service domain token
  target="$(coord_normalize_csv "${1:-}")"
  [[ -z "$target" ]] && return 0

  while IFS=',' read -r token service domain; do
    [[ -z "${token// }" ]] && continue
    [[ "$token" =~ ^[[:space:]]*# ]] && continue

    service="$(coord_normalize_csv "$service")"
    domain="$(coord_normalize_csv "$domain")"

    if [[ "$service" == "$target" ]]; then
      printf '%s\n' "$domain"
      return 0
    fi
  done < "$COORD_SERVICE_MAP"

  printf '%s\n' ""
}

coord_services_to_domains() {
  local services service domain domains
  services="$(coord_normalize_csv "${1:-}")"
  domains=""

  while IFS= read -r service; do
    [[ -z "$service" ]] && continue
    domain="$(coord_domain_for_service "$service")"
    [[ -n "$domain" ]] && domains="$(coord_csv_union "$domains" "$domain")"
  done < <(coord_csv_to_lines "$services")

  printf '%s\n' "$domains"
}

coord_branch_services() {
  local branch branch_lc token service domain detected
  branch="${1:-$(coord_branch)}"
  branch_lc="$(printf '%s\n' "$branch" | tr '[:upper:]' '[:lower:]')"
  detected=""

  while IFS=',' read -r token service domain; do
    [[ -z "${token// }" ]] && continue
    [[ "$token" =~ ^[[:space:]]*# ]] && continue

    token="$(coord_normalize_csv "$token")"
    service="$(coord_normalize_csv "$service")"
    [[ -z "$token" || -z "$service" ]] && continue

    if [[ "$branch_lc" == *"$token"* ]]; then
      detected="$(coord_csv_union "$detected" "$service")"
    fi
  done < "$COORD_SERVICE_MAP"

  printf '%s\n' "$detected"
}

coord_dependency_services() {
  local services service line_service deps detected line
  services="$(coord_normalize_csv "${1:-}")"
  detected=""

  while IFS= read -r line; do
    [[ -z "${line// }" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    line_service="${line%%,*}"
    deps="${line#*,}"
    line_service="$(coord_normalize_csv "$line_service")"
    deps="$(coord_normalize_csv "$deps")"

    [[ -z "$line_service" || -z "$deps" ]] && continue

    if coord_csv_contains "$services" "$line_service"; then
      detected="$(coord_csv_union "$detected" "$deps")"
    fi
  done < "$COORD_SERVICE_DEPS"

  printf '%s\n' "$detected"
}

coord_required_unstable_for_plan() {
  local services branch required
  services="$(coord_normalize_csv "${PLAN_SERVICES_NORM:-}")"
  branch="${PLAN_BRANCH:-$(coord_branch)}"

  required="$(coord_csv_union "$services" "$(coord_dependency_services "$services")")"
  required="$(coord_csv_union "$required" "$(coord_branch_services "$branch")")"

  printf '%s\n' "$required"
}

coord_load_plan() {
  local plan_file="${1:-$(coord_current_plan_file)}"
  [[ -f "$plan_file" ]] || coord_die "Task plan not found: $plan_file"

  # shellcheck disable=SC1090
  source "$plan_file"

  # shellcheck disable=SC2034
  PLAN_FILE="$plan_file"
  PLAN_BRANCH="${BRANCH:-}"
  PLAN_OWNER="${OWNER:-}"
  PLAN_SUMMARY="${TASK_SUMMARY:-}"
  PLAN_SERVICES_NORM="$(coord_normalize_csv "${SERVICES:-}")"
  PLAN_UNSTABLE_NORM="$(coord_normalize_csv "${UNSTABLE_SERVICES:-}")"

  [[ -n "$PLAN_BRANCH" ]] || coord_die "BRANCH is missing in $plan_file"
  [[ -n "$PLAN_OWNER" ]] || coord_die "OWNER is missing in $plan_file"
  [[ -n "$PLAN_SUMMARY" ]] || coord_die "TASK_SUMMARY is missing in $plan_file"
  [[ -n "$PLAN_SERVICES_NORM" ]] || coord_die "SERVICES is missing/empty in $plan_file"
  [[ -n "$PLAN_UNSTABLE_NORM" ]] || coord_die "UNSTABLE_SERVICES is missing/empty in $plan_file"
}

coord_lock_keys_from_unstable() {
  local unstable services domains key
  unstable="$(coord_normalize_csv "${1:-}")"
  services="$unstable"
  domains="$(coord_services_to_domains "$unstable")"

  local keys=""

  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    keys="$(coord_csv_union "$keys" "service__$key")"
  done < <(coord_csv_to_lines "$services")

  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    keys="$(coord_csv_union "$keys" "domain__$key")"
  done < <(coord_csv_to_lines "$domains")

  coord_csv_to_lines "$keys"
}

coord_lock_dir_for_key() {
  local key="${1:-}"
  printf '%s/%s.lock\n' "$COORD_LOCK_DIR" "$key"
}

coord_lock_meta_file_for_key() {
  local key="${1:-}"
  printf '%s/metadata.env\n' "$(coord_lock_dir_for_key "$key")"
}

coord_lock_meta_field() {
  local meta_file key
  meta_file="${1:-}"
  key="${2:-}"
  [[ -f "$meta_file" ]] || return 1
  awk -F'=' -v k="$key" '$1==k{print substr($0, index($0,"=")+1)}' "$meta_file" | head -n1
}
