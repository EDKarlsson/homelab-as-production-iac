# Changelog

All notable changes to the homelab-iac project are documented here.

Canonical session-by-session history is tracked in `docs/CHANGELOG.md`.
This root file is kept as a high-level release log and may lag behind the docs changelog.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
Versioning: `v0.<PR#>.0` (pre-1.0 convention — PR number is the minor version)

## [Unreleased]

### Added

- **HA 1Password Connect module** — New Terraform module `infrastructure/modules/op-connect/` (8 files). Deploys 2 privileged LXC containers on separate Proxmox nodes (node-01 MASTER, node-05 BACKUP) running Docker with connect-api + connect-sync. Keepalived VRRP with unicast peers provides VIP failover at 10.0.0.72. `null_resource` provisioners handle Docker CE + keepalived + Connect setup (LXC doesn't support cloud-init).
- **Reference docs** — `docs/reference/proxmox-lxc-patterns.md` (Docker-in-LXC, privileged containers, keepalived VRRP, LXC provisioning patterns).

### Changed

- `infrastructure/main.tf` — Added `module "op_connect"` block and `data "onepassword_item" "op_connect_server"` data source for credentials.
- `kubernetes/platform/configs/cluster-secret-store.yaml` — Updated `connectHost` from `http://10.0.0.66:8080` (workstation) to `http://10.0.0.72:8080` (keepalived VIP).
- `docs/reference/1password-integration.md` — Replaced single-server docs with HA architecture diagram, design rationale, and Terraform module reference.
- `docs/reference/technical-gotchas.md` — Added LXC provisioning, keepalived unicast, Windmill roles, and Connect cache gotchas.

## [v0.180.0] - 2026-02-26

### Added

- Session 42 knowledge-capture docs for Dependency-Track OIDC/JVM truststore, GitLab shell runner operations, and CI troubleshooting patterns (see `docs/reference/technical-gotchas.md`, `docs/reference/ansible-patterns.md`, and `docs/CHANGELOG.md`).

### Changed

- Updated project planning and version tracking docs to reflect the Session 42 platform state and release progression (`docs/PROJECT-PLAN.md`, `docs/reference/version-matrix.md`).

## [v0.158.0] - 2026-02-25

### Added

- **1Password Ansible Collection** — `ansible/requirements.yml` (new file). Declares `community.general >=8.1.0`, `artis3n.tailscale`, and `onepassword.connect` as collection dependencies. Install with `ansible-galaxy collection install -r ansible/requirements.yml`.
- **1Password secret lookups in group_vars** — `ansible/inventory/group_vars/k3s_cluster.yml` updated to use `community.general.onepassword` lookups instead of `vault_*` fallback variables. `k3s_cluster_token` resolves from `homelab-k3s-cluster` item, field `server-token`, section `cluster`; `postgres_password` resolves from field `password`, section `database`. Lookups are lazy (evaluated only when task references the variable) and require the `op` CLI and 1Password desktop app running.

### Changed

- `ansible/README.md` — Full rewrite with collection install instructions, op CLI prerequisite, SSH agent setup, run commands, bootstrap override with `-e` flags, and future CI path with Connect API (`https://op-connect.homelab.ts.net`).

### Fixed

- **Ansible lint violations across 4 playbooks** — Fixed all pre-existing violations to achieve 5/5 stars production profile:
  - `no-relative-paths` — Changed `../templates/` to `{{ playbook_dir | dirname }}/templates/` in k3s-agents.yml, k3s-servers.yml, and pg-backup.yml.
  - `command-instead-of-module` + `risky-shell-pipe` — Replaced `curl | sh` installer pattern with `ansible.builtin.get_url` + `ansible.builtin.shell` in all 4 playbooks (server install, agent install, server upgrade, agent upgrade).
  - `risky-shell-pipe` — Added `set -o pipefail` + `executable: /bin/bash` to all shell tasks using pipes (node-ready checks, pg_dump|gzip in k3s-upgrade.yml, VIP check in pg-backup.yml).
  - `command-instead-of-module` — Replaced `command: mount` with `ansible.posix.mount state: mounted` in pg-backup.yml.
  - `no-changed-when` — Added `changed_when: true` to upgrade installer shell tasks.
  - **backup verification** — Replaced `ls | tail` with `ansible.builtin.find` module in k3s-upgrade.yml.
- **Secret exposure in logs** — Added `no_log: true` to K3S_TOKEN shell tasks in k3s-upgrade.yml and k3s-agents.yml.

## [v0.157.0] - 2026-02-25

### Added

- **GitLab CE Prometheus metrics** — `kubernetes/apps/gitlab/deployment.yaml` updated with `gitlab_rails['monitoring_whitelist'] = ['10.42.0.0/16']` to allow in-cluster Prometheus scraping of `/-/metrics`. Restricted to K3s pod CIDR (not `0.0.0.0/0`) for security.
- **ServiceMonitor for GitLab** — `kubernetes/apps/gitlab/servicemonitor.yaml` (new file). Scrapes `/-/metrics` on the `http` port every 60 seconds. Labels include `app.kubernetes.io/component: monitoring`.
- **GitLab SSH over Tailscale** — `kubernetes/apps/gitlab/tailscale-ssh-service.yaml` (new file). Kubernetes `Service` with `loadBalancerClass: tailscale` and `tailscale.com/hostname: gitlab-ssh` creates a dedicated Tailscale node (`gitlab-ssh.homelab.ts.net:22`) for SSH clone access. `gitlab_rails['gitlab_ssh_host']` and `gitlab_rails['gitlab_shell_ssh_port']` configure the SSH clone URL shown in GitLab UI.
- **Grafana dashboard — GitLab CE Overview** — `kubernetes/platform/monitoring/configs/dashboards/gitlab.json` (new file). Custom 13-panel dashboard (UID `gitlab-ce-overview`) organized into 4 rows: Puma (active connections, queued connections, thread utilization), Sidekiq (queue depth, job throughput rate), HTTP (request rate by status, latency p50/p95/p99), Ruby runtime (GC fraction in `percentunit`, SQL query duration p50/p95). All histogram panels use `sum by (le)` before `histogram_quantile` for correct aggregation.
- **PVC Storage panels in Applications dashboard** — `kubernetes/platform/monitoring/configs/dashboards/applications.json` updated. Added "PVC Storage" row (3 panels): PVC Usage by Namespace timeseries (utilization fraction) + PVC Usage Detail table (used/capacity GB with color thresholds: green <70%, yellow 70–90%, red >90%) using `kubelet_volume_stats_used_bytes` and `kubelet_volume_stats_capacity_bytes` (already scraped by kube-prometheus-stack default config).

### Changed

- `kubernetes/apps/gitlab/kustomization.yaml` — Added `servicemonitor.yaml` and `tailscale-ssh-service.yaml` to `resources:` list.
- `kubernetes/platform/monitoring/configs/kustomization.yaml` — Added `dashboards/gitlab.json` to the `cicd-grafana-dashboards` configMapGenerator.

## [v0.155.0] - 2026-02-25

### Added

- **n8n Prometheus metrics** — `kubernetes/apps/n8n/deployment.yaml` updated with three env vars to enable Prometheus metrics exposure: `N8N_METRICS=true`, `N8N_METRICS_INCLUDE_DEFAULT_METRICS=true`, `N8N_METRICS_INCLUDE_API_ENDPOINTS=false`. n8n exposes a `/metrics` endpoint on the existing HTTP port.
- **ServiceMonitor for n8n** — `kubernetes/apps/n8n/servicemonitor.yaml` (new file). Configures Prometheus to scrape the `/metrics` endpoint on the `http` port every 30 seconds. Labels include `app.kubernetes.io/name: n8n` and `app.kubernetes.io/component: monitoring` for consistency with other monitored services.
- **Grafana dashboard — n8n System Health Overview** — `kubernetes/platform/monitoring/configs/dashboards/n8n.json`. Community dashboard 24474 adapted for the homelab. Panels cover n8n process metrics (CPU, memory, event loop lag, garbage collection), workflow execution counters, and queue/job health. Dashboard UID fixed to `n8n-system-health-overview`. Includes `DS_PROMETHEUS` datasource template variable for portability across Grafana instances.

### Changed

- `kubernetes/apps/n8n/kustomization.yaml` — Added `servicemonitor.yaml` to `resources:` list.
- `kubernetes/platform/monitoring/configs/kustomization.yaml` — Added `dashboards/n8n.json` to the `homelab-grafana-dashboards` configMapGenerator (label `grafana_dashboard: "1"` triggers Grafana sidecar auto-import).

### Fixed

- **n8n dashboard quality** — Typo "Gargabe" corrected to "Garbage" in GC panel titles. Datasource template variable `DS_PROMETHEUS` added so the dashboard works without manual datasource selection after import.

## [v0.131.0] - 2026-02-21

### Added

- **ServiceMonitor for podinfo-staging** — `kubernetes/staging/podinfo/servicemonitor.yaml`. Tells Prometheus to scrape podinfo's `/metrics` endpoint on port `http` (9898) every 30s with `scrapeTimeout: 20s`. Namespace injected by kustomization `namespace: podinfo-staging` field. Labels include `app.kubernetes.io/name: podinfo` and `app.kubernetes.io/component: monitoring` for consistency.
- **Grafana dashboard — Podinfo Staging** — `kubernetes/platform/monitoring/configs/dashboards/staging.json`. Dedicated dashboard with 3 rows: Summary (request rate, 5xx error rate with `or vector(0)`, pod availability ratio, p99 latency), HTTP Traffic (request rate by status code, p50/p95/p99 latency percentiles), Pod Health (CPU in `cores` unit, memory in bytes). Uses hidden `$namespace` constant variable (value: `podinfo-staging`) in all PromQL exprs for portability. Pod Availability panel uses `available/desired` ratio with 90%/100% thresholds.

### Changed

- `kubernetes/staging/podinfo/kustomization.yaml` — Added `servicemonitor.yaml` to `resources:` list.
- `kubernetes/platform/monitoring/configs/kustomization.yaml` — Added `dashboards/staging.json` to `homelab-grafana-dashboards` configMapGenerator (label `grafana_dashboard: "1"` triggers Grafana sidecar auto-import).

## [v0.71.0] - 2026-02-18

### Added

- **Draw.io** — Stateless diagramming tool in `kubernetes/apps/drawio/` (6 files). OAuth2 Proxy protected, no persistence needed. Dual ingress (nginx LAN + Tailscale).
- **Calibre-web** — Ebook library in `kubernetes/apps/calibre-web/` (8 files). Static NFS PV pointing at existing Synology library `/volume1/Calibre_Library`. Default login admin/admin123.
- **Linkwarden** — Bookmark manager in `kubernetes/apps/linkwarden/` (8 files). External PostgreSQL via ESO ExternalSecret (`nextauth-secret` + `db-connection-url` from 1Password item `linkwarden`). NFS for screenshots/PDFs.
- **GitLab CE** — Omnibus self-hosted Git forge in `kubernetes/apps/gitlab/` (7 files). NFS persistence (config/data/logs), startupProbe with 10-minute window for first boot migrations. Built-in auth (no OAuth2 Proxy).
- **Homepage widgets** — Service widgets for 10 apps (Grafana, Plex, qBittorrent, Stash, Portainer, GitLab, Linkwarden, Calibre-web, Proxmox, Tailscale) + Longhorn info widget. Credentials sourced from 1Password item `homepage-widgets` via ExternalSecret with `optional: true` on all env vars.
- **Homepage service entries** — Added Proxmox (hypervisor cluster) and Tailscale (mesh VPN) under Platform category.

### Changed

- `kubernetes/apps/kustomization.yaml` — Added `./drawio`, `./calibre-web`, `./linkwarden`, `./gitlab` to app resources.
- `kubernetes/apps/homepage/release.yaml` — Added widget configs to all supported services, new Proxmox/Tailscale entries, Longhorn info widget, 12 env vars from ExternalSecret.
- `kubernetes/apps/homepage/kustomization.yaml` — Added `external-secret.yaml` to resources.

## [v0.58.0] - 2026-02-17

- fix: Windmill ExternalSecret key mismatch (db-connection-url → url)

## [v0.57.0] - 2026-02-17

### Added
- **Longhorn distributed block storage** — Platform controller in `kubernetes/platform/controllers/longhorn.yaml`. CNCF-graduated distributed block storage for K3s with 2-replica redundancy. Enables pod/workspace migration without data loss. Requires `open-iscsi` + `nfs-common` on all K3s nodes (Ansible prerequisite).
- **Coder remote dev environments** — App deployment in `kubernetes/apps/coder/` (6 files). Self-hosted CDE platform for AI agent orchestration (Claude Code, Aider). Uses external PostgreSQL (10.0.0.45), 1Password ExternalSecret for credentials, Tailscale ingress at `coder.homelab.ts.net`. Requires manual DB setup and 1Password item creation.
- **Windmill workflow automation** — App deployment in `kubernetes/apps/windmill/` (6 files). Open-source workflow engine with Rust server + horizontal workers. Lean config: 1 app replica, 2 default workers, 1 native worker. External PostgreSQL, indexer ephemeral-storage reduced from 50Gi default to 10Gi. Tailscale ingress at `windmill.homelab.ts.net`.
- **Reference docs** — `docs/reference/flux-gitops-patterns.md` (Flux reconciliation chain, standard app pattern), `docs/reference/storage-longhorn.md` (StorageClass comparison, Longhorn config), `docs/reference/app-deployment-patterns.md` (Coder/Windmill patterns, external PostgreSQL convention).

### Changed
- `kubernetes/platform/controllers/kustomization.yaml` — Added `longhorn.yaml` to platform controllers
- `kubernetes/apps/kustomization.yaml` — Added `./coder` and `./windmill` to app list
- `docs/reference/1password-integration.md` — Added Connect server redundancy/LXC architecture section

### Fixed
- **Homepage code-server URL** — Changed `code.homelab.ts.net` to `code-server.homelab.ts.net` in `kubernetes/apps/homepage/release.yaml`

## [v0.56.0] - 2026-02-17
- docs: Add K3s upgrade procedure and update reference docs

## [v0.55.0] - 2026-02-17
- fix: Move group_vars adjacent to inventory for Ansible discovery

## [v0.54.0] - 2026-02-17
- feat: Add K3s Ansible playbooks, inventory, and upgrade templates
