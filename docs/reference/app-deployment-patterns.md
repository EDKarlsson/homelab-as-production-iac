---
title: Application Deployment Patterns
description: Deployment patterns for applications with external PostgreSQL, 1Password ExternalSecrets, and Tailscale ingress
published: true
date: 2026-02-19
tags:
  - apps
  - helm
  - postgresql
  - external-secrets
  - tailscale
  - coder
  - windmill
---

Deployment patterns for applications with external PostgreSQL, 1Password ExternalSecrets, and Tailscale ingress. Each pattern documents the specific configuration decisions and gotchas for the app.

## Coder (Remote Development Platform)

Coder provides remote development environments (workspaces) running as K8s pods. Deployed via the standard Flux Helm app pattern.

### Architecture

```
[User] --Tailscale--> coder.homelab.ts.net --> Coder Server
                                                     |
                                                     +--> PostgreSQL (VIP 10.0.0.44, HA cluster)
                                                     |
                                                     +--> Workspace pods (dynamic, same cluster)
```

### Key Configuration

**External PostgreSQL:** Coder connects to the shared external PostgreSQL HA cluster via the VIP (10.0.0.44). The connection URL is stored in 1Password as a custom text field on the `Coder` item.

```yaml
# release.yaml - environment variables
coder:
  env:
    - name: CODER_PG_CONNECTION_URL
      valueFrom:
        secretKeyRef:
          name: coder-secrets
          key: db-connection-url
    - name: CODER_ACCESS_URL
      value: "https://coder.homelab.ts.net"
    - name: CODER_WILDCARD_ACCESS_URL
      value: "*.coder.homelab.ts.net"
  service:
    type: ClusterIP
```

**Wildcard access URL:** `CODER_WILDCARD_ACCESS_URL` (`*.coder.homelab.ts.net`) enables Coder's workspace port-forwarding feature. Each workspace gets a subdomain (e.g., `my-workspace.coder.homelab.ts.net`) that routes through the Coder server to the workspace pod. Without this, workspace web apps are only accessible via the Coder dashboard's built-in terminal.

**Service type:** `ClusterIP` (not LoadBalancer) because all external access is via Tailscale ingress. No MetalLB IP allocation needed.

### ExternalSecret

```yaml
# 1Password item: "Coder" (Homelab vault)
# Custom text field: "db-connection-url"
# Value format: postgres://coder:<password>@10.0.0.44:5432/coder?sslmode=disable
data:
  - secretKey: db-connection-url
    remoteRef:
      key: Coder
      property: db-connection-url
```

### Files

| File | Purpose |
|------|---------|
| `kubernetes/apps/coder/namespace.yaml` | Namespace with `dev-team` tenant label |
| `kubernetes/apps/coder/repository.yaml` | HelmRepository: `https://helm.coder.com/v2` |
| `kubernetes/apps/coder/external-secret.yaml` | ExternalSecret for PostgreSQL connection URL |
| `kubernetes/apps/coder/release.yaml` | HelmRelease (chart 2.x) |
| `kubernetes/apps/coder/tailscale-ingress.yaml` | Tailscale Ingress for `coder.homelab.ts.net` |

---

## Windmill (Workflow Automation)

Windmill is a developer platform for building scripts, flows, and apps. It bundles a PostgreSQL dependency by default, which must be disabled for external PostgreSQL.

### Architecture

```
[User] --Tailscale--> windmill.homelab.ts.net --> Windmill App (port 8000)
                                                        |
                                                        +--> PostgreSQL (VIP 10.0.0.44, HA cluster)
                                                        |
                                                        +--> Worker pods (default + native groups)
                                                        |
                                                        +--> Indexer pod
```

### Key Configuration

**Disable bundled PostgreSQL:** The Windmill Helm chart includes a PostgreSQL subchart. Setting `postgresql.enabled: false` disables it in favor of the external PostgreSQL VM.

**Database URL secret:** Windmill reads the PostgreSQL connection URL from a Kubernetes Secret referenced by `windmill.databaseUrlSecretName`. The secret key must be `db-connection-url`.

```yaml
# release.yaml
values:
  windmill:
    databaseUrlSecretName: windmill-secrets
    baseDomain: windmill.homelab.ts.net
    baseProtocol: https
    appReplicas: 1
  postgresql:
    enabled: false                 # Disable bundled PostgreSQL
  windmill_extra:
    replicas: 1                    # LSP service for web IDE
  indexer:
    replicas: 1
    resources:
      limits:
        ephemeral-storage: 10Gi   # Reduced from 50Gi default
  workerGroups:
    - name: "default"
      replicas: 2
      resources:
        limits:
          memory: "1Gi"
    - name: "native"
      replicas: 1
      resources:
        limits:
          memory: "1Gi"
```

### Configuration Decisions

| Setting | Value | Rationale |
|---------|-------|-----------|
| `postgresql.enabled: false` | Disabled | Use shared external PostgreSQL HA cluster (VIP 10.0.0.44) |
| `indexer.resources.limits.ephemeral-storage: 10Gi` | 10Gi | Default is 50Gi which exceeds node ephemeral storage; 10Gi is sufficient for a homelab |
| `workerGroups[default].replicas: 2` | 2 workers | Lean config: enough for concurrent script execution without over-allocating |
| `workerGroups[native].replicas: 1` | 1 worker | Native workers handle Go/Rust/etc.; 1 is sufficient for light usage |
| `windmill_extra.replicas: 1` | 1 replica | LSP service for web IDE code completion |
| `appReplicas: 1` | 1 replica | Single app server; scale up only if needed |

### Indexer Ephemeral Storage

The Windmill indexer requests 50Gi of ephemeral storage by default. On K3s nodes with smaller root disks, this causes the pod to be unschedulable (`Insufficient ephemeral-storage`). Reducing to 10Gi resolves this while providing ample space for the search index in a homelab context.

### ExternalSecret

```yaml
# 1Password item: "Windmill" (Homelab vault)
# Custom text field: "db-connection-url"
# Value format: postgres://windmill:<password>@10.0.0.44:5432/windmill?sslmode=disable
data:
  - secretKey: db-connection-url
    remoteRef:
      key: Windmill
      property: db-connection-url
```

### Tailscale Ingress

Windmill's app service runs on port 8000 (not the default 80):

```yaml
spec:
  ingressClassName: tailscale
  defaultBackend:
    service:
      name: windmill-app       # Service name from chart (not "windmill")
      port:
        number: 8000           # Windmill app port
  tls:
    - hosts:
        - windmill             # -> windmill.homelab.ts.net
```

### Files

| File | Purpose |
|------|---------|
| `kubernetes/apps/windmill/namespace.yaml` | Namespace with `dev-team` tenant label |
| `kubernetes/apps/windmill/repository.yaml` | HelmRepository: `https://windmill-labs.github.io/windmill-helm-charts/` |
| `kubernetes/apps/windmill/external-secret.yaml` | ExternalSecret for PostgreSQL connection URL |
| `kubernetes/apps/windmill/release.yaml` | HelmRelease (chart 2.x) with lean worker config |
| `kubernetes/apps/windmill/tailscale-ingress.yaml` | Tailscale Ingress for `windmill.homelab.ts.net` |

---

## Homepage (Dashboard)

Homepage is a modern, self-hosted application dashboard deployed via the jameswynn Helm chart with extensive widget integration.

### Architecture

```
[User] --Tailscale--> homepage.homelab.ts.net --> Homepage (port 3000)
                                                       |
                                                       +--> K8s API (cluster stats via RBAC)
                                                       |
                                                       +--> Service widgets (server-side API calls)
                                                       |
                                                       +--> Longhorn API (storage stats)
```

### Key Configuration

**Image override (critical):** The jameswynn chart v2.x bundles Homepage app v1.2.0. The latest app version is v1.10.1, which adds support for many widgets (including Portainer K8s stats, post-June 2025). Always override the image:

```yaml
values:
  image:
    repository: ghcr.io/gethomepage/homepage
    tag: v1.10.1
```

**Kubernetes cluster widget:** Requires RBAC. Set `enableRbac: true` and `serviceAccount.create: true` in the chart values. The `kubernetes` widget in the config then shows cluster CPU/memory.

**Widget credential pattern:** All widget credentials are stored in a single 1Password item (`homepage-widgets`) with 12 custom text fields. An ExternalSecret syncs these into `homepage-widget-secrets` K8s Secret. Environment variables use `HOMEPAGE_VAR_*` naming convention and `optional: true` on every `secretKeyRef` so Homepage starts even before credentials exist.

**Longhorn widget:** The provider URL goes in `settingsString` under `providers.longhorn.url`, NOT in the widget definition:

```yaml
settingsString: |
  providers:
    longhorn:
      url: http://longhorn-frontend.longhorn-system.svc.cluster.local
widgets:
  - longhorn:
      expanded: true
      total: true
```

### Widget Service Name Discovery

Widget URLs must use the actual K8s Service names (not app names). Common mismatches:

| App | Service Name | Port | Namespace |
|-----|-------------|------|-----------|
| Plex | `plex-plex-media-server` | 32400 | media |
| Grafana | `kube-prometheus-stack-grafana` | 80 | monitoring |
| Portainer | `portainer` | 9000 | portainer |
| Longhorn | `longhorn-frontend` | 80 | longhorn-system |

Discover with: `kubectl get svc -n <namespace>`

### Proxmox Widget Token Permissions

Proxmox API tokens created under `root@pam` with "Privilege Separation" checked (default) have zero permissions -- they do NOT inherit root's privileges. The Homepage Proxmox widget needs at minimum `PVEAuditor` role:

1. Create token: Datacenter -> Permissions -> API Tokens -> Add (under `root@pam`, Token ID: `homepage`)
2. Grant permissions: Datacenter -> Permissions -> Add -> API Token Permission -> Path: `/`, Role: `PVEAuditor`, Token: `root@pam!homepage`
3. Or: uncheck "Privilege Separation" on the token to inherit full `root@pam` permissions

### ExternalSecret

```yaml
# 1Password item: "homepage-widgets" (Homelab vault)
# 12 custom text fields for widget credentials
data:
  - secretKey: grafana-password
    remoteRef:
      key: homepage-widgets
      property: grafana-password
  - secretKey: proxmox-url
    remoteRef:
      key: homepage-widgets
      property: proxmox-url
  # ... (12 fields total)
```

### Files

| File | Purpose |
|------|---------|
| `kubernetes/apps/homepage/namespace.yaml` | Namespace with `dev-team` tenant label |
| `kubernetes/apps/homepage/repository.yaml` | HelmRepository: `https://jameswynn.github.io/helm-charts` |
| `kubernetes/apps/homepage/external-secret.yaml` | ExternalSecret for all widget credentials (12 fields) |
| `kubernetes/apps/homepage/release.yaml` | HelmRelease (chart 2.x) with image override, RBAC, widgets config |
| `kubernetes/apps/homepage/tailscale-ingress.yaml` | Tailscale Ingress for `homepage.homelab.ts.net` |

---

## Image Tag Pinning Patterns

All images are pinned to specific versions. The CI policy check (`scripts/ci/policy-check.sh`) rejects `:latest` tags unless explicitly allowlisted in `ci/allowlists/image-tag-latest.txt`. After pinning an image, remove its corresponding entry from the allowlist.

### Tag Formats by Image Source

Different registries and projects use different tag conventions:

| Source / Project | Tag Format | Example |
|-----------------|------------|---------|
| Standard semver | `X.Y.Z` | `code-server:4.109.2`, `n8n:2.8.3` |
| LinuxServer.io | Bare version (no `-lsNNN` suffix) | `calibre-web:0.6.26` (not `0.6.26-ls123`) |
| GitLab CE | Semver with `-ce.0` suffix | `gitlab-ce:18.9.0-ce.0` |
| JupyterLab (Jupyter Docker Stacks) | Date-based: `cuda12-YYYY-MM-DD` | `cuda12-2026-02-16` (was `cuda12-latest`) |
| Wiki.js | Full semver (was floating `:2` major tag) | `wiki:2.5.312` |
| Homepage (jameswynn chart) | Chart bundles old version; override `image.tag` | `v1.10.1` (chart default is v1.2.0) |
| Prometheus exporters | Standard semver | `pve-exporter:3.8.1` |
| GHCR images | GitHub releases use `v`-prefix; GHCR Docker tags do NOT. Pulling `:v0.3.1` from `ghcr.io` returns 404. | Use bare version: `ghcr.io/someorg/someapp:0.3.1`. Verify tags at `https://github.com/<org>/<repo>/pkgs/container/<name>`. |

### CI Allowlist Cleanup

After pinning a floating tag to a specific version:

1. **Remove the allowlist entry** from `ci/allowlists/image-tag-latest.txt`
2. The CI policy check will now enforce the pinned tag going forward
3. Only images that genuinely need `:latest` (e.g., infrastructure containers managed outside Flux) should remain in the allowlist

Current allowlist entries (infrastructure-only, not Flux-managed):

```
infrastructure/modules/op-connect/templates/docker-compose.yml|1password/connect-api:latest
infrastructure/modules/op-connect/templates/docker-compose.yml|1password/connect-sync:latest
```

These are acceptable because 1Password Connect containers run in Docker on LXC (outside Kubernetes), and the Connect team recommends using `:latest` for automatic security updates.

---

---

## AFFiNE (Collaborative Document / Knowledge Base)

AFFiNE is a self-hosted collaborative workspace combining docs, whiteboards, and databases. It uses PostgreSQL for structured data, a filesystem PVC for binary blobs, and Redis for ephemeral queuing.

### Architecture

```
[User] --Tailscale--> affine.homelab.ts.net --> AFFiNE Server (port 3010)
                                                     |
                                                     +--> PostgreSQL (VIP 10.0.0.44, HA cluster)
                                                     |    CRDT doc content + structured data (Prisma)
                                                     |
                                                     +--> PVC at /root/.affine/storage
                                                     |    Binary blobs: images, attachments, exports
                                                     |
                                                     +--> Redis (in-cluster)
                                                          Ephemeral BullMQ job queues only
```

### Storage Split

AFFiNE splits storage across three layers with different durability requirements:

| Layer | Storage | Contents | Persistence Required |
|-------|---------|----------|---------------------|
| PostgreSQL | External HA cluster (VIP 10.0.0.44) | Document content (CRDT), workspaces, user data | Yes — primary data store |
| Filesystem PVC | Longhorn `ReadWriteOnce` | Images, file attachments, exports, blob data | Yes — binary data at `/root/.affine/storage` |
| Redis | In-cluster ephemeral | BullMQ job queues (email, background tasks) | No — queues are transient; Redis can be recreated |

**Critical:** The "AFFiNE Cloud" option in the self-hosted UI refers to YOUR server's cloud sync feature, not `affine.pro`. It enables client-side sync to the self-hosted server. Do not confuse with the managed cloud service.

### Migration Init Container

AFFiNE requires a database migration init container to run before the main container starts:

```yaml
initContainers:
  - name: migration
    image: ghcr.io/toeverything/affine:0.20.x
    command: ["node", "./scripts/self-host-predeploy.js"]
    env:
      - name: DATABASE_URL
        valueFrom:
          secretKeyRef:
            name: affine-secrets
            key: db-connection-url
      - name: REDIS_SERVER_HOST
        value: "affine-redis.affine.svc.cluster.local"
```

**Key properties of the migration container:**
- Command: `node ./scripts/self-host-predeploy.js` (equivalent to `yarn predeploy` in development)
- Requires `DATABASE_URL` and `REDIS_SERVER_HOST` env vars
- Is idempotent -- runs on every pod restart, skips already-applied migrations
- Prisma error `P1010: User was denied access on the database '<IP>'` means `pg_hba.conf` is rejecting the connection from the K3s node IP. The error message shows the node IP (e.g., `10.0.0.x`), not the pod IP -- add `10.0.0.0/24` to `pg_hba.conf` on both primary and standby (changes are not replicated automatically).

### Key Configuration

```yaml
# release.yaml env vars
env:
  - name: DATABASE_URL
    valueFrom:
      secretKeyRef:
        name: affine-secrets
        key: db-connection-url
  - name: REDIS_SERVER_HOST
    value: "affine-redis.affine.svc.cluster.local"
  - name: REDIS_SERVER_PORT
    value: "6379"
  - name: NODE_OPTIONS
    value: "--import=./scripts/register.js"
  - name: AFFINE_SERVER_HTTPS
    value: "true"
  - name: AFFINE_SERVER_HOST
    value: "affine.homelab.ts.net"
```

**`NODE_OPTIONS` is required** -- AFFiNE uses ES module imports that require the register hook. Omitting it causes the server to fail to start with module resolution errors.

### ExternalSecret

```yaml
# 1Password item: "AFFiNE" (Homelab vault)
# Custom text fields: "db-connection-url"
# Value format: postgres://affine:<password>@10.0.0.44:5432/affine?sslmode=disable
data:
  - secretKey: db-connection-url
    remoteRef:
      key: AFFiNE
      property: db-connection-url
```

### Files

| File | Purpose |
|------|---------|
| `kubernetes/apps/affine/namespace.yaml` | Namespace |
| `kubernetes/apps/affine/external-secret.yaml` | ExternalSecret for PostgreSQL connection URL |
| `kubernetes/apps/affine/deployment.yaml` | Deployment with migration init container + main container |
| `kubernetes/apps/affine/service.yaml` | ClusterIP service on port 3010 |
| `kubernetes/apps/affine/tailscale-ingress.yaml` | Tailscale Ingress for `affine.homelab.ts.net` |
| `kubernetes/apps/affine/redis.yaml` | In-cluster Redis deployment (ephemeral, no PVC needed) |
| `kubernetes/apps/affine/pvc.yaml` | PVC for blob storage at `/root/.affine/storage` |

---

## Common Pattern: External PostgreSQL Apps

All PostgreSQL-backed apps (Coder, Windmill, n8n, Wiki.js, Keycloak, TeamCity) share this pattern:

1. **Database lives on external PostgreSQL HA cluster** -- primary at `10.0.0.45`, standby at `10.0.0.46`, VIP at `10.0.0.44` (see [postgresql-ha.md](./postgresql-ha.md)). All consumers connect via the VIP.
2. **Connection URL in 1Password** as a custom text field (not a default Login field)
3. **ExternalSecret** pulls the URL into a K8s Secret via ClusterSecretStore `onepassword-connect`
4. **HelmRelease** references the Secret via `secretKeyRef` or chart-specific secret name config
5. **pg_hba.conf** on the PostgreSQL VM allows connections from `10.0.0.0/24` (pod traffic routes via node IP, not pod CIDR)

### PostgreSQL Connection URL Format

```
postgres://<user>:<password>@10.0.0.44:5432/<database>?sslmode=disable
```

**Gotcha:** Passwords with special characters (`@`, `#`, `%`, etc.) must be URL-encoded in the connection string. Simplest approach: use alphanumeric-only passwords when creating database users.
