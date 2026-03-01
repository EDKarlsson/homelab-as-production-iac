---
title: Application Version Matrix
description: Comprehensive version tracking for all deployed applications, platform services, and infrastructure components
published: true
date: 2026-02-25
tags:
  - versions
  - applications
  - maintenance
---

Comprehensive version tracking for all deployed applications, platform services, and infrastructure components.

Last audited: **2026-02-26** (Session 44 — docs-only; no version changes. Blog series created in homelab-as-production repo.)

## Infrastructure

| Component | Current Version | Latest Available | Deployed At | Notes |
|-----------|----------------|-----------------|-------------|-------|
| Proxmox VE | 9.1.5 | — | pre-v0.54.0 | 6 bare-metal nodes (gpu-workstation joined v0.138.0; IOMMU + vfio-pci active) |
| K3s | v1.32.12+k3s1 | v1.32.12+k3s1 | v0.75.0 | Upgraded from v1.28.3 via 4 sequential hops |
| Ubuntu (VMs) | 24.04.4 LTS | 24.04.4 LTS | v0.75.0 | Kernel 6.8.0-100-generic |
| Terraform | >= 1.5 | — | pre-v0.54.0 | bpg/proxmox provider v0.95.0 |
| Ansible | — | — | pre-v0.54.0 | K3s provisioning |
| 1Password Connect | — | — | v0.54.0 | HA on 2 LXC containers (VIP 10.0.0.72) |
| PostgreSQL (VM) | — | — | v0.67.0 | HA primary/standby, VIP 10.0.0.44 |
| ComfyUI (gpu-workstation) | NVIDIA 580.126.18 | — | unreleased | KVM VFIO abandoned (X299/Ampere incompatibility); LXC approach implemented but pct exec crashes blocked completion; gpu-workstation removed from cluster, reinstalled as standalone Ubuntu workstation. `module "comfyui_lxc"` in Terraform commented out pending state cleanup. |

## GitOps & Cluster Platform

| Component | Image Version | Chart Version | Latest Available | Deployed At | Status |
|-----------|--------------|---------------|-----------------|-------------|--------|
| FluxCD | v2.7.5 | — | v2.7.5 | v0.99.0 | Upgraded from v2.3.0; K8s 1.32 unlocked v2.5+ |
| MetalLB | v0.15.3 | 0.15.x | v0.15.3 | v0.54.0 | Current |
| ingress-nginx | v1.14.3 | 4.x | v1.14.3 | v0.54.0 | Current |
| cert-manager | v1.19.3 | 1.19.x | v1.19.3 | v0.99.0 | Current; upgraded from 1.17.x |
| NFS provisioner | v4.0.2 | 4.x | v4.0.2 | v0.54.0 | Current |
| Tailscale operator | v1.94.2 | 1.x | — | v0.54.0 | Current |
| ESO | v2.0.0 | 2.0.x | v2.0.0 | v0.103.0 | Current; upgraded from 1.x (removed Alibaba/Device42 providers) |
| Longhorn | v1.11.0 | 1.x | v1.11.0 | v0.57.0 | Current |
| Velero | v1.17.2 | 11.x (11.3.2) | v1.17.2 | v0.90.0 | Current |
| velero-plugin-for-aws | v1.13.2 | — | v1.13.2 | v0.90.0 | Current |
| Snapshot Controller | v8.2.0 | — | v8.2.0 | v0.90.0 | Current |
| MinIO | latest | 5.x (5.4.0) | — | v0.90.0 | Current |

## Monitoring Stack

| Component | Image Version | Chart Version | Latest Available | Deployed At | Status |
|-----------|--------------|---------------|-----------------|-------------|--------|
| GitHub Actions Exporter | 1.9.0 | — (raw manifests) | 1.9.0 | v0.95.0 | Current; Labbs/github-actions-exporter, pull-based polling |
| Grafana | 12.3.3 | (kube-prometheus-stack 82.1.1) | 12.3.3 | v0.99.0 | Current; upgraded via chart 69→82 |
| Prometheus | v3.9.1 | (kube-prometheus-stack 82.1.1) | v3.9.1 | v0.99.0 | Current; upgraded via chart 69→82 |
| Alertmanager | v0.31.1 | (kube-prometheus-stack 82.1.1) | v0.31.1 | v0.99.0 | Current; upgraded via chart 69→82 |
| kube-state-metrics | v2.18.0 | (kube-prometheus-stack 82.1.1) | v2.18.0 | v0.99.0 | Current; upgraded via chart 69→82 |
| prometheus-operator | v0.89.0 | (kube-prometheus-stack 82.1.1) | v0.89.0 | v0.99.0 | Current; upgraded via chart 69→82 |
| node-exporter | v1.10.2 | (kube-prometheus-stack 82.1.1) | v1.10.2 | v0.99.0 | Current; upgraded via chart 69→82 |
| Loki | 3.6.5 | 6.x (6.53.0) | 3.6.5 | v0.99.0 | Chart bumped 6.x→6.53.0 |
| Promtail | 3.5.1 | 6.x | — | v0.54.0 | — |
| pve-exporter | 3.8.1 | — | 3.8.1 | v0.54.0 | Current (pinned from :latest) |

## Identity & Auth

| Component | Image Version | Chart Version | Latest Available | Deployed At | Status |
|-----------|--------------|---------------|-----------------|-------------|--------|
| Keycloak | 26.5.3 | 7.x (keycloakx) | 26.5.3 | v0.54.0 | Current |
| OAuth2 Proxy | v7.14.2 | 7.x (7.18.0) | v7.14.2 | v0.100.0 | Current; image tag pinned in HelmRelease values |

## Applications (Helm)

| App | Image Version | Chart Version | Latest Available | Deployed At | Status |
|-----|--------------|---------------|-----------------|-------------|--------|
| Homepage | v1.10.1 (overridden) | 2.x (jameswynn) | v1.10.1 | v0.54.0 | Chart bundles v1.2.0; image tag overridden in release.yaml |
| Portainer CE | 2.33.7 | 2.x | 2.33.7 | v0.54.0 | Current |
| Plex | :latest | 1.x | 1.43.0.10492 | v0.54.0 | Unpin to 1.43.0 |
| Nexus | 3.89.1 | 64.x | 3.89.1 | v0.108.0 | Current; upgraded via 3.70.3 checkpoint + OrientDB→H2 migration |
| Coder | v2.30.1 | 2.x | v2.30.1 | v0.57.0 | Current |
| Windmill | 1.639.0 | 2.x | 1.639.0 | v0.100.0 | Current; image tag pinned in HelmRelease values |
| Linkwarden | v2.13.5 | v2.13.5 | v0.71.0 | Current (pinned from :latest) |

## Applications (Raw Manifests)

| App | Image Version | Latest Available | Deployed At | Status |
|-----|--------------|-----------------|-------------|--------|
| code-server | 4.109.2 | 4.109.2 | v0.54.0 | Current (pinned from :latest) |
| n8n | 2.8.3 | 2.8.3 | v0.54.0 | Current (pinned from :latest) |
| JupyterLab | cuda12-2026-02-16 | cuda12-2026-02-19 | v0.54.0 | Pinned to date tag (was cuda12-latest) |
| Wiki.js | 2.5.312 | 2.5.312 | v0.54.0 | Current (pinned from :2) |
| YouTrack | 2025.3.124603 | 2025.3.124603 | v0.54.0 | Current |
| TeamCity | 2025.11.2 | 2025.11.2 | v0.54.0 | Current |
| Draw.io | 29.3.6 | 29.3.6 | v0.71.0 | Current (pinned from :latest) |
| GitLab CE | 18.9.0-ce.0 | 18.9.0-ce.0 | v0.71.0 | Current (pinned from :latest) |
| Calibre-web | 0.6.26 | 0.6.26 | v0.71.0 | Current (pinned from :latest) |
| AFFiNE | 0.26.2 | 0.26.2 | v0.151.0 | Current; ghcr.io/toeverything/affine (no v prefix on GHCR tags) |
| Redis (affine) | 7.4.2 | — | v0.151.0 | In-cluster Redis for AFFiNE BullMQ queues; appendonly + noeviction |
| Dependency-Track | 4.13.6 | 4.13.6 | v0.160.0 | Current; bundled image (API + frontend); ALPINE_MEMORY_MAXIMUM=6g; pinned to node-05 |

## Utility / System

| Component | Image Version | Latest Available | Deployed At | Status |
|-----------|--------------|-----------------|-------------|--------|
| podinfo | 6.10.1 | — | v0.54.0 | Test app, version not critical |
| podinfo-redis | 7.0.6 | — | v0.54.0 | Test app, version not critical |
| Windmill LSP | :latest | (follows main) | v0.57.0 | Floating tag |

## Version Change Log

Track version changes across sessions. Each entry records what changed, why, and the homelab tag.

| Date | App | From | To | Homelab Tag | Reason |
|------|-----|------|----|-------------|--------|
| 2026-02-18 | K3s | v1.28.3+k3s1 | v1.32.12+k3s1 | v0.75.0 | Rolling upgrade (4 sequential hops) for Flux v2.5+ compat |
| 2026-02-19 | Velero | — (new) | v1.17.2 | v0.90.0 | New deployment: K8s backup with Longhorn CSI snapshots |
| 2026-02-19 | velero-plugin-for-aws | — (new) | v1.13.2 | v0.90.0 | S3 plugin for MinIO BSL |
| 2026-02-19 | Snapshot Controller | — (new) | v8.2.0 | v0.90.0 | CSI VolumeSnapshot CRDs + controller (K3s prerequisite) |
| 2026-02-19 | MinIO | — (new) | 5.4.0 | v0.90.0 | S3-compatible storage for Velero on NFS |
| 2026-02-19 | YouTrack (storage) | local-path | longhorn | v0.90.0 | Migrated for Velero CSI snapshot support |
| 2026-02-19 | GitHub Actions Exporter | — (new) | 1.9.0 | v0.95.0 | New deployment: CI/CD metrics for Prometheus |
| 2026-02-19 | code-server | :latest | 4.109.2 | v0.96.0 | Pinned to semver |
| 2026-02-19 | n8n | :latest | 2.8.3 | v0.96.0 | Pinned to semver |
| 2026-02-19 | JupyterLab | cuda12-latest | cuda12-2026-02-16 | v0.96.0 | Pinned to date-based tag (format: cuda12-YYYY-MM-DD) |
| 2026-02-19 | Wiki.js | :2 | 2.5.312 | v0.96.0 | Pinned from major floating tag to full semver |
| 2026-02-19 | Draw.io | :latest | 29.3.6 | v0.96.0 | Pinned to semver |
| 2026-02-19 | GitLab CE | :latest | 18.9.0-ce.0 | v0.96.0 | Pinned to semver (GitLab uses -ce.0 suffix for CE images) |
| 2026-02-19 | Calibre-web | :latest | 0.6.26 | v0.96.0 | Pinned to semver (LinuxServer.io bare version tag, no -lsNNN) |
| 2026-02-19 | pve-exporter | :latest | 3.8.1 | v0.96.0 | Pinned to semver; v3.8.0 breaking change: gauges replaced with counters |
| 2026-02-19 | Linkwarden | :latest | v2.13.5 | v0.96.0 | Pinned to semver |
| 2026-02-19 | Plex | :latest | (still :latest) | — | Suspended; pin to 1.43.0 when resumed |
| 2026-02-19 | Homepage | v1.2.0 (chart default) | v1.10.1 | v0.96.0 | Image tag overridden in HelmRelease values |
| 2026-02-19 | FluxCD | v2.3.0 | v2.7.5 | v0.99.0 | Self-upgrade via gotk-components.yaml; K8s 1.32 unlocked v2.5+ |
| 2026-02-19 | cert-manager | v1.17.4 (chart 1.17.x) | v1.19.x (chart 1.19.x) | v0.99.0 | Security fix for DNS response caching panic DoS |
| 2026-02-19 | kube-prometheus-stack | chart 69.x | chart 82.x | v0.99.0 | Grafana 12, Prometheus 3.8+, AlertMgr 0.31, kube-state-metrics 2.18+ |
| 2026-02-19 | OAuth2 Proxy | chart 7.x | chart 7.18.0 | v0.99.0 | Chart bump via force-reconcile; image still v7.11.0 (pinned) |
| 2026-02-19 | Loki | chart 6.x | chart 6.53.0 | v0.99.0 | Chart bump via force-reconcile |
| 2026-02-19 | OCIRepository API | v1beta2 | v1 | v0.99.0 | Promoted in Flux v2.5; updated proactively |
| 2026-02-19 | Bucket API (kube-state-metrics) | v1beta2 | v1 | v0.99.0 | Promoted in Flux v2.5; updated in kube-state-metrics config |
| 2026-02-19 | OAuth2 Proxy | v7.11.0 | v7.14.2 | v0.100.0 | Image tag pinned in HelmRelease values |
| 2026-02-19 | Windmill | 1.555.0 | 1.639.0 | v0.100.0 | Image tag pinned in HelmRelease values; ~84 releases of incremental fixes |
| 2026-02-19 | ComfyUI VM (infra) | — (new) | source ref `master` | unreleased | New Terraform module for Proxmox VM deployment; Docker image built from upstream source, GPU passthrough hooks included |
| 2026-02-19 | ESO | v1.3.2 (chart 1.x) | v2.0.0 (chart 2.0.x) | v0.103.0 | Major upgrade; removed Alibaba/Device42 providers (unused), 1Password Connect unchanged |
| 2026-02-19 | Nexus | 3.64.0 | 3.89.1 | v0.108.0 | Multi-step: 3.64→3.70.3 (checkpoint) → OrientDB→H2 offline migration → 3.89.1; Java 8→21 |
| 2026-02-19 | ComfyUI VM passthrough | disabled in root module wiring | enabled (`0000:01:00.0`, `0000:01:00.1`) | unreleased | Enabled RTX 3060 host PCI passthrough settings in root Terraform module call |
| 2026-02-20 | kube-state-metrics (config) | custom-resource-only | default collectors + Flux CRDs | — | Fixed: `collectors: []` + `--custom-resource-state-only` was blocking all standard K8s metrics |
| 2026-02-20 | kube-prometheus-stack (K3s) | all components enabled | scheduler/proxy/controller-mgr/etcd disabled | — | K3s bundles these into server binary; disabling removes broken ServiceMonitors |
| 2026-02-20 | HelmRepository URLs (×20) | upstream registries | Nexus cluster-internal proxy | — | All chart fetches now go through Nexus cache (resilience + bandwidth savings) |
| 2026-02-20 | cert-manager (chart) | 1.17.x | 1.19.x | — | Allowlist updated to match current chart version constraint |
| 2026-02-20 | ESO (chart) | 1.x | 2.0.x | — | Allowlist updated to match current chart version constraint |
| 2026-02-20 | kube-prometheus-stack (config) | serviceMonitorSelector: default | serviceMonitorSelector: {} + NilUsesHelmValues: false | — | Fix: custom ServiceMonitors (pve-exporter, github-actions-exporter, velero, nexus) were invisible to Prometheus due to default release label filter |
| 2026-02-21 | podinfo-staging (ServiceMonitor) | — (new) | monitoring.coreos.com/v1 ServiceMonitor | v0.131.0 | Wire up Prometheus scraping for staging namespace; no image change |
| 2026-02-21 | podinfo-staging (Grafana dashboard) | — (new) | staging.json ConfigMap | v0.131.0 | Dedicated dashboard: HTTP traffic, latency percentiles, pod availability ratio |
| 2026-02-21 | AlertManager routing | default catch-all | default-null + whitelist | v0.133.0 | Only warning/critical routed to Slack; Watchdog → null; info/debug silently dropped |
| 2026-02-21 | maintenance-checks (CI) | — (new) | tailscale/github-action@v3 | v0.135.0 | Weekly scheduled workflow: cert expiry, K3s lag, backup health checks + Slack digest |
| 2026-02-25 | Grafana (SSO method) | oauth2-proxy annotation | native auth.generic_oauth | v0.146.0 | Migrated to kube-prometheus-stack values; no proxy hop; auto_login=true |
| 2026-02-25 | AFFiNE | — (new) | 0.26.2 | v0.151.0 | New deployment: collaborative knowledge base + whiteboard; PostgreSQL + NFS PVC + Redis |
| 2026-02-25 | Redis (affine) | — (new) | 7.4.2 | v0.151.0 | New deployment: in-cluster Redis for AFFiNE BullMQ job queues |
| 2026-02-25 | K3s registry mirrors | /repository/*/  (no /v2 suffix) | /repository/*/v2 | v0.151.0 | Fix: containerd override_path=true strips /v2; Nexus returned 400 without it |
| 2026-02-25 | Dependency-Track | — (new) | 4.13.6 | v0.160.0 | New deployment: SBOM vulnerability analysis; bundled image; external PG; OAuth2 Proxy SSO |
| 2026-02-25 | generate-sbom.sh (CI) | — (new) | 1.0 | v0.162.0 | New CI script: CycloneDX 1.4 SBOM from K8s manifests → Dependency-Track upload (27 images, pkg:oci PURLs) |
| 2026-02-24 | Wiki.js (CPU limit) | 1000m | 2000m | v0.153.0 | CPUThrottlingHigh alert: Node.js burst workload (startup + Git sync) needs >1 vCPU burst headroom; request stays 100m |
| 2026-02-24 | Alertmanager (inhibit_rules) | no inhibit_rules | InfoInhibitor → severity=info suppression | v0.153.0 | Added standard inhibit_rules; suppresses info alerts per-namespace when InfoInhibitor fires |
| 2026-02-24 | GitLab CE (metrics) | no scraping | ServiceMonitor + /-/metrics | v0.157.0 | monitoring_whitelist=10.42.0.0/16; custom 13-panel Grafana dashboard |
| 2026-02-24 | GitLab CE (SSH) | port 80 only | Tailscale L4 LoadBalancer :22 | v0.157.0 | New Service with loadBalancerClass=tailscale; hostname=gitlab-ssh |
| 2026-02-24 | Applications dashboard (PVC) | no storage panels | PVC usage timeseries + table | v0.157.0 | kubelet_volume_stats_* metrics; color thresholds at 70%/90% |
| 2026-02-24 | Ansible (secrets) | vault_* fallback vars | community.general.onepassword lookup | v0.158.0 | Lazy evaluation from group_vars; requires op CLI + 1Password desktop |
| 2026-02-24 | Ansible (lint) | pre-existing violations | 5/5 stars production profile | v0.158.0 | Fixed risky-shell-pipe, command-instead-of-module, no-relative-paths, no-changed-when |
| 2026-02-25 | Terraform CI | (no gcompat) | gcompat added | v0.170.0 | 1Password provider is CGO/glibc binary; Alpine musl can't exec it without gcompat shim |
| 2026-02-25 | Dependency-Track (OIDC) | no SSO | ALPINE_OIDC_* env vars | v0.171.0 | Public PKCE client with Keycloak homelab realm; USER_PROVISIONING=true |
| 2026-02-25 | oauth2-proxy (nginx) | default proxy-buffer-size | proxy-buffer-size: 128k | v0.172.0 | Keycloak JWTs with realm-management roles exceed 4k/8k default; caused 502 on /oauth2/callback |
| 2026-02-25 | Dependency-Track (JVM TLS) | system default truststore | init container + keytool + JAVA_TOOL_OPTIONS | v0.174.0 | ALPINE_HTTPS_TRUST_ALL_CERTIFICATES only covers Alpine HttpUtil, not JVM SSLContext; PKIX path failed on OIDC calls |
| 2026-02-25 | publish-nexus CI | no git, Tailscale NEXUS_URL | git installed, K8s-internal URL | v0.175.0 | ubuntu:24.04 lacks git; job pods can't resolve Tailscale MagicDNS |
| 2026-02-25 | sbom CI job | always-on (pending forever) | when: manual | v0.177.0 | No shell runner registered; allow_failure doesn't unblock pending jobs; manual is correct |
| 2026-02-25 | GitLab shell runner | not deployed | homelab-shell-homelab-kcs-1 registered | v0.179.0 | New Ansible playbook; yq v4.44.5, flux v2.7.5, gitlab-runner installed on k3s server node |
| 2026-02-25 | Dependency-Track (SSO) | OIDC vars only (non-functional) | postStart hook patches config.json | v0.183.0 | Bundled image has no entrypoint.sh; Jetty extracts config.json at runtime; hook uses find+sed-i |
| 2026-02-25 | Dependency-Track (oauth2-proxy) | oauth2-proxy nginx gate | native OIDC (PKCE via Keycloak) | v0.182.0 | Removed auth-url/auth-signin/auth-response-headers annotations; avoids double-login |

## Summary Statistics

- **Total tracked components:** 50
- **Current / up to date:** 44
- **Behind (pinned, needs upgrade):** 1 (Plex — suspended)
- **Using floating tags (`:latest` / `:2`):** 2 (Windmill LSP — Helm-managed, Plex — suspended)
- **Last full audit:** 2026-02-24 (Session 38: Alertmanager inhibit_rules + Wiki.js CPU limit raise)

## Upgrade Priority

### High (security/functionality impact)

- ~~**Homepage** v1.2.0 -> v1.10.1~~ DONE v0.96.0
- ~~**cert-manager** v1.17.4 -> v1.19.x~~ DONE v0.99.0 — security fix for DNS caching panic
- ~~**Nexus** 3.64.0 -> 3.89.1~~ DONE v0.108.0 — multi-step migration via 3.70.3 checkpoint

### Medium (feature/maintenance)
- ~~**Grafana** 11.5.2 -> ~12.x~~ DONE v0.99.0 — via kube-prometheus-stack 82.x
- ~~**Prometheus** v3.2.1 -> ~v3.8+~~ DONE v0.99.0 — via kube-prometheus-stack 82.x
- ~~**kube-state-metrics** v2.15.0 -> ~v2.18+~~ DONE v0.99.0 — via kube-prometheus-stack 82.x
- ~~**OAuth2 Proxy** v7.11.0 -> v7.14.2~~ DONE v0.100.0 — image tag pinned in HelmRelease values
- ~~**Windmill** 1.555.0 -> 1.639.0~~ DONE v0.100.0 — image tag pinned in HelmRelease values

### Low (patch/optional)
- ~~**Loki** chart bump~~ DONE v0.99.0 — chart 6.53.0
- ~~**ESO** v1.3.2 -> v2.0.0~~ DONE v0.103.0 — major version, no impact on 1Password Connect provider

### ~~Pin floating tags (operational hygiene)~~ DONE
