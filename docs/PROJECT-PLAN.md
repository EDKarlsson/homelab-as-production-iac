# Homelab IaC — Project Plan

Status: **Phases 0-3 complete.** K3s cluster operational (v1.32.12), FluxCD GitOps pipeline active, full platform + identity + application stack deployed (21 active app resources, with `jackett` and `docmost` disabled). PG HA cluster with keepalived VIP failover. Repository cleaned up and documented.
Phase 4.1 (PG backup automation) **COMPLETE**. Phase 4.3 (CI/CD) **COMPLETE**. Phase 4.6 (coordination) **COMPLETE**. Phase 5.3 (GitLab) **COMPLETE** — Keycloak SSO, GitHub mirror, GitLab CI pipeline, homelab CA cert TLS fix. Grafana native Keycloak SSO (auth.generic_oauth) **COMPLETE** — PR #146, replaces oauth2-proxy annotation. Nexus consumer migration (apt/Helm/npm/pypi/cargo/go) **COMPLETE** — TeamCity build agent env vars + ServiceMonitor basicAuth fix (PR #147), Cargo proxy via ConfigMap (PR #148). AFFiNE collaborative knowledge base **DEPLOYED** (PRs #149-151) — PostgreSQL + NFS blob storage + Redis, WebSocket support, K3s registry mirror /v2 path fix. Alert noise reduction **COMPLETE** (PR #153) — Alertmanager inhibit_rules + Wiki.js CPU limit raised. n8n Prometheus metrics + Grafana dashboard **COMPLETE** (PR #155) — ServiceMonitor, n8n System Health Overview dashboard (community 24474), datasource variable + typo fixes. ComfyUI on gpu-workstation (standalone). Phase 5.4 (Dependency-Track) **COMPLETE** (PRs #160, #162, #182-184) — bundled image, external PG, dual ingress, native OIDC SSO (postStart hook patches Jetty-extracted config.json), JVM truststore for homelab CA, SBOM upload pipeline via `generate-sbom.sh`. Next up: Phase 4.7 dashboard coverage (Windmill, TeamCity, JupyterLab), Phase 5.5 Kong evaluation.

---

## Phase 0: Repository Cleanup & Reorganization

Housekeeping to remove stale content, consolidate docs, and archive legacy scripts before building on top.

### 0.1 — Rewrite root README.md

- [x] Remove references to abandoned sibling repos (`homelab-flux`, `homelab-vms`, `homelab-infra`)
- [x] Update directory tree to match actual structure (`kubernetes/` not `cluster/`, no `argocd`)
- [x] Replace "Deployed" status badges with actual state at the time (17 apps deployed, 3 disabled)
- [x] Move commented-out app wishlist to PROJECT-PLAN.md Phase 5
- [x] Add current cluster topology (3 servers + 5 agents + PostgreSQL HA)
- [x] Add quick-start section: `terraform apply` → `ansible-playbook` → `flux bootstrap`

### 0.2 — Reorganize docs/ directory

Current structure is flat and mixed. Reorganize:

```
docs/
├── README.md                  ← Rewrite as index
├── CHANGELOG.md               ← Keep
├── architecture/              ← NEW: project-level reference
│   ├── cluster-topology.md    ← Merge hardware-infrastructure.md + pve-node-spec-config.md
│   └── homelab-architecture.drawio
├── guides/                    ← Keep as-is (active, well-maintained)
│   ├── README.md
│   ├── 01-terraform-provider-setup.md  ← Rename with numeric prefixes
│   └── ...
├── reference/                 ← NEW: slim operational reference
│   ├── CONTRIBUTING.md        ← Extract real practices from standards/
│   └── app-wishlist.md        ← Aspirational apps from README
└── archive/                   ← NEW: preserved but not active
    ├── standards/             ← Move all 10 AI-generated standards docs
    ├── memory-bank/           ← Move after consolidation (0.3)
    └── ai-generated/          ← Move security-audit-report.md
```

- [x] Create `docs/architecture/` and merge the two hardware docs
- [x] Create `docs/reference/CONTRIBUTING.md` with actual practices (pre-commit, branch workflow, 1Password)
- [x] Move `docs/standards/` → `docs/archive/standards/`
- [x] Move `docs/ai-generated/` → `docs/archive/ai-generated/`
- [x] Delete `docs/TODO.md` (TaskMaster boilerplate, no content)
- [x] Rewrite `docs/README.md` as a proper index (guides, architecture, 13 reference docs, analysis, archive)

### 0.3 — Consolidate memory-bank/ into Claude memory

- [x] Review each memory-bank file for unique content not already in `.claude/` memory
- [x] Merge useful content into MEMORY.md or topic-specific memory files
- [x] Move `docs/memory-bank/` → `docs/archive/memory-bank/`

### 0.4 — Archive legacy scripts

Move scripts superseded by cloud-init or that are broken/outdated to `scripts/_archive/`:

- [x] `scripts/k8s/config-k3s.sh` — Marked BROKEN, replaced by cloud-init
- [x] `scripts/k8s/simple_setup.sh` — Too simple, replaced by cloud-init
- [x] `scripts/k8s/k3s-install-helm.sh` — Helm v2 with Tiller (dead since 2019)
- [x] `scripts/k8s/init-k3s.sh` — Uses `--cluster-init` with external DB (conflict), replaced by cloud-init
- [x] `scripts/k8s/install-docker.sh` — K3s uses containerd, Docker not needed
- [x] `scripts/misc/config-env.sh` — Duplicates env-load.sh functionality

Keep active:
- `scripts/k8s/k3s-ssh.sh` (active, 1Password SSH)
- `scripts/k8s/k3s-verify.sh` (active, deployment verification)
- `scripts/k8s/bootstrap-flux.sh` (needed soon, but needs path fix)
- `scripts/k8s/validate.sh` (Flux validation, from upstream)
- `scripts/pve/create-tf-user.sh` (Proxmox setup)
- `scripts/pve/test-api.sh` (needs fix but useful)
- `scripts/1password/` (Connect setup)
- `scripts/nut/` (UPS monitoring, used by Ansible)

### 0.5 — Clean up other AI tool artifacts

- [x] Remove `.clinerules` (Cline config) — already absent
- [x] Remove `GEMINI.md` and `.gemini/` (Gemini config) — already absent
- [x] Remove `.mcp.op.json` — legacy Cline/TaskMaster MCP config, superseded by `.mcp.json`

---

## Phase 1: Platform Infrastructure (FluxCD + Core Services)

Deploy the GitOps pipeline and essential platform services that all applications depend on.

### 1.1 — Activate Terraform remote state

- [x] Verify PostgreSQL `terraform_state` database is accessible from workstation
- [x] Uncomment `infrastructure/backend.tf`
- [x] Run `terraform init -migrate-state`
- [x] Verify: `terraform plan` shows no changes

### 1.2 — Bootstrap FluxCD

- [x] Restructure Flux: `infrastructure/flux/` → `clusters/homelab/` (community standard pattern)
- [x] Fix `scripts/k8s/bootstrap-flux.sh` (correct repo, path, add pre-flight checks)
- [x] Fix `kubernetes/apps/kustomization.yaml` (two-document bug)
- [x] Add missing `kubernetes/platform/monitoring/controllers/kustomization.yaml`
- [x] Document architecture decision in `docs/architecture/flux-structure.md`
- [x] Decide: bootstrap to this repo (`homelab-iac`) ← chosen
- [x] Install Flux CLI on workstation (v2.3.0 — Flux v2.5+ requires K8s >= 1.32)
- [x] Create GitHub personal access token for Flux (1Password: `gh-homelab-fluxcd`)
- [x] Run `flux bootstrap github --path=clusters/homelab`
- [x] Verify: `flux get kustomizations` shows synced

### 1.3 — Deploy ingress-nginx

- [x] Review `kubernetes/platform/controllers/ingress-nginx.yaml` values
- [x] Decision: Use LoadBalancer type (MetalLB provides IPs) ← chosen
- [x] Update `service.type` from `NodePort` → `LoadBalancer`
- [x] Verify: ingress-nginx LoadBalancer IP `10.0.0.201` from MetalLB pool

### 1.4 — Deploy MetalLB for LoadBalancer services

K3s was configured with `--disable servicelb` — need a real LB controller.

- [x] Choose IP range: `10.0.0.201-10.0.0.250` (50 IPs, DHCP ceiling at .200)
- [x] Create Flux HelmRelease for MetalLB (L2 mode, chart 0.15.x)
- [x] Create IPAddressPool and L2Advertisement CRDs in `platform/configs/`
- [x] Verify: 1 controller + 8 speakers running, ingress-nginx got `10.0.0.201`

### 1.5 — Deploy cert-manager + TLS strategy

Dual ingress: ingress-nginx (LAN, self-signed CA) + Tailscale operator (remote, auto `*.ts.net` TLS).

- [x] Review `kubernetes/platform/controllers/cert-manager.yaml` (chart 1.17.x, CRDs installed)
- [x] Decision: Self-signed internal CA for LAN; Tailscale operator for remote TLS (future)
- [x] Replace Let's Encrypt ClusterIssuer with self-signed CA chain (`selfsigned-issuer` → `homelab-ca` → `homelab-ca-issuer`)
- [x] Remove stale ACME server patch from `clusters/homelab/platform.yaml`
- [x] Verify: `kubectl get clusterissuer` shows `selfsigned-issuer` and `homelab-ca-issuer` Ready
- [x] Verify: `kubectl get certificate -n cert-manager homelab-ca` shows Ready
- [ ] Optional: export CA cert and trust on LAN devices
- [x] Deploy Tailscale K8s operator (chart 1.x) for remote access with auto `*.ts.net` TLS
- [x] Enable Tailscale API server proxy (`apiServerProxyConfig.mode: "true"`) for remote kubectl
- [x] Verify: Grafana accessible at `grafana.homelab.ts.net` (Tailscale) + `grafana.10.0.0.201.nip.io` (LAN)

### 1.6 — Deploy monitoring stack (kube-prometheus-stack + Loki)

- [x] Review existing manifests in `kubernetes/platform/monitoring/`
- [x] Configure persistent storage: Prometheus 10Gi, Grafana 2Gi, Loki 5Gi, Minio 5Gi (all NFS)
- [x] NFS CSI driver already deployed in Phase 1.7
- [x] Deploy kube-prometheus-stack with Grafana ingress (`grafana.10.0.0.201.nip.io`)
- [x] Deploy Loki + Promtail for log aggregation
- [x] Verify: Grafana accessible via ingress, Prometheus scraping nodes

### 1.7 — NFS persistent storage

Required by monitoring, media apps, and any stateful workload.

- [x] Deploy `nfs-subdir-external-provisioner` via Flux HelmRelease (chart 4.x)
- [x] Create StorageClass `nfs-kubernetes` pointing to `10.0.0.161:/volume1/kubernetes` (reclaimPolicy: Retain)
- [x] Test with a PVC claim — Bound successfully
- [x] Verify: `kubectl get storageclass` shows `nfs-kubernetes` (Immediate binding, volume expansion enabled)

---

## Phase 2: Identity & Access Management

Centralized auth before deploying user-facing applications.

### 2.1 — Deploy Keycloak

- [x] Decision: Codecentric `keycloakx` chart (Quarkus-based, Bitnami deprecated Aug 2025)
- [x] Decision: External PostgreSQL VM at 10.0.0.45 (reuse existing infra)
- [x] Create Flux HelmRelease for Keycloak (codecentric keycloakx chart 7.x)
- [x] Configure external PostgreSQL backend (keycloak database on 10.0.0.45)
- [x] Update cloud-config template with keycloak database + user + pg_hba entry
- [x] Create ExternalSecrets for admin credentials and DB password
- [x] Configure dual ingress: LAN (nginx + homelab-ca-issuer) + Tailscale
- [x] Create 1Password items: `keycloak-admin` (admin creds) + `keycloak-db` (DB creds)
- [x] Provision keycloak database on live PostgreSQL VM (SSH + createdb)
- [x] Verify: Keycloak admin console accessible at `keycloak.homelab.ts.net` + LAN
- [x] Create admin user with full realm admin privileges
- [x] Create `homelab` realm and configure OIDC clients (Phase 2.2 prerequisite)

### 2.2 — Deploy OAuth2 Proxy

- [x] Create Flux HelmRelease for OAuth2 Proxy (oauth2-proxy chart 7.x)
- [x] Create `homelab` realm in Keycloak with `oauth2-proxy` OIDC client (confidential)
- [x] Configure audience mapper and groups mapper on OIDC client
- [x] Create ExternalSecret for client-id, client-secret, cookie-secret from 1Password
- [x] Integrate with ingress-nginx (`auth-url` / `auth-signin` annotations) on Grafana
- [x] Verify: Grafana LAN ingress redirects to Keycloak login
- [x] Verify: Grafana Tailscale ingress still works without OAuth2 Proxy
- [x] SSO coverage audit: 14/21 nginx apps protected; added Portainer; GitLab/Plex/Windmill intentionally exempt (own auth or Tailscale-only)
- [x] Grafana native Keycloak SSO (PR #146) — migrated from oauth2-proxy annotation to `auth.generic_oauth` in kube-prometheus-stack values; Grafana no longer behind OAuth2 Proxy; `auto_login = true`

### 2.3 — External Secrets Operator (ESO) for 1Password

Bridge 1Password secrets into Kubernetes.

- [x] Decision: Continue using existing Connect server over Tailscale (no in-cluster deployment)
- [x] Deploy External Secrets Operator via Flux (chart 1.x, CRDs managed)
- [x] Create bootstrap secret script (`scripts/k8s/create-eso-connect-secret.sh`)
- [x] Create ClusterSecretStore pointing to 1Password Connect (`onepassword-connect`)
- [x] Create ExternalSecret for Tailscale OAuth (`tailscale-operator-oauth`)
- [x] Create ExternalSecret for Grafana admin password (`grafana-admin`)
- [x] Create `grafana-admin` item in 1Password
- [x] Run bootstrap: `./scripts/k8s/create-eso-connect-secret.sh`
- [x] Verify: `kubectl get externalsecret -A` shows synced

---

## Phase 3: Application Stack

All apps get dual ingress (nginx LAN + Tailscale) and OAuth2 Proxy SSO (except Plex).

### 3.1 — Deploy Homepage (dashboard)

- [x] Create Flux HelmRelease (jameswynn/homepage chart 2.x)
- [x] Configure RBAC + service account for K8s service discovery
- [x] Configure LAN ingress with OAuth2 Proxy + homelab-ca-issuer
- [x] Configure Tailscale ingress
- [x] Pre-populate services: Portainer, Keycloak, Grafana
- [x] Add Prometheus widget (targets up/down/total)
- [x] Reorganize groups: Platform, Network & Security, Monitoring, Media, Services, Dev
- [x] Move Keycloak + Tailscale nodes to "Network & Security" group
- [x] Move Calibre-web to Media, n8n + Windmill to Dev
- [x] Professional dashboard design: dark theme, slate color, boxedWidgets, background image, row layout with columns
- [x] Add Synology DiskStation widget (Leviathan) with nested volume entries for /volume1, /volume2, /volume3
- [x] Nest Tailscale widgets in collapsible sub-group within Network & Security
- [x] Add DiskStation credentials to `homepage-widgets` 1Password item (copy from "Synology: Remote Stat")
- [ ] Add Prometheus Metrics iframe card (embedded Grafana panel — requires Grafana anonymous viewer access)
- [x] Verify: Homepage accessible at `homepage.10.0.0.201.nip.io` + Tailscale

### 3.2 — Deploy Plex (media server)

- [x] Create Flux HelmRelease (plexinc/plex-media-server chart 0.x)
- [x] Create static PV/PVCs for NFS media libraries (movies, music, photos, adult, adult-v3)
- [x] Configure LAN ingress with homelab-ca-issuer (no OAuth2 — Plex has own auth)
- [x] Configure Tailscale ingress
- [x] Fix NAS NFS permissions for new VM IPs (.50-.64)
- [ ] Get Plex claim token from <https://plex.tv/claim> (valid ~4 min), uncomment in values
- [x] Verify: Plex web UI accessible, can browse all 5 media libraries
- [x] Decision: GPU transcoding deferred (GTX 1080 Pascal limitations)

### 3.5 — Deploy code-server (VS Code in browser)

- [x] Create Flux HelmRelease (coder/code-server chart 3.x)
- [x] Create ExternalSecret for password from 1Password
- [x] Create dynamic PVC for workspace (nfs-kubernetes, 10Gi)
- [x] Configure LAN ingress with OAuth2 Proxy + homelab-ca-issuer
- [x] Configure Tailscale ingress
- [ ] Create 1Password item `code-server` with `password` field
- [x] Verify: code-server accessible, workspace persists across restarts

### 3.6 — Deploy n8n (workflow automation)

- [x] Create Flux HelmRelease (8gears/n8n chart 1.x)
- [x] Configure external PostgreSQL backend (10.0.0.45)
- [x] Create ExternalSecret for DB password + encryption key from 1Password
- [x] Configure LAN ingress with OAuth2 Proxy + homelab-ca-issuer
- [x] Configure Tailscale ingress
- [x] Create `n8n` database + user on PG VM
- [ ] Create 1Password item `n8n` with `db-password` and `encryption-key` fields
- [x] Verify: n8n accessible, can create and execute workflows

### 3.7 — Deploy Nexus Repository Manager (artifact repo)

- [x] Create Flux HelmRelease (sonatype/nexus-repository-manager chart 64.x)
- [x] Configure embedded H2 database (homelab scale, no external PG needed)
- [x] Create dynamic PVC for data (nfs-kubernetes, 50Gi)
- [x] Configure LAN ingress with OAuth2 Proxy + homelab-ca-issuer + unlimited upload size
- [x] Configure Tailscale ingress
- [x] Verify: Nexus web UI accessible, can publish/pull artifacts
- [x] Configure 13 proxy repositories (docker-hub, ghcr, quay, apt, helm, npm, pypi, cargo, go, etc.) — PR #115
- [x] Configure K3s containerd registry mirrors → Nexus docker proxies — PR #127
- [x] Expose Nexus on dedicated MetalLB IP for apt proxy — PR #126
- [x] Migrate K3s VMs apt sources → Nexus apt-ubuntu / apt-ubuntu-security proxies (cloud-init or Ansible)
- [x] Migrate Flux HelmRepositories → Nexus helm-stable proxy (update `spec.url`)
- [x] Configure TeamCity build agent env vars for npm/pypi/go/cargo proxies
- [x] Connect Nexus metrics to Grafana (Prometheus endpoint at `/service/metrics`)
- [ ] Connect Nexus to GitHub/TeamCity/GitLab for build artifact publishing (see Tailscale GH Action)
- [ ] Optional: JupyterLab `pip.conf` → pypi-proxy; Terraform `.terraformrc` → terraform-registry proxy

### 5.1 — Deploy Linkwarden (bookmark manager)

[Linkwarden](https://linkwarden.app/) — collaborative bookmark manager with archival.

- [x] Evaluate deployment method (Docker image, Helm chart availability)
- [x] Create Flux manifests (raw K8s manifests — Deployment, Service, Ingress)
- [x] Configure external PostgreSQL backend (10.0.0.44 VIP)
- [x] Create 1Password items + ExternalSecret
- [x] Configure dual ingress (LAN nginx + Tailscale) with OAuth2 Proxy
- [x] Resources: 2 vCPU / 8Gi (Puppeteer headless Chrome is memory-hungry)

### 5.2 — Deploy Draw.io (diagramming)

[Draw.io](https://github.com/jgraph/docker-drawio) — self-hosted diagramming tool.

- [x] Create Flux manifests (raw K8s manifests — simple single-container app)
- [x] Configure dual ingress (LAN nginx + Tailscale) with OAuth2 Proxy
- [x] Verify: accessible and can save/export diagrams

### 5.3 — Deploy GitLab (source code management + CI/CD)

[GitLab](https://docs.gitlab.com/install/docker/) — self-hosted Git with CI/CD pipelines. Resource-heavy — evaluate cluster capacity before deploying.

- [x] Evaluate resource requirements vs available cluster capacity
- [x] Decision: GitLab CE Omnibus Docker image (raw manifests, not Helm chart)
- [x] Decision: Database — embedded PostgreSQL (GitLab manages its own)
- [x] Create Flux manifests (raw K8s manifests — Deployment, Service, PVC)
- [x] Configure persistent storage (NFS 50Gi for config/repos/registry)
- [x] Configure dual ingress (LAN nginx + Tailscale) with OAuth2 Proxy
- [x] Probes: tcpSocket (health endpoints only respond on localhost)
- [x] Keycloak OIDC SSO — users log in with Keycloak account; omniauth OIDC provider configured in OMNIBUS_CONFIG; homelab CA cert mounted via initContainer for TLS trust
- [x] GitHub → GitLab push mirror — self-hosted runner mirrors main branch to gitlab.homelab.ts.net/homelab/homelab-iac on every push
- [x] GitLab CI pipeline — .gitlab-ci.yml matching GitHub Actions validation (terraform, ansible, k8s, shellcheck, Nexus publish)
- [x] Decision: GitHub stays as Flux source; GitLab is primary for new work (circular dependency risk if cluster-hosted GitLab used for IaC)
- [x] Optional: Integrate GitLab Runners with K3s cluster — Kubernetes executor runner (PRs #164-169) + homelab shell runner on k3s_servers[0] (PRs #178-179)
- [x] GitLab CI pipeline hardening — gcompat fix for 1Password Alpine provider (#170), git install + internal K8s service URL for publish-nexus (#175-176), sbom job made manual pending runner registration (#177); PR review comments addressed (#179)
- [ ] Optional: Set up GitLab as mirror destination for app repos (new projects start on GitLab)

### 5.4 — Deploy security scanning suite (Nexus companion tools)

Security and dependency scanning tools intended to complement Nexus Repository Manager.

#### OWASP Dependency-Track (primary)

[Dependency-Track](https://owasp.org/www-project-dependency-track/) — continuous SBOM analysis platform with dashboard.

- [x] Create Flux manifests (Docker-based deployment)
- [x] Configure external PostgreSQL backend (VIP)
- [x] Configure dual ingress with OAuth2 Proxy
- [x] Integrate with Nexus for artifact scanning (upload SBOMs from CI pipeline)
- [x] Native OIDC SSO via Keycloak — public OIDC client (PKCE), DT frontend initiates flow directly; homelab CA imported into JVM truststore via init container (PRs #171, #173-174)
- [x] SSO button visible and functional — postStart lifecycle hook patches Jetty-extracted config.json; Keycloak Web Origins configured for PKCE CORS (PRs #182-184)

#### OWASP Dependency-Check (CLI tool)

[Dependency-Check](https://owasp.org/www-project-dependency-check/) — CLI scanner for known vulnerabilities. Can run as CI job rather than persistent deployment.

- [ ] Decision: Persistent deployment vs CI/CD job in GitLab/TeamCity
- [ ] Configure NVD data mirror if persistent

#### Additional scanning tools (evaluate)

These are CLI/library tools — evaluate whether they need K8s deployments or are better as CI pipeline steps:

- [ORT: OSS Review Toolkit](https://github.com/oss-review-toolkit/ort) — license compliance + vulnerability scanning
- [AuditJS](https://www.npmjs.com/package/auditjs) — npm dependency auditing (Sonatype OSS Index)
- [Nancy](https://github.com/sonatype-nexus-community/nancy) — Go dependency auditing
- [OSS Audit](https://github.com/illikainen/ossaudit) — Python dependency auditing
- [Cargo Pants](https://github.com/sonatype-nexus-community/cargo-pants) — Rust dependency auditing
- [Ahab](https://github.com/sonatype-nexus-community/ahab) — OS package auditing (dpkg/apk)

### 5.5 — Deploy Kong API Gateway

[Kong](https://konghq.com/products/kong-gateway) — aggregate all service APIs behind a single gateway with rate limiting, auth, and observability.

- [ ] Evaluate deployment method (Kong Ingress Controller vs standalone gateway)
- [ ] Create Flux HelmRelease (kong chart)
- [ ] Configure external PostgreSQL backend (VIP 10.0.0.44)
- [ ] Configure dual ingress (LAN nginx + Tailscale)
- [ ] Route existing service APIs through Kong
- [ ] Configure rate limiting and authentication plugins

### 5.6 — Optional apps (evaluate)

- **Octelium** — evaluate use case and resource requirements
- **Arkime** — full packet capture and analysis (network security monitoring)
- [ ] Deploy OpenVAS (vulnerability scanner) — low priority, security hardening; raw K8s manifests, needs persistent storage and PG backend

### 5.7 — Deploy ComfyUI (GPU compute)

gpu-workstation repurposed as standalone Ubuntu 24.04 workstation (VFIO passthrough abandoned — RTX 3060/X299 host crash, PR #140). ComfyUI runs natively. Terraform module commented out.

- [x] Create Terraform module `infrastructure/modules/comfyui` (VM + cloud-init bootstrap)
- [x] Docker Compose deployment model with source-built ComfyUI image (no ComfyUI base image)
- [x] Add optional GPU passthrough controls (`hostpci`, q35/OVMF defaults, configurable PCI IDs)
- [x] Add guest bootstrap for NVIDIA container runtime setup when GPU is detected
- [x] Configure initial PCI IDs in Terraform (`0000:01:00.0` GPU, `0000:01:00.1` audio)
- [x] Confirm final PCI IDs — RTX 3060 at `65:00.0/65:00.1`, GTX 1080 Ti at `17:00.0`
- [x] VFIO passthrough attempted and abandoned — X299 host kernel panic on NVIDIA driver init; hardware limitation
- [x] gpu-workstation running ComfyUI natively (bare install at `~/comfy/ComfyUI/`, 88G+ models, NVIDIA 580.126.16, CUDA 12.5)
- [x] Pin ComfyUI to release tag — N/A; gpu-workstation removed from cluster, ComfyUI runs natively outside this repo's scope

### 5.8 — Deploy AFFiNE (collaborative knowledge base)

[AFFiNE](https://affine.pro/) — self-hosted collaborative knowledge base, whiteboard, and document editor. All-in-one image, single-replica.

- [x] Evaluate deployment method (Docker/K8s raw manifests, all-in-one image port 3010)
- [x] Create namespace, PVC (10Gi NFS ReadWriteMany for blob storage), Redis (in-cluster, ephemeral)
- [x] Create Deployment with migration init container (`self-host-predeploy.js` — idempotent, runs every restart)
- [x] Configure external PostgreSQL backend (10.0.0.44 VIP) with pgvector; create `affine` DB + user
- [x] Create 1Password item + ExternalSecret for `db-password` and `private-key`
- [x] Configure dual ingress (LAN nginx + Tailscale) with WebSocket support (proxy-set-headers ConfigMap)
- [x] Fix: `configuration-snippet` blocked by admission webhook → proxy-set-headers ConfigMap (PR #150)
- [x] Fix: GHCR image tag `v0.26.2` → `0.26.2` (GitHub release prefix ≠ Docker tag) (PR #151)
- [x] Fix: K3s registry mirror `/v2` path bug — containerd `override_path=true` strips the prefix; endpoint must include `/v2` (PR #151)
- [x] Fix: pg_hba.conf missing `affine` entry — added on primary (.45) + standby (.46); `SELECT pg_reload_conf()` (out of band)
- [x] Verify: AFFiNE accessible via Tailscale (`affine.homelab.ts.net`), workspace creation works, data persists in PostgreSQL

---

## Phase 4: Day-2 Operations

### 4.1 — PostgreSQL backup automation

- [x] Design two-tier backup strategy (Tier 1: K8s CronJob pg_dumpall, Tier 2: VM-level per-db dumps)
- [x] Create Ansible playbook `pg-backup.yml` with VIP guard pattern for HA-aware execution
- [x] Create backup script template (`backup-pg-dbs.sh.j2`) covering all 8 databases
- [x] Add `pg_nodes` inventory group with both PG HA VMs (.45 + .46)
- [x] Update cloud-init templates: add 5 missing DBs, pg_hba entries, nfs-common, backup script
- [x] Fix stale K8s CronJob comment (listed 5 DBs, uses pg_dumpall for all 8)
- [x] Create Synology NAS share `/volume1/postgresql-backups` with NFS for .45/.46
- [x] Run playbook: `ansible-playbook -i inventory/k3s.yml playbooks/pg-backup.yml --forks=1`
- [x] Verify: 8 `.sql.gz` files in `/var/backups/postgresql/` + NAS sync (2026-02-21)
- [x] Test restore procedure (n8n dump → throwaway DB, 10 tables verified)

### 4.4 — 1Password Ansible Collection

Integrate the [official 1Password Connect Ansible collection](https://developer.1password.com/docs/connect/ansible-collection/) for credential management in playbooks.

- [x] Install collection: `ansible-galaxy collection install -r ansible/requirements.yml` (PR #158, `community.general >=8.1.0` + `onepassword.connect`)
- [x] Configure collection vars — `community.general.onepassword` lookup against `homelab-k3s-cluster` item in Homelab vault; lazy evaluation from `group_vars/k3s_cluster.yml`
- [x] Refactor group_vars to use `community.general.onepassword` lookups for `k3s_cluster_token` and `postgres_password` — replaced `vault_*` fallback pattern (PR #158)
- [x] Document collection usage patterns — `ansible/README.md` rewritten with full setup guide (PR #158)
- [x] Fix all ansible-lint violations (risky-shell-pipe, command-instead-of-module, no-relative-paths, no-changed-when) across all playbooks — 5/5 stars production profile (PR #158)

### 4.5 — Synology Terraform Provider (DEFERRED)

[synology-community/synology](https://registry.terraform.io/providers/synology-community/synology/latest) — community provider for NAS automation. Currently v0.6.9 (pre-1.0), **lacks shared folder and NFS permission resources**. The generic `synology_api` resource can call raw DSM endpoints but is fragile.

- [ ] Revisit when provider reaches v1.0 or adds `shared_folder`/`nfs_permission` resources
- [ ] Alternative: use Ansible `uri` module to call DSM API for NFS share provisioning

### 4.2 — K3s cluster upgrade strategy

- [x] Document current K3s version — upgraded from `v1.28.3+k3s1` to `v1.32.12+k3s1` (4 sequential hops)
- [x] Create Ansible playbook for rolling upgrades (`ansible/playbooks/k3s-upgrade.yml`, serial: 1, drain/upgrade/uncordon)
- [x] Test upgrade path in place — successfully upgraded live cluster with zero downtime

### 4.3 — CI/CD with GitHub Actions

- [x] Flux manifest validation (`scripts/k8s/validate.sh`)
- [x] Terraform plan on PR
- [x] Ansible lint
- [x] Secret scanning
- [ ] Integrate 1Password GitHub Action (`1password/load-secrets-action`) for CI secret injection — official, avoids storing secrets as GitHub Actions secrets directly

### 4.7 — Monitoring Improvements

Fix broken dashboards, expand coverage for new apps, and reduce alert noise.

#### Broken dashboards (immediate)

- [x] Fix Proxmox VE Cluster dashboard (working)
- [x] Fix CI/CD Pipeline dashboard (working — runner status panel empty by design, no self-hosted runners active)
- [x] Fix Homelab Applications dashboard (working)
- [x] Fix Kubernetes dashboards (Compute Resources, Networking, Scheduler — all working)

#### Expanded coverage

- [x] Add dashboard for n8n (PR #155 — n8n System Health Overview with process metrics, workflow counters)
- [x] Add dashboard for GitLab CE (PR #157 — 13-panel overview: Puma, Sidekiq, HTTP, Ruby runtime)
- [x] Add PVC Storage panels to Applications dashboard (PR #157 — usage timeseries + detail table)
- [x] Add dashboards for Windmill, TeamCity, JupyterLab (PRs #188-189 — K8s-level dashboards using kube-state-metrics + cadvisor; apps-grafana-dashboards ConfigMap group)
- [ ] Add Loki log aggregation rules for new app namespaces
- [x] Add Nexus metrics scraping (Nexus exposes Prometheus metrics at `/service/metrics`) — ServiceMonitor basicAuth secret fixed PR #147

#### Alert noise reduction

- [x] Audit current Alertmanager firing alerts — 3 active (Watchdog → null, InfoInhibitor → null, CPUThrottlingHigh wikijs → null via inhibition). Zero Slack notifications. PR #153.
- [x] Add Alertmanager `inhibit_rules` for InfoInhibitor — suppresses severity=info alerts per namespace when InfoInhibitor is firing (PR #153)
- [x] Raise Wiki.js CPU limit 1000m → 2000m — resolves CPUThrottlingHigh alert (PR #153)
- [ ] Consider AI-assisted alert triage (pre-filter before Slack notification) — see `docs/user-updates/grafana-fixes.md` for notes

### 4.6 — Parallel Developer/Agent Coordination (Local Runtime)

Enable safe parallel changes when two or more developers/agents are working simultaneously on overlapping services.

- [x] Add branch token/service lock-domain map (`configs/coordination/service-map.csv`)
- [x] Add service dependency map for unstable scope expansion (`configs/coordination/service-deps.csv`)
- [x] Add branch task plan init + validation scripts (`scripts/coord/task-plan-init.sh`, `scripts/coord/task-plan-validate.sh`)
- [x] Add runtime lock lifecycle scripts (`scripts/coord/lock-acquire.sh`, `scripts/coord/lock-release.sh`, `scripts/coord/lock-status.sh`)
- [x] Add command guard wrapper enforcing plan+lock checks per invocation (`scripts/coord/guard.sh`)
- [x] Add operator guide and command template integration (`docs/guides/concurrent-agent-coordination-workflow.md`, `.claude/commands/start-task.md`)
- [x] Define GPU passthrough overlap handling for AI/ML work by locking `comfyui` + `proxmox-infra` and following `docs/guides/comfyui-rtx3060-passthrough.md`

---

## Decision Log

Decisions to make during implementation (to be filled in as we go):

| # | Decision | Options | Chosen | Rationale |
|---|----------|---------|--------|-----------|
| 1 | Flux bootstrap target repo | This repo vs separate | This repo (`homelab-iac`) | Single repo simplifies GitOps, Flux manages everything |
| 2 | LoadBalancer IP range | 10.0.0.200-250 vs other | 10.0.0.200-250 | 51 IPs from end of LAN subnet, avoids DHCP range |
| 3 | TLS strategy | Let's Encrypt vs self-signed vs Tailscale | Self-signed CA (LAN) + Tailscale (remote) | No port forwarding (security), LAN devices need access without Tailscale |
| 4 | Keycloak DB | External PG VM vs in-cluster | External PG VM (10.0.0.45) | Reuses existing infra, single backup strategy, plenty of capacity |
| 5 | 1Password in-cluster | Deploy Connect in K8s vs Tailscale | Tailscale (existing) | Connect server already running, no added complexity |
| 6 | NFS provisioner | nfs-subdir vs democratic-csi | nfs-subdir | Simpler, proven, no CSI complexity needed for Synology NFS |
| 7 | Phase 3 app list | Various | 7 apps (Stash deferred) | Homepage, Plex, qBittorrent, Jackett, code-server, n8n, Nexus |
| 8 | n8n database | SQLite vs external PG | External PG (10.0.0.45) | Reuses existing VM, better for production workflows |
| 9 | Nexus database | External PG vs embedded H2 | Embedded H2 | Homelab scale, avoids unnecessary PG complexity |
| 10 | OAuth2 Proxy scope | All apps vs selective | All except Plex | Plex has its own auth system |
| 11 | Jackett deployment | Helm chart vs raw manifests | Raw manifests + FlareSolverr sidecar | No official Helm chart, sidecar simplifies networking |

---

## Dependencies

```
Phase 0 (Cleanup)
  └─ Phase 1.1 (Remote state)
      └─ Phase 1.2 (FluxCD bootstrap)
          ├─ Phase 1.3 (ingress-nginx) ─┐
          ├─ Phase 1.4 (MetalLB)       ─┤─ These can be parallel
          └─ Phase 1.7 (NFS storage)   ─┘
              ├─ Phase 1.5 (cert-manager) ← needs ingress
              └─ Phase 1.6 (monitoring) ← needs NFS
                  └─ Phase 2 (Identity)
                      └─ Phase 3 (Application Stack)
                          └─ Phase 5 (Future Apps) ← needs Phase 3 platform + Phase 4 VIP cutover

Phase 0 (Cleanup) and Phase 4 (Day-2) can run in parallel with Phases 2-3
Phase 5.3 (GitLab) and 5.4 (Security) depend on Nexus (3.7) being operational
```
