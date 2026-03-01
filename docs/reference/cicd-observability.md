---
title: CI/CD Observability
description: CI/CD monitoring stack architecture covering GitHub Actions metrics, Flux notifications, Grafana dashboards, Prometheus alert rules, and incident triage patterns
published: true
date: 2026-02-19
tags:
  - cicd
  - monitoring
  - grafana
  - prometheus
  - flux
  - github-actions
  - slack
  - dashboards
  - alerting
  - observability
---

CI/CD observability stack for the homelab. Covers three pillars: GitHub Actions metrics (pull-based exporter), Flux GitOps notifications (push to Slack), and Prometheus alert rules with Grafana dashboards.

## Architecture Overview

```
GitHub REST API                          Flux notification-controller
      |                                           |
      | poll every 300s                           | push on error events
      v                                           v
github-actions-exporter ──> Prometheus ──> Grafana    Slack (#homelab-alerts)
  (port 9999/metrics)        scrape         dashboards
                               |
                               v
                         PrometheusRule
                         (9 CI/CD alerts)
                               |
                               v
                         Alertmanager ──> Slack (#homelab-alerts)
```

Two independent notification paths:

1. **Prometheus alerts via Alertmanager** -- delayed (requires `for` duration), fires only on sustained failures. Covers both GitHub Actions and Flux resources.
2. **Flux notification-controller via Provider** -- immediate, fires on any error event. Covers Flux resources only.

## GitHub Actions Exporter

### Why Pull-Based

The homelab runs behind Tailscale with NO public internet exposure. Webhook-based exporters (e.g., `cpanato/github_actions_exporter`) require inbound HTTP connections from GitHub, which is impossible in this network topology. The `Labbs/github-actions-exporter` uses pull-based polling via the GitHub REST API instead.

### Deployment

| Parameter | Value |
|-----------|-------|
| Image | `ghcr.io/labbs/github-actions-exporter:1.9.0` |
| Namespace | `monitoring` |
| Metrics port | 9999 |
| Poll interval | 300 seconds (`GITHUB_REFRESH`) |
| Repos monitored | `homelab-admin/homelab-iac` |
| Auth | GitHub PAT with `repo` scope (from 1Password via ExternalSecret) |

### Metrics Exported

The exporter provides these key metric families (scraped by Prometheus via ServiceMonitor):

| Metric | Type | Description |
|--------|------|-------------|
| `github_workflow_run_status` | Gauge | Current status of workflow runs (0=failed, 1=success, 2=skipped, 3=in_progress, 4=queued) |
| `github_workflow_run_duration_ms` | Gauge | Duration of workflow runs in milliseconds |
| `github_runner_status` | Gauge | Self-hosted runner online status (0=offline, 1=online) |

Labels include: `repo`, `workflow`, `head_branch`, `run_number`, `status`, `name` (runner), `os` (runner).

### ServiceMonitor Configuration

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: github-actions-exporter
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: github-actions-exporter
  endpoints:
    - port: metrics
      path: /metrics
      interval: 300s      # Match GITHUB_REFRESH to avoid scraping stale data
      scrapeTimeout: 30s
```

The scrape interval matches `GITHUB_REFRESH` (300s) to avoid scraping the same data multiple times between polls.

### 1Password Setup

```bash
# Create the 1Password item with a GitHub PAT (classic, repo scope)
env -u OP_CONNECT_HOST -u OP_CONNECT_TOKEN \
  op item create --vault Homelab --category login \
    --title "github-actions-exporter" \
    'token=ghp_...'
```

The ExternalSecret maps `property: token` to `secretKey: token`, injected as `GITHUB_TOKEN` env var.

### Probes

The `Labbs/github-actions-exporter` does NOT expose a `/healthz` endpoint -- it only serves `/metrics`. Using `httpGet` probes on `/healthz` (or any path other than `/metrics`) returns 404 and kills the pod in a restart loop.

**Use `tcpSocket` probes on the metrics port:**

```yaml
livenessProbe:
  tcpSocket:
    port: metrics
  initialDelaySeconds: 10
  periodSeconds: 30
readinessProbe:
  tcpSocket:
    port: metrics
  initialDelaySeconds: 5
  periodSeconds: 10
```

**Gotcha: Changing probe type requires pod recreation.** Kubernetes does not allow changing a probe's handler type (e.g., `httpGet` to `tcpSocket`) via `kubectl apply`. The API returns: `may not specify more than 1 handler type`. You must delete the Deployment and recreate it (or let Flux handle the recreation with `spec.upgrade.force: true`).

### Resource Requirements

Lightweight single-replica deployment:

```yaml
resources:
  requests:
    cpu: 25m
    memory: 32Mi
  limits:
    cpu: 100m
    memory: 64Mi
```

### Key Files

| File | Purpose |
|------|---------|
| `kubernetes/platform/monitoring/controllers/github-actions-exporter/deployment.yaml` | Deployment manifest |
| `kubernetes/platform/monitoring/controllers/github-actions-exporter/service.yaml` | ClusterIP Service (port 9999) |
| `kubernetes/platform/monitoring/controllers/github-actions-exporter/servicemonitor.yaml` | Prometheus ServiceMonitor |
| `kubernetes/platform/monitoring/controllers/github-actions-exporter/external-secret.yaml` | ExternalSecret for GitHub PAT |
| `kubernetes/platform/monitoring/controllers/github-actions-exporter/kustomization.yaml` | Kustomize resource list |

## Flux Slack Notifications

### API Version

Uses `notification.toolkit.fluxcd.io/v1beta3` (the current stable API for Flux notification-controller). This API group provides `Provider` and `Alert` CRDs.

### Provider

The Provider defines the Slack integration. It references a Secret containing the webhook URL:

```yaml
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Provider
metadata:
  name: slack
  namespace: flux-system
spec:
  type: slack
  channel: homelab-alerts
  secretRef:
    name: flux-slack-webhook    # Secret with key "address" containing the webhook URL
```

**Key detail:** The Flux Provider expects the Secret key to be `address` (not `webhook-url` or `url`). The ExternalSecret maps the 1Password field `webhook-url` from the `alertmanager-slack` item to Secret key `address`.

### Alert (Error-Only)

```yaml
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Alert
metadata:
  name: flux-errors-slack
  namespace: flux-system
spec:
  providerRef:
    name: slack
  eventSeverity: error
  eventSources:
    - kind: Kustomization
      name: "*"
    - kind: HelmRelease
      name: "*"
    - kind: HelmRepository
      name: "*"
    - kind: GitRepository
      name: "*"
    - kind: HelmChart
      name: "*"
```

**Design decision:** Only `error` severity is configured. With 20+ HelmReleases reconciling hourly, info-level notifications would generate excessive noise. Info-level alerts can be added later with `inclusionList` filters for specific resources.

### Shared Webhook Secret

The Flux notification Provider reuses the same Slack incoming webhook as Alertmanager (`alertmanager-slack` 1Password item). The ExternalSecret in `flux-system` namespace maps:

- 1Password item: `alertmanager-slack`
- 1Password field: `webhook-url`
- K8s Secret key: `address` (Flux Provider requirement)

### Placement Decision

Flux notifications are deployed under `kubernetes/platform/configs/flux-notifications/`, NOT under `monitoring/configs/`. Reason: the `monitoring/configs/` Kustomization applies a `namespace: monitoring` transformer, which would rewrite the Provider and Alert resources away from `flux-system` namespace where the notification-controller expects them.

### Key Files

| File | Purpose |
|------|---------|
| `kubernetes/platform/configs/flux-notifications/provider.yaml` | Slack Provider |
| `kubernetes/platform/configs/flux-notifications/alert-errors.yaml` | Error-only Alert |
| `kubernetes/platform/configs/flux-notifications/external-secret.yaml` | Slack webhook Secret |
| `kubernetes/platform/configs/flux-notifications/kustomization.yaml` | Kustomize resource list |

## Prometheus Alert Rules

Nine CI/CD-related alert rules are defined in the `homelab-alerts` PrometheusRule (`kubernetes/platform/monitoring/configs/homelab-alerts.yaml`).

### GitHub Actions Alerts

| Alert | Expression | For | Severity | Description |
|-------|-----------|-----|----------|-------------|
| `GitHubWorkflowFailed` | `github_workflow_run_status{status="completed"} == 0` | 5m | warning | Workflow completed with failure status |
| `GitHubWorkflowStuck` | `github_workflow_run_status == 3` | 30m | warning | Workflow has been "in progress" for 30+ minutes |
| `GitHubSelfHostedRunnerOffline` | `github_runner_status == 0` | 10m | warning | Self-hosted runner offline for 10+ minutes |

### Flux Deployment Health Alerts

| Alert | Expression | For | Severity | Description |
|-------|-----------|-----|----------|-------------|
| `FluxReconciliationFailed` | `gotk_resource_info{ready="False"} == 1` | 15m | warning | Any Flux resource in failed state |
| `FluxReconciliationErrorRate` | Error rate > 25% over 15m window | 15m | warning | Intermittent failures (flapping resources) |
| `FluxSourceRevisionStale` | No new revision in 6+ hours | 30m | info | GitRepository has not received new commits |
| `FluxHelmReleaseSuspendedLong` | `suspended="true"` for 72+ hours | 72h | info | Intentionally suspended but possibly forgotten |

### Existing Alerts (for context)

The PrometheusRule also contains non-CI/CD alerts in the same file: pod health (3 rules), node health (3 rules), storage (2 rules), Proxmox VE (5 rules), External Secrets (1 rule), PostgreSQL backups (2 rules), and Velero backups (3 rules).

## Grafana Dashboards

### Provisioning via configMapGenerator

Dashboards are provisioned to Grafana using Kustomize `configMapGenerator` in `kubernetes/platform/monitoring/configs/kustomization.yaml`. The `grafana_dashboard: "1"` label triggers Grafana's sidecar to auto-discover and load the dashboard JSON.

```yaml
configMapGenerator:
  - name: cicd-grafana-dashboards
    files:
      - dashboards/cicd-pipeline.json
      - dashboards/gitops-health.json
    options:
      labels:
        grafana_dashboard: "1"
        app.kubernetes.io/component: monitoring
```

**How sidecar discovery works:** The kube-prometheus-stack Grafana deployment includes a sidecar container that watches for ConfigMaps with the label `grafana_dashboard: "1"` across all namespaces. When found, it mounts the JSON files into Grafana's provisioning directory. No manual Grafana UI import needed.

**Three dashboard groups** are provisioned this way:

| ConfigMap | Dashboards | Purpose |
|-----------|-----------|---------|
| `flux-grafana-dashboards` | control-plane.json, cluster.json, logs.json | Flux controller internals |
| `homelab-grafana-dashboards` | applications.json, application-logs.json, proxmox.json | Application and PVE monitoring |
| `cicd-grafana-dashboards` | cicd-pipeline.json, gitops-health.json | CI/CD observability |

**Flux substitution gotcha:** The `flux-grafana-dashboards` ConfigMap includes `kustomize.toolkit.fluxcd.io/substitute: disabled` to prevent Flux from treating `${...}` Grafana variables as Flux substitution variables.

### CI/CD Pipeline Dashboard

Located at `dashboards/cicd-pipeline.json`. Covers GitHub Actions metrics.

**Panels:**

- Workflow Status -- stat panels showing latest run status per workflow (color-coded: green=success, red=failed, yellow=in_progress)
- Workflow Duration -- bar chart showing run duration by workflow over time
- Recent Runs -- table showing recent workflow runs with status, duration, branch, run number
- Runner Health -- stat panels showing self-hosted runner online/offline status

**Data source:** Prometheus (uses `${datasource}` template variable for portability).

**Key metrics used:**

- `github_workflow_run_status` -- workflow run state
- `github_workflow_run_duration_ms` -- execution time
- `github_runner_status` -- runner health

### GitOps Health Dashboard

Located at `dashboards/gitops-health.json`. Covers Flux resource health.

**Panels:**

- Resource Overview -- stat panels: total Kustomizations, HelmReleases, sources (all kinds)
- Resource Status Table -- multi-column table with resource kind, name, namespace, ready status, suspended status
- Reconciliation Rate -- time series showing reconciliation success/failure rates over time
- Source Health -- table showing GitRepository/HelmRepository fetch status and last update
- Reconciliation Duration Percentiles -- heatmap or percentile lines for reconciliation time

**Key metrics used:**

- `gotk_resource_info` -- resource metadata (kind, name, namespace, ready, suspended)
- `gotk_reconcile_condition` -- reconciliation outcomes (Ready=True/False)
- `gotk_reconcile_time` -- reconciliation timestamps
- `gotk_reconcile_duration_seconds` -- reconciliation duration

## Operational Runbook

A detailed triage runbook for all CI/CD alert scenarios is maintained at `docs/runbooks/cicd-incident-triage.md`. It covers:

1. **GitHub Actions alerts** -- `GitHubWorkflowFailed`, `GitHubWorkflowStuck`, `GitHubSelfHostedRunnerOffline`
2. **Flux deployment health alerts** -- `FluxReconciliationFailed`, `FluxReconciliationErrorRate`, `FluxSourceRevisionStale`, `FluxHelmReleaseSuspendedLong`
3. **Flux Slack notification events** -- Kustomization/HelmRelease errors, source fetch errors
4. **Escalation procedures** -- self-service, infrastructure, and secrets troubleshooting

Each alert section includes: PromQL queries for investigation, `kubectl`/`flux` CLI commands, common root causes, and remediation steps.

## pve-exporter v3.8.0 Breaking Change

The `prometheus-pve-exporter` v3.8.0 replaced running total gauge metrics with Prometheus counters. This is a semantic change: gauges report current totals, while counters are monotonically increasing and require `rate()` or `increase()` in PromQL queries.

**Impact:** Any Grafana dashboard panels or PrometheusRule expressions that query pve-exporter metrics directly (without `rate()`) may show unexpected values after upgrading from < 3.8.0 to >= 3.8.0. Review the `proxmox.json` dashboard and any custom alert rules referencing `pve_*` metrics.

**Current version deployed:** 3.8.1 (pinned from `:latest`).

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Pull-based exporter over webhook-based | Tailscale-only network has no inbound HTTP from GitHub |
| Error-only Flux notifications | 20+ HelmReleases reconciling hourly would generate excessive noise at info level |
| Shared Slack webhook (Alertmanager + Flux) | Single channel for all alerts simplifies triage; shared 1Password item avoids credential duplication |
| Flux notifications in `platform/configs/` not `monitoring/configs/` | monitoring/configs namespace transformer rewrites CRDs away from flux-system |
| ServiceMonitor interval matches GITHUB_REFRESH | Prevents scraping identical stale data between poll cycles |
| Dashboard JSON in configMapGenerator | Grafana sidecar auto-loads; no manual import or API provisioning needed |
| `grafana_dashboard: "1"` label convention | Standard kube-prometheus-stack sidecar discovery label |

## Complete File Inventory

```
kubernetes/platform/monitoring/controllers/github-actions-exporter/
  deployment.yaml          # Exporter pod
  service.yaml             # ClusterIP Service
  servicemonitor.yaml      # Prometheus scrape config
  external-secret.yaml     # GitHub PAT from 1Password
  kustomization.yaml       # Resource list

kubernetes/platform/configs/flux-notifications/
  provider.yaml            # Slack Provider (v1beta3)
  alert-errors.yaml        # Error-only Alert (v1beta3)
  external-secret.yaml     # Slack webhook from 1Password
  kustomization.yaml       # Resource list

kubernetes/platform/monitoring/configs/
  homelab-alerts.yaml      # PrometheusRule with 9 CI/CD alert rules
  kustomization.yaml       # configMapGenerator for dashboard ConfigMaps

kubernetes/platform/monitoring/configs/dashboards/
  cicd-pipeline.json       # GitHub Actions dashboard
  gitops-health.json       # Flux resource health dashboard

docs/runbooks/
  cicd-incident-triage.md  # Triage steps for all alert scenarios
```

## GitHub Actions Workflow Patterns and Gotchas

### Tailscale Access from GitHub Actions

The homelab is Tailscale-only (no public internet exposure). GitHub Actions workflows that need to reach cluster resources (e.g., smoke tests, deployment checks) must join the tailnet as an ephemeral node.

**Recommended approach: `tailscale/github-action@v3` with an ephemeral auth key**

```yaml
- name: Connect to Tailscale
  uses: tailscale/github-action@v3
  with:
    authkey: ${{ secrets.TS_AUTH_KEY }}
    hostname: github-actions-runner
```

Key properties of this approach:

- Uses a **reusable ephemeral auth key** (`TS_AUTH_KEY`) stored as a GitHub Actions secret
- No OAuth client required -- a pre-generated ephemeral auth key suffices
- No Tailscale ACL tags are required for the auth key itself (unlike OAuth)
- Ephemeral nodes auto-expire from the tailnet after the job ends -- no manual cleanup
- The runner becomes a full Tailscale peer during the job and can reach any tailnet resource (e.g., `10.0.0.72`, `*.homelab.ts.net`)

**Generating the auth key:**

In the Tailscale admin console: Settings -> Keys -> Generate auth key. Enable "Reusable" and "Ephemeral". Store the resulting `tskey-auth-...` value as a GitHub repository secret named `TS_AUTH_KEY`.

**Contrast with webhook-based approaches:** Webhook or inbound-HTTP CI patterns cannot work in this homelab because there is no public internet exposure. All CI-to-homelab communication must be initiated from the CI runner (outbound, over Tailscale), not from the homelab.

### Kubernetes Job Filtering: --field-selector Limitations

`kubectl --field-selector=status.successful=1` is unreliable for filtering Jobs by integer status fields. The field selector spec only guarantees support for `metadata.name` and `metadata.namespace` on most resource types; additional fields (like `status.successful`) are not indexed and may silently return all resources or no resources depending on the Kubernetes version and API server implementation.

**Use `jq` filtering instead:**

```bash
# Correct: filter completed jobs via jq
kubectl get jobs -n <namespace> -o json \
  | jq '[.items[] | select(.status.succeeded > 0)] | length'

# Also useful: get names of successful jobs
kubectl get jobs -n <namespace> -o json \
  | jq -r '.items[] | select(.status.succeeded > 0) | .metadata.name'

# Filter failed jobs
kubectl get jobs -n <namespace> -o json \
  | jq '[.items[] | select(.status.failed > 0)]'
```

This pattern works reliably across all Kubernetes versions and avoids field-selector indexing assumptions.

### grep -oP Not Available on ubuntu-latest Runners

`grep -oP` (Perl-compatible regex with `-o` output-only) is not reliably available on `ubuntu-latest` GitHub Actions runners. While `grep` is present, the GNU grep build shipped on some runner images does not include PCRE support (`--enable-perl-regexp`).

**Use `sed` for version number extraction and similar tasks:**

```bash
# Instead of: grep -oP '\d+\.\d+\.\d+' version.txt
# Use:
sed -n 's/.*\([0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/p' version.txt

# For extracting a semver tag from a string like "v1.2.3":
echo "v1.2.3" | sed 's/^v//'

# Extract version from a Helm chart output line:
helm show chart <repo>/<chart> | sed -n 's/^version: //p'
```

Alternatively, use `python3 -c "import re; ..."` for complex regex needs -- Python 3 is always available on GitHub-hosted runners.

### Claude Code Review Action: Comment vs PR Review

The `anthropics/claude-code-action@v1` GitHub Action for automated code review does NOT post to the GitHub PR review interface (the "Review changes" section where reviewers submit approvals or request changes). It posts feedback as a **regular PR comment** instead.

This means:
- Claude's review does not appear in the "Review changes" / "Files changed" view with inline line annotations
- It cannot submit "Approve", "Request changes", or "Comment" review decisions
- The output is a flat comment on the PR conversation tab

For structured code reviews with inline annotations and the ability to request changes programmatically, consider alternatives such as the **Gemini CLI GitHub Action** (`google-gemini/gemini-cli-action`), which supports submitting PR reviews via the GitHub PR review API.

**Design decision for this homelab:** Automated code review (whether Claude or Gemini) is supplemental. Final merge decisions remain manual after CI passes.
