---
title: "Slack/GitHub Workflow 3: Capacity Planning Alerts → GitHub Issues"
description: Prometheus sustained-pressure rules trigger n8n to create capacity planning GitHub issues with metrics snapshots before resources reach critical levels.
published: true
date: 2026-02-21
tags:
  - slack
  - github
  - prometheus
  - n8n
  - capacity
  - alertmanager
  - automation
---

# Workflow 3: Capacity Planning Alerts → GitHub Issues

## Summary

Unlike the existing homelab alerts (which fire when a threshold is breached and recover when it drops), this workflow detects *sustained* resource pressure — resources held above a softer threshold for an extended period. It creates a GitHub issue with a Prometheus metrics snapshot so you can make an informed decision (migrate a workload, add storage, add a node) before a crisis.

```
Prometheus: resource above soft threshold for 1+ hours
        ↓
AlertManager receiver: capacity-planning
        ↓  webhook → n8n
n8n queries Prometheus for context snapshot
        ↓
GitHub issue created with:
  - affected node/namespace
  - current usage + 7-day trend
  - projected runway
  - suggested remediation options
        ↓
Slack: capacity warning + issue link
```

---

## Plan

### Capacity signals to monitor

| Signal | Soft threshold | Duration | Severity | What it means |
|---|---|---|---|---|
| Node CPU | > 75% | 1 hour | warning | Workload pressure building |
| Node memory | > 80% | 1 hour | warning | Pod eviction risk approaching |
| PVC usage | > 80% | 30 minutes | warning | Storage growth needs attention |
| PostgreSQL data disk | > 75% | 30 minutes | warning | DB growth rate may need new disk |
| NFS storage pool | > 80% | 1 hour | warning | Backup/media storage pressure |

### Distinction from existing alerts

The existing `homelab-alerts.yaml` rules fire at 90% CPU/memory (15 minutes) and 85% PVC (15 minutes). These are **crisis** alerts.

This workflow fires at lower thresholds with longer durations — these are **trend** signals. The intent is to give 1–2 weeks of lead time, not to page you at 2am.

### Components

| Component | Role | Already deployed? |
|---|---|---|
| PrometheusRule | New sustained-pressure alert rules | Add to `homelab-alerts.yaml` |
| AlertManager | New `capacity-planning` receiver + route | Add to `release.yaml` |
| n8n | Webhook receiver, Prometheus queries, GitHub issue creation | ✅ yes |
| Prometheus HTTP API | Metrics snapshot at issue creation time | ✅ yes (in-cluster) |
| GitHub API | Issue create/update | ✅ yes |
| Slack | Capacity warning notification | ✅ yes |

---

## Prototype

### PrometheusRule additions (add to `kubernetes/platform/monitoring/configs/homelab-alerts.yaml`)

```yaml
# ── Capacity Planning ─────────────────────────────
- name: capacity-planning
  rules:
    - alert: NodeSustainedHighCPU
      expr: |
        (1 - avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))) > 0.75
      for: 1h
      labels:
        severity: warning
        category: capacity
      annotations:
        summary: "Node {{ $labels.instance }} CPU sustained above 75% for 1h"
        description: "Node {{ $labels.instance }} has held CPU usage above 75% for over an hour. Current: {{ $value | humanizePercentage }}. Consider migrating or scaling workloads."

    - alert: NodeSustainedHighMemory
      expr: |
        (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) > 0.80
      for: 1h
      labels:
        severity: warning
        category: capacity
      annotations:
        summary: "Node {{ $labels.instance }} memory sustained above 80% for 1h"
        description: "Node {{ $labels.instance }} has held memory usage above 80% for over an hour. Current: {{ $value | humanizePercentage }}. Risk of pod eviction if usage continues to grow."

    - alert: PVCSustainedHigh
      expr: |
        kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes > 0.80
        and kubelet_volume_stats_capacity_bytes > 0
      for: 30m
      labels:
        severity: warning
        category: capacity
      annotations:
        summary: "PVC {{ $labels.namespace }}/{{ $labels.persistentvolumeclaim }} above 80% for 30m"
        description: "PVC {{ $labels.persistentvolumeclaim }} in {{ $labels.namespace }} is {{ $value | humanizePercentage }} full. Existing alert fires at 85% — act before that threshold."

    - alert: PostgreSQLDiskSustainedHigh
      expr: |
        (1 - node_filesystem_avail_bytes{mountpoint="/data", instance=~".*192\\.168\\.2\\.4[45].*"}
           / node_filesystem_size_bytes{mountpoint="/data", instance=~".*192\\.168\\.2\\.4[45].*"}) > 0.75
      for: 30m
      labels:
        severity: warning
        category: capacity
      annotations:
        summary: "PostgreSQL data disk on {{ $labels.instance }} above 75%"
        description: "The PostgreSQL /data filesystem on {{ $labels.instance }} is {{ $value | humanizePercentage }} full. The 100GB data volume may need expansion."
```

> **Note**: Adjust the `instance` regex for PostgreSQL to match your node exporter labels. The VIP is `10.0.0.44`; the individual nodes are `.44` (primary) and `.45` (standby).

### AlertManager receiver (add to `release.yaml`)

```yaml
# In alertmanager.config.receivers:
- name: capacity-planning
  webhook_configs:
    - url: "http://n8n.n8n.svc.cluster.local:5678/webhook/capacity-planning"
      send_resolved: false   # capacity issues don't auto-resolve — close manually
```

> No `http_config.authorization` needed — the webhook is in-cluster only (not exposed via ingress), matching the existing pattern for in-cluster service-to-service calls in this homelab.

### AlertManager route (add before the `github-issues` catch-all route)

```yaml
# In alertmanager.config.route.routes — insert before other warning routes:
- receiver: capacity-planning
  matchers:
    - category = "capacity"
  continue: false    # don't send capacity alerts to slack-notifications (too noisy)
```

> Capacity planning alerts intentionally **don't** go to `slack-notifications` directly — n8n posts a richer Slack message with the GitHub issue link instead.

### n8n workflow: Capacity Planning Issue Creator

```
Trigger: Webhook POST /webhook/capacity-planning

For each alert in payload.alerts (status == "firing"):

  1. Extract labels: alertname, instance, namespace, persistentvolumeclaim, category
  2. Extract annotations: summary, description

  3. Build Prometheus query based on alertname:
     NodeSustainedHighCPU:
       instant:  rate(node_cpu_seconds_total{mode="idle",instance="..."}[5m])
       range:    over 7 days (step=1h)
     NodeSustainedHighMemory:
       instant:  node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes
       range:    over 7 days
     PVCSustainedHigh:
       instant:  kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes
       range:    over 7 days

  4. HTTP GET http://kube-prometheus-stack-prometheus.monitoring.svc:9090/api/v1/query
       params: { query: <instant_query> }
     → current_value

  5. HTTP GET .../api/v1/query_range
       params: { query, start: now-7d, end: now, step: 3600 }
     → sparkline_data (last value of each hour)

  6. Compute runway:
     growth_rate = (last_value - first_value_7d_ago) / 7  # per day
     days_to_90pct = (0.90 - current_value) / growth_rate
     (if growth_rate <= 0: runway = "stable / shrinking")

  7. Search GitHub: open issues with title containing alertname + instance/namespace
     If exists: add comment with fresh snapshot → exit
     Else: create issue (see template below)

  8. Post to Slack:
     channel: #homelab-alerts
     text: "🟡 Capacity warning: {summary}\nGitHub issue: {issue_url}"
```

### GitHub issue template (capacity planning)

```markdown
## Capacity Planning: {alertname}

| Field | Value |
|---|---|
| **Host / Resource** | `{instance}` / `{namespace}/{pvc}` |
| **Current usage** | {current_pct}% |
| **7-day average growth** | +{growth_pct}%/day |
| **Projected runway to 90%** | {runway} days |
| **First detected** | {startsAt} |

### Current reading
{description}

### 7-day trend (hourly samples)
```
{sparkline}  ← ASCII sparkline or CSV for pasting into Grafana
```

### Suggested actions
- [ ] **Migrate workload** — move high-usage pods to a lower-utilization node
- [ ] **Scale storage** — expand PVC or resize the underlying NFS allocation
- [ ] **Prune data** — check for stale logs, old backups, or unused images
- [ ] **Add capacity** — provision a new node (see `docs/guides/cloning-k3s-vms.md`)
- [ ] **Monitor only** — usage is stable, close this issue

### Links
- [Grafana node dashboard](https://grafana.homelab.ts.net/d/rYdddlPWk)
- [Prometheus query](http://kube-prometheus-stack-prometheus.monitoring.svc:9090/graph)

_Generated by n8n capacity-planning workflow at {timestamp}_
```

---

## Workflow (Operational Guide)

### One-time setup

1. Add the four new PrometheusRules to `kubernetes/platform/monitoring/configs/homelab-alerts.yaml`.
2. Add the `capacity-planning` receiver and route to `release.yaml`.
3. In n8n, build or import the capacity planning workflow.
4. Add a **Prometheus API** HTTP credential in n8n pointing to `http://kube-prometheus-stack-prometheus.monitoring.svc:9090`.
5. Commit and push — Flux reconciles both the PrometheusRule and the HelmRelease.
6. Verify in Prometheus UI (`:9090/rules`) that the new rules appear under `capacity-planning` group.

### Typical triaging flow

When a capacity issue appears in GitHub:

1. Check the 7-day trend in the issue — is it a spike or a trend?
2. Open the Grafana node dashboard for a fuller picture.
3. If it's a trend, work through the checklist items in the issue.
4. Close the issue when usage drops below the threshold or action is taken.

### Closing vs ignoring

- **Close**: you've taken action or the trend reversed.
- **Don't close**: if you're monitoring — instead add a comment "Watching — runway is 14 days, will act if trend continues."
- n8n will append a fresh snapshot comment every time the alert re-fires (every 4h by default). This gives you a built-in activity log.

### Threshold tuning

The soft thresholds (75% CPU, 80% memory, 80% PVC) are starting points. Adjust them in `homelab-alerts.yaml` based on your homelab's baseline:

```bash
# Check current average CPU across nodes
KUBECONFIG=~/.kube/config-homelab kubectl exec -n monitoring \
  deployment/kube-prometheus-stack-prometheus -- \
  promtool query instant http://localhost:9090 \
  'avg(1 - rate(node_cpu_seconds_total{mode="idle"}[5m]))'
```

If your nodes routinely run at 60% CPU, lower the threshold to 65% for earlier warning. If a node is consistently at 75% with no issues, raise it to 82%.

### Relation to existing crisis alerts

```
capacity-planning alerts (this workflow)   →  "act in the next 2 weeks"
  threshold: 75-80%, for: 1h

existing homelab-alerts.yaml               →  "act now"
  threshold: 85-90%, for: 15m
```

Both coexist in the same PrometheusRule file. They serve different time horizons and shouldn't conflict.
