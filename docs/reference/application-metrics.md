---
title: Application Metrics
description: Prometheus ServiceMonitor configuration and custom Grafana dashboards for homelab applications (n8n, GitLab CE)
published: true
date: 2026-02-24
tags:
  - prometheus
  - grafana
  - servicemonitor
  - dashboards
  - n8n
  - gitlab
  - monitoring
  - observability
---

Prometheus ServiceMonitor configuration and custom Grafana dashboards for homelab applications. Covers the pattern for exposing application metrics to the kube-prometheus-stack and provisioning dashboards via ConfigMap sidecar.

## Overview

The homelab monitoring stack (kube-prometheus-stack) scrapes application metrics via `ServiceMonitor` resources. Custom Grafana dashboards are provisioned via Kustomize `configMapGenerator`. This pattern is consistent across all monitored applications.

### ServiceMonitor Discovery

kube-prometheus-stack's Prometheus must be configured to discover ServiceMonitors in all namespaces (not just `monitoring`):

```yaml
# kubernetes/platform/monitoring/controllers/kube-prometheus-stack/values.yaml
prometheus:
  prometheusSpec:
    serviceMonitorNamespaceSelector: {}   # empty = all namespaces
    serviceMonitorSelector: {}            # empty = no label filter
    podMonitorNamespaceSelector: {}
    podMonitorSelector: {}
```

Without `serviceMonitorNamespaceSelector: {}`, ServiceMonitors in application namespaces (e.g., `n8n-system`, `gitlab`) are silently ignored.

### Dashboard Provisioning

Dashboards are provisioned to Grafana using Kustomize `configMapGenerator` in `kubernetes/platform/monitoring/configs/kustomization.yaml`:

```yaml
configMapGenerator:
  - name: homelab-grafana-dashboards
    files:
      - dashboards/applications.json
      - dashboards/n8n-system-health-overview.json
      - dashboards/gitlab-ce-overview.json
    options:
      labels:
        grafana_dashboard: "1"
```

The `grafana_dashboard: "1"` label triggers Grafana's sidecar container to auto-discover and load the JSON. No manual Grafana UI import is needed.

**Datasource variables in provisioned dashboards:** The `__inputs` section in dashboard JSON (used for Grafana import wizard) is ignored when provisioning via ConfigMap. Define datasource variables in `templating.list` instead:

```json
"templating": {
  "list": [
    {
      "name": "datasource",
      "type": "datasource",
      "query": "prometheus",
      "current": { "selected": true, "text": "Prometheus", "value": "prometheus" }
    }
  ]
}
```

---

## n8n

n8n exposes a Prometheus metrics endpoint natively. No additional configuration is required beyond enabling the endpoint.

### Metrics Endpoint

n8n exposes metrics at `/metrics` on its HTTP port (port 5678). The endpoint is enabled by default in recent n8n versions.

**Key metrics:**

| Metric | Type | Description |
|--------|------|-------------|
| `n8n_workflow_execution_total` | Counter | Total workflow executions by status (success/error) |
| `n8n_workflow_execution_duration_seconds` | Histogram | Workflow execution duration |
| `n8n_active_workflows` | Gauge | Number of active (enabled) workflows |
| `n8n_queue_depth` | Gauge | Queue depth (when using queue mode) |
| `process_cpu_seconds_total` | Counter | Node.js process CPU time |
| `process_resident_memory_bytes` | Gauge | Process memory usage |
| `nodejs_heap_size_used_bytes` | Gauge | V8 heap used |

### ServiceMonitor

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: n8n
  namespace: n8n-system
  labels:
    app.kubernetes.io/name: n8n
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: n8n
  endpoints:
    - port: http
      path: /metrics
      interval: 60s
      scrapeTimeout: 10s
```

The scrape interval is set to 60s (versus the default 30s) because n8n metrics are workflow-level aggregates that do not need sub-minute resolution.

### Grafana Dashboard: n8n System Health Overview

Located at `kubernetes/platform/monitoring/configs/dashboards/n8n-system-health-overview.json`. The dashboard covers workflow health and runtime resource usage.

**Panels:**

| Panel | Type | Metric |
|-------|------|--------|
| Workflow Executions (success rate) | Stat | `rate(n8n_workflow_execution_total{status="success"}[5m])` / total |
| Workflow Execution Duration P95 | Stat | `histogram_quantile(0.95, sum by (le) (rate(n8n_workflow_execution_duration_seconds_bucket[5m])))` |
| Active Workflows | Stat | `n8n_active_workflows` |
| Execution Rate (success vs error) | Time series | `rate(n8n_workflow_execution_total[5m])` by status |
| Heap Memory Usage | Time series | `nodejs_heap_size_used_bytes` |
| CPU Usage | Time series | `rate(process_cpu_seconds_total[5m])` |
| Resident Memory | Gauge | `process_resident_memory_bytes` |

**PromQL pattern for histogram quantiles:**

Always aggregate with `sum by (le)` before computing quantiles:

```promql
# Correct
histogram_quantile(0.95, sum by (le) (rate(n8n_workflow_execution_duration_seconds_bucket[5m])))

# Incorrect -- computes quantile per label set (noisy)
histogram_quantile(0.95, rate(n8n_workflow_execution_duration_seconds_bucket[5m]))
```

### Key Files

| File | Purpose |
|------|---------|
| `kubernetes/apps/n8n/servicemonitor.yaml` | ServiceMonitor for n8n metrics |
| `kubernetes/platform/monitoring/configs/dashboards/n8n-system-health-overview.json` | Custom Grafana dashboard |

---

## GitLab CE

GitLab CE has a built-in Prometheus metrics endpoint but it is disabled by default for external scrapers. It also ships a bundled Prometheus that must be disabled to avoid conflicts.

### Enabling the Metrics Endpoint

Add to `gitlab.rb` (via the `omnibus_gitlab.rb` ConfigMap key in the GitLab Omnibus Kubernetes deployment):

```ruby
# Allow scraping from K3s pod CIDR
gitlab_rails['monitoring_whitelist'] = ['10.42.0.0/16']

# Disable bundled Prometheus (use external kube-prometheus-stack instead)
prometheus_monitoring['enable'] = false
```

The metrics endpoint is available at `/-/metrics` (not `/metrics`). It requires no authentication but is restricted to the IPs in `monitoring_whitelist`. K3s pods run on the `10.42.0.0/16` CIDR, so adding that range allows kube-prometheus-stack's Prometheus to scrape.

**Why not use the bundled Prometheus:** GitLab CE ships Prometheus as part of the Omnibus package. Running both the bundled Prometheus and the external kube-prometheus-stack creates confusion and resource waste. Disabling the bundled one (`prometheus_monitoring['enable'] = false`) does not affect the metrics endpoint -- the endpoint is a separate Rails middleware feature.

### Available Metrics

GitLab CE metrics available at `/-/metrics`:

| Metric family | Description |
|---------------|-------------|
| `puma_*` | Puma web server thread utilization, backlog, request rate |
| `sidekiq_*` | Sidekiq job queue depth, processing rate, latency by queue |
| `http_requests_total` | HTTP request counts by method, route, status |
| `http_request_duration_seconds` | HTTP request latency histogram |
| `ruby_gc_duration_seconds_total` | Ruby garbage collection duration (counter) |
| `ruby_gc_stat_*` | Ruby GC statistics (heap slots, objects, etc.) |
| `sql_duration_seconds` | Database query duration histogram |
| `gitlab_transaction_*` | GitLab-specific transaction counters |

### ServiceMonitor

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: gitlab-ce
  namespace: gitlab
  labels:
    app.kubernetes.io/name: gitlab
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: gitlab
  endpoints:
    - port: http
      path: /-/metrics
      interval: 60s
      scrapeTimeout: 30s   # GitLab metrics endpoint can be slow to respond
```

The `scrapeTimeout` is set higher (30s) because GitLab's metrics endpoint makes several database queries to generate the response and can be slow under load.

### Grafana Dashboard: GitLab CE Overview

Located at `kubernetes/platform/monitoring/configs/dashboards/gitlab-ce-overview.json`. 13-panel dashboard covering web performance, background job processing, and runtime health.

**Panels:**

| Panel | Type | Metric |
|-------|------|--------|
| Request Rate | Time series | `rate(http_requests_total[5m])` by status code range |
| Request Latency P99 | Stat | `histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))` |
| Puma Thread Utilization | Gauge | `puma_busy_threads / puma_max_threads` |
| Puma Request Backlog | Time series | `puma_backlog_count` |
| Sidekiq Queue Depth | Stat | `sum(sidekiq_queue_size)` |
| Sidekiq Latency | Time series | `sidekiq_queue_latency` by queue |
| SQL Query Duration P95 | Stat | `histogram_quantile(0.95, sum by (le) (rate(sql_duration_seconds_bucket[5m])))` |
| Ruby GC Time Fraction | Gauge | `rate(ruby_gc_duration_seconds_total[5m])` |
| Ruby Heap Objects | Time series | `ruby_gc_stat_heap_live_slots` |
| HTTP Error Rate | Time series | `rate(http_requests_total{status=~"5.."}[5m])` |
| Cache Hit Ratio | Stat | derived from `gitlab_cache_*` counters |
| Active Users | Stat | `gitlab_transaction_authorized_requests_total` |
| Background Job Success Rate | Time series | sidekiq success vs failure rate |

**Ruby GC duration field unit:**

`rate(ruby_gc_duration_seconds_total[5m])` returns seconds per second -- a dimensionless fraction between 0 and 1 representing the proportion of time spent in GC. Set the Grafana panel unit to `percentunit` (not `s`) to display this correctly as a percentage.

### SSH Over Tailscale

GitLab SSH (port 22) is exposed to the tailnet via a separate Tailscale L4 LoadBalancer Service. See [tailscale-kubernetes.md](./tailscale-kubernetes.md#l4-tcp-forwarding) for the full configuration pattern.

**Required GitLab configuration** to show the correct SSH clone URL in the web UI:

```ruby
gitlab_rails['gitlab_ssh_host'] = 'gitlab-ssh.homelab.ts.net'
gitlab_rails['gitlab_shell_ssh_port'] = 22
```

Without these settings, GitLab shows the internal Kubernetes Service hostname (e.g., `gitlab.gitlab.svc.cluster.local`) in the SSH clone URL, which is not reachable from outside the cluster.

### Key Files

| File | Purpose |
|------|---------|
| `kubernetes/apps/gitlab/servicemonitor.yaml` | ServiceMonitor for GitLab CE metrics |
| `kubernetes/platform/monitoring/configs/dashboards/gitlab-ce-overview.json` | 13-panel Grafana dashboard |
| `kubernetes/apps/gitlab/configmap-gitlab-rb.yaml` | `gitlab.rb` configuration (includes monitoring whitelist) |

---

## PVC Storage Panels

The `applications.json` dashboard includes PVC storage usage panels for all monitored namespaces. These use metrics from the kubelet scrape job that kube-prometheus-stack enables by default -- no additional ServiceMonitor is needed.

**Metrics:**

```promql
# PVC used bytes by namespace and PVC name
kubelet_volume_stats_used_bytes{namespace="n8n-system"}

# PVC capacity by namespace and PVC name
kubelet_volume_stats_capacity_bytes{namespace="n8n-system"}

# Storage utilization percentage
kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes * 100
```

**Panel configuration:**

```json
{
  "title": "PVC Storage Usage",
  "type": "gauge",
  "fieldConfig": {
    "defaults": {
      "unit": "percent",
      "min": 0,
      "max": 100,
      "thresholds": {
        "steps": [
          { "color": "green", "value": 0 },
          { "color": "yellow", "value": 75 },
          { "color": "red", "value": 90 }
        ]
      }
    }
  }
}
```

---

## Adding Metrics for a New Application

Follow this checklist when adding Prometheus metrics for a new application:

1. **Verify the metrics endpoint** -- confirm the app exposes metrics (check docs; common paths: `/metrics`, `/-/metrics`, `/actuator/prometheus`)
2. **Confirm kube-prometheus-stack discovery** -- `serviceMonitorNamespaceSelector: {}` must be set (already configured in this homelab)
3. **Create a ServiceMonitor** in the app's namespace with `selector.matchLabels` matching the app's Service
4. **Set scrape interval** -- use 60s for application metrics (30s is fine for infrastructure metrics)
5. **Verify scraping** -- check `Status > Targets` in the Prometheus UI; the target should appear in a few minutes
6. **Create the dashboard JSON** -- use the Grafana UI (provisioned data, then export as JSON), then add to `configMapGenerator`
7. **Add the datasource variable** to `templating.list` in the JSON (not just `__inputs`)
8. **Add `kustomize.toolkit.fluxcd.io/substitute: disabled`** label if the dashboard JSON contains `${...}` variable syntax to prevent Flux from treating them as substitution variables

---

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| ServiceMonitor in app namespace (not monitoring namespace) | Co-location with the app simplifies ownership; discovery works cluster-wide with `serviceMonitorNamespaceSelector: {}` |
| 60s scrape interval for apps | Application-level metrics (workflow counts, queue depth) change slowly; 60s reduces cardinality and storage |
| 30s scrapeTimeout for GitLab | GitLab metrics endpoint queries the database; slow responses are expected |
| Disable GitLab bundled Prometheus | Avoids dual-scraping and resource waste; external kube-prometheus-stack is the single metrics store |
| Dashboard JSON in configMapGenerator | Grafana sidecar auto-loads; no manual import or API provisioning needed |
| Datasource in `templating.list` not `__inputs` | `__inputs` is for the Grafana import wizard only; provisioned dashboards must define variables in `templating.list` |
