---
title: Homelab IAC Reference Index
description: Master reference index for the homelab infrastructure-as-code project covering architecture, topology, services, and operational state
published: true
date: 2026-02-18
tags:
  - index
  - architecture
  - topology
  - k3s
  - proxmox
  - terraform
  - ansible
---

Master reference index for the homelab infrastructure-as-code project. This page summarizes the current architecture, topology, deployed services, and operational state. Detailed topics are covered in dedicated reference pages linked throughout.

## Project Overview

- Proxmox homelab with 5 bare-metal nodes managed via Terraform (bpg/proxmox provider v0.95.0)
- K3s cluster: 3 servers + 5 agents + 1 PostgreSQL HA pair, Ansible for K3s provisioning
- 1Password Connect for secrets management (HA on 2 Proxmox LXC containers)
- Credentials: 1Password Connect data sources in Terraform (no TF_VAR secrets in env)
- Env files: `.env.d/terraform.env` (only Connect token + non-secret defaults)
- Cluster name: "homelab-k3s-cluster" (formerly "valhalla"), all nodes PVE 9.1.5
- K3s version: v1.32.12+k3s1 (upgraded from v1.28.3+k3s1 via 4 sequential hops)

## Proxmox Cluster and K3s Topology

### Proxmox Nodes

| Node | CPU | RAM | Role | LAN IP |
|------|-----|-----|------|--------|
| node-01 | 16 cores | 32 GB | Agent host, PG primary host | 10.0.0.13 |
| node-02 | 12 cores | 31 GB | Server host, VM template host, API endpoint | 10.0.0.10 |
| node-03 | 16 cores | 31 GB | Server host | 10.0.0.11 |
| node-04 | 16 cores | 31 GB | Server host | 10.0.0.12 |
| node-05 | 12 cores | 67 GB | Agent host, PG standby host | 10.0.0.14 |

### K3s Control Plane (Servers)

Hosted on: node-02, node-03, node-04

### K3s Workers (Agents)

5 agent nodes with varied sizing across all 5 Proxmox hosts. See `docs/pve-node-spec-config.md` for the full allocation table.

### PostgreSQL HA

See [postgresql-ha.md](./postgresql-ha.md) for full details.

- Primary: VM 520 on node-01 (10.0.0.45), keepalived MASTER priority 100
- Standby: VM 521 on node-05 (10.0.0.46), keepalived BACKUP priority 90
- VIP: 10.0.0.44 (floats via keepalived VRRP, virtual_router_id 44)
- Async streaming replication, failover tested (~15s cutover)

### Infrastructure Components

- VM template: VM 9000 on node-02 (Ubuntu 24.04 cloud image)
- API endpoint: `https://node-02.homelab.ts.net:8006`
- NFS storage: `Proxmox_NAS` (10.0.0.161:/volume1/proxmox)
- All nodes have `vmbr0` bridge on 10.0.0.0/24, VLAN 2

## 1Password Setup

See [1password-integration.md](./1password-integration.md) for full details.

- Connect server: HA on 2 Proxmox LXC containers (CT200 on node-01, CT201 on node-05)
- VIP: `http://10.0.0.72:8080` (keepalived failover), nodes: 10.0.0.70 + 10.0.0.71
- 2 vaults: Homelab (`e2xu6xow3lm3xssqph2jftrny4`), Dev (`qxhlzrgegpplamzkgg7kuxnhmm`)
- TF provider: Connect mode in `infrastructure/main.tf`, data sources read Proxmox creds
- 1Password SSH agent: socket at `~/.1password/agent.sock`
- SSH key for K3s VMs: `homelab-k3s-cluster` (item UUID: `j23jpbwjm2gzxtht7hezuf4ili`), username `k3sadmin`

## Flux GitOps Structure

See [flux-gitops-patterns.md](./flux-gitops-patterns.md) for full details.

- Entry point: `clusters/homelab/` (community standard `clusters/<name>/` pattern)
- Follows [flux2-kustomize-helm-example](https://github.com/fluxcd/flux2-kustomize-helm-example)
- Separation: `clusters/` = HOW (orchestration), `kubernetes/` = WHAT (manifests), `infrastructure/` = WHERE (Terraform)
- Dependency chain: platform-controllers -> platform-configs -> apps
- Monitoring: monitoring-controllers -> monitoring-configs (depends on platform-configs for ESO CRDs)
- GitHub PAT for Flux: 1Password item `gh-homelab-fluxcd` (vault: Homelab)

## Tailscale Integration

See [tailscale-kubernetes.md](./tailscale-kubernetes.md) for full details.

- User accesses homelab exclusively via Tailscale -- NO public internet exposure
- Tailscale login identity: `admin@example.com`
- Tailscale K8s operator: replaces cert-manager TLS + provides private ingress
- Three exposure methods: `ingressClassName: tailscale`, `loadBalancerClass: tailscale`, annotation `tailscale.com/expose: "true"`
- API server proxy: ACTIVE, enables remote kubectl via Tailscale
- Decision: Dual ingress -- ingress-nginx (LAN, self-signed CA) + Tailscale operator (remote, auto `*.ts.net` TLS)
- Grafana accessible at `https://grafana.homelab.ts.net` (Tailscale) + `https://grafana.10.0.0.201.nip.io` (LAN)

## Platform Services Deployed

See [version-matrix.md](./version-matrix.md) for version details.

### Phase 1: Platform Infrastructure

| Service | Description | Namespace |
|---------|-------------|-----------|
| MetalLB | L2 mode, IPAddressPool 10.0.0.201-250 | metallb-system |
| ingress-nginx | LoadBalancer type, external IP 10.0.0.201 | ingress-nginx |
| NFS provisioner | StorageClass `nfs-kubernetes`, Synology NAS | nfs-provisioner |
| cert-manager | Self-signed CA chain | cert-manager |
| Tailscale operator | OAuth Secret, IngressClass `tailscale` | tailscale |
| Longhorn | Distributed block storage, 2-replica, StorageClass `longhorn` | longhorn-system |

### Phase 2: Identity and Auth

| Service | Description | Namespace |
|---------|-------------|-----------|
| ESO | ClusterSecretStore `onepassword-connect` | external-secrets |
| Keycloak | codecentric chart, `homelab` realm, external PG | keycloak |
| OAuth2 Proxy | `keycloak-oidc` provider, protects LAN ingresses | oauth2-proxy |
| Portainer CE | Dual ingress (LAN + Tailscale) | portainer |

### Monitoring Stack

| Service | Description | Namespace |
|---------|-------------|-----------|
| kube-prometheus-stack | Grafana + Prometheus + Alertmanager | monitoring |
| Loki | Log aggregation | monitoring |
| Promtail | Log collection | monitoring |
| pve-exporter | Proxmox metrics | monitoring |
| GitHub Actions exporter | Pull-based CI/CD metrics (Labbs v1.9.0) | monitoring |
| Flux notifications | Error events to Slack (v1beta3 Provider + Alert) | flux-system |

### Dashboards

3 Flux dashboards (control-plane, cluster, logs) + 3 custom (applications, application-logs, proxmox) + 2 CI/CD (cicd-pipeline, gitops-health) + 2 application dashboards (n8n-system-health-overview, gitlab-ce-overview) + ~20 default kube-prometheus-stack. See [cicd-observability.md](./cicd-observability.md) for CI/CD dashboard details and [application-metrics.md](./application-metrics.md) for application ServiceMonitors and dashboards.

## Applications Deployed

See [app-deployment-patterns.md](./app-deployment-patterns.md) for deployment patterns.

### Phase 3: Application Stack

| App | Type | Notes |
|-----|------|-------|
| Homepage | HelmRelease | Dashboard with widget integrations |
| Plex | HelmRelease | **Suspended** -- needs NAS NFS permissions for new VM IPs |
| Nexus | HelmRelease | Artifact repository |
| code-server | Raw manifests | Web-based VS Code |
| n8n | Raw manifests | Workflow automation, external PG |
| JupyterLab | Raw manifests | Data science notebooks |
| Wiki.js | Raw manifests | Knowledge base, external PG, Git storage backend |
| YouTrack | Raw manifests | Issue tracker, Longhorn SC for Xodus DB |
| TeamCity | Raw manifests | CI/CD server + 3 build agents, external PG |
| Draw.io | Raw manifests | Diagramming tool |
| GitLab CE | Raw manifests | Self-hosted Git forge |
| Calibre-web | Raw manifests | E-book library, NFS-backed |
| Linkwarden | HelmRelease | Bookmark/link archival (needs 8Gi memory limit for Puppeteer) |

- Docmost: disabled (replaced by Wiki.js)

### Phase 4: Day-2 Operations

| App | Type | Notes |
|-----|------|-------|
| Velero | HelmRelease | K8s backup with CSI snapshots + Kopia data movement |
| Snapshot Controller | Raw manifests | external-snapshotter v8.2.0, VolumeSnapshotClass for Longhorn |
| MinIO | HelmRelease | Standalone S3-compatible storage for Velero BSL |
| Coder | HelmRelease | AI agent orchestration CDE, external PG |
| Windmill | HelmRelease | Workflow automation, external PG |

All apps use dual ingress (nginx LAN + Tailscale) and OAuth2 Proxy SSO (except Plex).

## PostgreSQL Databases

All hosted on the HA cluster at VIP 10.0.0.44. See [postgresql-ha.md](./postgresql-ha.md).

| Database | Consumer |
|----------|----------|
| `k3s` | K3s datastore |
| `terraform_state` | Terraform remote backend |
| `keycloak` | Keycloak identity provider |
| `n8n` | n8n workflow automation |
| `wikijs` | Wiki.js knowledge base |
| `teamcity` | TeamCity CI/CD server |
| `coder` | Coder remote development |
| `windmill` | Windmill workflow automation |

## Cluster Status

- K3s cluster: 8 nodes (3 servers + 5 agents) Ready, v1.32.12+k3s1
- Local kubectl: `~/.kube/config-homelab` (KUBECONFIG=~/.kube/config-homelab) -- LAN only (10.0.0.50:6443)
- Remote kubectl: `kubectl --context=tailscale-operator.homelab.ts.net` -- works from any network via Tailscale
- 1Password Connect: HA on LXC (VIP 10.0.0.72), failover tested
- Terraform remote state: PostgreSQL backend ACTIVE
- FluxCD v2.7.5, all 6 Kustomizations reconciling
- 20 HelmReleases deployed, 19 Ready (Plex suspended)
- 15 ExternalSecrets all SecretSynced

## Key Files

| File | Purpose |
|------|---------|
| `infrastructure/main.tf` | Root module with providers, 1Password data sources, module "pve" |
| `infrastructure/vm-template.tf` | Ubuntu 24.04 VM template (VM 9000) |
| `infrastructure/backend.tf` | PostgreSQL backend (state at 10.0.0.44) |
| `infrastructure/modules/k3s/k3s-cluster.tf` | K3s cluster (3 servers + 5 agents + PostgreSQL) |
| `infrastructure/modules/pg-ha/` | PostgreSQL HA module |
| `infrastructure/modules/op-connect/` | 1Password Connect HA module |
| `ansible/inventory/k3s.yml` | K3s cluster inventory |
| `ansible/playbooks/k3s-cluster.yml` | Site playbook (servers + agents provisioning) |
| `ansible/playbooks/k3s-upgrade.yml` | Rolling upgrade playbook |
| `ansible/playbooks/pg-backup.yml` | Backup automation deployment |
| `clusters/homelab/` | Flux GitOps entry point |
| `kubernetes/platform/` | Platform controllers and configs |
| `kubernetes/apps/` | Application manifests |
| `docs/PROJECT-PLAN.md` | 5-phase project plan |
| `docs/pve-node-spec-config.md` | Node hardware and resource allocation |

## Project Plan Status

| Phase | Description | Status |
|-------|-------------|--------|
| Phase 0 | Repo cleanup | COMPLETE |
| Phase 1 | Platform infra (remote state, FluxCD, ingress, MetalLB, cert-manager, monitoring, NFS) | COMPLETE |
| Phase 2 | Identity (Keycloak, OAuth2 Proxy, ESO) | COMPLETE |
| Phase 3 | Application stack (8 apps running) | COMPLETE |
| Phase 4 | Day-2 ops (backups, upgrades, CI/CD, monitoring expansion) | IN PROGRESS |

## Reference Pages

| Page | Description |
|------|-------------|
| [1password-integration.md](./1password-integration.md) | 1Password integration across Terraform, Ansible, ESO, CLI, SSH |
| [ai-and-llm-information.md](./ai-and-llm-information.md) | AI/LLM tools and MCP server configurations |
| [ansible-patterns.md](./ansible-patterns.md) | Ansible patterns: 1Password lookup, lint compliance, idiomatic task modules |
| [app-deployment-patterns.md](./app-deployment-patterns.md) | Application deployment patterns (Coder, Windmill, Homepage) |
| [application-metrics.md](./application-metrics.md) | Prometheus ServiceMonitors and Grafana dashboards for apps (n8n, GitLab CE) |
| [backup-strategy.md](./backup-strategy.md) | Two-tier PostgreSQL backup strategy |
| [cicd-observability.md](./cicd-observability.md) | CI/CD monitoring: GitHub Actions exporter, Flux notifications, dashboards, alerts |
| [cicd-ops-checklist.md](./cicd-ops-checklist.md) | CI/CD setup checklist and session handoff notes |
| [CONTRIBUTING.md](./CONTRIBUTING.md) | Git workflow, pre-commit hooks, conventions |
| [deployment-troubleshooting.md](./deployment-troubleshooting.md) | Deployment issues with root cause analysis |
| [environment-variables.md](./environment-variables.md) | Environment variable architecture and credential flow |
| [flux-gitops-patterns.md](./flux-gitops-patterns.md) | Flux GitOps patterns, conventions, and notification-controller |
| [k3s-upgrade-procedure.md](./k3s-upgrade-procedure.md) | Rolling K3s upgrade procedure |
| [mcp-kubernetes-deployment-strategy.md](./mcp-kubernetes-deployment-strategy.md) | MCP server centralization in Kubernetes |
| [nexus-migration.md](./nexus-migration.md) | Nexus OrientDB to H2 migration procedure |
| [postgresql-ha.md](./postgresql-ha.md) | PostgreSQL HA architecture and operations |
| [proxmox-lxc-patterns.md](./proxmox-lxc-patterns.md) | Proxmox LXC container patterns |
| [storage-longhorn.md](./storage-longhorn.md) | Longhorn distributed block storage |
| [tailscale-kubernetes.md](./tailscale-kubernetes.md) | Tailscale Kubernetes operator integration |
| [technical-gotchas.md](./technical-gotchas.md) | Cross-cutting technical gotchas |
| [version-matrix.md](./version-matrix.md) | Application version tracking |

## Nexus Proxy Infrastructure

Nexus Repository Manager acts as a caching proxy for all upstream registries. See [nexus-migration.md](./nexus-migration.md) for full setup details.

- **Helm proxy repos:** 20 repos managed via `scripts/nexus/configure-proxy-repos.sh`
- **Docker proxy repos:** docker-hub, docker-ghcr, docker-quay
- **APT proxy repos:** apt-ubuntu, apt-ubuntu-security
- **Containerd registry mirrors:** Configured on K3s nodes via `ansible/playbooks/k3s-registry-mirrors.yml`
- **Internal URL pattern:** `http://nexus-nexus-repository-manager.nexus.svc.cluster.local:8081/repository/<name>/`
- **APT proxy LAN IP:** `10.0.0.202:8081` (dedicated MetalLB LoadBalancer, bypasses OAuth2 Proxy)
- **ingress-nginx IP:** `10.0.0.201` (OAuth2-protected, NOT suitable for apt/cloud-init)

## Staging Environment

A namespace-based staging environment for testing app changes without touching production. See `docs/guides/staging-environment.md` and [flux-gitops-patterns.md](./flux-gitops-patterns.md#staging-environment-namespace-based-overlays).

- Entry point: `clusters/homelab/staging.yaml`
- Overlay directory: `kubernetes/staging/`
- Pattern: Kustomize overlays over `kubernetes/apps/<app>` bases, namespace renamed to `<app>-staging`
- Prune enabled: removing from `kubernetes/staging/kustomization.yaml` deletes the staging namespace
- Working example: `kubernetes/staging/podinfo/`

## Next Steps

1. Consider adding `nopreempt` to keepalived MASTER config (prevent VIP snap-back)
2. Fix Synology NAS NFS permissions for video shares, then `flux resume helmrelease plex -n media`
3. Phase 5 app deployments (see `docs/PROJECT-PLAN.md`)
4. Phase 4 Day-2 ops (CI/CD, monitoring expansion, version pinning)
