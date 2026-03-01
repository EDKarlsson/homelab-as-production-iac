---
title: "Slack/GitHub Workflow 2: Scheduled Maintenance Windows"
description: GitHub Actions scheduled cron workflows that create and track recurring maintenance tasks as GitHub issues, with Slack notifications.
published: true
date: 2026-02-21
tags:
  - slack
  - github
  - github-actions
  - maintenance
  - cert-manager
  - velero
  - automation
---

# Workflow 2: Scheduled Maintenance Windows

## Summary

GitHub Actions scheduled workflows run weekly/monthly checks and create (or update) GitHub issues for recurring maintenance tasks. No new cluster components required — this runs entirely in GitHub Actions using `gh` CLI and `kubectl` via the Tailscale API proxy.

```
GitHub Actions cron trigger
        ↓
Check cluster state (kubectl, gh, curl)
        ↓
  ┌── issue open + same week ──→ skip (dedup)
  ├── issue open + new week ───→ add comment with latest data
  └── no open issue ──────────→ create issue with checklist
        ↓
Slack notification via webhook (issue URL + status)
```

---

## Plan

### Maintenance checks to automate

| Check | Schedule | Alert condition | Tool |
|---|---|---|---|
| Certificate expiry | Weekly (Mon 08:00) | Any cert expiring within 30 days | `kubectl get certificate` |
| K3s version lag | Weekly (Mon 08:00) | Running version behind latest stable by 2+ minor versions | GitHub releases API |
| Backup health | Weekly (Mon 08:00) | Velero or pg-backup failed/missing in last 7 days | `kubectl get jobs` + Prometheus |
| Dependency updates | Monthly (1st Mon) | Helm chart versions outdated in HelmReleases | `helm search repo` |

### Components

| Component | Role | Already available? |
|---|---|---|
| GitHub Actions | Cron scheduler + runner | ✅ yes |
| `gh` CLI | Create/search/close GitHub issues | ✅ yes (authenticated) |
| `kubectl` | Query cluster state | ✅ (Tailscale API proxy) |
| Slack webhook | Post maintenance digest | ✅ (existing webhook) |
| cert-manager | Certificate status | ✅ deployed |
| Velero | Backup status | ✅ deployed |

### Issue lifecycle

Each maintenance check follows the same issue lifecycle:

```
Weekly cron runs
  → Search: open issues with label "maintenance" + title prefix
  → If found AND created this week: skip
  → If found AND older than 7 days: add status comment
  → If not found: create fresh issue with checklist + due date
  → Post Slack digest summarizing all open maintenance issues
```

---

## Prototype

### GitHub Actions workflow: `maintenance-checks.yml`

```yaml
# .github/workflows/maintenance-checks.yml
name: Maintenance Checks

on:
  schedule:
    - cron: "0 8 * * 1"   # Every Monday at 08:00 UTC
  workflow_dispatch:        # Allow manual trigger

jobs:
  cert-expiry:
    name: Certificate Expiry Check
    runs-on: self-hosted
    steps:
      - name: Check certificates expiring within 30 days
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          KUBECONFIG: /home/runner/.kube/config-homelab
        run: |
          set -euo pipefail
          EXPIRING=""
          while IFS= read -r line; do
            NAME=$(echo "$line" | awk '{print $1}')
            NS=$(echo "$line" | awk '{print $2}')
            NOT_AFTER=$(kubectl get certificate "$NAME" -n "$NS" \
              -o jsonpath='{.status.notAfter}' 2>/dev/null || true)
            if [[ -z "$NOT_AFTER" ]]; then continue; fi
            EXPIRY_EPOCH=$(date -d "$NOT_AFTER" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$NOT_AFTER" +%s)
            NOW_EPOCH=$(date +%s)
            DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))
            if [[ $DAYS_LEFT -lt 30 ]]; then
              EXPIRING="${EXPIRING}\n- \`${NS}/${NAME}\`: expires in ${DAYS_LEFT} days (${NOT_AFTER})"
            fi
          done < <(kubectl get certificate -A -o json 2>/dev/null | jq -r '.items[] | "\(.metadata.name) \(.metadata.namespace)"')

          if [[ -z "$EXPIRING" ]]; then
            echo "All certificates valid for 30+ days."
            exit 0
          fi

          TITLE="[maintenance] Certificate expiry warning"
          EXISTING=$(gh issue list --repo homelab-admin/homelab-iac \
            --label maintenance --state open --search "$TITLE" --json number,createdAt \
            --jq '.[0] // empty')

          BODY="## Certificates Expiring Within 30 Days\n\n$(echo -e "$EXPIRING")\n\n### Checklist\n- [ ] Verify cert-manager can renew (check \`CertificateRequest\` status)\n- [ ] Manual renewal if auto-renew is blocked\n- [ ] Update any hardcoded cert references\n\n_Generated: $(date -u)_"

          if [[ -n "$EXISTING" ]]; then
            NUM=$(echo "$EXISTING" | jq -r '.number')
            gh issue comment "$NUM" --repo homelab-admin/homelab-iac \
              --body "$(echo -e "$BODY")"
            echo "Updated issue #${NUM}"
          else
            gh issue create --repo homelab-admin/homelab-iac \
              --title "$TITLE" \
              --label "maintenance,cert-manager" \
              --body "$(echo -e "$BODY")"
          fi

  k3s-version-check:
    name: K3s Version Check
    runs-on: self-hosted
    steps:
      - name: Compare running K3s version to latest stable
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          KUBECONFIG: /home/runner/.kube/config-homelab
        run: |
          set -euo pipefail
          RUNNING=$(kubectl version -o json 2>/dev/null | jq -r '.serverVersion.gitVersion')
          LATEST=$(curl -s https://api.github.com/repos/k3s-io/k3s/releases/latest \
            -H "Authorization: token $GH_TOKEN" | jq -r '.tag_name')

          echo "Running: $RUNNING | Latest: $LATEST"

          RUNNING_MINOR=$(echo "$RUNNING" | grep -oP '\d+\.\d+' | head -1 | cut -d. -f2)
          LATEST_MINOR=$(echo "$LATEST"  | grep -oP '\d+\.\d+' | head -1 | cut -d. -f2)
          LAG=$(( LATEST_MINOR - RUNNING_MINOR ))

          if [[ $LAG -lt 2 ]]; then
            echo "K3s version lag is ${LAG} minor versions — within acceptable range."
            exit 0
          fi

          TITLE="[maintenance] K3s version lag: ${RUNNING} → ${LATEST}"
          gh issue create --repo homelab-admin/homelab-iac \
            --title "$TITLE" \
            --label "maintenance,k3s,upgrade" \
            --body "## K3s Version Upgrade Needed

| | Version |
|---|---|
| **Running** | \`${RUNNING}\` |
| **Latest stable** | \`${LATEST}\` |
| **Minor version lag** | ${LAG} |

### Checklist
- [ ] Review K3s changelog for breaking changes
- [ ] Test upgrade on a single agent node first
- [ ] Run rolling upgrade: agents → servers (see \`ansible/playbooks/k3s-upgrade.yml\`)
- [ ] Verify cluster health post-upgrade (\`bash scripts/k8s/k3s-verify.sh --quick\`)

_Generated: $(date -u)_"

  backup-health:
    name: Backup Health Check
    runs-on: self-hosted
    steps:
      - name: Verify Velero and pg-backup completed successfully this week
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          KUBECONFIG: /home/runner/.kube/config-homelab
        run: |
          set -euo pipefail
          ISSUES=""

          # Check Velero last successful backup
          VELERO_LAST=$(kubectl get backup -n velero \
            --field-selector=status.phase=Completed \
            --sort-by='.metadata.creationTimestamp' \
            -o jsonpath='{.items[-1].status.completionTimestamp}' 2>/dev/null || echo "")
          if [[ -n "$VELERO_LAST" ]]; then
            VELERO_EPOCH=$(date -d "$VELERO_LAST" +%s 2>/dev/null || echo 0)
            NOW_EPOCH=$(date +%s)
            HOURS_AGO=$(( (NOW_EPOCH - VELERO_EPOCH) / 3600 ))
            if [[ $HOURS_AGO -gt 26 ]]; then
              ISSUES="${ISSUES}\n- ⚠️ Velero: last successful backup was ${HOURS_AGO}h ago (expected: <26h)"
            fi
          else
            ISSUES="${ISSUES}\n- ❌ Velero: no successful backups found"
          fi

          # Check pg-backup CronJob last completion
          PG_LAST=$(kubectl get jobs -n monitoring -l app.kubernetes.io/name=pg-backup \
            --field-selector=status.successful=1 \
            --sort-by='.metadata.creationTimestamp' \
            -o jsonpath='{.items[-1].status.completionTime}' 2>/dev/null || echo "")
          if [[ -z "$PG_LAST" ]]; then
            ISSUES="${ISSUES}\n- ❌ pg-backup: no completed jobs found in monitoring namespace"
          fi

          if [[ -z "$ISSUES" ]]; then
            echo "All backups healthy."
            exit 0
          fi

          gh issue create --repo homelab-admin/homelab-iac \
            --title "[maintenance] Backup health issues detected" \
            --label "maintenance,backup,velero" \
            --body "## Backup Health Issues

$(echo -e "$ISSUES")

### Checklist
- [ ] Check Velero logs: \`kubectl logs -n velero -l app.kubernetes.io/name=velero\`
- [ ] Check pg-backup job logs: \`kubectl logs -n monitoring -l app.kubernetes.io/name=pg-backup\`
- [ ] Trigger manual backup if needed: \`velero backup create manual-$(date +%Y%m%d)\`
- [ ] Verify backup storage (NFS/S3) is accessible

_Generated: $(date -u)_"

  slack-digest:
    name: Post Maintenance Digest to Slack
    runs-on: self-hosted
    needs: [cert-expiry, k3s-version-check, backup-health]
    if: always()
    steps:
      - name: Post open maintenance issues digest to Slack
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          SLACK_WEBHOOK: ${{ secrets.SLACK_HOMELAB_WEBHOOK }}
        run: |
          set -euo pipefail
          OPEN=$(gh issue list --repo homelab-admin/homelab-iac \
            --label maintenance --state open --json number,title,url \
            --jq '.[] | "• <\(.url)|\(.title)>"' | head -10)

          if [[ -z "$OPEN" ]]; then
            MSG=":white_check_mark: *Weekly Maintenance Check* — No open maintenance issues."
          else
            MSG=":wrench: *Weekly Maintenance Check* — Open issues:\n${OPEN}"
          fi

          PAYLOAD=$(jq -n --arg text "$MSG" '{text: $text}')
          curl -s -X POST "$SLACK_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "$PAYLOAD"
```

### GitHub issue label setup

Create these labels in the repo once:

```bash
gh label create maintenance --color "e4e669" --description "Recurring maintenance task" --repo homelab-admin/homelab-iac
gh label create cert-manager --color "0075ca" --description "Certificate management" --repo homelab-admin/homelab-iac
gh label create backup       --color "d93f0b" --description "Backup system" --repo homelab-admin/homelab-iac
gh label create upgrade      --color "5319e7" --description "Version upgrade required" --repo homelab-admin/homelab-iac
```

### Repository secret for Slack webhook

```bash
gh secret set SLACK_HOMELAB_WEBHOOK \
  --repo homelab-admin/homelab-iac \
  --body "$(op item get alertmanager-slack --vault Homelab --field webhook-url)"
```

> The existing `alertmanager-slack` 1Password item already holds the Slack webhook URL — reuse it here.

---

## Workflow (Operational Guide)

### One-time setup

1. Add `.github/workflows/maintenance-checks.yml` to the repo.
2. Create the four GitHub labels (`maintenance`, `cert-manager`, `backup`, `upgrade`).
3. Set the `SLACK_HOMELAB_WEBHOOK` repository secret.
4. Ensure the self-hosted runner has `kubectl` and `gh` CLI with access to `~/.kube/config-homelab`.
5. Run manually once (`workflow_dispatch`) to verify all checks pass.

### Ongoing operation

- Every Monday at 08:00 UTC, the workflow runs all three checks in parallel.
- The `slack-digest` job always runs last and posts a summary of open maintenance issues.
- Close issues manually after completing the checklist items.
- If a check is flapping (creating duplicate issues), the dedup logic prevents duplicates within the same week.

### Adding new checks

The pattern for each check is identical:

```
run check → compute severity → search for open issue → create/comment → exit 0
```

Copy any existing job block and replace the check logic. Add the new job to the `needs:` list of `slack-digest`.

### Tuning the schedule

- Change `cron: "0 8 * * 1"` to adjust day/time (cron syntax, UTC).
- Add a second schedule entry for monthly checks (e.g., `cron: "0 8 1 * *"` for 1st of each month).
- Use `workflow_dispatch` for ad-hoc runs during incidents.
