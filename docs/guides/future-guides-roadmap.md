# Future Guides Roadmap & Script Improvements

This document lists proposed future guides based on analysis of the repository, project PRD, and
existing infrastructure. It also documents improvements for existing scripts.

---

## Completed guides

| # | Guide | Status |
|---|---|---|
| Ref | [Terraform Provider Setup](./terraform-provider-setup.md) | Done |
| 1 | [Importing Existing Proxmox VMs](./importing-existing-vms.md) | Done |
| 2 | [Creating a Ubuntu 24.04 VM Template](./creating-vm-template.md) | Done |
| 3 | [Cloning k3s Node VMs from Template](./cloning-k3s-vms.md) | Done |
| Audit | [Terraform Module Audit Report](./terraform-module-audit.md) | Done |
| 4 | [Ansible K3s Provisioning](./ansible-k3s-provisioning.md) | Done |
| 5 | [FluxCD Bootstrap](./fluxcd-bootstrap.md) | Done |
| 6 | [1Password Secrets Management](./1password-secrets-management.md) | Done |

---

## Proposed future guides

Listed in recommended implementation order, aligned with the PRD's 7-phase roadmap.

### Phase 1: Foundation (infrastructure fixes)

#### Guide 6: Fixing the K3s Terraform Module

**Priority:** High — blocks all Terraform-managed VM provisioning

**What it would cover:**
- Resolving all 9 ERROR-level issues from the [TF audit report](./terraform-module-audit.md)
- Moving cloud-config templates to the correct path (`modules/k3s/cloud-configs/`)
- Adding missing variable declarations
- Removing `user_account`/`user_data_file_id` conflict
- Adding `clone.node_name` and `clone.datastore_id` for cross-node cloning
- Adding `required_providers` blocks to all modules
- Fixing the SSH username in the provider config
- Wiring up `module "k3s"` in `main.tf`

**Relevant files:**
- `infrastructure/modules/k3s/k3s-cluster.tf`
- `infrastructure/modules/k3s/k3s-cloud-configs.tf`
- `infrastructure/modules/k3s/variables.tf`
- `infrastructure/modules/cloud-configs/*.yml.tpl`
- `infrastructure/main.tf`

---

#### Guide 7: Terraform Remote State Backend

**Priority:** High — currently using local state which is fragile and single-user

**What it would cover:**
- Options: S3-compatible (MinIO on NAS), Terraform Cloud (free tier), Consul, PostgreSQL
- For a homelab with Synology NAS: MinIO on Synology as an S3 backend is practical
- Alternatively: `pg` backend using the same PostgreSQL that K3s uses
- Setting up `backend.tf` with state locking
- Migrating from local to remote state (`terraform init -migrate-state`)

**Relevant docs:**
- https://developer.hashicorp.com/terraform/language/backend/s3
- https://developer.hashicorp.com/terraform/language/backend/pg

---

#### Guide 8: Cleaning Up Example/Reference Modules

**Priority:** Medium — reduces confusion

**What it would cover:**
- Decision: keep, fix, or remove `modules/vm-clone/` and `modules/vm/`
- These modules contain example code from provider docs and are not referenced
- If keeping: fix the issues identified in the audit (issues #11-19)
- If removing: safe deletion and cleanup

---

### Phase 2: K3s cluster day-2 operations

#### Guide 9: K3s Cluster Upgrades with Ansible

**Priority:** Medium — needed after initial deployment

**What it would cover:**
- Rolling upgrade strategy (one server at a time, then agents)
- Version pinning and testing in a staging environment
- Using `serial: 1` in Ansible for zero-downtime upgrades
- Drain/cordon nodes before upgrade
- Rollback procedure
- K3s upgrade mechanisms: `INSTALL_K3S_VERSION` environment variable

**Relevant docs:**
- https://docs.k3s.io/upgrades/manual
- https://docs.k3s.io/upgrades/automated

---

#### Guide 10: PostgreSQL Database Backup & Recovery

**Priority:** High — the K3s datastore is a single point of failure

**What it would cover:**
- `pg_dump` scheduled backups to NAS
- Backup rotation and retention
- Restore procedure and testing
- Monitoring database health
- Consideration: is PostgreSQL worth the complexity vs embedded etcd?

---

### Phase 3: GitOps infrastructure

#### Guide 11: SOPS + Age Deep Dive

**Priority:** Medium — the FluxCD guide covers basics, this goes deeper

**What it would cover:**
- `.sops.yaml` creation rules and path-based encryption
- Encrypting different secrets for different environments
- Key rotation procedure
- Backup strategy for age private keys (1Password integration)
- CI/CD integration for secret validation

**Relevant docs:**
- https://fluxcd.io/flux/guides/mozilla-sops/
- https://github.com/getsops/sops

---

#### Guide 12: Monitoring Stack (Prometheus + Grafana)

**Priority:** Medium — essential for visibility

**What it would cover:**
- Deploying kube-prometheus-stack via Flux HelmRelease
- Grafana dashboards for K3s, node metrics, Proxmox
- AlertManager configuration
- Persistent storage on NFS
- Ingress and TLS for Grafana

**Relevant files:**
- `infrastructure/flux/monitoring.yaml` (exists but needs completing)

---

#### Guide 13: Keycloak + OAuth2 Proxy

**Priority:** Low — needed for SSO but not blocking

**What it would cover:**
- Deploying Keycloak via Flux HelmRelease
- Configuring OAuth2 Proxy for Kubernetes dashboard, Grafana
- Integrating with ingress-nginx
- User management and realm setup

---

### Phase 4: Infrastructure services

#### Guide 14: MetalLB or kube-vip for LoadBalancer Services

**Priority:** Medium — K3s disables its built-in servicelb per config

**What it would cover:**
- MetalLB vs kube-vip comparison for a homelab
- L2 mode configuration (no BGP needed for homelab)
- IP address pool from the VLAN02-Homelab static range
- Deployment via Flux HelmRelease

---

#### Guide 15: External DNS + Pi-hole Integration

**Priority:** Low

**What it would cover:**
- ExternalDNS controller for automatic DNS records
- Integrating with Pi-hole/AdGuard Home for local DNS
- Wildcard domains for ingress

---

#### Guide 16: NFS Persistent Volumes

**Priority:** Medium — needed for stateful workloads

**What it would cover:**
- NFS CSI driver (nfs-subdir-external-provisioner)
- StorageClass configuration pointing to Proxmox_NAS
- PVC examples for common workloads
- Performance considerations

---

### Phase 5: Developer experience

#### ~~Guide 17: 1Password Connect Integration~~ → Completed as Guide 6

**Status:** Done — see [Guide 6: 1Password Secrets Management](./1password-secrets-management.md)

Covers CLI integration, Terraform provider, Ansible Connect lookup, External Secrets Operator
with FluxCD, Kubernetes operator comparison, the bootstrap problem, and deploying Connect in K8s.

---

#### Guide 18: CI/CD Pipeline with GitHub Actions

**Priority:** Low

**What it would cover:**
- Flux manifest validation in CI (using existing `scripts/k8s/validate.sh`)
- Terraform plan on PR, apply on merge
- Ansible lint and dry-run checks
- Secret scanning

---

---

## Script improvements

### `scripts/env-load.sh` — Environment loading

**Current issues:**

1. **`op run --env-file` and `cat << EOF` don't chain correctly** (line 13-14)
   - `op run` executes a command with injected env vars, but the `cat << EOF` after `--` is a
     separate shell construct. The heredoc content contains `op://` references that should be
     resolved by `op inject`, not `op run`.
   - The `op run` command on line 13 likely does nothing useful because `cat` doesn't read the
     env vars — it just outputs the heredoc literally.

2. **No error handling** — `set -e` or `set -euo pipefail` is missing. If `find` returns nothing
   or `op` fails, the script continues silently.

3. **Relative path assumptions** — `find ./configs` assumes the script is run from the repo root.
   No validation that `configs/base.env` exists.

4. **Alias AND function with same name** (lines 67-72) — `init-env` is defined as both an alias
   (line 67) and a function (lines 68-72). The function will shadow the alias. Pick one.

5. **Temporary file left on failure** — If `op inject` fails on line 70, `.env.load` may contain
   partial/incorrect data and the `source` on line 71 will load bad values.

6. **macOS vs Linux path differences** — `gen-ssh-key.sh` hardcodes `/Users/dank/.ssh/config.d/`
   which only works on macOS.

**Suggested improvements:**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Resolve script directory for reliable relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Validate prerequisites
if ! command -v op &>/dev/null; then
  echo "ERROR: 1Password CLI (op) not found in PATH" >&2
  exit 1
fi

base_env="$REPO_ROOT/configs/base.env"
if [[ ! -f "$base_env" ]]; then
  echo "ERROR: base.env not found at $base_env" >&2
  exit 1
fi

# Use op inject (not op run) to resolve op:// references
# ...
```

---

### `scripts/pve/test-api.sh` — Proxmox API test

**Current issues:**

1. **Line 5: Bash syntax error** — `${3:${PROXMOX_VE_USER_REALM:-pve}}` and
   `${4:${PROXMOX_VE_TOKEN_NAME:-provider}}` use `:` (substring) instead of `:-` (default value).
   Should be `${3:-${PROXMOX_VE_USER_REALM:-pve}}`.

2. **Line 9: `echo` instead of `curl`** — The script prints the auth header and URL but doesn't
   actually make a request. The working `curl` command is commented out on line 10.

3. **Hardcoded endpoint on line 9** — Uses `node-02.homelab.ts.net:8006` instead of the
   `$endpoint` variable.

4. **Line 3: Redundant `@${realm}!${token_name}` parsing** — The `PROXMOX_VE_USERNAME` env var
   already contains the full token ID (`terraform@pve!provider`). Reconstructing it from parts
   is error-prone.

**Suggested fix:**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Source credentials if not already set
if [[ -z "${PROXMOX_VE_USERNAME:-}" ]]; then
  source "$(dirname "$0")/../../.env.saved" 2>/dev/null || {
    echo "ERROR: Set PROXMOX_VE_USERNAME, PROXMOX_VE_API_TOKEN, PROXMOX_VE_ENDPOINT" >&2
    exit 1
  }
fi

AUTH="Authorization: PVEAPIToken=${PROXMOX_VE_USERNAME}=${PROXMOX_VE_API_TOKEN}"
API="${PROXMOX_VE_ENDPOINT}/api2/json"

echo "Testing API: $API"
curl -sk -H "$AUTH" "$API/nodes" | python3 -m json.tool
```

---

### `scripts/k8s/config-k3s.sh` — K3s configuration (BROKEN)

**Current issues:**

1. **Marked as broken** — The file header says "Needs to be fixed".

2. **Line 57: Hardcoded call** — `install_k3s kca-fnw4la` runs a specific agent installation
   instead of being parameterized.

3. **Mixed concerns** — The script tries to be both a library (functions) and an executable
   (calls `install_k3s` directly).

4. **No version pinning** — `curl -sfL https://get.k3s.io | sh -s -` installs latest, causing
   version skew between nodes.

5. **Tokens passed via SSH command line** — `--token=${K3S_TOKEN}` in the SSH command is visible
   in process listings (`ps aux`).

**Recommendation:** Replace with the Ansible playbook approach from the
[Ansible K3s guide](./ansible-k3s-provisioning.md). Ansible handles SSH, templating, idempotency,
and secrets management properly. If a shell script is still wanted, rewrite with:
- Version pinning (`INSTALL_K3S_VERSION`)
- Config file instead of CLI flags (avoids token in process list)
- `set -euo pipefail`
- Usage/help text

---

### `scripts/k8s/init-k3s.sh` — K3s installation

**Current issues:**

1. **Hardcoded username** — `k3sifnpmq` on line 8 (likely a randomly generated name from an old setup).

2. **No version pinning** — Same issue as config-k3s.sh.

3. **`--cluster-init` used with external datastore** — Line 29 uses both `--cluster-init` and
   `K3S_DATASTORE_ENDPOINT`, which conflict (see [audit issue #8](./terraform-module-audit.md)).

4. **No `set -e`** — Script continues on error.

---

### `scripts/k8s/k3s-install-helm.sh` — Helm installation

**Current issues:**

1. **Uses Helm v2 with Tiller** (lines 21-24) — Tiller was removed in Helm v3 (2019). This script
   is severely outdated. `helm init --service-account tiller` will fail on any modern Helm.

2. **Installs NATS as a test** — The script conflates Helm installation with deploying NATS, which
   makes it non-reusable.

3. **Uses deprecated `helm search`** — Should be `helm search repo`.

**Recommendation:** Delete and replace with a simple Helm v3 install:

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

Or better yet, install Helm via the Ansible K3s playbook.

---

### `scripts/k8s/bootstrap-flux.sh` — Flux bootstrap

**Current issues:**

1. **No `set -e`** — Continues silently on failure.

2. **Repository path mismatch** — Points to `infrastructure/kubernetes` but the FluxCD guide
   recommends `infrastructure/kubernetes/cluster`. Verify which is correct for your setup.

3. **No version pinning for Flux CLI** — `curl -s https://fluxcd.io/install.sh | sudo bash`
   installs latest, which could be a breaking change.

---

### `scripts/k8s/validate.sh` — Flux validation

**Status:** This script is from the official FluxCD project and is well-written. No changes needed.

**Note:** Consider integrating it into a GitHub Actions CI pipeline.

---

### `scripts/k8s/simple_setup.sh` — K3s simple setup

**Current issues:**
- Only runs `curl | sh` and `kubectl get node` — too simple to be useful.
- No version pinning.

**Recommendation:** Delete. Covered by `init-k3s.sh` and the Ansible guide.

---

### `scripts/env-save.sh` — Save resolved env vars

**Current issues:**

1. **No `set -e`** — Continues on errors.

2. **Fragile parsing** — `sed 's/export //g;s/#.*$//g;s/=.*$//g;/^$/d'` can break on multi-line
   values or values containing `#`.

3. **Exposes secrets in process list** — The `for` loop echoes masked values but the actual values
   are written to `.env.saved`. The masking is cosmetic only.

**Improvements:**
- Add `set -euo pipefail`
- Use `grep -v '^#'` for comment removal instead of inline sed
- Add a warning about sensitive content in `.env.saved`

---

### `scripts/server/gen-ssh-key.sh` — SSH key generation

**Current issues:**

1. **Hardcoded macOS path** — `/Users/dank/.ssh/config.d/` only works on macOS for user `dank`.

2. **No key type flag** — Relies on default, which is ed25519 on modern OpenSSH but could be
   RSA on older versions.

**Fix:**

```bash
#!/usr/bin/env bash
set -euo pipefail
KEY_NAME="${1:?Usage: gen-ssh-key.sh <key-name>}"
KEY_DIR="${HOME}/.ssh/homelab"
mkdir -p "$KEY_DIR"
ssh-keygen -t ed25519 -C "${KEY_NAME}" -f "${KEY_DIR}/${KEY_NAME}_ed25519"
```

---

### `scripts/server/setup.sh` — Server initial setup

**Status:** Simple and functional. Installs basic tools and enables mDNS.

**Minor improvement:** Add `set -euo pipefail`.

---

### `scripts/config-mcps.sh` — MCP server configuration

**Current issues:**

1. **Incomplete functions** — `convert_to_json()` and `translate_keys()` are defined but
   never called. The `get_mcp_env_vars()` function is also never called.

2. **Fragile JSON construction** — Building JSON with sed is brittle. Use `jq` instead.

**Recommendation:** If this is still needed, rewrite with `jq`. Otherwise, remove the dead code.

---

### `scripts/pve/create-tf-user.sh` — Create Terraform user in Proxmox

**Status:** Simple and correct. Creates the `terraform@pve` user with an API token.

**Minor improvements:**
- Add `set -euo pipefail`
- Add a check for existing user (`pveum user list | grep terraform@pve`)
- Document the required role permissions (the "Terraform" role must be created separately)

---

## Common improvements across all scripts

1. **Add `set -euo pipefail`** to every script — prevents silent failures
2. **Add usage/help text** — `${1:?Usage: ...}` for required arguments
3. **Remove hardcoded paths** — Use `$HOME` instead of `/Users/dank`
4. **Pin tool versions** — K3s, Helm, Flux CLI
5. **Add ShellCheck compliance** — Run `shellcheck scripts/**/*.sh` and fix warnings
6. **Consolidate or remove redundant scripts** — `simple_setup.sh`, `k3s-install-helm.sh` (Helm v2)
