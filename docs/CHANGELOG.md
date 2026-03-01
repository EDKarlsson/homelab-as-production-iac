# Changelog

## 2026-02-26 — Blog Series: Homelab as Production

**Summary:** Session 44. Two workstreams: (1) repository housekeeping — deleted 25 stale merged branches, removed stale worktree, cleaned up remote-tracking refs; (2) created the complete first draft of the Substack blog series "Homelab as Production: AI-Assisted Infrastructure from Zero to GitOps" across 17 posts (~50,000 words). All posts drafted using parallel subagents, edited for tone (em-dash removal, contractions, humanized prose), and published to a new private repo `homelab-as-production`. Added draw.io MCP to project config. `docs/blog/` removed from this repo; blog content now lives exclusively in `homelab-as-production`.

### PRs merged this session

| PR | Summary |
|----|---------|
| #186 | docs(blog): Substack series — Homelab as Production (first draft, 18 files, ~50k words) |

### Blog series created

17 posts covering the full build arc, organized into 3 acts:

**Act I: Setup and Why**
- Post 00: Preface — tool evolution from Cline+TaskMaster to Claude Code; the 5-levels AI coding framework (Nate Jones); why removing abstraction layers was the key insight
- Post 01: The Production Homelab Thesis — multi-AI workflow (Claude Code + Codex + Claude Code Action + Copilot/Gemini review), tech stack overview

**Act II: Building It (Posts 02-13)**
- Post 02: Terraform + Proxmox (bpg/proxmox provider, cloud-init, PG HA, SSH username bug)
- Post 03: FluxCD GitOps (repo structure, reconciliation chain, two-doc YAML bug)
- Post 04: The Platform Layer (MetalLB, ingress-nginx, cert-manager, NFS, dual ingress)
- Post 05: Observability First (kube-prometheus-stack, Loki, InfoInhibitor pattern)
- Post 06: SSO with Keycloak + OAuth2 Proxy (OIDC, Grafana native SSO migration)
- Post 07: Secrets with 1Password + ESO (Connect HA, ClusterSecretStore, custom fields gotcha)
- Post 08: The App Deployment Pattern (7-manifest set, Flux atomicity)
- Post 09: Nexus Supply Chain (13 proxy repos, K3s /v2 path bug)
- Post 10: Day-2 Operations (PG HA failover, VIP guard backup, K3s 4-hop upgrade)
- Post 11: CI/CD Validation (GitHub Actions, Claude Code Review Action, GitLab debugging chain)
- Post 12: GitLab on Kubernetes (homelab CA TLS, PR #178 review exchange, glrt- token)
- Post 13: OIDC Debugging Arc (3-session DT OIDC story: JVM SSLContext, Jetty config.json, CORS)

**Act III: Reflection (Posts 14-16)**
- Post 14: Retrospective (6 things Claude got right, 5 it got wrong, PR review loop)
- Post 15: Team Adoption (5-levels framework, prompting patterns, 3-phase model)
- Post 15b: Executive Summary (corporate one-pager)
- Post 16: Lessons + Future Work (10 lessons, open task inventory, agent control plane preview)

### Key decisions

- **Single source of truth**: `docs/blog/` removed from this repo. Blog content lives at `https://github.com/homelab-admin/homelab-as-production`. Pointer added to `docs/README.md`.
- **draw.io MCP**: Added `@drawio/mcp` to `.mcp.json` for diagram export. Self-hosted draw.io `/export` endpoint requires headless Chrome (not included in base Docker image). MCP is the correct approach.
- **Series 2 planned**: The `agent-control-plane` companion project (multi-agent orchestration hub for Claude, Codex, Gemini, Copilot) is the subject of the next blog series. 13-post arc planned.
- **5-levels framework**: Nate Jones' framework mapped to this project's journey: L0-1 (Cline/TaskMaster) → L2 (guided walkthroughs) → L3 (PR review). L4 (spec-first) is the next goal.

### Files changed

| File | Change |
|------|--------|
| `docs/README.md` | Added "Blog Series" section pointing to homelab-as-production |
| `docs/blog/` (24 files) | Removed — moved to homelab-as-production repo |
| `.mcp.json` (local only, gitignored) | Added `@drawio/mcp` server |
| `memory/MEMORY.md` | Added MCP server inventory table, draw.io MCP notes, future in-cluster MCP goal |

---

## 2026-02-25 — Dependency-Track OIDC SSO End-to-End Fix

**Summary:** Session 43. Completed the Dependency-Track OIDC SSO investigation started in Session 42. Root cause: the bundled DT image has no `entrypoint.sh`, so `OIDC_CLIENT_ID`/`OIDC_ISSUER` env vars have no effect — `config.json` is baked empty into the JAR and extracted by Jetty at runtime to a dynamically named path under `/tmp/`. Fixed via a `postStart` lifecycle hook that polls for Jetty extraction then `sed -i` patches the file in place. Additional issues resolved: CORS on PKCE token exchange (Keycloak `Web Origins` was empty — separate from redirect URIs); "no permissions" on first login (expected — `ALPINE_OIDC_USER_PROVISIONING` creates accounts but assigns no team). Documented OIDC teams provisioning config for future use.

### PRs merged this session

| PR | Summary |
|----|---------|
| #182 | fix(dependency-track): add frontend OIDC config + remove oauth2-proxy gate |
| #183 | fix(dependency-track): patch frontend config.json via postStart lifecycle hook |
| #184 | chore(dependency-track): document OIDC teams provisioning config for future use |

### Key technical decisions

- **Bundled DT image — no entrypoint.sh**: The `dependencytrack/bundled` image runs `java -jar dependency-track-bundled.jar` directly. Unlike the standalone frontend image (`dependencytrack/frontend`), there is no shell entrypoint to inject env vars into `config.json`. The file is baked empty at image build time and extracted by Jetty to `/tmp/jetty-*-8080-dependency-track-bundled_jar-_-any-*/webapp/` at startup. Fix: `lifecycle.postStart` hook using `find /tmp -maxdepth 5 -path '*/webapp/static/config.json'` with a 120s polling loop + `sed -i`.
- **CORS on PKCE token exchange**: Keycloak `Web Origins` (controls `Access-Control-Allow-Origin`) is completely separate from `Redirect URIs`. Even with correct redirect URIs configured, an empty `Web Origins` causes CORS errors on the XHR `/token` exchange. Fix: add DT origin(s) to Web Origins in Keycloak client (or use `+` to inherit from redirect URIs).
- **First-login "no permissions"**: `ALPINE_OIDC_USER_PROVISIONING=true` auto-creates the DT user account but assigns no permissions. Admin must manually assign team membership (Administration → Access Management → Teams) or enable `ALPINE_OIDC_TEAMS_PROVISIONING` (requires Keycloak groups claim mapper + DT team OIDC mapping).
- **oauth2-proxy removal**: The nginx ingress previously gated DT behind oauth2-proxy. Removed to allow DT native OIDC to handle auth (avoids double-login); Tailscale ingress was already direct.
- **OIDC_FLOW / OIDC_SCOPE defaults**: Confirmed via live `config.json` inspection that defaults are already `"code"` and `"openid email profile"` — no need to set explicitly.

### Files changed

| File | Change |
|------|--------|
| `kubernetes/apps/dependency-track/deployment.yaml` | Removed `OIDC_CLIENT_ID`/`OIDC_ISSUER` env vars (ineffective in bundled image); updated OIDC comment block; added `postStart` lifecycle hook to patch `config.json`; added commented-out `ALPINE_OIDC_TEAMS_PROVISIONING` for future use |
| `kubernetes/apps/dependency-track/ingress.yaml` | Removed oauth2-proxy annotations (`auth-url`, `auth-signin`, `auth-response-headers`) |

---

## 2026-02-26 — GitLab CI Hardening, DT Native OIDC SSO, Homelab Shell Runner

**Summary:** Session 42. Three areas of work: (1) GitLab CI pipeline hardened through a series of bug-fix PRs resolving real failures — gcompat for Alpine/musl, git missing in publish-nexus, Tailscale DNS not resolvable from job pods, sbom job blocking pipeline when no runner registered. (2) Dependency-Track OIDC SSO wired up — public Keycloak OIDC client, homelab CA imported into JVM truststore via init container (ALPINE_HTTPS_TRUST_ALL_CERTIFICATES was insufficient, JVM OidcConfigurationResolver uses its own SSLContext), oauth2-proxy nginx proxy-buffer-size raised for large Keycloak JWTs. (3) Homelab shell runner deployed to k3s_servers[0] via Ansible playbook — enables the `sbom` and `homelab-smoke` manual CI jobs.

### PRs merged this session

| PR | Summary |
|----|---------|
| #170 | fix(ci): add gcompat to Alpine Terraform image (1Password provider uses CGO/glibc) |
| #171 | feat(dependency-track): enable native OIDC SSO via Keycloak |
| #172 | fix(oauth2-proxy): raise nginx proxy-buffer-size to 128k for large Keycloak JWTs |
| #173 | fix(dependency-track): ALPINE_HTTPS_TRUST_ALL_CERTIFICATES=true (insufficient — reverted in #174) |
| #174 | fix(dependency-track): import homelab CA into JVM truststore via keytool init container |
| #175 | fix(ci): install git in publish-nexus job (build-artifacts.sh calls git rev-parse) |
| #176 | fix(ci): override NEXUS_URL with internal K8s service URL (Tailscale DNS not resolvable from job pods) |
| #177 | fix(ci): make sbom job manual (no homelab shell runner registered yet) |
| #178 | feat(ansible): homelab GitLab shell runner playbook (k3s_servers[0], kubectl + homelab CA) |
| #179 | fix(ansible): address PR #178 review comments (checksums, ubuntu codename, CA handler→task, idempotency guard) |

### Key technical decisions

- **DT JVM truststore**: `ALPINE_HTTPS_TRUST_ALL_CERTIFICATES` only covers Alpine's `HttpUtil` client; the OIDC resolver uses `java.net.HttpURLConnection` (JVM default SSLContext). Fix: init container with `keytool -import` + `JAVA_TOOL_OPTIONS=-Djavax.net.ssl.trustStore=...`
- **GitLab CI job pod DNS**: K8s executor pods cannot resolve Tailscale MagicDNS hostnames — use internal K8s service URLs (`.svc.cluster.local`) for anything that must be reached from job pods
- **glrt- runner token registration**: GitLab 16+ moved `--tag-list`, `--run-untagged` etc. to the server side (set when creating the token); they cannot be passed to `gitlab-runner register`
- **Ansible handlers on failure**: Handlers are skipped if a play aborts — for critical setup (CA bundle update), use inline task with `when: prev_task.changed` + `# noqa: no-handler`
- **oauth2-proxy large JWTs**: Keycloak tokens with realm-management roles exceed nginx default proxy buffer (4k/8k); `proxy-buffer-size: "128k"` on the oauth2-proxy ingress resolves 502 Bad Gateway

### Files changed

| File | Change |
|------|--------|
| `.gitlab-ci.yml` | gcompat in Terraform job; git in publish-nexus; internal K8s URL for Nexus; sbom job made manual; sbom yq before_script removed; DT_URL override to nip.io |
| `kubernetes/apps/dependency-track/deployment.yaml` | OIDC env vars; init container for JVM truststore; JAVA_TOOL_OPTIONS |
| `kubernetes/apps/dependency-track/homelab-ca-configmap.yaml` | New: homelab CA ConfigMap in dependency-track namespace |
| `kubernetes/apps/dependency-track/kustomization.yaml` | Added homelab-ca-configmap.yaml |
| `kubernetes/platform/controllers/oauth2-proxy.yaml` | proxy-buffer-size: "128k" annotation |
| `ansible/playbooks/gitlab-runner-shell.yml` | New: shell runner install + registration playbook |

---

## 2026-02-25 — CycloneDX SBOM CI Integration

**Summary:** Phase 5.4 CI integration complete. Added `scripts/ci/generate-sbom.sh` — extracts all container image references from Kubernetes manifests via `yq`, parses each into a `pkg:oci` PURL using Python3, assembles a CycloneDX 1.4 JSON document, and uploads to Dependency-Track via `PUT /api/v1/bom`. Added `sbom` job to `.gitlab-ci.yml` (homelab runner, publish stage, `allow_failure: true`) and fixed the GitLab CI ansible job to match the GitHub Actions collection list (`community.postgresql`, `pg-create-db.yml` syntax check).

### PRs merged this session

| PR | Summary |
|----|---------|
| #162 | feat(security): CycloneDX SBOM generation and Dependency-Track upload |

### SBOM generation script (PR #162)

- **Extraction**: `find kubernetes clusters | yq` extracts `containers[].image` and `initContainers[].image` from all deployment manifests; uses stdin redirect (`< file`) to bypass yq snap confinement restrictions on `/tmp/` paths
- **PURL parsing**: Python3 inline script handles registry detection (explicit `registry.io/` prefix vs implicit `docker.io`), org/name splitting, and `urllib.parse.quote` percent-encoding — more robust than bash string manipulation
- **CycloneDX 1.4**: Assembled via `jq -n`; 27 unique container images found across all deployed apps and platform controllers
- **API key security**: Key written to a `curl --config` temp file rather than passed via `-H` argv — keeps the token out of process listings (`/proc/<pid>/cmdline`, `ps aux`)
- **Temp file hygiene**: `trap cleanup EXIT` covers all mktemp files with `${VAR:+"${VAR}"}` idiom (safe before assignment)
- **yq install in CI**: Downloaded to `$CI_PROJECT_DIR/bin/` (no sudo), SHA256 verified against upstream checksums file before use

### Files changed

| File | Change |
|------|--------|
| `scripts/ci/generate-sbom.sh` | New: CycloneDX SBOM generation + DT upload |
| `.gitlab-ci.yml` | New `sbom` job; fix ansible collection list + pg-create-db syntax check |

---

## 2026-02-25 — OWASP Dependency-Track Deployment

**Summary:** Deployed OWASP Dependency-Track (Phase 5.4) as a full GitOps-managed K8s application — bundled image (API server + frontend), external PostgreSQL on HA VIP, dual ingress (nginx LAN + Tailscale), OAuth2 Proxy SSO, 10Gi NFS PVC for vulnerability data. Also added a reusable `pg-create-db.yml` Ansible playbook for PostgreSQL database bootstrap, extended `requirements.yml` with `community.postgresql`, and fixed CI to include that collection in the hardcoded install list. Two ansible-lint fixes: `become: true` required at task level alongside `become_user`.

### PRs merged this session

| PR | Summary |
|----|---------|
| #160 | feat(security): deploy OWASP Dependency-Track 4.13.6; pg-create-db.yml playbook; CI fixes |

### Dependency-Track deployment (PR #160)

- **Image**: `dependencytrack/bundled:4.13.6` — bundles API server (Java/Quarkus) and frontend; pulls through Nexus Docker Hub proxy automatically
- **Node placement**: pinned to `homelab-agent-node-05` (60GB RAM) via `nodeSelector`; DT's NVD vulnerability download and analysis needs sustained memory
- **JVM heap**: `ALPINE_MEMORY_MAXIMUM: 6g`; container limit 8Gi (6g heap + ~2Gi JVM overhead)
- **External PostgreSQL**: `ALPINE_DATABASE_MODE=external` + JDBC URL via HA VIP; password injected via ExternalSecret from 1Password item `dependency-track`
- **startupProbe**: 40×15s = 10-minute window for first-boot DB migration (DT runs Liquibase migrations on startup)
- **Ingress**: nginx LAN with OAuth2 Proxy SSO + `proxy-body-size: 32m` for SBOM uploads; Tailscale for remote access
- **Storage**: 10Gi NFS PVC (`nfs-kubernetes` StorageClass) for vulnerability database and SBOM data

### pg-create-db.yml playbook (PR #160)

- New reusable playbook at `ansible/playbooks/pg-create-db.yml` for bootstrapping PostgreSQL databases on the HA cluster
- Uses `community.postgresql` modules: `postgresql_user`, `postgresql_db`, `postgresql_privs`, `postgresql_pg_hba`
- Only runs user/db/grants on `pg_nodes[0]` (primary); `pg_hba` added on ALL nodes (replication doesn't copy `pg_hba.conf`)
- Usage: `-e db_name=X -e db_user=X -e db_password=X`

### CI fixes (PR #160)

- Added `community.postgresql` to hardcoded `ansible-galaxy collection install` line — CI does not read `requirements.yml`
- Added `pg-create-db.yml` to syntax-check step in CI workflow
- Fixed `partial-become` lint violation: tasks with `become_user` must also declare `become: true` at the task level

### Files changed

| File | Change |
|------|--------|
| `kubernetes/apps/dependency-track/deployment.yaml` | New: bundled DT deployment, node pin, JVM heap, external PG |
| `kubernetes/apps/dependency-track/external-secret.yaml` | New: db-password from 1Password `dependency-track` item |
| `kubernetes/apps/dependency-track/ingress.yaml` | New: nginx ingress with OAuth2 Proxy SSO, 32m body size |
| `kubernetes/apps/dependency-track/tailscale-ingress.yaml` | New: Tailscale ingress |
| `kubernetes/apps/dependency-track/pvc.yaml` | New: 10Gi NFS PVC |
| `kubernetes/apps/dependency-track/service.yaml` | New: ClusterIP on port 8080 |
| `kubernetes/apps/dependency-track/namespace.yaml` | New: `dependency-track` namespace |
| `kubernetes/apps/dependency-track/kustomization.yaml` | New: resource list |
| `kubernetes/apps/kustomization.yaml` | Added `./dependency-track` |
| `ansible/playbooks/pg-create-db.yml` | New: reusable PostgreSQL database bootstrap playbook |
| `ansible/requirements.yml` | Added `community.postgresql` collection |
| `.github/workflows/ci-testing.yml` | Added `community.postgresql`; pg-create-db syntax check |

---

## 2026-02-24 — Alertmanager inhibit_rules + Wiki.js CPU Limit

**Summary:** Two targeted fixes for alert noise reduction (Phase 4.7). Added standard `InfoInhibitor` `inhibit_rules` to Alertmanager config so severity=info alerts are suppressed per-namespace when InfoInhibitor is firing. Without this, any future severity=info receiver route would bypass info-alert suppression entirely. Raised Wiki.js CPU limit from 1000m to 2000m to stop CPUThrottlingHigh alert — Wiki.js is a Node.js app with burst startup and background Git sync behavior that is artificially constrained by a 1-core ceiling (requests remain at 100m for scheduler placement). Result: 3 active cluster alerts (Watchdog, InfoInhibitor, CPUThrottlingHigh wikijs) all routed to null. Zero Slack notifications.

### PRs merged this session

| PR | Summary |
|----|---------|
| #153 | Alertmanager inhibit_rules for InfoInhibitor; Wiki.js CPU limit 1000m → 2000m |

### Alertmanager inhibit_rules (PR #153)

- **Problem**: kube-prometheus-stack ships with an `InfoInhibitor` alert that fires whenever any `severity=info` alert is active. Its purpose is to be the source target in an `inhibit_rules` entry — suppressing all info-severity alerts by namespace. Without `inhibit_rules`, the InfoInhibitor fires but does nothing, and any future severity=info receiver route would propagate info alerts to Slack.
- **Fix**: Added standard `inhibit_rules` block to Alertmanager config in kube-prometheus-stack HelmRelease:
  ```yaml
  inhibit_rules:
    - source_matchers:
        - 'alertname = "InfoInhibitor"'
      target_matchers:
        - 'severity = "info"'
      equal:
        - namespace
  ```
- **Result**: CPUThrottlingHigh (info severity) routed to null via InfoInhibitor inhibition. InfoInhibitor itself routes to null receiver. Zero noise.

### Wiki.js CPU limit (PR #153)

- **Problem**: Wiki.js `CPUThrottlingHigh` alert was firing at 67-76% throttling. Root cause: CPU limit was 1000m (1 vCPU). Wiki.js is Node.js and bursts during startup and background Git sync jobs. The 1000m ceiling was artificially constraining legitimate burst throughput.
- **Fix**: Raised CPU limit from 1000m to 2000m in `kubernetes/apps/wikijs/deployment.yaml`. Request remains 100m (scheduler placement unaffected).
- **Decision**: Request/limit gap of 20x is intentional — Wiki.js runs mostly idle but needs burst headroom for Git sync. This pattern is appropriate for bursty apps on a homelab cluster with spare CPU capacity.

### Files changed

| File | Change |
|------|--------|
| `kubernetes/apps/wikijs/deployment.yaml` | CPU limit: 1000m → 2000m |
| `kubernetes/platform/monitoring/controllers/kube-prometheus-stack/release.yaml` | Added `inhibit_rules` for InfoInhibitor → severity=info suppression |

---

## 2026-02-25 — Grafana Native SSO, Nexus Consumers, AFFiNE Deployment

**Summary:** Three workstreams. First: migrated Grafana from oauth2-proxy annotation-based SSO to native `auth.generic_oauth` in kube-prometheus-stack values — cleaner, no proxy hop, auto-login. Second: completed Nexus consumer integration for TeamCity (build agent env vars for npm/pypi/cargo/go proxies, Nexus ServiceMonitor basicAuth fix, Cargo proxy via ConfigMap + subPath). Third: deployed AFFiNE collaborative knowledge base with four sequential bug fixes (WebSocket annotation → GHCR image tag → K3s registry mirror path → pg_hba.conf).

### PRs merged this session

| PR | Summary |
|----|---------|
| #146 | Grafana native Keycloak SSO via `auth.generic_oauth` (kube-prometheus-stack values) |
| #147 | TeamCity Nexus proxy env vars; Nexus ServiceMonitor basicAuth secret fix |
| #148 | TeamCity Cargo proxy via ConfigMap + subPath mount |
| #149 | AFFiNE initial deployment (Deployment, Service, PVC, Redis, ExternalSecret, ingress) |
| #150 | AFFiNE WebSocket headers fix (proxy-set-headers ConfigMap, replaces blocked configuration-snippet) |
| #151 | AFFiNE image tag fix (v0.26.2 → 0.26.2) + K3s registry mirror /v2 path fix |

### Part 1: Grafana native Keycloak SSO (PR #146)

- **Migrated from oauth2-proxy to `auth.generic_oauth`** — Grafana now handles OIDC directly via kube-prometheus-stack `grafana.grafana.ini` values; no nginx `auth-url`/`auth-signin` annotations needed
- **Auto-login** — `auto_login = true` + `auto_assign_org_role = Admin`; landing on Grafana redirects straight to Keycloak
- **Keycloak client** — `grafana-oidc` client in homelab realm with `profile`+`email` scopes; valid redirect URIs for both nip.io and ts.net hostnames
- **Decision** — kept `oauth2-proxy` deployment in place (still protects 14 other apps); only Grafana's annotations were removed

### Part 2: Nexus consumer integration (PRs #147–#148)

- **TeamCity build agent env vars** — `NEXUS_NPM_URL`, `NEXUS_PYPI_URL`, `NEXUS_GO_URL`, `NEXUS_CARGO_URL` injected via Deployment env; agents can now use all Nexus proxy repos in CI builds
- **Nexus ServiceMonitor basicAuth** — `basicAuth.password` secret key was wrong (`password` vs `nexus-admin-password`); ExternalSecret field name corrected; Prometheus can now scrape Nexus metrics
- **TeamCity Cargo proxy** — `CARGO_HOME/config.toml` injected via ConfigMap + subPath mount into agent container; Rust/Cargo builds route through Nexus crates.io proxy
- **K3s registry mirror Ansible** — `k3s-registry-mirrors.yml` playbook run on all 8 nodes to deploy the corrected `registries.yaml`

### Part 3: AFFiNE deployment (PRs #149–#151)

- **Architecture** — PostgreSQL for document content (Prisma/CRDT), NFS PVC (`/root/.affine/storage`) for binary blobs, in-cluster Redis (BullMQ job queues — ephemeral, appendonly for session persistence)
- **Migration init container** — `node ./scripts/self-host-predeploy.js` runs Prisma migrations on every pod start; idempotent, required for schema upgrades
- **WebSocket headers** — `nginx.ingress.kubernetes.io/proxy-set-headers: "affine/websocket-headers"` ConfigMap injects `Upgrade` + `Connection` headers without `configuration-snippet` (blocked by admission webhook in ingress-nginx 1.9+)
- **GHCR image tag** — GitHub release name `v0.26.2` ≠ Docker image tag `0.26.2` (no `v` prefix on GHCR); 404 was from tag mismatch
- **K3s registry mirror `/v2` path** — containerd generates `override_path = true` for path-based endpoints and strips `/v2/` prefix; Nexus returns `400 Not a docker request` without it; fixed by appending `/v2` to all three endpoint URLs in `k3s-registries.yaml.j2`
- **pg_hba.conf** — NOT replicated by PostgreSQL streaming replication; added `host affine affine 10.0.0.0/24 scram-sha-256` manually on both primary (10.0.0.45) and standby (10.0.0.46); `SELECT pg_reload_conf()` on each

### Notable decisions

- **AFFiNE "Cloud" = self-hosted server** — the "store in Affine Cloud" prompt in the UI refers to YOUR server (`AFFINE_SERVER_HOST`), not affine.pro; local storage mode stores blobs in-browser only
- **Redis is ephemeral** — Redis holds BullMQ job queues (background tasks); `appendonly yes` + `noeviction` policy chosen for session persistence without memory risk
- **Nexus as pull-through cache confirmed** — anonymous pulls work via Nexus GHCR proxy at `/repository/docker-ghcr/v2/`; bearer token negotiation handled by Nexus for authenticated upstreams

### Files changed (key)

| File | Change |
|------|--------|
| `kubernetes/platform/monitoring/controllers/kube-prometheus-stack/values.yaml` | Added `grafana.grafana.ini.auth.generic_oauth` block; removed oauth2-proxy annotations |
| `kubernetes/apps/teamcity/deployment.yaml` | Added Nexus proxy env vars for all 5 proxy types |
| `kubernetes/apps/teamcity/cargo-config-configmap.yaml` | New: CARGO_HOME/config.toml with Nexus crates.io proxy URL |
| `kubernetes/apps/nexus/servicemonitor.yaml` | Fixed basicAuth password secret key reference |
| `kubernetes/apps/affine/` | New: namespace, PVC, Redis, Deployment, Service, Ingress (×2), ExternalSecret, websocket-headers ConfigMap |
| `ansible/templates/k3s-registries.yaml.j2` | Appended `/v2` to all three docker mirror endpoint URLs |

---

## 2026-02-24 — SSO via Tailscale + GitLab Integration

**Summary:** Two major workstreams. First: rearchitected OAuth2 Proxy SSO so the Keycloak login page uses the Tailscale URL (`keycloak.homelab.ts.net`) with a valid Let's Encrypt cert instead of the self-signed nip.io cert. Added Portainer to SSO coverage, fixed `ssl-insecure-skip-verify` by mounting the homelab CA cert. Second: integrated GitLab as the primary development platform — Keycloak OIDC SSO login, GitHub → GitLab push mirror via self-hosted runner, and a `.gitlab-ci.yml` pipeline matching the GitHub Actions validation suite.

### PRs merged this session

| PR | Summary |
|----|---------|
| #141 | 15 Mermaid diagrams across 9 docs (architecture, reference, workflow) |
| #142 | OAuth2 SSO: Portainer coverage, CoreDNS override, Keycloak Tailscale hostname, homelab CA cert in OAuth2 Proxy |
| #143 | GitLab: Keycloak OIDC SSO, GitHub mirror workflow, `.gitlab-ci.yml` |
| #144 | GitLab: mount homelab CA cert for OIDC TLS trust |
| #145 | GitLab: initContainer for CA cert install (EROFS fix), homelab runner for Nexus publish |

### Part 1: OAuth2 Proxy SSO improvements (PR #142)

- **Portainer SSO** — added `auth-url`/`auth-signin` nginx annotations; 14/21 nginx ingresses now protected
- **Keycloak Tailscale hostname** — `KC_HOSTNAME_URL=https://keycloak.homelab.ts.net`; OIDC tokens issued with Tailscale URL as issuer; login page has valid LE cert
- **CoreDNS custom override** — `coredns-custom` ConfigMap in `kube-system` using `rewrite name` to resolve `keycloak.homelab.ts.net → keycloak.10.0.0.201.nip.io` for in-cluster pods
- **Homelab CA cert in OAuth2 Proxy** — removed `ssl-insecure-skip-verify`; mounted homelab CA via ConfigMap + `SSL_CERT_FILE` env var
- **1Password Connect DNS fix** — Docker containers in LXC were using Tailscale resolver (`100.100.100.100`) unreachable from bridge network; fixed with `/etc/docker/daemon.json` + `systemctl restart docker`

### Part 2: GitLab integration (PRs #143–#145)

- **Keycloak OIDC SSO** — `external-secret-keycloak-oidc.yaml` + omniauth OIDC provider in `GITLAB_OMNIBUS_CONFIG`; login with Keycloak button on GitLab
- **CA cert mounting** — initContainer copies homelab CA from ConfigMap into config PVC before Omnibus starts; subPath mounts cause EROFS when Omnibus tries to move certs
- **GitHub → GitLab mirror** — `.github/workflows/mirror-to-gitlab.yml` pushes to `gitlab.homelab.ts.net/homelab/homelab-iac` via self-hosted runner on every main push
- **GitLab CI pipeline** — `.gitlab-ci.yml` with same validation stages as GitHub Actions (terraform, ansible, kubernetes, shellcheck, Nexus publish on main)
- **Nexus publish runner** — `artifact_publish_raw` switched to self-hosted homelab runner (Nexus is Tailscale-only)
- **`.mcp.json` updates** — GitLab server added with Tailscale URL; kubernetes + flux MCPs switched to `config-homelab`

### Notable decisions

- **GitHub stays as Flux source** — GitLab is primary for new work/CI but not for IaC manifests; circular dependency risk (if cluster is down, can't push fixes to a cluster-hosted GitLab)
- **CoreDNS `rewrite name` not `hosts`** — K3s CoreDNS already uses `hosts` for NodeHosts; only one `hosts` block per server is allowed
- **initContainer pattern for trusted-certs** — ConfigMap subPath mounts are immutable; Omnibus's `add_trusted_certs` recipe renames files; initContainer copies cert into writable config PVC instead

### Files changed (key)

| File | Change |
|------|--------|
| `kubernetes/platform/controllers/oauth2-proxy.yaml` | Removed ssl-insecure-skip-verify, added SSL_CERT_FILE, issuer → Tailscale URL |
| `kubernetes/platform/controllers/keycloak.yaml` | Added KC_HOSTNAME_URL, KC_HOSTNAME_ADMIN_URL, nginx ingress host for ts.net |
| `kubernetes/platform/controllers/coredns-tailscale.yaml` | CoreDNS rewrite name override (new) |
| `kubernetes/platform/controllers/homelab-ca-configmap.yaml` | Homelab CA cert ConfigMap in oauth2-proxy ns (new) |
| `kubernetes/apps/gitlab/deployment.yaml` | OIDC config, initContainer, CA cert volume |
| `kubernetes/apps/gitlab/external-secret-keycloak-oidc.yaml` | New ExternalSecret for OIDC client creds |
| `kubernetes/apps/gitlab/homelab-ca-configmap.yaml` | Homelab CA cert in gitlab ns (new) |
| `.github/workflows/mirror-to-gitlab.yml` | New: GitHub → GitLab push mirror |
| `.github/workflows/ci-testing.yml` | Nexus publish job → self-hosted runner |
| `.gitlab-ci.yml` | New: full GitLab CI validation pipeline |
| `.mcp.json` | GitLab server added, kubeconfigs → config-homelab |

---

## 2026-02-23 — Mermaid Diagrams, Project Triage Skill

**Summary:** Two documentation sessions. First: added 15 Mermaid diagrams across 9 docs files, converting ASCII art and text-only architecture descriptions into rendered flowcharts, sequence diagrams, and topology graphs for Wiki.js. Second: created a new `/project-triage` skill and command that monitors the project plan, checks open PRs, surfaces stale tasks, and reprioritizes next actions — integrated into `/finalize` (Step 0) and `/review-updates` (tip).

### Completed

- **15 Mermaid diagrams added** to architecture, reference, and guide docs (PR #141)
- **`/project-triage` skill** at `~/.claude/skills/project-triage/SKILL.md` — global, 5-step workflow (gather → status map → report → confirm → act)
- **`/project-triage` command** at `.claude/commands/project-triage.md` — project-level entry point with focus filters
- **`/finalize` updated** — added optional Step 0 forward-look via project-triage
- **`/review-updates` updated** — added tip pointing to `/project-triage` for broader context

### Modified files

| File | Change |
|------|--------|
| `docs/architecture/flux-structure.md` | Flux reconciliation chain flowchart + 3-layer separation (WHERE/WHAT/HOW) graph |
| `docs/architecture/hardware-infrastructure.md` | Physical network topology + Proxmox cluster topology diagrams |
| `docs/architecture/pve-node-spec-config.md` | VM distribution across all 5 Proxmox nodes diagram |
| `docs/reference/1password-integration.md` | Connect HA architecture (replaces ASCII) + secrets data-flow diagram |
| `docs/reference/postgresql-ha.md` | HA cluster topology (replaces ASCII) + failover sequence diagram with timing |
| `docs/reference/tailscale-kubernetes.md` | Dual ingress architecture (nginx LAN + Tailscale remote) |
| `docs/reference/flux-gitops-patterns.md` | Dependency chain (replaces ASCII) + standard app deployment component diagram |
| `docs/guides/gitops-promotion-and-rollback.md` | PR→main→Flux promotion flow + rollback decision tree |
| `docs/guides/ci-cd-testing-workflow.md` | Improved parallel jobs pipeline diagram |
| `~/.claude/skills/project-triage/SKILL.md` | New global skill (not tracked in repo) |
| `.claude/commands/project-triage.md` | New project command |
| `.claude/commands/finalize.md` | Added optional Step 0 project-triage forward-look |
| `.claude/commands/review-updates.md` | Added tip referencing /project-triage |

### Notable decisions

- **Skill vs command split**: The `project-triage` logic lives in `~/.claude/skills/` (global, reusable across projects). The project-specific entry point is `.claude/commands/project-triage.md` (homelab paths, filter options)
- **Read-only by default**: The triage skill never modifies files without explicit user approval — a deliberate design choice to prevent accidental plan mutations
- **Mermaid augments, not replaces**: ASCII art was preserved in source where useful for CLI readers; Mermaid renders for the Wiki.js audience

---

## 2026-02-22 — ComfyUI GPU Approach: LXC Pivot, Investigation, Decision to Standalone

**Summary:** Pivoted ComfyUI GPU deployment from KVM VM + VFIO passthrough to privileged LXC with host NVIDIA driver bind-mount. Investigated and documented multiple crash vectors on gpu-workstation (ASRock X299 Taichi, kernel 6.17). After repeated host crashes during `pct exec` LXC workloads — unresolved after vendor-reset removal and BIOS P1.70 → P2.50 update — decided to remove gpu-workstation from the Proxmox cluster and operate it as a standalone Ubuntu workstation running ComfyUI natively. The LXC module is retained in code (commented out) for future reuse on more stable hardware.

### Completed

- **Cleared VFIO config**: Commented out GPU IDs from `/etc/modprobe.d/vfio.conf` so NVIDIA driver can claim RTX 3060
- **NVIDIA 580.126.18 installed**: Debian 550.x packages fail on kernel 6.17 (drm_framebuffer_funcs API change + dma_buf_attachment_is_dynamic removal). Official `.run` installer at 580.x succeeds
- **vendor-reset removed**: `dkms remove vendor-reset/0.1.1 --all` — AMD-only module with no benefit for NVIDIA, implicated in spontaneous host crashes
- **BIOS updated**: P1.70 (Dec 2017 launch BIOS) → P2.50 on ASRock X299 Taichi
- **New Terraform module `modules/comfyui-lxc/`**: `proxmox_virtual_environment_container` (privileged, nesting=true) + `null_resource` writing NVIDIA lxc.conf entries via SSH
- **LXC 530 deployed**: Created, NVIDIA devices visible inside (`/dev/nvidia0`, `/dev/nvidia1`, `/dev/nvidiactl`, `/dev/nvidia-uvm`, `/dev/nvidia-uvm-tools`)
- **`nvidia-device-nodes.service`**: Created on host — triggers lazy UVM device node creation via `nvidia-smi -L` before LXC starts
- **cgroup2 device allowlist fixed**: Replaced `c 236:*` (wrong major) with `c *:* rwm` — nvidia-uvm's major is dynamically assigned (510 on kernel 6.17 + NVIDIA 580, not 236)
- **`docs/guides/comfyui-lxc-setup.md`**: Full LXC setup runbook created (BIOS prereqs, NVIDIA .run installer, systemd service, Docker + nvidia-container-toolkit, ComfyUI docker-compose)
- **`module "comfyui_lxc"` disabled in main.tf**: Commented out with full history and `terraform state rm` instructions for cleanup

### Modified files

| File | Change |
|---|---|
| `infrastructure/main.tf` | Replaced `module "comfyui"` (VM) with `module "comfyui_lxc"` (LXC); added null provider; now commented out with history |
| `infrastructure/output.tf` | Updated output to reference `module.comfyui_lxc`; now commented out |
| `infrastructure/modules/comfyui-lxc/comfyui-lxc.tf` | New module: privileged LXC resource + null_resource NVIDIA passthrough; fixed cgroup2 allowlist |
| `infrastructure/modules/comfyui-lxc/variables.tf` | New: all LXC config vars with gpu-workstation defaults |
| `infrastructure/modules/comfyui-lxc/outputs.tf` | New: container_id, hostname, node_name, ip_address, ssh_command, gpu_passthrough |
| `infrastructure/modules/comfyui-lxc/providers.tf` | New: proxmox + null provider requirements |
| `docs/guides/comfyui-lxc-setup.md` | New: full LXC + NVIDIA + Docker + ComfyUI setup runbook |

### Notable decisions and discoveries

- **KVM VFIO conclusively abandoned**: RTX 3060/Ampere VFIO causes host kernel fault during guest NVIDIA driver init on X299/Skylake-X — hardware limitation, no BIOS/config fix exists
- **LXC approach partially working**: NVIDIA 580.126.18 installs cleanly, both GPUs visible via `nvidia-smi`, LXC devices confirmed — but `pct exec` workloads cause repeatable host crashes
- **`pct exec` crash pattern**: Crashes happen consistently during `pct exec` + apt-get inside privileged LXC — never during idle. Cause unknown (possible kernel bug with cgroup2 + process namespace on kernel 6.17 + X299). BIOS update and vendor-reset removal did not resolve
- **nvidia-uvm major number changed**: NVIDIA 580+ assigns major 510 dynamically (not 236 as in older drivers). Using `c *:* rwm` in lxc.cgroup2.devices.allow is resilient to this
- **`/dev/nvidia-modeset` absent in NVIDIA 580**: No longer created as a standalone device node — accessed via ioctl on nvidiactl
- **gpu-workstation → standalone workstation**: Persistent crash pattern + X299 platform limitations → decision to remove from cluster, reinstall Ubuntu, run ComfyUI natively

### Follow-up required

- **Manual**: Remove gpu-workstation from Proxmox cluster (`pvecm delnode gpu-workstation` from another node)
- **Manual**: Clean Terraform state: `terraform state rm 'module.comfyui_lxc.proxmox_virtual_environment_container.comfyui'` and `terraform state rm 'module.comfyui_lxc.null_resource.nvidia_lxc_passthrough[0]'`
- **Manual**: Reinstall gpu-workstation as Ubuntu 24.04, install NVIDIA 580+, run ComfyUI natively

---

## 2026-02-22 — gpu-workstation Cluster Join + GPU Passthrough Verified

**Summary:** Completed the physical onboarding of `gpu-workstation` (i7-7820X, RTX 3060 + GTX 1080 Ti, 48 GiB RAM). Node joined the `valhalla` Proxmox cluster as node 6, IOMMU/VFIO passthrough activated, and RTX 3060 bound to `vfio-pci` — ready for GPU VM deployment via Terraform.

### Completed (manual steps on gpu-workstation)

- **Hostname + hosts**: Set to `gpu-workstation`; all 6 cluster nodes added to `/etc/hosts`; default gateway corrected from `10.0.0.0` → `10.0.0.1`
- **PVE upgrade**: 9.1.1 → 9.1.5 via `apt dist-upgrade`; `grub-efi-amd64` installed to resolve EFI meta-package warning
- **IOMMU**: VT-d already enabled in BIOS (DMAR tables visible); added `intel_iommu=on iommu=pt` to `GRUB_CMDLINE_LINUX_DEFAULT`, ran `update-grub`
- **VFIO**: `/etc/modules-load.d/vfio.conf` (4 modules) + `/etc/modprobe.d/blacklist-nvidia-passthrough.conf` (nouveau/nvidia/nvidiafb) + `/etc/modprobe.d/vfio-pci.conf` (`ids=10de:2504,10de:228e`); initramfs regenerated
- **Cluster join**: `pvecm add node-02 --link0 address=10.0.0.15 --fingerprint <live-cert-sha256>`; 6-node quorum established

### Verified

| Check | Result |
|-------|--------|
| `pvecm nodes` | 6 nodes, quorate |
| `dmesg \| grep "IOMMU enabled"` | ✓ |
| `lspci -nnk -s 65:00.0` | `Kernel driver in use: vfio-pci` |
| `lspci -nnk -s 65:00.1` | `Kernel driver in use: vfio-pci` |

### Notable discoveries

- **GTX 1080 Ti also present** — `gpu-workstation` has two GPUs: GTX 1080 Ti (`17:00.0`) as host display card and RTX 3060 (`65:00.0`) for passthrough. Only RTX 3060 is bound to vfio-pci.
- **`pvecm add` TLS fingerprint** — PVE API cert CN is `node-02.lan`; bare hostname/IP fails verification. Required `--fingerprint $(openssl s_client -connect <node>:8006 ... | openssl x509 -fingerprint -sha256)` from the live endpoint (not the cert file, which served a different cert).
- **`vfio-pci` new_id vs bind** — `echo "VID DID" > /sys/bus/pci/drivers/vfio-pci/new_id` is the reliable dynamic binding path; the `bind` sysfs interface requires the device to already be unbound from its current driver first.

---

## 2026-02-22 — Add gpu-workstation to Proxmox Cluster (GPU Compute Node)

**Summary:** Onboarded a new 6th Proxmox node (`gpu-workstation`, Intel i7-7820X, RTX 3060, 48 GiB RAM) at 10.0.0.15. This is a GPU-dedicated node for AI/compute workloads — it joins the Proxmox cluster but does NOT run a K3s agent. Updated all architecture docs and memory to reflect the 6-node topology. Manual steps for cluster join (Phases 1–2) and IOMMU/VFIO passthrough setup (Phase 3) are documented in the session plan.

### Modified

- **`docs/architecture/hardware-infrastructure.md`** — Changed `Cluster: No` → `Yes (gpu-workstation)` for the Custom/DIY row.
- **`docs/architecture/pve-node-spec-config.md`** — Added `gpu-workstation` to the node list (16 cores, 48 GB, GPU compute VMs only — RTX 3060 passthrough). Added `ai-1` column to the resource allocation table (14 cores / 46 GB available, `GPU VMs` row placeholder for future AI VMs).

### Notable decisions

- **GPU-dedicated, no K3s agent** — `gpu-workstation` will host GPU passthrough VMs (ComfyUI, Ollama, etc.) but will not join the K3s cluster as a worker. GPU scheduling via K8s device plugins is deferred; VMs on this node are managed directly via Terraform/Proxmox.
- **IOMMU/VFIO passthrough required before VM deployment** — VT-d must be enabled in BIOS, `intel_iommu=on iommu=pt` added to GRUB, and VFIO modules + NVIDIA blacklists configured on the host. Steps follow the existing `docs/guides/comfyui-rtx3060-passthrough.md` pattern (Phases 1–3).
- **No Terraform provider changes needed** — The bpg/proxmox provider targets a single API endpoint (`node-02:8006`); once `gpu-workstation` joins the Proxmox cluster, resources can target it via `node_name = "gpu-workstation"` with no provider reconfiguration.

---

## 2026-02-21 — AlertManager Severity Filter, Slack+GitHub Workflow Docs, Maintenance Checks CI

**Summary:** Tightened AlertManager routing to only page on `warning` and `critical` alerts. Analysed 10 Slack+GitHub integration patterns and produced implementation plans for the top 3. Implemented Workflow 2 as a scheduled GitHub Actions pipeline that checks cert expiry, K3s version lag, and backup health weekly, creates/updates GitHub issues per finding, and posts a Slack digest.

### Added

- **`.github/workflows/maintenance-checks.yml`** — New scheduled workflow (Monday 08:00 UTC + manual dispatch). Four jobs: `cert-expiry` (cert-manager certificates expiring within 30 days), `k3s-version-check` (≥2 minor version lag vs latest stable), `backup-health` (Velero + pg-backup last successful run within 26h), `slack-digest` (Slack post of all open `maintenance`-labelled issues). Each job connects to the cluster via `tailscale/github-action@v3` with a reusable ephemeral auth key. GitHub issues are created or commented on (dedup) via `gh` CLI using `${{ github.repository }}`. Labels created: `maintenance`, `cert-manager`, `backup`, `upgrade`, `k3s`.
- **`docs/guides/slack-gh-workflows-overview.md`** — Scoring matrix for 10 Slack+GitHub integration patterns; top 3 selection with rationale and implementation order.
- **`docs/guides/slack-gh-workflow-1-alert-to-issue.md`** — AlertManager webhook → n8n dedup logic → GitHub issue with Slack link.
- **`docs/guides/slack-gh-workflow-2-scheduled-maintenance.md`** — Plan + prototype for the GitHub Actions maintenance cron (now implemented).
- **`docs/guides/slack-gh-workflow-3-capacity-planning.md`** — Sustained-pressure PrometheusRules → n8n → GitHub issue with metrics snapshot.

### Modified

- **`kubernetes/platform/monitoring/controllers/kube-prometheus-stack/release.yaml`** — AlertManager route changed from default catch-all (`receiver: slack-notifications`) to default-null with explicit whitelist routes. `Watchdog` → `null`. `severity=critical` → `slack-critical` (1h repeat). `severity=warning` → `slack-notifications` (4h repeat). Info and debug alerts are silently dropped.
- **`.github/workflows/claude-code-review.yml`** — Disabled `pull_request` auto-trigger (action was slow and didn't publish to GitHub's review section). Kept `workflow_dispatch` for manual use.

### Notable decisions

- **Default-null AlertManager routing** — Whitelist approach (allow only `warning`/`critical`) chosen over blacklist (block `info`/`debug`) for clarity. New alert rules are silently dropped until explicitly routed, which is the safer default for a homelab: no alert spam on new rules.
- **`ubuntu-latest` + Tailscale GitHub Action** — No self-hosted runner is registered. Ephemeral `ubuntu-latest` runners connect to the cluster via `tailscale/github-action@v3` with a reusable auth key (`TS_AUTH_KEY`). No tags required; ephemeral nodes auto-expire. OAuth client approach was considered but requires ACL tag setup.
- **Issue dedup via `gh issue list --search`** — cert-expiry and backup-health comment on existing open issues (idempotent); k3s-version-check comments on existing issue rather than creating a duplicate or silently skipping (so each weekly run adds updated version data).
- **26h backup threshold** — Daily backup schedule + 2h buffer for slow jobs. Extracted to `THRESHOLD_HOURS` variable for clarity.

---

## 2026-02-21 — Nexus Registry Mirrors, Staging Namespace, pg-ha Template Fix

**Summary:** Completed the Nexus containerd registry mirror rollout across all 11 cluster nodes. Activated a Flux-managed staging namespace environment with podinfo as the first live overlay. Fixed a pre-existing Terraform `templatefile()` parse error in the pg-ha cloud-init templates caused by unescaped bash array syntax.

### Added

- **kubernetes/staging/kustomization.yaml** — Activated `podinfo` as the first staging overlay. The root staging Kustomization now has `./podinfo` in its resource list, deploying into `podinfo-staging` namespace.
- **kubernetes/staging/podinfo/kustomization.yaml** — Kustomize overlay referencing production `kubernetes/apps/podinfo` base and patching namespace to `podinfo-staging`. Validates cleanly with `kubectl kustomize`.
- **clusters/homelab/staging.yaml** — Flux Kustomization entry point for the staging environment. Depends on `platform-configs`, reconciles every 10 minutes.
- **docs/guides/staging-environment.md** — Step-by-step guide for adding apps to the staging environment, including overlay template, patch types (namespace, ingress, replicas, Helm values), and troubleshooting.

### Modified

- **ansible/playbooks/k3s-registry-mirrors.yml** — Added `--disable-eviction` PDB warning to playbook header. Clarifies that this flag bypasses ALL PodDisruptionBudgets, not just Longhorn's, and is safe for homelab but requires review in HA environments.
- **infrastructure/modules/pg-ha/cloud-configs/postgresql-primary.yml.tftpl** — Escaped `${#ERRORS[@]}` → `$${#ERRORS[@]}` (2 occurrences). Terraform `templatefile()` interprets `${...}` as template interpolation; bash array length syntax must use `$$` prefix.
- **infrastructure/modules/pg-ha/cloud-configs/postgresql-standby.yml.tftpl** — Same escape fix as primary template.

### Operational

- Ran `nexus-apt-mirror.yml` against all 11 cluster nodes (8 K3s + 3 PostgreSQL). All nodes now use Nexus as their apt mirror (`http://10.0.0.202:8081`). `ubuntu.sources` renamed to `.disabled` (reversible).

### Notable decisions

- **Staging on same cluster, namespace isolation** — No new VMs or clusters needed. Each app gets a `<app>-staging` namespace; Kustomize overlays reference production bases. Flux's `staging` Kustomization manages the lifecycle.
- **`$${...}` not `{% raw %}`** — Terraform uses `$$` to escape literal `${}`, unlike Jinja2's block-level `{% raw %}`. No raw blocks exist in Terraform templates — escape per-occurrence.

---

## 2026-02-20 — Nexus APT Proxy Integration

**Summary:** Wired up Nexus as the apt package mirror for K3s VMs. Added a dedicated MetalLB LoadBalancer service for Nexus (10.0.0.202) so apt clients can reach it without OAuth2 authentication — required for cloud-init (runs before K8s networking). Updated Terraform to pass the URL to cloud-init for future VM provisions, and added an Ansible playbook to configure existing VMs in-place. PVE hosts (Debian bookworm) are deferred — require separate `apt-debian`/`apt-proxmox` Nexus proxy repos and a `pve_hosts` inventory group.

### Added

- **kubernetes/apps/nexus/service-lb.yaml** — LoadBalancer Service for Nexus with MetalLB annotation `metallb.universe.tf/loadBalancerIPs: 10.0.0.202`. Exposes port 8081 directly on LAN, bypassing ingress-nginx (which requires OAuth2). Required because apt clients cannot authenticate and cloud-init runs before Tailscale/K8s are available.
- **ansible/playbooks/nexus-apt-mirror.yml** — Configures apt sources on all K3s cluster nodes in-place (since cloud-init already ran). Writes `/etc/apt/sources.list.d/nexus-ubuntu.sources` in deb822 format pointing to `apt-ubuntu` and `apt-ubuntu-security` Nexus proxy repos. Renames `ubuntu.sources` → `ubuntu.sources.disabled` (reversible). Runs `apt update` to verify.
- **docs/guides/nexus-apt-proxy.md** — Reference guide: architecture diagram, all components, revert instructions, troubleshooting, IP allocation table, and PVE host roadmap.

### Modified

- **infrastructure/main.tf** — Added `nexus_apt_mirror_url = "http://10.0.0.202:8081"` to `module "k3s"`. Cloud-init templates already had the conditional apt block; this enables it for all future VM provisions.
- **kubernetes/apps/nexus/kustomization.yaml** — Added `service-lb.yaml` to the resources list.

### Architecture

```
K3s VM / PVE host
  └─ /etc/apt/sources.list.d/nexus-ubuntu.sources
        └─ http://10.0.0.202:8081/repository/apt-ubuntu/         (noble, noble-updates, noble-backports)
        └─ http://10.0.0.202:8081/repository/apt-ubuntu-security/ (noble-security)
              └─ Nexus proxy repos → cache on demand → upstream Ubuntu mirrors
```

### Notable decisions

- **HTTP not HTTPS** — cloud-init runs before the homelab CA cert is installed. TLS to the LAN IP would fail cert validation. Plain HTTP is acceptable on a private LAN.
- **Dedicated LoadBalancer IP, not ingress-nginx** — The ingress-nginx VIP (10.0.0.201) routes through OAuth2 Proxy. Unauthenticated apt clients would get a Keycloak login page instead of packages.
- **PVE hosts deferred** — PVE hosts run Debian bookworm, not Ubuntu. Requires adding `apt-debian` and `apt-proxmox` proxy repos to Nexus, plus a `pve_hosts` Ansible inventory group. Tracked in the guide.

---

## 2026-02-21 — Phase 4.1 PG Backup Automation Complete

**Summary:** PostgreSQL backup automation fully operational. Ansible playbook deployed to both HA nodes with VIP guard pattern — 8 databases dump every 6 hours, sync to Synology NAS. Restore procedure verified. Also resolved a cluster-wide Flux outage caused by missing Nexus proxy repos, and fixed ESO secrets for SMTP-dependent apps (GitLab, Linkwarden, n8n).

### Added

- **ansible/playbooks/pg-backup.yml** — Deploys NFS mount, per-database backup script, cron (`0 */6 * * *`), and logrotate to both PG HA nodes. VIP guard ensures only the current primary executes.
- **ansible/templates/backup-pg-dbs.sh.j2** — Bash backup script: dumps all 8 databases individually, syncs to NAS, writes `backup-status.json`, 7-day local retention, 30-day NAS retention.
- **ansible/inventory/group_vars/pg_nodes.yml** — Variables for both PG HA VMs: database list, VIP, NAS server/path/mount, retention, cron schedule.

### Fixed

- **Flux cluster-wide outage** — All 6 Kustomizations stuck False/Unknown after commit `f666323` migrated 20 HelmRepository URLs to Nexus proxy repos that didn't exist yet. Fix: ran `configure-proxy-repos.sh` to create all 20 repos, then force-annotated HelmRepositories to trigger re-fetch. Recovery: ~2 minutes.
- **ESO SMTP secret failure (GitLab, Linkwarden, n8n)** — `ExternalSecret` used `property: username` and `property: password` which match default Login item fields — ESO reported `got 0` matches. Fixed by adding custom text fields (`smtp-username`, `smtp-password`, `host`, `port`, `from`) to the `google-smtp` 1Password item and updating all three ExternalSecrets to reference them. PRs #121, #123.

### Verified

- 8/8 databases dumped successfully on first playbook run (2026-02-21 04:01 UTC)
- NAS sync to `10.0.0.161:/volume1/postgresql-backups/homelab-psql-dbs-k3s/` confirmed
- Restore test: `n8n` dump → throwaway DB → 10 tables verified → DB dropped. PASSED.
- Cron running since 2026-02-19, 11 snapshots of every DB already on disk

### Architecture

```
Both PG nodes (.45 + .46): cron every 6h → VIP guard (10.0.0.44) → skip if not primary
Primary only: pg_dump × 8 → /var/backups/postgresql/ → NFS cp → /mnt/nas-backups/
Status: /var/backups/postgresql/backup-status.json (JSON, machine-readable)
```

---

## 2026-02-19 — Nexus Proxy Repository Configuration

**Summary:** Added version-controlled Nexus proxy repository configuration — an idempotent bash script that creates/updates 13 proxy repositories via the Nexus REST API, plus an ExternalSecret for admin credentials from 1Password.

### Added

- **`scripts/nexus/configure-proxy-repos.sh`** — Idempotent script to configure 13 proxy repositories across 8 formats (apt, docker, go, helm, npm, pypi, cargo, raw). Supports `--dry-run`, single-repo filtering, and configurable blob store. GET→POST/PUT pattern for create-or-update.
- **`kubernetes/apps/nexus/external-secret.yaml`** — ExternalSecret pulling Nexus admin credentials (`username`, `password`) from 1Password item `nexus-repository` via ClusterSecretStore `onepassword-connect`.

### Changed

- **`kubernetes/apps/nexus/kustomization.yaml`** — Added `external-secret.yaml` to resources list.

### Proxy Repositories Configured

| Name | Format | Upstream |
|------|--------|----------|
| apt-ubuntu | apt | archive.ubuntu.com/ubuntu |
| apt-ubuntu-security | apt | security.ubuntu.com/ubuntu |
| docker-hub | docker | registry-1.docker.io |
| docker-ghcr | docker | ghcr.io |
| docker-quay | docker | quay.io |
| go-proxy | go | proxy.golang.org |
| helm-stable | helm | charts.helm.sh/stable |
| npm-proxy | npm | registry.npmjs.org |
| pypi-proxy | pypi | pypi.org |
| cargo-proxy | cargo | index.crates.io |
| gitlfs-github | raw | github.com |
| huggingface | raw | huggingface.co |
| terraform-registry | raw | registry.terraform.io |

### Notes

- 1Password item `nexus-repository` updated with custom text fields (`admin-username`, `admin-password`) — ESO cannot read default Login fields.
- All 13 repos verified: created on first run, updated idempotently on re-run.
- Script tested via port-forward to live Nexus 3.89.1 instance.

---

## 2026-02-20 — Concurrent Agent Coordination Workflow

**Summary:** Added a local concurrency coordination workflow to support 2+ developers/agents working in parallel on overlapping services. The workflow introduces branch-scoped task plans, branch/service instability validation, local runtime lock files, and a guard wrapper that checks locks before every command invocation.

### Added

- **`docs/guides/concurrent-agent-coordination-workflow.md`** — end-to-end workflow for branch planning, overlap deconfliction, lock lifecycle, and guarded command execution
- **`configs/coordination/service-map.csv`** — token-to-service and lock-domain mapping used for branch/service inference
- **`configs/coordination/service-deps.csv`** — dependency map used to enforce unstable-service declarations
- **`scripts/coord/common.sh`** — shared coordination helpers (plan resolution, CSV normalization, service/domain lookup, lock metadata utilities)
- **`scripts/coord/task-plan-init.sh`** — creates branch-scoped task plans
- **`scripts/coord/task-plan-validate.sh`** — validates branch name detection and unstable-service coverage
- **`scripts/coord/lock-acquire.sh`** — acquires per-service and per-domain local locks with TTL
- **`scripts/coord/lock-release.sh`** — releases owned locks for branch handoff/finalize
- **`scripts/coord/lock-status.sh`** — displays active/expired lock state
- **`scripts/coord/guard.sh`** — mandatory command preflight wrapper for lock checks and mutating-command enforcement
- **`.coord/task-plans/TEMPLATE.env`** — plan template for branch-scoped service instability declarations
- **`.coord/README.md`** and **`.coord/locks/.gitkeep`** — coordination runtime layout docs and lock directory placeholder

### Changed

- **`.claude/commands/start-task.md`** — now includes task-plan init/validate, lock acquisition, and guarded command execution steps
- **`.codex/commands/start-task.md`** — synchronized start-task workflow with coordination steps
- **`docs/reference/CONTRIBUTING.md`** — added required parallel-work coordination practices
- **`docs/guides/README.md`** and **`docs/README.md`** — indexed the new coordination workflow guide
- **`docs/PROJECT-PLAN.md`** — added Phase 4.6 checklist for concurrent developer/agent coordination operations
- **`.gitignore`** — ignores runtime lock state and generated branch plan files while keeping templates tracked

### Notes

- Lock files are local runtime coordination primitives; they are designed for multi-agent safety on shared workstation/runner environments.
- For multi-machine coordination, use PR sequencing plus merge windows in addition to this local lock workflow.

---

## 2026-02-19 — ComfyUI GPU Passthrough Enabled in Root Module Config

**Summary:** Enabled NVIDIA GPU passthrough inputs in root Terraform wiring for the ComfyUI VM module using RTX 3060 PCI function IDs.

### Changed

- **`infrastructure/main.tf`** — set `gpu_passthrough_enabled = true`, `gpu_pci_id = "0000:01:00.0"`, and `gpu_audio_pci_id = "0000:01:00.1"` on `module "comfyui"`
- **`docs/PROJECT-PLAN.md`** — marked PCI ID configuration step complete and retained runtime verification as pending

### Notes

- This config assumes RTX 3060 functions are exposed as `0000:01:00.0` (GPU) and `0000:01:00.1` (audio); confirm on target Proxmox host with `lspci -nn`.

---

## 2026-02-19 — ComfyUI Proxmox VM Module (Session 29)

**Summary:** Added a new Terraform module to provision a dedicated ComfyUI VM on Proxmox with cloud-init bootstrap for Docker Compose and a source-built ComfyUI container (no ComfyUI base image). Wired the module into root infrastructure outputs and documented rollout status.

### Added

- **`infrastructure/modules/comfyui/providers.tf`** — module provider constraints aligned with existing Proxmox modules
- **`infrastructure/modules/comfyui/variables.tf`** — VM sizing, placement, network, and ComfyUI runtime variables
- **`infrastructure/modules/comfyui/comfyui-vm.tf`** — cloud-config snippet + VM resources (template clone, static IP, tags, lifecycle protections)
- **`infrastructure/modules/comfyui/cloud-configs/comfyui.yml.tftpl`** — first-boot bootstrap for Docker, Compose, and ComfyUI systemd stack
- **`infrastructure/modules/comfyui/outputs.tf`** — VM and access outputs (URL, SSH command)
- **`docs/guides/comfyui-rtx3060-passthrough.md`** — host + guest walkthrough for Proxmox GPU passthrough and Docker CUDA runtime verification

### Changed

- **`infrastructure/main.tf`** — added `module "comfyui"` wired to existing SSH public key source
- **`infrastructure/output.tf`** — added `output "comfyui_vm"` for VM metadata and access endpoints
- **`docs/PROJECT-PLAN.md`** — added Phase 5.7 ComfyUI deployment checklist and current status
- **`docs/reference/version-matrix.md`** — added ComfyUI infrastructure/version tracking entry
- **`docs/guides/README.md`** and **`docs/README.md`** — added ComfyUI GPU passthrough guide links

### Notes

- Current default `comfyui_source_ref` is `master` (floating) pending final pin decision.
- Module includes optional `hostpci` passthrough fields for RTX 3060 GPU + audio functions.
- Planned follow-up before apply: confirm final node placement, VM sizing, source tag/commit, and exact PCI IDs on target host.

---

## 2026-02-19 — Image Tag Pins & Flux Kustomization Fixes (Session 28)

**Summary:** Pinned image tags for OAuth2 Proxy (v7.14.2), qBittorrent (5.1.4-r2), and Windmill (1.639.0). Fixed two immutable resource issues blocking the Flux `apps` Kustomization: Plex PV NFS path change and YouTrack PVC missing `volumeName`. Verified all Session 27 upgrades running correctly (FluxCD v2.7.5, cert-manager v1.19.3, kube-prometheus-stack 82.1.1 with Grafana 12.3.3).

### Changed (PR #100, v0.100.0)

- **`kubernetes/platform/controllers/oauth2-proxy.yaml`** — added `image.tag: "v7.14.2"` pin
- **`kubernetes/apps/qbittorrent/release.yaml`** — added `image.tag: "version-5.1.4-r2"` pin
- **`kubernetes/apps/windmill/release.yaml`** — added `windmill.tag: "1.639.0"` pin
- **`docs/reference/version-matrix.md`** — updated pinned versions and change log

### Fixed (PR #101, v0.101.0)

- **`kubernetes/apps/youtrack/pvc.yaml`** — added `volumeName: pvc-c5a32694-...` to match cluster-bound state (Flux dry-run immutable spec error)
- **Plex PV `plex-adult-v3`** — deleted/recreated in cluster to apply NFS path change (`/volume3/Adult/videos` → `/volume3/Adult/VR`)

### Key Findings

- Flux Kustomization is **atomic**: one failing resource blocks ALL resources from reconciling
- Dynamically provisioned PVCs get `volumeName` on binding — must include in manifest for GitOps
- PV/PVC protection finalizers can deadlock during deletion — patch both to remove

---

## 2026-02-19 — Safe Batch Version Upgrades (Session 27)

**Summary:** Upgraded FluxCD (v2.3.0 → v2.7.5), cert-manager (1.17.x → 1.19.x), and kube-prometheus-stack (69.x → 82.x). K3s v1.32 unlocked FluxCD v2.5+ compatibility. Force-reconciled floating chart pins (OAuth2 Proxy, Loki, qBittorrent). Updated OCIRepository/Bucket API versions from v1beta2 → v1. Reduced behind-count from 12 to 6 components.

### Changed

- **`clusters/homelab/flux-system/gotk-components.yaml`** — regenerated with Flux CLI v2.7.5 (self-upgrade mechanism)
- **`kubernetes/platform/controllers/cert-manager.yaml`** — chart constraint 1.17.x → 1.19.x
- **`kubernetes/platform/monitoring/controllers/kube-prometheus-stack/repository.yaml`** — semver 69.x → 82.x, API v1beta2 → v1
- **`kubernetes/platform/monitoring/controllers/kube-prometheus-stack/kube-state-metrics-config.yaml`** — Bucket/OCIRepository API v1beta2 → v1
- **`docs/reference/version-matrix.md`** — updated all upgraded component versions, change log, summary stats

### Runtime Changes (no file edits)

- Force-reconciled floating chart pins: OAuth2 Proxy → 7.18.0, Loki → 6.53.0, qBittorrent → 0.4.1
- Windmill chart 2.0.508 unchanged (already at latest)

### What's Deferred

- **Nexus** 3.64.0 → 3.89.1: Requires OrientDB→H2 migration at v3.71.0
- **ESO** v1.3.2 → v2.0.0: Major version with breaking changes
- **Image tag bumps**: OAuth2 Proxy (v7.11.0→v7.14.2), qBittorrent (5.0.3→5.1.4), Windmill (1.555.0→latest)

### Post-merge Verification Needed

1. `flux check` — all components v2.7.5
2. `kubectl get pods -n cert-manager` — all Running
3. `kubectl get certificates -A` — all Ready/True
4. Grafana UI loads, custom dashboards render
5. Prometheus targets page healthy

---

## 2026-02-19 — Pin Floating Image Tags + Knowledge Capture

**Summary:** Pinned 13 container images from floating tags (`:latest`, `:2`, `cuda12-latest`) to exact semver/date versions. Cleaned CI allowlist from 14 to 2 entries (only 1Password Connect infrastructure images remain). Updated reference docs with session findings including probe gotchas, pve-exporter breaking change, and image tag pinning patterns.

### Changed

- **10 active app deployments pinned:** code-server (4.109.2), n8n (2.8.3), Stash (v0.30.1), Draw.io (29.3.6), Calibre-web (0.6.26), Linkwarden (v2.13.5), GitLab CE (18.9.0-ce.0), Wiki.js (2.5.312), JupyterLab (cuda12-2026-02-16), pve-exporter (3.8.1)
- **3 disabled app deployments pinned:** Docmost (0.8.2), Jackett (0.22.1372), FlareSolverr (v3.3.21)
- **`ci/allowlists/image-tag-latest.txt`** — reduced from 14 to 2 entries
- **`docs/reference/version-matrix.md`** — updated all statuses, added 13 version change log entries, marked "Pin floating tags" as DONE

### Reference Docs Updated (knowledge capture)

- **`docs/reference/cicd-observability.md`** — added probe gotchas (tcpSocket requirement), pve-exporter v3.8.0 breaking change
- **`docs/reference/technical-gotchas.md`** — 3 new entries (probe type change, GH Actions exporter, pve-exporter)
- **`docs/reference/deployment-troubleshooting.md`** — issue #19 (exporter probe failure + resolution)
- **`docs/reference/app-deployment-patterns.md`** — image tag pinning patterns section with format table and CI allowlist workflow

---

## 2026-02-19 — CI/CD Observability & Operations (Phase 4)

**Summary:** Completed CICD-PLAN.md Phase 4 — added CI/CD metrics export, alert rules, Grafana dashboards, Flux Slack notifications, and operational runbook. GitHub Actions exporter polls workflow/runner metrics into Prometheus. Six new alert rules cover workflow failures, stuck runs, runner health, Flux error rates, stale sources, and long-suspended releases. Flux notification-controller now sends error events to Slack in real-time.

### Added

- **GitHub Actions Exporter** (`kubernetes/platform/monitoring/controllers/github-actions-exporter/`) — `ghcr.io/labbs/github-actions-exporter:1.9.0`, polls `homelab-admin/homelab-iac` every 300s via GitHub REST API, exports `github_workflow_run_status`, `github_workflow_run_duration_ms`, `github_runner_status`
- **6 new Prometheus alert rules** in `homelab-alerts.yaml`:
  - `github-actions` group: `GitHubWorkflowFailed` (5m), `GitHubWorkflowStuck` (30m), `GitHubSelfHostedRunnerOffline` (10m)
  - `flux-deployment-health` group: `FluxReconciliationErrorRate` (>25% over 15m), `FluxSourceRevisionStale` (6h), `FluxHelmReleaseSuspendedLong` (72h)
- **Flux Slack notifications** (`kubernetes/platform/configs/flux-notifications/`) — Provider + Alert (error-only) using `notification.toolkit.fluxcd.io/v1beta3`, reuses `alertmanager-slack` 1Password webhook
- **CI/CD Pipeline dashboard** (`dashboards/cicd-pipeline.json`) — workflow status, duration bars, runs table, runner health
- **GitOps Health dashboard** (`dashboards/gitops-health.json`) — resource overview stats, status table, reconciliation rates, source health, duration percentiles
- **Operational runbook** (`docs/runbooks/cicd-incident-triage.md`) — triage steps for all 9 alert/notification scenarios

### Changed

- **`kubernetes/platform/monitoring/controllers/kustomization.yaml`** — added `./github-actions-exporter`
- **`kubernetes/platform/monitoring/configs/kustomization.yaml`** — added `cicd-grafana-dashboards` configMapGenerator
- **`kubernetes/platform/configs/kustomization.yaml`** — added `./flux-notifications`
- **`docs/CICD-PLAN.md`** — checked off all Phase 4 items

### Prerequisites (manual)

- Create 1Password item `github-actions-exporter` in Homelab vault with custom text field `token` (GitHub PAT, `repo` scope)
- Verify Slack channel name matches `homelab-alerts` in `provider.yaml`

### Design Decisions

- **Pull-based exporter**: `Labbs/github-actions-exporter` chosen over `cpanato/github_actions_exporter` because the latter requires inbound webhooks (impossible with Tailscale-only network)
- **Error-only Flux notifications**: `eventSeverity: error` prevents noise from 20+ HelmReleases reconciling hourly
- **Flux notifications in platform/configs/**: `monitoring/configs/` has `namespace: monitoring` transformer which would rewrite CRDs away from `flux-system`

---

## 2026-02-19 — MCP Kubernetes Consolidation Strategy (Docs)

**Summary:** Added a dedicated MCP strategy document that inventories MCP servers currently referenced in the repo, identifies which ones should be centralized in Kubernetes, and defines an automatic agent configuration pattern using generated `.mcp.json` files with 1Password-backed secret injection.

### Added

- **`docs/reference/mcp-kubernetes-deployment-strategy.md`** — Deployment decision matrix for MCP servers (deploy vs keep local), recommended first-wave servers (Kubernetes, Flux, Prometheus, PostgreSQL), Flux placement guidance, security guardrails, and phased rollout plan

### Changed

- **`docs/README.md`** — Added MCP strategy link in Reference section
- **`docs/reference/ai-and-llm-information.md`** — Added MCP operations section linking to the new strategy and related MCP docs

---

## 2026-02-19 — Velero K8s Backup with Longhorn CSI Snapshots (PRs #90-#91)

**Summary:** Deployed Velero v1.17.2 for full Kubernetes backup with CSI snapshot support. MinIO on NFS provides S3-compatible storage target. Longhorn CSI snapshots with Kopia data movement protect all PVC data. YouTrack migrated from local-path to Longhorn for backup coverage. Fixed Flux circular dependency (ExternalSecrets in configs blocking controller startup).

### Added

- **CSI Snapshot Controller** (external-snapshotter v8.2.0) — 3 VolumeSnapshot CRDs + 2-replica controller deployment in kube-system (K3s doesn't bundle these)
- **`kubernetes/platform/controllers/velero/minio.yaml`** — MinIO standalone HelmRelease (chart 5.4.0), 50Gi NFS storage, cluster-internal S3 endpoint
- **`kubernetes/platform/controllers/velero/velero.yaml`** — Velero HelmRelease (chart 11.3.2, image v1.17.2), AWS plugin v1.13.2, CSI feature enabled, node-agent DaemonSet (8 pods)
- **`kubernetes/platform/controllers/velero/external-secrets.yaml`** — 3 ExternalSecrets: MinIO credentials, Velero S3 credentials (AWS format via ESO template), Kopia repo password (immutable)
- **`kubernetes/platform/configs/velero-snapshot-class.yaml`** — VolumeSnapshotClass `longhorn-snapshot-vsc` (driver.longhorn.io, `type: snap`, Velero auto-discovery label)
- **Backup schedules** — Daily at 12:00 UTC (7-day retention), weekly Sunday at 13:00 UTC (30-day retention), all namespaces with `snapshotMoveData: true`
- **Velero monitoring alerts** — `VeleroBackupFailed`, `VeleroBackupMissing` (26h threshold), `VeleroBackupPartialFailure` added to homelab-alerts PrometheusRule

### Changed

- **`kubernetes/apps/youtrack/pvc.yaml`** — Migrated `youtrack-data` from `local-path` to `longhorn` StorageClass (enables CSI snapshot backups)
- **`kubernetes/apps/youtrack/deployment.yaml`** — Removed `nodeSelector: storage-class/local: "true"` (Longhorn is distributed)
- **`kubernetes/platform/controllers/kustomization.yaml`** — Added `./snapshot-controller` and `./velero` resources
- **`kubernetes/platform/configs/kustomization.yaml`** — Added `velero-snapshot-class.yaml`

### Fixed

- **Flux circular dependency** (PR #91) — MinIO pod couldn't start because `minio-credentials` secret was in `platform-configs` (which depends on `platform-controllers` being Ready). Moved ExternalSecrets to `controllers/velero/` to co-locate with consumer.

### Gotchas Discovered

- **Flux circular dep pattern**: ExternalSecrets in `platform-configs` can't create secrets needed by pods in `platform-controllers` — always co-locate ExternalSecret with its consumer
- **PVC storageClassName immutable**: Migration requires PV retain → delete PVC → clear claimRef → create new PVC with `volumeName` binding
- **Kopia repo password is IMMUTABLE**: Cannot be changed after first backup — set correctly before deploying
- **Velero CSI snapshots are temporary**: With `snapshotMoveData: true`, Kopia uploads data then deletes the VolumeSnapshot — no snapshots visible after completion

### Verified

- BSL `default`: Phase Available (MinIO S3 connection)
- Test backup: 1,969 K8s resources backed up in ~11 seconds
- CSI snapshot test: YouTrack Longhorn volume snapshot → Kopia upload → MinIO confirmed
- All 8 node-agents running, both schedules enabled

---

## 2026-02-18 — MCP Server Setup & Prometheus Ingress (PRs #86-#87)

**Summary:** Completed PG backup automation (fixed 4 bugs found during live testing), set up 7 MCP servers for enhanced AI-assisted development, deployed Tailscale ingress for Prometheus, and created a PostgreSQL read-only user for MCP access.

### Added

- **`kubernetes/platform/configs/prometheus-tailscale-ingress.yaml`** (PR #87) — Tailscale Ingress for Prometheus at `https://prometheus.homelab.ts.net`, follows Grafana/Portainer pattern
- **PostgreSQL `mcp_readonly` user** — SELECT-only access on all 8 databases, credentials stored in 1Password (`pg-mcp-readonly`)
- **5 new MCP servers** (`.mcp.json`, gitignored) — Context7 (library docs), GitHub (HTTP remote), Prometheus (metric queries), PostgreSQL (DB queries), verified existing Kubernetes/Terraform/Flux

### Fixed (PR #86, bug fixes during playbook testing)

- **Bash arithmetic exit code** — `((TOTAL_OK++))` when TOTAL_OK=0 returns exit 1 (0 is falsy in bash arithmetic); replaced with `TOTAL_FAIL=${#ERRORS[@]}` direct computation
- **Jinja2/Bash syntax collision** — `${#ERRORS[@]}` contains `{#` which Jinja2 treats as comment start; wrapped in `{% raw %}` blocks
- **Stale NFS mount** — Previous failed mount leaves EPERM on `stat()`; added `umount -l` before retry
- **Ansible template path** — `template` module searches relative to playbook directory, not project root; fixed to `../templates/backup-pg-dbs.sh.j2`

### Changed

- **`kubernetes/platform/configs/kustomization.yaml`** (PR #87) — Added `prometheus-tailscale-ingress.yaml` to resources

### Gotchas Discovered

- **Jinja2 + Bash collision**: `${#array[@]}` (bash array length) contains `{#` which is Jinja2's comment delimiter — must wrap in `{% raw %}...{% endraw %}`
- **Bash `((var++))` with `set -e`**: When var=0, `((0++))` returns exit code 1 (0 is falsy in arithmetic context) — kills the script with `set -euo pipefail`
- **`pg_ctl` not in PATH via sudo**: Ubuntu PG binaries live in `/usr/lib/postgresql/16/bin/` — use `sudo systemctl reload postgresql` instead
- **GitHub MCP server**: `@anthropic/github-mcp-server` npm package does not exist — official server is a Go binary; use remote HTTP endpoint `https://api.githubcopilot.com/mcp/`

---

## 2026-02-18 — PG Backup Automation & Homepage Fixes (PRs #85-#86)

**Summary:** Implemented two-tier PostgreSQL backup strategy for all 8 databases on the HA cluster. Tier 1 (K8s CronJob `pg_dumpall`) already existed with Prometheus alerts; this adds Tier 2 VM-level per-database dumps via Ansible with VIP-aware execution and NAS sync. Also fixed Homepage dashboard layout (flattened nested groups) and corrected Plex NFS volume path.

### Added

- **`ansible/playbooks/pg-backup.yml`** (PR #86) — Ansible playbook to deploy backup automation to both PG HA nodes (NFS mount, backup script, cron, logrotate, verification)
- **`ansible/templates/backup-pg-dbs.sh.j2`** (PR #86) — Jinja2 template for VIP-guarded backup script: per-database `pg_dump`, gzip compression, local 7-day + NAS 30-day retention, status JSON output
- **`ansible/inventory/group_vars/pg_nodes.yml`** (PR #86) — Database list and backup config variables for PG HA nodes
- **`pg_nodes` inventory group** (PR #86) — Added both PG HA VMs (primary .45, standby .46) to Ansible inventory

### Changed

- **`postgresql-primary.yml.tftpl`** (PR #86) — Added `nfs-common` package, 5 missing database creation blocks (n8n, wikijs, teamcity, coder, windmill with full GRANTs), 5 missing `pg_hba.conf` entries, NFS mount for NAS backups, updated backup script (all 8 DBs + VIP guard + NAS sync)
- **`postgresql-standby.yml.tftpl`** (PR #86) — Added `nfs-common` package, NFS mount, backup script with VIP guard, cron entry, logrotate config
- **`pg-backup/cronjob.yaml`** (PR #86) — Fixed stale comment (listed 5 DBs → notes `pg_dumpall` captures all 8 databases, added monitoring reference)
- **`kubernetes/apps/homepage/release.yaml`** (PR #85) — Flattened nested groups (NAS Volumes, Tailscale) that broke CSS column grid layout
- **`kubernetes/apps/plex/pv-adult-v3.yaml`** (PR #85) — Fixed NFS path from `/volume3/Adult/videos` → `/volume3/Adult/VR`
- **`docs/PROJECT-PLAN.md`** (PR #85) — Marked Tailscale API proxy + NAS NFS permissions complete; added PG backup automation + Kong API Gateway as on-deck

### Gotchas Discovered

- **Homepage nested groups**: Nested group syntax (`- GroupName:` with children) creates full-width collapsible sections that bypass the CSS column grid — flatten all items to same level for proper column layout
- **cloud-init fstab**: `/etc/fstab.d/` doesn't exist on Ubuntu and `write_files` doesn't support `append` — use `runcmd` with `echo >> /etc/fstab` instead
- **VIP guard pattern**: Both HA nodes get identical cron + script; the backup script checks `ip addr show | grep VIP` and exits early if not the VIP holder — enables automatic failover without cron reconfiguration

---

## 2026-02-18 — Homepage Widget Audit & Upgrade (PRs #78-#81)

**Summary:** Debugged and fixed all Homepage dashboard widgets (Portainer, Grafana, Proxmox, Plex, Longhorn), upgraded Homepage from v1.2.0 to v1.10.1 via image tag override, created a comprehensive version matrix tracking 42 components, and added a version check step to the finalize workflow.

### Fixed

- **Plex widget** (PR #78, #79) — Corrected service URL from `plex.media.svc` to `plex-plex-media-server.media.svc` (Helm `<release>-<chart>` naming)
- **Proxmox widget** (PR #79) — Updated 1Password URL from 10.0.0.50 (K3s VM) to 10.0.0.10 (PVE host); user created dedicated `api-ro-app@pam` user with PVEAuditor role
- **Portainer widget** (PR #78, #80) — Added `kubernetes: true` for K8s environment; disabled in v1.2.0 (unsupported), re-enabled after v1.10.1 upgrade
- **Grafana widget** (PR #78) — Added `version: 2` for Grafana API v2 compatibility
- **GitLab widget** (PR #78) — Added `user_id: 1` for personal project stats
- **Longhorn widget** (PR #81) — Moved URL from widget definition to `settings.providers.longhorn.url` (Homepage expects it there); added `expanded: true` and `total: true`

### Changed

- **Homepage** (PR #80) — Upgraded from v1.2.0 to v1.10.1 via image tag override (`image.tag: v1.10.1` in HelmRelease values); jameswynn chart 2.x bundles v1.2.0
- **Tailscale widgets** (PR #78) — Added 5 per-node Tailscale widgets with device IDs for all Proxmox hosts
- **`.claude/commands/finalize.md`** (PR #80) — Added Step 8: Version check after tagging (detects version changes, spot-checks for newer releases, updates matrix)

### Added

- **`docs/reference/version-matrix.md`** (PR #80) — Comprehensive version tracking for 42 components across 7 categories (Infrastructure, GitOps/Platform, Monitoring, Identity, Helm Apps, Raw Manifest Apps, Utility); includes Version Change Log, Summary Statistics, and prioritized Upgrade list

### Gotchas Discovered

- **Proxmox API token privilege separation**: Tokens with privilege separation enabled start with ZERO permissions, even under `root@pam` — must assign ACLs explicitly
- **Helm chart service naming**: Charts generate `<release>-<chart>` service names (e.g., `plex-plex-media-server`), not just `<release>`
- **Homepage jameswynn chart version lag**: Chart 2.x bundles Homepage v1.2.0; override with `image.tag` in HelmRelease values for latest
- **Homepage Longhorn widget**: URL goes in `settings.providers.longhorn.url`, NOT in the widget definition block
- **Homepage Portainer K8s widget**: `kubernetes: true` only works in Homepage versions after Jun 2025

---

## 2026-02-18 — Tailscale API Server Proxy + Phase 0 Cleanup (PRs #73-#76)

**Summary:** Enabled remote `kubectl` access via the Tailscale operator's built-in API server proxy, completed Phase 0 repository cleanup (README rewrite, docs index update, legacy config deletion), and optimized Claude Code permissions.

### Added

- **`kubernetes/platform/configs/tailscale-api-rbac.yaml`** (PR #75) — ClusterRoleBinding mapping Tailscale identity (`admin@example.com`) to `cluster-admin` for remote kubectl access
- **`apiServerProxyConfig.mode: "true"`** (PR #75) — Enabled in Tailscale operator HelmRelease for identity-based API server proxy

### Changed

- **`README.md`** (PR #74) — Full rewrite: cluster overview, tech stack, 17 deployed apps table, PostgreSQL HA topology, repo structure tree
- **`docs/README.md`** (PR #74) — Added Analysis section, expanded Reference from 5 to 13 docs
- **`docs/PROJECT-PLAN.md`** (PR #74) — Marked Phase 0 complete, updated K3s version, marked deployed Phase 5 items
- **`.claude/settings.local.json`** — Optimized permissions from 222 to 85 entries; generalized git/gh to use 1Password SSH agent
- **`docs/reference/tailscale-kubernetes.md`** — Added operational API proxy details, homelab-specific config, fallback strategy, 3 new gotchas

### Fixed

- **`tailscale-api-rbac.yaml`** (PR #76) — Corrected Tailscale identity email from `edkarlsson0@gmail.com` to `admin@example.com`

### Removed

- **`.mcp.op.json`** (PR #74) — Deleted legacy Cline/TaskMaster MCP config (superseded by `.mcp.json`)

### Gotchas Discovered

- **Tailscale kubeconfig context uses FQDN**: `tailscale configure kubeconfig` creates context `tailscale-operator.<tailnet>.ts.net`, not the shortname
- **Tailscale identity must match exactly**: ClusterRoleBinding email must match `tailscale status --self` — GitHub username ≠ Tailscale login email
- **`grants` vs `acls` are separate sections**: The `app` property for `tailscale.com/cap/kubernetes` belongs in `grants` (top-level), NOT inside `acls`

---

## 2026-02-18 — Deployment Fixes, Overnight Audit & Homepage Widgets (PR #73)

**Summary:** Fixed deployment issues for GitLab, Linkwarden, and Calibre-web. Ran comprehensive overnight analysis of K8s manifests, Homepage, app recommendations, MCP utilization, and Wiki.js. Created `homepage-widgets` 1Password item and activated 10 service widgets.

### Fixed

- **GitLab** — Switched all probes to `tcpSocket` (health endpoints only respond on localhost)
- **Linkwarden** — Escalated memory through 4 rounds (1Gi→8Gi); Puppeteer headless Chrome for link archival requires 8Gi
- **Calibre-web** — Fixed NFS path to use export root `/volume1/books` + `subPath: Calibre_Library`
- **Homepage** — Fixed Proxmox widget URL from Tailscale to LAN IP (pods can't resolve .ts.net)

### Added

- **`docs/analysis/overnight-audit-2026-02-18.md`** — Comprehensive audit: manifest consistency, app recommendations, MCP gaps
- **`docs/analysis/homepage-setup-guide.md`** — Step-by-step guide for populating Homepage widget credentials
- **`docs/reference/technical-gotchas.md`** — 7 new gotchas (GitLab probes, Linkwarden OOM, NFS subPath, 1Password dot separator, PV immutability, Homepage widget URL, secretKeyRef optional pattern)
- **1Password item `homepage-widgets`** — 13 custom text fields for service widget API tokens

### Changed

- **`.claude/session-notes.md`** — Updated for session 20

## 2026-02-17 — PG HA VIP Cutover + Project Plan Update (PR #70)

**Summary:** Cut over all PostgreSQL consumers from the direct primary IP (10.0.0.45) to the HA VIP (10.0.0.44), making the keepalived failover cluster fully active. Also consolidated `docs/apps-to-deploy.md` into the project plan as Phase 5.

### Changed

- **`.env.d/terraform.env`** — `PG_CONN_STR` now connects via VIP 10.0.0.44
- **`infrastructure/backend.tf`** — Updated comments to reference VIP
- **`infrastructure/modules/k3s/variables.tf`** — `postgres_ip` default changed to VIP
- **`ansible/inventory/group_vars/k3s_cluster.yml`** — `k3s_datastore_endpoint` updated to VIP
- **`kubernetes/platform/controllers/keycloak.yaml`** — `KC_DB_URL_HOST` → VIP
- **`kubernetes/apps/n8n/deployment.yaml`** — `DB_POSTGRESDB_HOST` → VIP
- **`kubernetes/apps/wikijs/deployment.yaml`** — `DB_HOST` → VIP
- **`kubernetes/apps/teamcity/server-deployment.yaml`** — Comment updated
- **`kubernetes/apps/docmost/external-secret.yaml`** — Comment updated
- **`kubernetes/platform/configs/keycloak-external-secret.yaml`** — Comments updated
- **`kubernetes/platform/monitoring/controllers/pg-backup/external-secret.yaml`** — Comments updated
- **`scripts/k8s/k3s-ssh.sh`** — Added `postgres` (VIP), `postgres-primary`, `postgres-standby` roles
- **`scripts/k8s/k3s-verify.sh`** — Phase 6 rewritten for HA: checks both nodes, replication roles, VIP connectivity

### Added

- **`docs/PROJECT-PLAN.md`** — Phase 5: Future App Deployments (Linkwarden, Draw.io, GitLab, security scanning suite, optional apps)

### Removed

- **`docs/apps-to-deploy.md`** — Content merged into PROJECT-PLAN.md Phase 5

### Manual Steps (not in git)

- 3 K3s server nodes: updated `/etc/rancher/k3s/config.yaml` datastore-endpoint, rolling restart
- 3 1Password items updated: `pg-backup` (pg-host), `Coder` (db-connection-url), `Windmill` (db-connection-url)
- ESO re-sync forced on pg-backup-credentials, coder-secrets, windmill-secrets ExternalSecrets

---

## 2026-02-17 — YouTrack + TeamCity Deployment Fixes (PRs #45-#47)

**Summary:** Fixed deployment issues that prevented YouTrack and TeamCity from starting, then enabled the 3 build agents after server setup.

### Fixed (PR #45)

- **`youtrack/deployment.yaml`** — Image tag `2024.3.45869` doesn't exist on Docker Hub → updated to `2025.3.124603`
- **`teamcity/server-deployment.yaml`** — Added `optional: true` to `TEAMCITY_DB_PASSWORD` secretKeyRef so pod starts before 1Password item exists
- **`teamcity/server-deployment.yaml`** + **`teamcity/agents-statefulset.yaml`** — Updated from `2024.12.1` → `2025.11.2` (latest stable; server + agents must match)

### Fixed (PR #46)

- **`youtrack/deployment.yaml`** — `/api/config` returns 404 during setup wizard → liveness changed to `tcpSocket`, readiness changed to `/`
- **`teamcity/server-deployment.yaml`** — `/healthCheck/ready` returns 503 during setup wizard → readiness changed to `/healthCheck/healthy`

### Changed (PR #47)

- **`teamcity/kustomization.yaml`** — Uncommented `agents-statefulset.yaml` and `agents-service.yaml` after server setup wizard completed

### Gotchas Discovered

- **YouTrack `/api/config`**: Only available after first-boot wizard completes — use `/` or TCP socket for probes during initial setup
- **TeamCity `/healthCheck/ready` vs `/healthCheck/healthy`**: "ready" returns 503 until DB is configured; "healthy" returns 200 in all states
- **TeamCity `secretKeyRef` without `optional: true`**: Blocks pod startup with `CreateContainerConfigError` if secret doesn't exist yet
- **pg_hba.conf for K3s pods**: Pod traffic to PostgreSQL on same LAN routes through the node IP (10.0.0.x), not pod CIDR (10.42.0.0/16) — pg_hba needs `10.0.0.0/24`

---

## 2026-02-17 — Alerting, PG Backups, YouTrack + TeamCity (PRs #42-#43)

**Summary:** Enabled Alertmanager with Slack webhook notifications, added 16 custom PrometheusRule alerts across 7 groups, deployed a nightly PostgreSQL backup CronJob, and added JetBrains YouTrack (issue tracker) and TeamCity (CI/CD with 3 build agents).

### Added

**Alertmanager + Custom Alerts** (PR #42)

- **`monitoring/controllers/kube-prometheus-stack/alertmanager-external-secret.yaml`** — Slack webhook URL from 1Password
- **`monitoring/configs/homelab-alerts.yaml`** — PrometheusRule with 16 alerts across 7 groups:
  - Pod health (3): PodCrashLooping, PodNotReady, DeploymentReplicasMismatch
  - Node health (3): NodeNotReady (critical), NodeHighCPU, NodeHighMemory
  - Storage (2): PVCAlmostFull, NodeDiskAlmostFull
  - Proxmox VE (5): PVENodeDown (critical), PVEHighCPU, PVEHighMemory, PVEStorageAlmostFull, PVEVMDown
  - External Secrets (1): ExternalSecretSyncFailed
  - PostgreSQL backups (2): PGBackupJobFailed, PGBackupMissing (26h threshold)
  - Flux GitOps (1): FluxReconciliationFailed

**PostgreSQL Backup CronJob** (PR #42)

- **`monitoring/controllers/pg-backup/`** — Nightly `pg_dumpall` at 2 AM Pacific, gzip compression, 14-day retention, 5Gi NFS PVC, credentials from 1Password via ExternalSecret with `.pgpass` templating

**YouTrack** (PR #43) — `kubernetes/apps/youtrack/`

- Raw manifest deployment (7 files): Deployment, Service, dual Ingress, 4 PVCs
- Embedded Xodus DB on `local-path` StorageClass (NFS not supported by JetBrains)
- Node-pinned via `storage-class/local=true` nodeSelector
- UID/GID 13001 securityContext

**TeamCity Server + 3 Build Agents** (PR #43) — `kubernetes/apps/teamcity/`

- Raw manifest deployment (10 files): server Deployment, server Service, dual Ingress, PVC, ExternalSecret, agents StatefulSet (3 replicas), headless agents Service
- External PostgreSQL on 10.0.0.45 (configured via web wizard, not env vars)
- Agents use `volumeClaimTemplates` for per-agent config + work PVCs
- Agents commented out in kustomization until server setup wizard is complete

### Changed

- **`monitoring/controllers/kube-prometheus-stack/release.yaml`** — Enabled Alertmanager with 1Gi NFS storage, Slack routing config (warning + critical receivers), Watchdog suppression
- **`kubernetes/apps/kustomization.yaml`** — Added `./youtrack` and `./teamcity`

### Hotfixes (direct to main)

- **`release.yaml`** — Removed `slack_api_url: "placeholder"` (broke Alertmanager — operator validates URL before Flux `valuesFrom` merge)
- **`release.yaml`** — Removed `{{ "{{" }}` double-escaping from Slack templates (chart passes config verbatim, no Helm templating)
- **`homelab-alerts.yaml`** — Replaced `mul()` with `humanizePercentage` (Prometheus templates don't have `mul()`)

### Decisions

| # | Decision | Chosen | Rationale |
|---|----------|--------|-----------|
| 20 | Alert target | Slack webhook | Simple, already in use for other notifications |
| 21 | PG backup method | pg_dumpall CronJob | Backs up all databases (keycloak, n8n, wikijs, terraform_state, k3s) in one pass |
| 22 | YouTrack data storage | local-path StorageClass | Xodus embedded DB requires POSIX-compliant filesystem (NFS not supported) |
| 23 | TeamCity deploy method | Raw manifests (not Operator) | Consistent with existing app patterns; Operator is v0.0.21 beta |
| 24 | TeamCity agents | StatefulSet (3 static replicas) | Stable PVC identity for auth tokens; simple, predictable resource usage |

### Gotchas Discovered

- **1Password Connect default fields**: Login item default fields (username, password, URL) are NOT addressable by `property` in ExternalSecrets — only custom text fields work
- **Alertmanager `slack_api_url` placeholder**: prometheus-operator validates config before Flux `valuesFrom` overrides apply — invalid URLs break reconciliation
- **Helm chart config passthrough**: kube-prometheus-stack passes `alertmanager.config` verbatim to the Secret — no Helm template rendering occurs, so Go template syntax goes through as-is (no escaping needed)
- **Prometheus template functions**: `mul()` doesn't exist — use `humanizePercentage` for ratio-to-percentage formatting

---

## 2026-02-17 — Monitoring Stack + Docmost Removal + Homepage (PRs #37-#40)

**Summary:** Removed Docmost (replaced by Wiki.js), enabled full monitoring stack with custom dashboards, deployed Proxmox VE exporter for hypervisor metrics, and populated Homepage with all 11 deployed services.

### Removed

- **PR #37** — Disabled Docmost deployment (commented out in `kubernetes/apps/kustomization.yaml`). Wiki.js is the preferred knowledge base. Manifests kept in-tree for reference.

### Added

**Monitoring Dashboards** (PR #38)

- **`kubernetes/platform/monitoring/configs/dashboards/applications.json`** — "Homelab Applications" Grafana dashboard: pod status, CPU/memory/network by app namespace, restart counts, resource table with per-pod detail
- **`kubernetes/platform/monitoring/configs/dashboards/application-logs.json`** — "Application Logs" Grafana dashboard: Loki log volume by namespace, error rate highlighting (regex: error/exception/fatal/panic/fail), live log viewer with search and pod filtering
- **`kubernetes/platform/monitoring/configs/dashboards/proxmox.json`** — "Proxmox VE Cluster" Grafana dashboard: node online/offline status, CPU usage, memory usage (absolute + gauge %), storage usage bar chart, VM table with CPU/memory/status, per-VM time series

**Proxmox VE Exporter** (PRs #38, #39)

- **`kubernetes/platform/monitoring/controllers/pve-exporter/`** — Deployment (`prompve/prometheus-pve-exporter:latest`), Service (port 9221), ServiceMonitor (scrapes `/pve` at 60s interval targeting `node-02.homelab.ts.net`), ExternalSecret (templates PVE API token credentials from 1Password into `pve.yml` config file)
- PVE monitoring user: `monitoring@pve` with `PVEAuditor` role and API token (no privilege separation)

### Changed

- **PR #38** — `kube-prometheus-stack` release: `defaultDashboardsEnabled: false` → `true` (enables ~20 community dashboards for node exporter, pod resources, kubelet, CoreDNS, API server, etc.)
- **PR #38** — `monitoring/configs/kustomization.yaml`: Added `homelab-grafana-dashboards` ConfigMapGenerator (applications, application-logs, proxmox)
- **PR #38** — `monitoring/controllers/kustomization.yaml`: Added `./pve-exporter` resource
- **PR #39** — Moved `pve-external-secret.yaml` from `monitoring/configs/` to `monitoring/controllers/pve-exporter/external-secret.yaml` (fixed circular dependency: Deployment needs Secret from ExternalSecret, but configs depends on controllers being healthy)
- **PR #40** — Homepage `release.yaml`: Populated all 5 layout sections with 11 services (Platform: Portainer, Keycloak; Monitoring: Grafana, Prometheus; Media: Plex, qBittorrent; Services: Wiki.js, n8n; Dev: code-server, JupyterLab, Nexus). All links use Tailscale URLs.

### Decisions

| # | Decision | Chosen | Rationale |
|---|----------|--------|-----------|
| 16 | Monitoring dashboards | Custom JSON + default enabled | Custom for app overview + Loki logs; defaults for node/cluster (20+ dashboards) |
| 17 | Proxmox monitoring | prometheus-pve-exporter | Single exporter scrapes entire PVE cluster via one API endpoint |
| 18 | PVE auth | API token (not user/password) | Tokens don't expire with sessions, more secure for long-running exporters |
| 19 | PVE ExternalSecret location | Controllers (not configs) | Avoids circular dependency between Flux Kustomization stages |

### Gotcha: Flux Kustomization Circular Dependencies

When a Flux Kustomization (e.g. `monitoring-configs`) depends on another (e.g. `monitoring-controllers`), any resource in the downstream Kustomization that the upstream Deployment needs will deadlock. Solution: co-locate the ExternalSecret with the Deployment that consumes it.

---

## 2026-02-17 — Phase 3 Fixes + JupyterLab + Docmost (PRs #28-#34)

**Summary:** Fixed 6 deployment issues across Phase 3 apps, converted broken HelmReleases to raw K8s manifests, added JupyterLab (PyTorch/CUDA) and Docmost (collaborative wiki) as new apps. All 8 active apps running and accessible via dual ingress.

### Fixed (PR #28)

- **code-server** — Converted from HelmRelease to raw manifests (Deployment/Service/Ingress/PVC); chart repo URL returned 404
- **n8n** — Converted from HelmRelease to raw manifests; 8gears chart repo returned malformed JSON
- **qBittorrent** — Chart version constraint `1.x` → `0.x` (latest is 0.4.3)
- **Jackett** — Liveness/readiness probes changed from `httpGet /UI/Dashboard` (400) to `tcpSocket`
- **Homepage** — Widget service `href` links changed from `*.nip.io` → `*.homelab.ts.net` (Tailscale URLs work from both LAN and remote)
- **Plex** — Added `spec.upgrade.force: true` to HelmRelease for StatefulSet immutable field updates

### Changed

- **PR #29** — Disabled Jackett (crashloop, revisit later); commented out in `kubernetes/apps/kustomization.yaml`
- **PR #30** — Set Plex claim token for initial server registration

### Added

**JupyterLab** (`kubernetes/apps/jupyterlab/`) — PRs #31, #32, #33

- `namespace.yaml`, `deployment.yaml` — `quay.io/jupyter/pytorch-notebook:cuda12-latest`, 8Gi memory limit, 8Gi shared memory (emptyDir), token auth via 1Password ExternalSecret
- `service.yaml` — ClusterIP port 8888
- `ingress.yaml` — nginx with OAuth2 Proxy + websocket timeouts (3600s)
- `pvc.yaml` — 10Gi workspace on nfs-kubernetes
- `external-secret.yaml` — Token from 1Password
- `tailscale-ingress.yaml`, `kustomization.yaml`
- Fixed probe 403 (tcpSocket instead of httpGet on token-protected `/api/status`)

**Docmost** (`kubernetes/apps/docmost/`) — PR #34

- `namespace.yaml`, `deployment.yaml` — Docmost wiki (port 3000) with external PostgreSQL + Redis
- `redis.yaml` — Redis deployment + service + PVC (1Gi, AOF persistence)
- `service.yaml` — ClusterIP port 3000
- `ingress.yaml` — nginx with OAuth2 Proxy + websocket timeouts
- `pvc.yaml` — 5Gi file storage on nfs-kubernetes
- `external-secret.yaml` — app-secret + database-url from 1Password
- `tailscale-ingress.yaml`, `kustomization.yaml`

### Decisions

| # | Decision | Chosen | Rationale |
|---|----------|--------|-----------|
| 12 | Broken Helm charts | Raw K8s manifests | code-server (no repo) and n8n (malformed JSON) — user preference for vanilla K8s |
| 13 | JupyterLab image | pytorch-notebook:cuda12-latest | Matches user's existing Docker Compose setup; CPU fallback until GPU passthrough |
| 14 | Docmost database | External PG (10.0.0.45) | Reuses existing VM alongside n8n and Keycloak databases |
| 15 | Docmost Redis | Separate deployment (not sidecar) | Persistent AOF data survives pod restarts |

### Running Apps (post-session)

| App | Type | Auth |
|-----|------|------|
| Homepage | HelmRelease | OAuth2 Proxy |
| Plex | HelmRelease | Plex account |
| qBittorrent | HelmRelease | Built-in admin |
| code-server | Raw manifests | OAuth2 Proxy + 1Password password |
| n8n | Raw manifests | OAuth2 Proxy + account creation |
| Nexus | HelmRelease | Built-in admin |
| JupyterLab | Raw manifests | OAuth2 Proxy + 1Password token |
| Docmost | Raw manifests | OAuth2 Proxy + account creation |
| Jackett | Disabled | — |

---

## 2026-02-17 — Phase 3: Application Stack (6 apps + Plex media volumes)

**Summary:** Create Kubernetes manifests for all 7 Phase 3 applications (Stash deferred). Each app follows the established Flux GitOps pattern with dual ingress (nginx LAN + Tailscale), OAuth2 Proxy SSO (except Plex), and NFS-backed persistence. All 47 resources pass `kubectl kustomize` validation.

### Added

**Homepage** (`kubernetes/apps/homepage/`)

- `namespace.yaml` — Namespace with `dev-team` tenant label
- `repository.yaml` — HelmRepository for `jameswynn` charts
- `release.yaml` — HelmRelease (chart 2.x) with RBAC service discovery, OAuth2 Proxy auth annotations, pre-populated services (Portainer, Keycloak, Grafana), K8s cluster widgets
- `tailscale-ingress.yaml` — Tailscale ingress (port 3000)
- `kustomization.yaml` — Local resource list

**Plex** (`kubernetes/apps/plex/`)

- `pv-movies.yaml` — Static PV/PVC for `/volume1/videos/Movies` (ReadOnlyMany, 1Ti)
- `pv-music.yaml` — Static PV/PVC for `/volume1/music/Music` (ReadOnlyMany, 500Gi)
- `pv-photos.yaml` — Static PV/PVC for `/volume1/photos` (ReadOnlyMany, 500Gi)
- `pv-adult.yaml` — Static PV/PVC for `/volume1/videos/Adult` (ReadOnlyMany, 1Ti)
- `pv-adult-v3.yaml` — Static PV/PVC for `/volume3/Adult/videos` (ReadOnlyMany, 1Ti)
- `tailscale-ingress.yaml` — Tailscale ingress (port 32400)

**qBittorrent** (`kubernetes/apps/qbittorrent/`)

- `namespace.yaml`, `repository.yaml` — gabe565 chart repo
- `release.yaml` — HelmRelease (chart 1.x) with OAuth2 Proxy, BitTorrent port, NFS downloads
- `pv-downloads.yaml` — Static PV/PVC for `/volume1/downloads/torrents` (ReadWriteMany, 1Ti)
- `tailscale-ingress.yaml`, `kustomization.yaml`

**Jackett + FlareSolverr** (`kubernetes/apps/jackett/`)

- `namespace.yaml`, `deployment.yaml` — Raw Deployment with FlareSolverr sidecar container
- `service.yaml` — ClusterIP on port 9117
- `ingress.yaml` — nginx with OAuth2 Proxy + homelab-ca-issuer
- `pvc.yaml` — Dynamic 1Gi config PVC (nfs-kubernetes)
- `tailscale-ingress.yaml`, `kustomization.yaml`

**code-server** (`kubernetes/apps/code-server/`)

- `namespace.yaml`, `repository.yaml` — code-server chart repo
- `release.yaml` — HelmRelease (chart 3.x) with OAuth2 Proxy, 10Gi workspace
- `external-secret.yaml` — ExternalSecret for password from 1Password
- `tailscale-ingress.yaml`, `kustomization.yaml`

**n8n** (`kubernetes/apps/n8n/`)

- `namespace.yaml`, `repository.yaml` — 8gears chart repo
- `release.yaml` — HelmRelease (chart 1.x) with external PostgreSQL (10.0.0.45), OAuth2 Proxy
- `external-secret.yaml` — ExternalSecret for DB password + encryption key from 1Password
- `tailscale-ingress.yaml`, `kustomization.yaml`

**Nexus** (`kubernetes/apps/nexus/`)

- `namespace.yaml`, `repository.yaml` — Sonatype chart repo
- `release.yaml` — HelmRelease (chart 64.x) with embedded H2, 50Gi storage, unlimited upload size
- `tailscale-ingress.yaml`, `kustomization.yaml`

- `docs/architecture/nas-volume-layout.md` — NAS volume paths and mount strategy

### Changed

- `kubernetes/apps/kustomization.yaml` — Added 6 new app directories to resources list
- `kubernetes/apps/plex-values.yaml` — Rewrote as kustomize strategic merge patch (HelmRelease wrapper) with full values: image, pms config, ingress, 5 NFS volume mounts, resources
- `kubernetes/apps/plex/release.yaml` — Added chart version pin (`0.x`), sourceRef namespace, interval
- `kubernetes/apps/plex/kustomization.yaml` — Added PV files and tailscale-ingress to resources
- `docs/PROJECT-PLAN.md` — Replaced Phase 3 "Media Stack" with expanded "Application Stack" (7 apps), added 5 Decision Log entries (#7-#11), updated status to Phase 2 complete

### Decisions

| # | Decision | Chosen | Rationale |
|---|----------|--------|-----------|
| 7 | Phase 3 app list | 7 apps (Stash deferred) | Homepage, Plex, qBittorrent, Jackett, code-server, n8n, Nexus |
| 8 | n8n database | External PG (10.0.0.45) | Reuses existing VM, better for production workflows |
| 9 | Nexus database | Embedded H2 | Homelab scale, avoids unnecessary PG complexity |
| 10 | OAuth2 Proxy scope | All except Plex | Plex has its own auth system |
| 11 | Jackett deployment | Raw manifests + FlareSolverr sidecar | No official Helm chart, sidecar simplifies networking |

### Manual steps before deploy

1. **Plex**: Get claim token from `https://plex.tv/claim`, uncomment `PLEX_CLAIM` in plex-values.yaml
2. **code-server**: Create 1Password item `code-server` with `password` field
3. **n8n**: Create `n8n` database + user on PG VM; create 1Password item `n8n` with `db-password` and `encryption-key`

---

## 2026-02-17 — Phase 2.2: Deploy OAuth2 Proxy (SSO for LAN Services)

**Summary:** Deploy OAuth2 Proxy as authentication middleware for LAN-facing nginx ingresses, using Keycloak as the OIDC provider. Protects Grafana as the first service — LAN access requires Keycloak SSO login, while Tailscale access remains Tailscale-authenticated. Uses `keycloak-oidc` provider with PKCE, cookie-based sessions, and credentials managed via ESO from 1Password.

### Added

- **kubernetes/platform/controllers/oauth2-proxy.yaml** — Namespace, HelmRepository, and HelmRelease for oauth2-proxy (chart 7.x). Configured with `keycloak-oidc` provider, OIDC issuer at `keycloak.10.0.0.201.nip.io/auth/realms/homelab`, PKCE (S256), cookie-domain scoped to `.10.0.0.201.nip.io`.
- **kubernetes/platform/configs/oauth2-proxy-external-secret.yaml** — ExternalSecret syncing client-id, client-secret, and cookie-secret from 1Password `oauth2-proxy` item.

### Changed

- **kubernetes/platform/monitoring/controllers/kube-prometheus-stack/release.yaml** — Added `auth-url`, `auth-signin`, and `auth-response-headers` annotations to Grafana's nginx ingress for OAuth2 Proxy integration.
- **kubernetes/platform/controllers/kustomization.yaml** — Added `oauth2-proxy.yaml`
- **kubernetes/platform/configs/kustomization.yaml** — Added `oauth2-proxy-external-secret.yaml`
- **docs/PROJECT-PLAN.md** — Updated Phase 2.2 checklist

### Keycloak Configuration (manual, not in git)

- Created `homelab` realm with test user
- Created `oauth2-proxy` confidential OIDC client with audience mapper and groups mapper
- OIDC issuer: `https://keycloak.10.0.0.201.nip.io/auth/realms/homelab`

---

## 2026-02-16 — Phase 2.1: Deploy Keycloak (Identity Provider)

**Summary:** Deploy Keycloak via Flux HelmRelease (codecentric keycloakx chart, Quarkus-based) as the centralized identity provider for SSO/OIDC. Uses external PostgreSQL VM at 10.0.0.45 for the database backend. Accessible on LAN (`keycloak.10.0.0.201.nip.io`) and remotely via Tailscale. Admin and DB credentials managed via ESO ExternalSecrets from 1Password.

### Added

- **kubernetes/platform/controllers/keycloak.yaml** — Namespace, HelmRepository (codecentric), and HelmRelease for keycloakx (chart 7.x). Configured with external PostgreSQL, edge proxy mode, health/metrics endpoints, nginx ingress with homelab-ca-issuer TLS.
- **kubernetes/platform/configs/keycloak-external-secret.yaml** — Two ExternalSecrets: `keycloak-admin` (admin console password) and `keycloak-db` (PostgreSQL password), both synced from 1Password Homelab vault.
- **kubernetes/platform/configs/keycloak-tailscale-ingress.yaml** — Tailscale Ingress for remote access with auto-provisioned TLS.

### Changed

- **kubernetes/platform/controllers/kustomization.yaml** — Added `keycloak.yaml`
- **kubernetes/platform/configs/kustomization.yaml** — Added `keycloak-external-secret.yaml` and `keycloak-tailscale-ingress.yaml`
- **infrastructure/modules/k3s/cloud-configs/postgresql.yml.tftpl** — Added `keycloak` database, user, and pg_hba.conf entry for future VM rebuilds
- **docs/PROJECT-PLAN.md** — Updated Phase 2.1 checklist, filled in Decision #4 (External PG VM)

---

## 2026-02-16 — Deploy Portainer CE (cluster management UI)

**Summary:** Add Portainer CE via Flux HelmRelease for visual Kubernetes cluster management. Accessible on LAN (`portainer.10.0.0.201.nip.io`) and remotely via Tailscale (`portainer.<tailnet>.ts.net`). NFS-backed persistence, self-signed CA TLS on LAN, automatic Let's Encrypt TLS on Tailscale.

### Added

- **kubernetes/platform/controllers/portainer.yaml** — Namespace, HelmRepository, and HelmRelease for Portainer CE (chart 2.x). Includes nginx ingress with HTTPS backend protocol, NFS persistence (2Gi), `localMgmt: true` for managing the local K3s cluster.
- **kubernetes/platform/configs/portainer-tailscale-ingress.yaml** — Tailscale Ingress for remote access with auto-provisioned TLS.

### Changed

- **kubernetes/platform/controllers/kustomization.yaml** — Added `portainer.yaml`
- **kubernetes/platform/configs/kustomization.yaml** — Added `portainer-tailscale-ingress.yaml`

---

## 2026-02-16 — Phase 2.3: External Secrets Operator + 1Password integration

**Summary:** Deploy External Secrets Operator (ESO) via Flux to automatically sync secrets from 1Password into Kubernetes. Uses the existing 1Password Connect server over Tailscale. One bootstrap secret (Connect token) unlocks everything — ESO then manages Tailscale OAuth and Grafana admin credentials via ExternalSecret resources.

### Added

- **kubernetes/platform/controllers/external-secrets.yaml** — Namespace, HelmRepository, and HelmRelease for ESO chart (v1.x). CRDs managed via `install.crds: CreateReplace`.
- **kubernetes/platform/configs/cluster-secret-store.yaml** — ClusterSecretStore for 1Password Connect (`https://op-connect.homelab.ts.net`), Homelab (priority 1) and Dev (priority 2) vaults.
- **kubernetes/platform/configs/tailscale-external-secret.yaml** — ExternalSecret to sync Tailscale OAuth credentials from 1Password, replacing the manual bootstrap secret.
- **kubernetes/platform/monitoring/configs/grafana-external-secret.yaml** — ExternalSecret to sync Grafana admin password from 1Password, replacing the hardcoded `flux` password.
- **scripts/k8s/create-eso-connect-secret.sh** — Bootstrap script to create the 1Password Connect token Secret from environment variable.

### Changed

- **kubernetes/platform/controllers/kustomization.yaml** — Added `external-secrets.yaml`
- **kubernetes/platform/configs/kustomization.yaml** — Added `cluster-secret-store.yaml`, `tailscale-external-secret.yaml`
- **kubernetes/platform/monitoring/configs/kustomization.yaml** — Added `grafana-external-secret.yaml`
- **clusters/homelab/monitoring.yaml** — Added `platform-configs` dependency to `monitoring-configs` (ensures ESO CRDs are available before ExternalSecrets apply)
- **kubernetes/platform/monitoring/controllers/kube-prometheus-stack/release.yaml** — Added `valuesFrom` entry for `grafana-admin` Secret (`optional: true` for first-deploy tolerance), updated admin password comment

### Deployment steps

1. Create Grafana admin item in 1Password: `op item create --vault Homelab --category login --title "grafana-admin" --generate-password='20,letters,digits,symbols'`
2. Create bootstrap secret: `./scripts/k8s/create-eso-connect-secret.sh`
3. Push changes → Flux deploys ESO → ExternalSecrets sync automatically

---

## 2026-02-16 — Tailscale Kubernetes Operator (dual ingress)

**Summary:** Deploy the Tailscale Kubernetes operator via Flux for remote access with automatic `*.ts.net` HTTPS certificates. Adds a Tailscale Ingress for Grafana as the first test service. OAuth credentials stored in 1Password and injected via K8s Secret.

### Added

- **kubernetes/platform/controllers/tailscale-operator.yaml** — Namespace, HelmRepository, and HelmRelease for `tailscale-operator` chart (v1.x). OAuth credentials via `valuesFrom` Secret reference.
- **kubernetes/platform/configs/tailscale-ingress.yaml** — Tailscale Ingress for Grafana (`https://grafana.<tailnet>.ts.net` with auto-provisioned LetsEncrypt TLS)
- **scripts/k8s/create-tailscale-secret.sh** — Idempotent script to create the OAuth Secret from 1Password CLI

### Changed

- **kubernetes/platform/controllers/kustomization.yaml** — Added `tailscale-operator.yaml`
- **kubernetes/platform/configs/kustomization.yaml** — Added `tailscale-ingress.yaml`

---

## 2026-02-16 — Phase 1.6: Monitoring persistence, Grafana ingress

**Summary:** Added NFS persistent storage for Prometheus (10Gi), Grafana (2Gi), Loki (5Gi), and Minio (5Gi). Added Grafana Ingress with self-signed CA TLS via nip.io wildcard DNS. Monitoring stack was already deployed by Flux — this adds data durability and browser access.

### Changed

- **kubernetes/platform/monitoring/controllers/kube-prometheus-stack/release.yaml** — Added Prometheus `storageSpec` (10Gi NFS), Grafana `persistence` (2Gi NFS), Grafana `ingress` (nginx class, homelab-ca-issuer TLS, `grafana.10.0.0.201.nip.io`)
- **kubernetes/platform/monitoring/controllers/loki-stack/release.yaml** — Added Loki single-binary `persistence` (5Gi NFS) and Minio `persistence` (5Gi NFS)

### Decisions

| Decision         | Chosen                         | Rationale                                                       |
| ---------------- | ------------------------------ | --------------------------------------------------------------- |
| Grafana hostname | `grafana.10.0.0.201.nip.io` | nip.io wildcard DNS, no /etc/hosts or router DNS config needed  |
| Grafana password | Deferred to Phase 2.3 (ESO)   | LAN-only, low risk; will use 1Password ExternalSecret later     |

---

## 2026-02-16 — Phase 1.5: Self-signed CA for LAN TLS, Tailscale strategy documented

**Summary:** Replaced the Let's Encrypt HTTP-01 ClusterIssuer (which required public port forwarding) with a self-signed internal CA chain for LAN TLS. Dual ingress strategy: ingress-nginx + MetalLB for LAN access, Tailscale operator planned for remote access with auto `*.ts.net` TLS. Researched and documented Tailscale Kubernetes integration.

### Changed

- **kubernetes/platform/configs/cluster-issuers.yaml** — Replaced Let's Encrypt ACME ClusterIssuer with 3-resource self-signed CA chain: `selfsigned-issuer` (bootstrap) → `homelab-ca` Certificate (10yr ECDSA) → `homelab-ca-issuer` (signs Ingress certs)
- **clusters/homelab/platform.yaml** — Removed stale ACME staging→production server patch (no longer needed)
- **docs/PROJECT-PLAN.md** — Updated Phase 1.3/1.4/1.7 as verified complete; rewrote Phase 1.5 for self-signed CA + Tailscale dual strategy; updated Decision Log entry #3

### Added (memory)

- **memory/tailscale-kubernetes.md** — Comprehensive research on Tailscale K8s operator: Ingress, auto-TLS, API server proxy, deployment patterns, comparison with traditional ingress+cert-manager

### Decisions

| #   | Decision     | Chosen                              | Rationale                                                               |
| --- | ------------ | ----------------------------------- | ----------------------------------------------------------------------- |
| 3   | TLS strategy | Self-signed CA (LAN) + Tailscale (remote) | No port forwarding needed, LAN devices work without Tailscale |

---

## 2026-02-16 — Phase 1.3/1.4/1.7: MetalLB, NFS provisioner, ingress-nginx LoadBalancer

**Summary:** Added MetalLB (L2 mode) and nfs-subdir-external-provisioner as Flux HelmReleases, and switched ingress-nginx from NodePort to LoadBalancer. These two new platform controllers unblock persistent storage for monitoring (Phase 1.6) and external IP allocation for ingress (Phase 1.3).

### Added

- **kubernetes/platform/controllers/metallb.yaml** — MetalLB HelmRelease (chart 0.15.x), Namespace `metallb-system`, HelmRepository
- **kubernetes/platform/configs/metallb-config.yaml** — IPAddressPool (`10.0.0.200-250`) and L2Advertisement for ARP-based IP announcement
- **kubernetes/platform/controllers/nfs-provisioner.yaml** — nfs-subdir-external-provisioner HelmRelease (chart 4.x), Namespace `nfs-provisioner`, StorageClass `nfs-kubernetes` targeting Synology NAS (`10.0.0.161:/volume1/kubernetes`)

### Changed

- **kubernetes/platform/controllers/ingress-nginx.yaml** — `service.type`: `NodePort` → `LoadBalancer` (MetalLB now provides external IPs)
- **kubernetes/platform/controllers/kustomization.yaml** — Added `metallb.yaml` and `nfs-provisioner.yaml` to resource list
- **kubernetes/platform/configs/kustomization.yaml** — Added `metallb-config.yaml` to resource list
- **docs/PROJECT-PLAN.md** — Marked Phase 1.2 fully complete, updated 1.3/1.4/1.7 progress, filled Decision Log entries #2 (IP range) and #6 (NFS provisioner)

### Decisions

| #   | Decision              | Chosen            | Rationale                                                                |
| --- | --------------------- | ----------------- | ------------------------------------------------------------------------ |
| 2   | LoadBalancer IP range | 10.0.0.200-250 | 51 IPs at end of LAN subnet, avoids DHCP and static VM range             |
| 6   | NFS provisioner       | nfs-subdir        | Simpler than democratic-csi, proven with Synology NFS, no CSI complexity |

---

## 2026-02-16 — Phase 1: Activate remote state, bootstrap FluxCD, restructure Flux

**Summary:** Activated the PostgreSQL remote state backend, reduced QEMU agent timeout for fast terraform plan (~10min → ~1.4s), bootstrapped FluxCD v2.3.0, and restructured the Flux entry point from `infrastructure/flux/` to `clusters/homelab/` following the community-standard monorepo pattern. Fixed two pre-existing kustomization bugs.

### Added

- **clusters/homelab/platform.yaml** — Flux Kustomization for platform controllers + configs (moved from infrastructure/flux/)
- **clusters/homelab/apps.yaml** — Flux Kustomization for application workloads (moved from infrastructure/flux/)
- **clusters/homelab/monitoring.yaml** — Flux Kustomization for monitoring stack (moved from infrastructure/flux/)
- **docs/architecture/flux-structure.md** — Architecture decision record for Flux directory structure
- **kubernetes/platform/monitoring/controllers/kustomization.yaml** — Missing parent kustomization including kube-prometheus-stack and loki-stack subdirectories
- **.claude/commands/finalize.md** — Added Step 5: post-merge branch cleanup

### Changed

- **infrastructure/backend.tf** — Uncommented `backend "pg" {}` block (remote state now active)
- **infrastructure/modules/k3s/k3s-cluster.tf** — Reduced QEMU agent timeout from 15m to 2m on all 9 VMs; added documentation block explaining QEMU guest agent requirements and cloud-init immutability
- **docs/reference/CONTRIBUTING.md** — Added QEMU Guest Agent section with troubleshooting; updated state backend reference; added cloud-init immutability warning
- **README.md** — Updated repository structure to show `clusters/` at root
- **docs/PROJECT-PLAN.md** — Marked Phase 1.1 complete, updated 1.2 with completed prep steps
- **docs/guides/fluxcd-bootstrap.md** — Updated all paths from `infrastructure/kubernetes/` to actual `kubernetes/platform/` and `clusters/homelab/`; updated repo name from `homelab` to `homelab-iac`
- **scripts/k8s/bootstrap-flux.sh** — Rewrote with correct repo/path, pre-flight checks, error handling
- **kubernetes/apps/kustomization.yaml** — Fixed two-document bug (only first document was processed; plex was silently ignored)

### Removed

- **infrastructure/flux/** — Deleted entire directory (stale: wrong repo `homelab`, wrong path `./kubernetes/cluster`, gotk-components.yaml regenerated by bootstrap)

### Architecture

```
Before: infrastructure/flux/ (mixed Terraform + Flux, stale references)
After:  clusters/homelab/    (community-standard, clean separation)

clusters/  → HOW to deploy (Flux orchestration)
kubernetes/ → WHAT to deploy (K8s manifests)
infrastructure/ → WHERE to deploy (Terraform VMs)
```

---

## 2026-02-16 — Fix deployment blockers and add verification tooling

**Summary:** Fixed 6 deployment blockers that prevented K3s cluster from booting (VLAN double-tagging, missing QEMU guest agent, wrong DNS servers, cloud-init write_files ordering, SSH agent incompatibility). Added deployment verification script and SSH helper for cluster operations. Cluster fully deployed: 9 VMs, 8 K3s nodes Ready, PostgreSQL operational.

### Fixed

- **k3s-cluster.tf** — Removed `vlan_id` from all 3 `network_device` blocks. The Proxmox bridge `vmbr0` is on an access port for VLAN 2; adding `vlan_id` caused 802.1Q double-tagging that the upstream switch dropped.
- **k3s-cluster.tf** — Changed DNS servers from PVE node IPs (`10.0.0.10`, `10.0.0.11`) to Google DNS (`8.8.8.8`, `8.8.4.4`) in all 3 `initialization.dns` blocks. No local DNS server runs on this network.
- **k3s-agent.yml.tftpl / postgresql.yml.tftpl** — Added `defer: true` to `write_files` entries with `owner: ${username}:${username}`. Without deferral, `write_files` runs during `init-network` stage before user creation in `config` stage, causing `OSError: Unknown user`.
- **k3s-server.yml.tftpl / k3s-agent.yml.tftpl / postgresql.yml.tftpl** — Added `qemu-guest-agent` to all 3 cloud-config `packages:` lists. Without the agent, the bpg/proxmox provider waits indefinitely for guest agent response during `terraform apply`.
- **main.tf** — Added `onepassword_item.pve_root` data source and passed `private_key` to the Proxmox provider SSH block. Go's SSH agent library is incompatible with GNOME Keyring's agent protocol, so the key is provided directly from 1Password.

### Added

- **scripts/k8s/k3s-ssh.sh** — SSH helper for K3s cluster VMs. Supports role names (`server1`, `agent3`, `postgres`), batch operations (`all`, `servers`, `agents`), and uses 1Password SSH agent with key pinning.
- **scripts/k8s/k3s-verify.sh** — 7-phase deployment verification (46 checks): network reachability, SSH access, cloud-init status, K3s server/agent health, PostgreSQL health, and full cluster validation.

### Changed

- **.claude/settings.json** — Added `Bash(ssh-add:*)` to tool allow list.
- **.claude/session-notes.md** — Updated with Session 8 deployment summary.

---

## 2026-02-16 — Fix k3s module deploy blockers

**Summary:** Fixed cloud-config snippet storage targeting wrong datastore, added PostgreSQL data disk provisioning, removed contradictory swap blocks, and renamed template files from `.tpl` to `.tftpl` for VS Code Terraform extension support.

### Fixed

- **k3s-cloud-configs.tf** — Cloud-config snippets now target `Proxmox_NAS` (supports snippets content type) instead of `local-lvm` (only supports images/rootdir). Added new `virtual_environment_snippet_datastore_id` variable.
- **k3s-server.yml.tftpl / k3s-agent.yml.tftpl** — Removed contradictory `swap:` block that created swap only to have `runcmd` immediately disable it.
- **postgresql.yml.tftpl** — Added data disk provisioning: partition, format, mount `/dev/sdb` to `/mnt/data`, move PostgreSQL data directory to dedicated 100GB disk with UUID-based fstab entry.

### Changed

- **cloud-configs/*.tpl → *.tftpl** — Renamed all 3 template files to use the official Terraform template extension for proper IDE syntax highlighting.
- **variables.tf** — Added `virtual_environment_snippet_datastore_id` (default: `Proxmox_NAS`) to decouple snippet storage from VM disk storage.

---

## 2026-02-15 — Wire k3s module in root configuration

**Summary:** Connected the k3s child module to the root Terraform configuration. All sensitive credentials (cluster token, SSH key, PostgreSQL password) are sourced from a single 1Password SSH Key item via data source. Renamed `vm_username` to `k3s_username` with a default of `k3sadmin`.

### Changed

- **infrastructure/main.tf** — Added `onepassword_item.k3s_cluster` data source for the `homelab-k3s-cluster` 1Password item. Added `module "k3s"` block passing 3 sensitive values from 1Password (`k3s_cluster_token`, `postgres_password`, `ssh_public_key`).
- **infrastructure/modules/k3s/variables.tf** — Renamed `vm_username` → `k3s_username`, added `default = "k3sadmin"`, updated description.
- **infrastructure/modules/k3s/k3s-cloud-configs.tf** — Updated all 3 `var.vm_username` references to `var.k3s_username`.
- **infrastructure/modules/k3s/outputs.tf** — Updated 2 `var.vm_username` references to `var.k3s_username`.

### Architecture

```
1Password item "homelab-k3s-cluster" (SSH Key type)
├── section "cluster"
│   └── field "server-token" → module.k3s.k3s_cluster_token
├── section "database"
│   └── field "password"      → module.k3s.postgres_password
└── top-level public_key      → module.k3s.ssh_public_key

k3s_username defaults to "k3sadmin" (no longer passed from root module)
```

---

## 2026-02-15 — Update k3s module topology (3 servers + 5 heterogeneous agents)

**Summary:** Rewrote the k3s module from a homogeneous 5-server/5-agent topology to 3 dedicated servers on the smallest nodes plus 5 agents with per-node CPU, memory, and disk sizing based on physical hardware capacity. GPU passthrough deferred (GTX 1080 lacks modern CUDA support).

### Changed

- **infrastructure/modules/k3s/k3s-cluster.tf** — Replaced flat `proxmox_nodes` list with `server_nodes` list (3 nodes) and `agent_nodes` map (5 nodes with per-node `cpu_cores`, `memory_gb`, `disk_gb`). Agent VM resource uses `each.value.*` for heterogeneous sizing. IP generation uses `keys()` + `index()` for map-based ordering. Fixed `postgres_config.node_name` reference.
- **infrastructure/modules/k3s/k3s-cloud-configs.tf** — Server cloud-configs iterate over `server_nodes`, agent cloud-configs iterate over `agent_nodes` map. Agent `server_url` references `server_nodes[0]`.
- **infrastructure/modules/k3s/outputs.tf** — Cluster overview uses dynamic `length()` counts instead of hardcoded values. Agent output iterates with map keys. All `proxmox_nodes` references replaced.

### Added

- **docs/pve-node-spec-config.md** — Proxmox node hardware specs and resource allocation table.

### Architecture

```
Before: 5 identical servers (4cpu/4GB) + 5 identical agents (6cpu/8GB)
After:  3 servers (4cpu/4GB) + 5 agents (6-14cpu / 20-60GB / 100-1000GB per node)

Server nodes: node-02, node-03, node-04
Agent-only:   node-01, node-05
Dual-role:    um560-xt-1, um773-lite-1, um773-lite-2 (server + agent)
```

---

## 2026-02-15 — Add PostgreSQL remote state backend

**Summary:** Prepare the Terraform pg backend for remote state storage in PostgreSQL. The backend block is commented out until the PostgreSQL VM (10.0.0.45) is deployed. Cloud-config provisions a `terraform_state` database and `terraform` user alongside the existing K3s database.

### Added

- **infrastructure/backend.tf** — pg backend block (commented out, activate after PostgreSQL VM deploy).
- **postgresql.yml.tpl** — `terraform_state` database, `terraform` user, and `pg_hba.conf` entry.
- **.env.example** — `PG_CONN_STR` variable (commented out until migration).
- **docs/guides/terraform-remote-state.md** — Guide 7: full walkthrough for the 2-phase migration.

---

## 2026-02-15 — Fix all K3s module audit issues

**Summary:** Resolved all 23 issues from the Terraform module audit. The k3s module now passes `terraform validate` and `tflint` with no exclusions. Deleted unused `vm/` and `vm-clone/` modules.

### Fixed (k3s module)

- **Issue #1** — Removed `user_account` blocks from all 3 VMs (conflicts with `user_data_file_id`).
- **Issue #2** — Removed `file_id = null` from 4 clone disk blocks.
- **Issues #3 & #4** — Added `clone.node_name` and `clone.datastore_id` for cross-node cloning.
- **Issue #5** — Added 3 missing variable declarations (`vm_username`, `ssh_public_key`, `virtual_environment_datastore_id`) plus new `k3s_template_node_name`.
- **Issue #6** — Created `providers.tf` with `required_providers` and `required_version`.
- **Issue #7** — Moved cloud-config templates from `modules/cloud-configs/` into `modules/k3s/cloud-configs/`.
- **Issue #8** — Removed `cluster-init` and `server` lines from K3s server config (incompatible with PostgreSQL datastore).
- **Issue #9** — Removed unnecessary `mac_address = null` from 3 VMs.
- **Issue #10** — Removed `file_format = "raw"` from 4 clone disk blocks.
- Replaced all deprecated `lookup()` calls with direct map access syntax.

### Removed

- **infrastructure/modules/vm/** and **infrastructure/modules/vm-clone/** — Unused example code (resolves issues #11-#19, #22).

### Changed

- **.pre-commit-config.yaml** — Removed all exclude patterns; all modules now pass validation.
- **docs/guides/terraform-module-audit.md** — All 23 issues marked resolved.

---

## 2026-02-15 — Pre-commit hooks for Terraform

**Summary:** Added pre-commit hooks for `terraform fmt`, `terraform validate`, and `tflint`. Fixed formatting in k3s module and added `required_version` constraints.

### Added

- **.pre-commit-config.yaml** — Pre-commit hooks using `antonbabenko/pre-commit-terraform` v1.105.0: format checking, validation, and linting.
- **`required_version = ">= 1.5"`** — Added to root `infrastructure/main.tf` and `modules/pve/providers.tf`.

### Fixed

- **Terraform formatting** — Auto-fixed 3 files in k3s module (`k3s-cloud-configs.tf`, `k3s-cluster.tf`, `outputs.tf`).

### Notes

- `validate` and `tflint` hooks exclude `modules/(k3s|vm|vm-clone)/` — these modules have known issues (see audit report) and need separate cleanup.
- `terraform fmt` runs on all files including excluded modules.

---

## 2026-02-15 — Terraform 1Password integration

**Summary:** Proxmox credentials are now read directly from 1Password at `terraform plan`/`apply` time. This eliminates hardcoded secrets from environment files and establishes 1Password as the single source of truth for infrastructure credentials.

### Changed

- **infrastructure/main.tf** — Added `onepassword_vault` and `onepassword_item` data sources. Proxmox provider now reads `endpoint` and `api_token` from 1Password item `PVE_Terraform` using `section_map["credentials"]` field access. Reordered provider blocks (1Password first, then data sources, then Proxmox).
- **infrastructure/variables.tf** — Removed 5 variables (`proxmox_ve_endpoint`, `proxmox_ve_username`, `proxmox_ve_token`, old `op_connect_token`, old `op_connect_host`). Replaced with 2 clean variables for 1Password Connect auth. Added descriptions referencing `TF_VAR_` env var names.
- **infrastructure/output.tf** — `pve_endpoint` now sources from 1Password data source (marked sensitive). Removed `pve_username` and `op_connect_host` outputs.
- **.env.d/terraform.env** — Removed `TF_VAR_proxmox_ve_token`, `TF_VAR_proxmox_ve_username`, `TF_VAR_proxmox_ve_endpoint`. Only Connect credentials and non-secret defaults remain.
- **.env.example** — Replaced Proxmox credential placeholders with 1Password Connect variables. Updated comments to reflect new auth flow.

### Fixed

- **SSH username bug** — `provider.proxmox.ssh.username` was set to `var.proxmox_ve_username` (`terraform@pve!provider`), which is the PVE API token ID, not an OS user. Fixed to `"root"`.

### Added

- **.claude/commands/finalize.md** — Reusable `/finalize` slash command for end-of-session workflow (document, changelog, branch, PR).

### Architecture

```
Before: .env → TF_VAR_proxmox_ve_token → variable → provider "proxmox"
After:  .env → TF_VAR_op_connect_token → provider "onepassword" → data source → provider "proxmox"
```

Only the 1Password Connect token and URL need to be in the environment. All Proxmox credentials rotate in 1Password without touching Terraform.
