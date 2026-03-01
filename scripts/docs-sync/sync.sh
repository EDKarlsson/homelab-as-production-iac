#!/usr/bin/env bash
# sync.sh — One-way sync of docs/ to the Wiki.js Git storage repo.
#
# Usage: bash scripts/docs-sync/sync.sh <target-repo-path> [project-prefix]
#
# The project-prefix (default: repo directory name) namespaces all synced
# pages under a project directory in the Wiki.js repo, preventing conflicts
# when multiple projects sync to the same wiki. Set to "" to sync to root.
#
# Path mapping (with prefix "projects/homelab-iac"):
#   docs/README.md           → projects/homelab-iac.md    (sibling landing page)
#   docs/CHANGELOG.md        → projects/homelab-iac/changelog.md
#   docs/PROJECT-PLAN.md     → projects/homelab-iac/project-plan.md
#   docs/guides/README.md    → projects/homelab-iac/guides.md  (section index, sibling)
#   docs/guides/<name>.md    → projects/homelab-iac/guides/<name>.md
#   docs/architecture/*.md   → projects/homelab-iac/architecture/<name>.md
#   docs/reference/*.md      → projects/homelab-iac/reference/<name>.md
#
# The project README is placed as a "sibling page" (prefix.md alongside prefix/)
# so Wiki.js displays the frontmatter title in the navigation tree instead of
# the raw folder name. This also makes breadcrumbs clickable at every level.
#
# Files in docs/archive/ are excluded (handled by workflow path filter).
# Wiki.js YAML frontmatter is added if missing, preserved if present.
# The wiki root home.md and projects.md are hand-curated — never overwritten.

set -euo pipefail

TARGET="${1:?Usage: sync.sh <target-repo-path> [project-prefix]}"
PREFIX="${2:-$(basename "$(pwd)")}"
DOCS_DIR="docs"
NOW="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"

# Build the output directory
if [[ -n "$PREFIX" ]]; then
  OUT_DIR="$TARGET/$PREFIX"
else
  OUT_DIR="$TARGET"
fi

# Derive a title from filename: kebab-case → Title Case
title_from_filename() {
  local name="$1"
  echo "$name" | sed 's/\.md$//' | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1'
}

# Add Wiki.js frontmatter if the file doesn't already have it
ensure_frontmatter() {
  local file="$1"
  local title="$2"
  local description="${3:-}"

  # Check if file already starts with ---
  if head -1 "$file" | grep -q '^---$'; then
    return 0
  fi

  local tmp
  tmp="$(mktemp)"
  cat > "$tmp" <<EOF
---
title: ${title}
description: ${description}
published: true
date: ${NOW}
tags:
editor: markdown
dateCreated: ${NOW}
---

EOF
  cat "$file" >> "$tmp"
  mv "$tmp" "$file"
}

# Sync a single file: copy to target, ensure frontmatter
sync_file() {
  local src="$1"
  local dest="$2"
  local title="$3"
  local desc="${4:-}"

  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
  ensure_frontmatter "$dest" "$title" "$desc"
}

echo "Syncing docs/ → ${OUT_DIR}/ (prefix: ${PREFIX:-<none>})"

# Clean previous sync for this project (remove stale pages)
if [[ -d "$OUT_DIR" ]]; then
  find "$OUT_DIR" -name '*.md' -delete
  # Remove empty directories left behind
  find "$OUT_DIR" -type d -empty -delete 2>/dev/null || true
fi
# Also clean the sibling landing page (prefix.md alongside prefix/)
if [[ -n "$PREFIX" && -f "${OUT_DIR}.md" ]]; then
  rm "${OUT_DIR}.md"
fi
mkdir -p "$OUT_DIR"

# --- Special mappings for README/index files ---
# Project README → sibling page (prefix.md) for clean Wiki.js navigation
sync_file "$DOCS_DIR/README.md" "${OUT_DIR}.md" \
  "Homelab IAC" "Infrastructure as Code documentation for Proxmox homelab"

sync_file "$DOCS_DIR/CHANGELOG.md" "$OUT_DIR/changelog.md" \
  "Changelog" "Project changelog and decision log"

sync_file "$DOCS_DIR/PROJECT-PLAN.md" "$OUT_DIR/project-plan.md" \
  "Project Plan" "Phased roadmap from repo cleanup to app deployment"

# Guides section index
if [[ -f "$DOCS_DIR/guides/README.md" ]]; then
  sync_file "$DOCS_DIR/guides/README.md" "$OUT_DIR/guides.md" \
    "Infrastructure Guides" "Step-by-step walkthroughs for Proxmox homelab with Terraform"
fi

# --- Sync directories: guides, architecture, reference ---
for dir in guides architecture reference; do
  if [[ ! -d "$DOCS_DIR/$dir" ]]; then
    continue
  fi

  for file in "$DOCS_DIR/$dir"/*.md; do
    [[ -f "$file" ]] || continue
    local_name="$(basename "$file")"

    # Skip README.md — already handled as section index above
    if [[ "$local_name" == "README.md" ]]; then
      continue
    fi

    title="$(title_from_filename "$local_name")"
    sync_file "$file" "$OUT_DIR/$dir/$local_name" "$title"
  done
done

# Summary (count pages inside prefix dir + the sibling landing page)
synced=$(find "$OUT_DIR" -name '*.md' -not -path '*/.git/*' | wc -l)
[[ -n "$PREFIX" && -f "${OUT_DIR}.md" ]] && synced=$((synced + 1))
echo "Done — ${synced} pages synced to ${OUT_DIR}/"
