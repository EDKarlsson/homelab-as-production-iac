---
title: "Slack/GitHub Workflow 1: Prometheus Alert → GitHub Issue"
description: Automatically create and track GitHub issues when Prometheus alerts fire, using n8n as the webhook bridge.
published: true
date: 2026-02-21
tags:
  - slack
  - github
  - alertmanager
  - n8n
  - prometheus
  - automation
---

# Workflow 1: Prometheus Alert → GitHub Issue

## Summary

When a `warning` or `critical` AlertManager alert fires, n8n receives a webhook, checks whether an open GitHub issue already exists for that alert, and creates one if not. When the alert resolves, n8n closes the issue with a resolution comment. Slack gets the GitHub issue link alongside the alert notification.

```
Prometheus fires alert
        ↓
AlertManager (severity: warning|critical)
        ↓  webhook receiver → n8n
n8n checks open GitHub issues for this alert
        ↓
  ┌── exists ──→ append comment, update labels
  └── new ──────→ create issue with context snapshot
        ↓
Slack: alert message + GitHub issue link
        ↓  (on resolve)
n8n closes issue with resolution comment
```

---

## Plan

### Components

| Component | Role | Already deployed? |
|---|---|---|
| AlertManager | Fires alerts, calls n8n webhook | ✅ yes |
| n8n | Webhook receiver, GitHub API calls, deduplication logic | ✅ yes |
| GitHub API | Issue create/update/close | ✅ (gh token available) |
| Slack | Alert notification with issue link | ✅ yes |

### AlertManager Changes Required

Add a new receiver `github-issues` and route `warning`/`critical` alerts to it **with `continue: true`** so Slack still receives them. The existing Slack routes remain unchanged.

The new route structure becomes:

```
route:
  receiver: "null"
  routes:
    - receiver: "null"              # Watchdog silenced
    - receiver: slack-critical      # critical → Slack
      continue: true                # also falls through
    - receiver: github-issues       # critical → n8n
      matchers: [severity = "critical"]
    - receiver: slack-notifications # warning → Slack
      continue: true
    - receiver: github-issues       # warning → n8n
      matchers: [severity = "warning"]
```

**Alternative (simpler)**: Use a single `github-issues` route that catches both severities before the Slack routes, with `continue: true`:

```yaml
routes:
  - receiver: "null"
    matchers:
      - alertname = "Watchdog"
  - receiver: github-issues
    matchers:
      - severity =~ "warning|critical"
    continue: true
  - receiver: slack-critical
    matchers:
      - severity = "critical"
    repeat_interval: 1h
  - receiver: slack-notifications
    matchers:
      - severity = "warning"
```

### n8n Workflow Logic

```
Trigger: Webhook (POST /webhook/alertmanager-issues)

For each alert in payload.alerts:
  alertname  = alert.labels.alertname
  severity   = alert.labels.severity
  namespace  = alert.labels.namespace
  status     = alert.status  ("firing" | "resolved")
  summary    = alert.annotations.summary
  description = alert.annotations.description

  issue_title = "[{severity}] {alertname} — {namespace}"

  If status == "firing":
    Search GitHub issues: repo=homelab-iac, state=open, title contains "{alertname} — {namespace}"
    If issue found:
      → POST /repos/homelab-admin/homelab-iac/issues/{n}/comments
        body: "🔁 Alert still firing at {time}\n{description}"
    Else:
      → POST /repos/homelab-admin/homelab-iac/issues
        title: issue_title
        body: (see template below)
        labels: ["alert", severity, namespace]
    → Return issue URL to caller (for Slack message enrichment)

  If status == "resolved":
    Search GitHub issues: repo=homelab-iac, state=open, title contains "{alertname} — {namespace}"
    If issue found:
      → POST comment: "✅ Resolved at {time}. Duration: {firing_time}"
      → PATCH issue: state=closed
```

### GitHub Issue Template

```markdown
## Alert: {alertname}

| Field | Value |
|---|---|
| **Severity** | {severity} |
| **Namespace** | {namespace} |
| **Node/Instance** | {instance} |
| **First fired** | {startsAt} |

### Summary
{summary}

### Description
{description}

### Links
- [Grafana dashboard](https://grafana.homelab.ts.net)
- [AlertManager](https://alertmanager.homelab.ts.net) *(if deployed)*

### Checklist
- [ ] Root cause identified
- [ ] Remediation applied
- [ ] Runbook updated if needed
- [ ] Post-mortem written (for critical)
```

---

## Prototype

### AlertManager webhook receiver (add to `release.yaml`)

```yaml
# In alertmanager.config.receivers — add alongside existing receivers:
- name: github-issues
  webhook_configs:
    - url: "http://n8n.n8n.svc.cluster.local:5678/webhook/alertmanager-issues"
      send_resolved: true
```

> **Note**: The n8n webhook URL is in-cluster (no ingress required). The `n8n` service in the `n8n` namespace is reachable from the `monitoring` namespace via `http://n8n.n8n.svc.cluster.local:5678`. No `http_config.authorization` is needed — in-cluster access without an ingress is sufficient isolation for a homelab, matching the existing pattern for all other in-cluster service-to-service calls.

### AlertManager route change (updated route block)

```yaml
# In alertmanager.config.route.routes (replaces current routes):
routes:
  - receiver: "null"
    matchers:
      - alertname = "Watchdog"
  - receiver: github-issues
    matchers:
      - severity =~ "warning|critical"
    continue: true          # fall through so Slack routes still fire
  - receiver: slack-critical
    matchers:
      - severity = "critical"
    repeat_interval: 1h
  - receiver: slack-notifications
    matchers:
      - severity = "warning"
```

### n8n workflow nodes (import as JSON)

The n8n workflow requires these nodes in sequence:

1. **Webhook** — `POST /webhook/alertmanager-issues`, responds immediately (async mode off)
2. **Code (split alerts)** — `items = $json.alerts.map(a => ({json: a}))`
3. **IF (firing vs resolved)** — `{{ $json.status === 'firing' }}`
4. **HTTP Request (search issues)** — `GET https://api.github.com/search/issues?q={alertname}+repo:homelab-admin/homelab-iac+state:open+in:title`
5. **IF (issue exists)** — `{{ $json.total_count > 0 }}`
6. **HTTP Request (create issue)** — `POST https://api.github.com/repos/homelab-admin/homelab-iac/issues`
7. **HTTP Request (add comment)** — `POST .../issues/{number}/comments`
8. **HTTP Request (close issue)** — `PATCH .../issues/{number}` with `{"state": "closed"}`

Credentials: add a **GitHub API** credential in n8n with a fine-grained PAT scoped to `homelab-admin/homelab-iac` (issues: read/write).

### 1Password secret for n8n GitHub PAT

```bash
op item create --vault Homelab --category login \
  --title "n8n-github-pat" \
  'token=ghp_...'
```

ExternalSecret to sync it into n8n's namespace:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: n8n-github-pat
  namespace: n8n
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword-connect
  target:
    name: n8n-github-pat
    creationPolicy: Owner
  data:
    - secretKey: token
      remoteRef:
        key: n8n-github-pat
        property: token
```

---

## Workflow (Operational Guide)

### One-time setup

1. Create the GitHub PAT in 1Password and sync it to the `n8n` namespace via ExternalSecret.
2. In n8n, import the workflow JSON (or build manually from the node list above).
3. Add the GitHub credential using the PAT from the `n8n-github-pat` secret.
4. Update `release.yaml` to add the `github-issues` receiver and the `continue: true` route.
5. Flux will reconcile and AlertManager will reload its config (check `alertmanager.status.conditions`).

### Testing

Fire a test alert manually:

```bash
# Port-forward AlertManager
KUBECONFIG=~/.kube/config-homelab kubectl -n monitoring port-forward svc/alertmanager-operated 9093:9093 &

# POST a test alert
curl -s -X POST http://localhost:9093/api/v2/alerts \
  -H "Content-Type: application/json" \
  -d '[{
    "labels": {"alertname":"TestAlert","severity":"warning","namespace":"default"},
    "annotations": {"summary":"Test alert","description":"This is a test"},
    "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
  }]'
```

Then check n8n execution history and verify a GitHub issue was created.

### Ongoing operation

- Issues are created automatically — no manual action needed when alerts fire.
- Add a root cause and close the issue manually if the alert auto-resolves before you triage it.
- Label hygiene: the `alert` label set on all issues makes them filterable in GitHub Projects.
- Review open alert issues weekly; recurring ones indicate systemic problems.

### Tuning

- **Noisy alerts**: Add `continue: false` on specific alert routes to skip GitHub issue creation for known-noisy alerts.
- **Dedup window**: The search-then-create logic deduplicates by title prefix — ensure `alertname` is specific enough to not merge unrelated alerts.
- **repeat_interval**: AlertManager's `repeat_interval: 4h` means n8n will receive re-fire webhooks every 4h for sustained alerts — the "issue already exists" branch just adds a comment.
